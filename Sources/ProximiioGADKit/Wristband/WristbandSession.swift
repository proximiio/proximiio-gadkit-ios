//
//  WristbandSession.swift
//  ProximiioGADKit
//
//  The visitor's wristband session, held by the SDK's `BlueiotWristbandBinding`.
//  Follows proximiio-blueiot-minimal-ios `WristbandSession`.
//
//  The binding client stores the session in the Keychain and confirms it with the
//  relay-api at launch (`restore()`). The app stores no wristband id of its own: the
//  binding state is the only record of which band this phone follows. A bind of a band
//  another phone follows is a take-over; the relay-api decides whether it is allowed, and
//  the other phone's session ends with `.superseded`.
//
//  The SDK never asks for location permission. When the relay-api needs the phone's
//  location for a take-over, `locationReadiness()` says so and `LocationAccess` asks
//  before the bind.
//
import CoreLocation
import Foundation
import Observation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

/// What the app asks for before a bind.
@_spi(GADApp) public enum WristbandLocationAsk: Equatable, Sendable {
    /// "While Using the App" authorization. Asked only while it is undetermined.
    case permission
    /// Temporary full accuracy, when the visitor allowed approximate location only.
    case preciseLocation
}

@MainActor
@Observable
final class WristbandSession {
    /// The binding client. One per process; `VenueService` attaches its position provider.
    let binding: BlueiotWristbandBinding

    /// The latest binding state. `nil` until the first value arrives from `stateChanges()`.
    private(set) var state: BlueiotBindingState?

    @ObservationIgnored private let location = LocationAccess()
    /// Called after every state change, for `ProximiMap`.
    @ObservationIgnored var onStateChange: ((BlueiotBindingState) -> Void)?
    /// The SDK that gets the relay's privacy signal (`forwardPrivacy(to:)`).
    @ObservationIgnored private var privacySDK: Proximiio?
    /// The value last passed to `setPositioningSourcePrivate(since:)`; `.some(nil)` is "not private".
    @ObservationIgnored private var forwardedPrivateSince: Date??

    init(configuration backend: GADConfiguration) {
        binding = BlueiotWristbandBinding(configuration: Self.configuration(for: backend))
    }

    /// The binding configuration for `backend`.
    ///
    /// `runsInBackground: true` keeps the position stream open after the app leaves the
    /// screen. Without it the SDK pauses the provider on backgrounding.
    static func configuration(for backend: GADConfiguration) -> BlueiotBindingConfiguration {
        BlueiotBindingConfiguration(
            relayURL: backend.relayAPI,
            appToken: backend.relayAPIAppToken,
            runsInBackground: true
        )
    }

    /// `true` while a session is active. A bind in progress does not change it.
    var isActive: Bool { state?.session != nil }

    /// The notice for an ended session, or `nil` while none has ended.
    var endNotice: String? {
        if case .ended(let reason) = state { return WristbandCopy.notice(for: reason) }
        return nil
    }

    /// Follows the binding state and confirms a stored session with the relay-api. Call
    /// once at launch; returns when the calling task is cancelled.
    ///
    /// With `FieldLog.isEnabled` it logs each state with the session and the binding
    /// diagnostics, and the diagnostics every 10 s while a session is active.
    func run() async {
        let binding = binding
        Task { _ = await binding.restore() }
        let diagnosticsLog: Task<Void, Never>? = FieldLog.isEnabled ? Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let isActive = self?.isActive else { return }
                if isActive {
                    let diagnostics = await binding.diagnostics
                    FieldLog.log("binding diagnostics: \(BindingLog.diagnostics(diagnostics))")
                }
            }
        } : nil
        defer { diagnosticsLog?.cancel() }
        for await state in binding.stateChanges() {
            self.state = state
            onStateChange?(state)
            await forwardPrivacy()
            if FieldLog.isEnabled {
                FieldLog.log("wristband: \(WristbandCopy.logLine(for: state))")
                if let session = BindingLog.session(of: state) { FieldLog.log("wristband session: \(session)") }
                let diagnostics = await binding.diagnostics
                FieldLog.log("binding diagnostics: \(BindingLog.diagnostics(diagnostics))")
            }
        }
    }

    /// Passes the relay's privacy signal of every binding state to `sdk`
    /// (`setPositioningSourcePrivate(since:)`, SDK 6.0.0-beta.64), starting with the current state.
    /// The SDK cannot see the binding itself: a band without venue coverage in a restroom falls
    /// silent at the door, and only the relay knows that it is in a privacy zone.
    func forwardPrivacy(to sdk: Proximiio) async {
        privacySDK = sdk
        forwardedPrivateSince = nil
        await forwardPrivacy()
    }

    private func forwardPrivacy() async {
        guard let sdk = privacySDK else { return }
        let since = Self.privateSince(of: state)
        guard forwardedPrivateSince != .some(since) else { return }
        forwardedPrivateSince = .some(since)
        FieldLog.log("wristband privacy: \(since.map { "private since \($0.formatted(.iso8601))" } ?? "not private")")
        await sdk.setPositioningSourcePrivate(since: since)
    }

    /// When the relay saw the band fall silent in a privacy zone, or `nil`. Pure; covered by tests.
    nonisolated static func privateSince(of state: BlueiotBindingState?) -> Date? {
        if case let .active(_, _, .privacyZone(since)) = state { return since }
        return nil
    }

    /// Ends the visit on the relay-api. The state becomes `.ended(.userEnded)`.
    /// - Throws: `BlueiotBindingError` when the relay-api cannot be reached; the session
    ///   is kept.
    func end() async throws {
        try await binding.end()
    }
}

extension WristbandSession: WristbandConnecting {
    /// What to ask for before a bind, or `nil` when nothing can or needs to be asked. A
    /// denied permission returns `nil`: iOS shows no second dialog, and the bind is sent
    /// without a location.
    func locationAsk() async -> WristbandLocationAsk? {
        switch await binding.locationReadiness() {
        case .permissionNeeded: return location.canAskForPermission ? .permission : nil
        case .preciseLocationNeeded: return .preciseLocation
        case .ready, .notRequired: return nil
        @unknown default: return nil
        }
    }

    /// Shows the iOS dialog for `ask` and returns when it is answered.
    func ask(_ ask: WristbandLocationAsk) async {
        switch ask {
        case .permission: await location.requestWhenInUse()
        case .preciseLocation: await location.requestFullAccuracy()
        }
    }

    /// Binds this phone to the band with `label`, as scanned or typed. The relay-api
    /// resolves every label format. The new session replaces any current one.
    /// - Throws: `BlueiotBindingError`.
    func bind(_ label: String) async throws {
        do {
            let session = try await binding.bind(tagID: label)
            FieldLog.log("wristband bind: \(BindingLog.bind(label: label, bindingID: session.bindingID))")
        } catch {
            FieldLog.log("wristband bind: \(BindingLog.bind(label: label, error: error))")
            throw error
        }
    }
}

/// The two location dialogs a bind can need. CoreLocation reports the answer to a
/// delegate; this class turns it into an `await`.
@MainActor
final class LocationAccess: NSObject, CLLocationManagerDelegate {

    /// The key in `NSLocationTemporaryUsageDescriptionDictionary` (`project.yml`).
    static let purposeKey = "WristbandTakeover"

    private let manager = CLLocationManager()
    private var answer: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// `true` while authorization is undetermined: iOS shows its dialog once.
    var canAskForPermission: Bool { manager.authorizationStatus == .notDetermined }

    /// Asks for "While Using the App" and returns when the visitor answers.
    func requestWhenInUse() async {
        guard canAskForPermission, answer == nil else { return }
        await withCheckedContinuation { continuation in
            answer = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Asks for full accuracy until the app leaves the foreground. Returns at once when
    /// full accuracy is already granted.
    func requestFullAccuracy() async {
        guard manager.accuracyAuthorization == .reducedAccuracy else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.purposeKey) { _ in
                continuation.resume()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.resumeIfAnswered() }
    }

    private func resumeIfAnswered() {
        guard manager.authorizationStatus != .notDetermined, let answer else { return }
        self.answer = nil
        answer.resume()
    }
}
