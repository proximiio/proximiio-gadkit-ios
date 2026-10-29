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
//  `hosted(sdk:settings:)` uses an SDK the host app has started (`ProximiMapView`). The host
//  app attaches the position provider; the service attaches none.
//
import Foundation
import Proximiio
import ProximiioMap
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

@MainActor
final class VenueService {
    let sdk: Proximiio
    /// Times and distances of the screens, from `GADConfiguration.settings`. A screen reads them
    /// when it opens, so a change applies to the next one.
    var settings: GADSettings
    /// The venue's features, geofences and amenities in memory, and the changes of the venue data
    /// while the app runs (`Proximiio.venueDataChanges()`). Screens read the data again on a change.
    let data: VenueDataRefresh
    /// The binding client whose provider delivers the wristband's positions. `nil` on the host
    /// app's SDK.
    private let binding: BlueiotWristbandBinding?
    /// Name of the attached position provider. Providers are detached by name.
    private var attachedProvider: String?
    /// Writes the attached binding provider's samples to `FieldLog`.
    private var sampleLog: Task<Void, Never>?

    /// The venue data of the hosted screens. The next hosted screen on the same SDK reuses it.
    private static var hostedData: VenueDataRefresh?

    private init(sdk: Proximiio, binding: BlueiotWristbandBinding?, settings: GADSettings, data: VenueDataRefresh? = nil) {
        self.sdk = sdk
        self.settings = settings
        self.binding = binding
        self.data = data ?? VenueDataRefresh(sdk: sdk)
    }

    /// The SDK configuration for `backend`. Separate from `start` so tests can check it.
    static func configuration(for backend: GADConfiguration) -> ProximiioConfiguration {
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
        configuration.geofenceExitDelay = backend.settings.geofenceExitDelay
        // In a privacy zone `positions()` yields no fix and positioning counts as available, so the
        // map holds a grey dot at the last fix before the zone (SDK 6.0.0-beta.64). The relay's
        // `private` reaches the SDK through `WristbandSession.forwardPrivacy(to:)`.
        configuration.withholdsPositionsInPrivacyZones = true
        return configuration
    }

    /// Requests location authorization, authenticates, starts positioning, loads the
    /// route network and attaches the binding's position provider. The order matters; see
    /// proximiio-blueiot-minimal-ios `Venue.start`.
    ///
    /// The provider is attached once. It follows whichever session `binding` holds, so a
    /// bind, a take-over or an ended visit needs no re-attach.
    ///
    /// Without a connection the SDK starts on the data stored on the phone when the API accepted
    /// the token on this phone before (`tokenStatus == .unverified`, SDK 6.0.0-beta.65).
    static func start(configuration backend: GADConfiguration, binding: BlueiotWristbandBinding) async throws -> VenueService {
        let sdk = try Proximiio(configuration: configuration(for: backend))
        _ = await sdk.requestPermissions()
        try await authenticateAndStart(sdk)
        let venue = VenueService(sdk: sdk, binding: binding, settings: backend.settings)
        await venue.attachBinding()
        venue.cacheMapStyle()
        await venue.data.start()
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

    /// Authenticates, starts positioning and installs the route network. Before the API has
    /// accepted the token in this run, the network comes from the stored features first; otherwise
    /// it is downloaded, and the stored features are the fallback.
    private static func authenticateAndStart(_ sdk: Proximiio) async throws {
        _ = try await sdk.authenticate()
        try await sdk.start()
        let token = await sdk.tokenStatus
        if token != .verified, await sdk.loadCachedRouteNetwork() > 0 {
            FieldLog.log("venue: started on the stored data · token \(token)")
            return
        }
        do {
            _ = try await sdk.loadRouteNetwork()
        } catch {
            guard await sdk.loadCachedRouteNetwork() > 0 else { throw error }
            FieldLog.log("venue: route network from the stored features: \(error.localizedDescription)")
        }
    }

    /// Starts the SDK again after it stopped on a refused token (`tokenStatus == .rejected`). It
    /// throws until the API accepts the token again. The binding's provider is attached again.
    func restart() async throws {
        try await Self.authenticateAndStart(sdk)
        await attachBinding()
        cacheMapStyle()
        // The stop ended the stream of the venue data changes.
        data.stop()
        await data.start()
    }

    /// A venue on the host app's started SDK. Requests no permission and attaches no position
    /// provider.
    ///
    /// The first call on an SDK installs the route network from the SDK's feature cache, or
    /// downloads it when the cache has no path, and starts reading the venue data. The later calls
    /// on the same SDK reuse the route network and the data in memory, which follows
    /// `venueDataChanges()` also while no screen is open. After the SDK stopped, which ends the
    /// stream of the changes, or when the SDK had no features, the next call starts again.
    static func hosted(sdk: Proximiio, settings: GADSettings) async -> VenueService {
        if let data = hostedData, data.sdk === sdk, data.isFollowing, await !data.features().isEmpty {
            return VenueService(sdk: sdk, binding: nil, settings: settings, data: data)
        }
        let started = ContinuousClock.now
        var paths = await sdk.loadCachedRouteNetwork()
        if paths == 0 {
            do {
                paths = try await sdk.loadRouteNetwork()
            } catch {
                FieldLog.log("hosted map: route network not loaded: \(error.localizedDescription)")
            }
        }
        FieldLog.log("hosted map: route network \(paths) paths in \(MapDiagnostics.Timing.text(MapDiagnostics.seconds(since: started)))")
        hostedData?.stop()
        let data = VenueDataRefresh(sdk: sdk)
        hostedData = data
        await data.start()
        return VenueService(sdk: sdk, binding: nil, settings: settings, data: data)
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
    func attachBinding() async {
        guard let binding else { return }
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
    func playJourney(id: String, speed: Double, loops: Bool) async throws {
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
