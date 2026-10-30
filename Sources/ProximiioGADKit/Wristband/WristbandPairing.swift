//
//  WristbandPairing.swift
//  ProximiioGADKit
//
//  State of the "Connect your wristband" flow (Figma section "Wristband", node 9330:83108).
//
//  Steps: intro → scan the QR code or enter the code → looking for the wristband →
//  connected, or failed. A wristband counts as connected when the relay-api accepts the
//  bind. The scanned payload or typed code goes to the relay-api unparsed; the relay-api
//  resolves every label format.
//
import Combine
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

/// Binds the phone to a wristband. `WristbandSession` in the app; a fake in tests and in
/// the Debug pairing demo.
@MainActor
@_spi(GADApp) public protocol WristbandConnecting: AnyObject {
    /// What to ask for before a bind, or `nil` when nothing can or needs to be asked.
    func locationAsk() async -> WristbandLocationAsk?
    /// Shows the iOS dialog for `ask` and returns when it is answered.
    func ask(_ ask: WristbandLocationAsk) async
    /// Binds the phone to the band with `label`. Returns when the session is active.
    /// - Throws: `BlueiotBindingError`.
    func bind(_ label: String) async throws
}

extension WristbandConnecting {
    /// Binds the phone to the wristband with `code`: a scanned QR payload or the code printed on
    /// the wristband. Surrounding whitespace is trimmed; the relay-api resolves every label
    /// format. When the relay-api needs the phone's location for a take-over, the iOS dialog for
    /// it comes first. Returns when the session is active. The session replaces any current one.
    /// - Throws: `BlueiotBindingError`, `.invalidTagID` for an empty code.
    ///   `WristbandCopy.message(for:)` is the text for the visitor.
    @_spi(GADApp) public func connect(code: String) async throws {
        let label = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw BlueiotBindingError.invalidTagID(requestID: nil) }
        if let ask = await locationAsk() {
            await self.ask(ask)
        }
        try await bind(label)
    }
}

@MainActor
@_spi(GADApp) public final class WristbandPairing: ObservableObject, Identifiable {
    public enum Step: Equatable {
        /// "Connect your wristband" with "Scan QR code" and "Skip for now".
        case intro
        /// Camera scanner for the QR code on the back of the wristband.
        case scanning
        /// Text field for the code printed on the wristband.
        case manualEntry
        /// "Looking for your wristband": the bind request is in flight.
        case looking(String)
        /// "Wristband connected!".
        case connected(String)
        /// "We couldn't connect your wristband" with the message for the error.
        /// `attempts` selects the first or the repeated-failure variant of the screen.
        case failed(String, message: String, attempts: Int)
        /// "Camera permission denied".
        case cameraDenied
    }

    @Published private(set) var step: Step = .intro
    @Published private(set) var failedAttempts = 0
    /// Message under the code field: an empty code, or a code the relay-api rejected.
    @Published private(set) var invalidCodeMessage: String?
    /// The last typed code. Fills the field when the entry screen is shown again.
    @Published private(set) var enteredCode = ""

    private let connector: WristbandConnecting

    public init(connector: WristbandConnecting) {
        self.connector = connector
    }

    func startScanning() {
        invalidCodeMessage = nil
        step = .scanning
    }

    func enterCodeManually() {
        invalidCodeMessage = nil
        step = .manualEntry
    }

    func cancelScanning() {
        step = .intro
    }

    func cameraAccessDenied() {
        step = .cameraDenied
    }

    /// Binds the band with a scanned QR payload or a typed code. Surrounding whitespace is
    /// trimmed; the rest goes to the relay-api as is.
    func submit(code: String) async {
        let label = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTyped = step == .manualEntry
        if isTyped { enteredCode = label }
        guard !label.isEmpty else {
            invalidCodeMessage = String(localized: "Enter the code printed on the wristband.", bundle: .localized)
            return
        }
        invalidCodeMessage = nil
        await connect(label, isTyped: isTyped)
    }

    func retry() async {
        guard case .failed(let label, _, _) = step else { return }
        await connect(label, isTyped: false)
    }

    private func connect(_ label: String, isTyped: Bool) async {
        step = .looking(label)
        do {
            try await connector.connect(code: label)
            failedAttempts = 0
            step = .connected(label)
        } catch {
            // A typed code the relay-api does not know goes back to the field.
            if isTyped, case .invalidTagID? = error as? BlueiotBindingError {
                invalidCodeMessage = WristbandCopy.message(for: error)
                step = .manualEntry
                return
            }
            failedAttempts += 1
            step = .failed(label, message: WristbandCopy.message(for: error), attempts: failedAttempts)
        }
    }
}
