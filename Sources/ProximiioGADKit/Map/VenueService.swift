//
//  VenueService.swift
//  ProximiioGADKit
//
//  Starts the Proximi.io SDK against the host app's backend and attaches the wristband
//  binding's position provider.
//
//  Positions come from the venue's BlueIoT anchors through the relay-api; the phone scans
//  nothing (`relayOnly`). Follows proximiio-blueiot-minimal-ios `Venue`, with one
//  difference: the API host comes from `GADConfiguration`, so a production build reaches
//  only the client's on-prem install.
//
import Foundation
import Proximiio
import ProximiioMap
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

@MainActor
public final class VenueService {
    public let sdk: Proximiio
    /// Times and distances of the screens, from `GADConfiguration.settings`. A screen reads them
    /// when it opens, so a change applies to the next one.
    public var settings: GADSettings
    /// The binding client whose provider delivers the wristband's positions.
    private let binding: BlueiotWristbandBinding
    /// Name of the attached position provider. Providers are detached by name.
    private var attachedProvider: String?
    /// Writes the attached binding provider's samples to `FieldLog`.
    private var sampleLog: Task<Void, Never>?

    private init(sdk: Proximiio, binding: BlueiotWristbandBinding, settings: GADSettings) {
        self.sdk = sdk
        self.settings = settings
        self.binding = binding
    }

    /// The SDK configuration for `backend`. Separate from `start` so tests can check it.
    public static func configuration(for backend: GADConfiguration) -> ProximiioConfiguration {
        var configuration = ProximiioConfiguration.relayOnly(
            token: backend.applicationToken,
            runsInBackground: true
        )
        configuration.apiBaseURL = backend.apiBaseURL
        // No fallback hosts: a production build must not fall back to *.proximi.fi.
        configuration.fallbackAPIBaseURLs = []
        // Visitor reporting: `PUT /core/visitors`, then positions in batches every 60 s
        // (`/core/positions/batch`) and each geofence enter and exit event as it happens
        // (`/core/events`) to `apiBaseURL`. Events that could not be sent wait on the device and go
        // out in a batch (`/core/events/batch`) once the network is back. The client requires no
        // visitor consent for it (2026-10-14), so it is on in every build. It is the SDK default
        // since 6.0.0-beta.58; it is set here so a later default does not turn it off.
        configuration.visitorReportingEnabled = true
        return configuration
    }

    /// Requests location authorization, authenticates, starts positioning, loads the
    /// route network and attaches the binding's position provider. The order matters; see
    /// proximiio-blueiot-minimal-ios `Venue.start`.
    ///
    /// The provider is attached once. It follows whichever session `binding` holds, so a
    /// bind, a take-over or an ended visit needs no re-attach.
    public static func start(configuration backend: GADConfiguration, binding: BlueiotWristbandBinding) async throws -> VenueService {
        let sdk = try Proximiio(configuration: configuration(for: backend))
        _ = await sdk.requestPermissions()
        _ = try await sdk.authenticate()
        try await sdk.start()
        _ = try await sdk.loadRouteNetwork()
        let venue = VenueService(sdk: sdk, binding: binding, settings: backend.settings)
        await venue.attachBinding()
        venue.cacheMapStyle()
        if FieldLog.isEnabled {
            // The visitor id finds this phone's visitor, positions and events on the backend.
            let consent = await sdk.visitorReportingConsent
            let visitorID = await sdk.visitorId
            FieldLog.log("visitor reporting \(consent ? "on" : "off") · visitor \(visitorID) · \(backend.apiBaseURL.absoluteString)")
            // The visitor reporting client logs registration and upload failures to os.Logger only.
            // It logs no successful upload. `syncFailed` also arrives after repeated failures.
            Task.detached { await FieldLog.copyOSLogEntries(subsystem: "io.proximi.sdk", category: "Reporting") }
            Task {
                for await event in await sdk.syncEvents() {
                    switch event {
                    case .syncFailed, .syncCompleted: FieldLog.log("sync: \(event)")
                    default: break
                    }
                }
            }
        }
        return venue
    }

    /// Fetches the organisation's map style in the background. The map library writes it to
    /// Caches, and a map screen opened later starts on it instead of an empty style. Without it,
    /// the first map screen after an install fetches the style while it is on screen.
    private func cacheMapStyle() {
        let sdk = sdk
        Task {
            do {
                _ = try await VenueStyle.load(from: sdk)
                FieldLog.log("map style cached")
            } catch {
                FieldLog.log("map style not cached: \(error.localizedDescription)")
            }
        }
    }

    /// Attaches the binding's position provider in place of the attached provider. A
    /// re-attach stops and starts the provider, which reopens its relay-api stream. In
    /// Debug builds it also ends journey playback.
    public func attachBinding() async {
        await detachProvider()
        let provider = binding.positionProvider
        attachedProvider = provider.name
        await sdk.attachPositionProvider(provider)
        if FieldLog.isEnabled { logSamples(of: provider) }
    }

    /// Logs every sample of `provider`: the relay-api positions before the SDK engine processes
    /// them. The binding has already dropped repeated positions. `age` is the relay-api
    /// `server_time − ts` plus the time until the line is written. Network transit is not in it.
    private func logSamples(of provider: any CustomPositionProviding) {
        let samples = provider.samples()
        let sdk = sdk
        sampleLog = Task {
            let levels = Dictionary(await sdk.floors().map { ($0.id, Int($0.level)) }) { first, _ in first }
            for await sample in samples {
                let floor = sample.floorID.map { levels[$0].map(String.init) ?? $0 } ?? "-"
                FieldLog.log(String(format: "relay %.6f,%.6f L%@ acc %.1f age %.2f",
                                    sample.coordinate.latitude, sample.coordinate.longitude, floor,
                                    sample.horizontalAccuracy, Date().timeIntervalSince(sample.timestamp)))
            }
        }
    }

    #if DEBUG
    /// Debug builds only. Replaces the attached provider with playback of a journey
    /// stored on Proximi.io. Positions are generated on the phone. `attachBinding()`
    /// ends the playback.
    public func playJourney(id: String, speed: Double, loops: Bool) async throws {
        let journey = try await sdk.fetchJourney(id: id)
        if let failure = journey.validationFailure() {
            throw JourneyNotPlayable(reason: String(describing: failure))
        }
        await detachProvider()
        let provider = JourneyPlaybackProvider(
            journey: journey,
            configuration: JourneyPlaybackConfiguration(speed: speed, loops: loops, runsInBackground: true)
        )
        attachedProvider = provider.name
        await sdk.attachPositionProvider(provider)
    }

    struct JourneyNotPlayable: LocalizedError {
        let reason: String
        var errorDescription: String? { "Journey cannot be played: \(reason)" }
    }
    #endif

    private func detachProvider() async {
        sampleLog?.cancel()
        sampleLog = nil
        guard let attachedProvider else { return }
        await sdk.detachPositionProvider(named: attachedProvider)
        self.attachedProvider = nil
    }
}
