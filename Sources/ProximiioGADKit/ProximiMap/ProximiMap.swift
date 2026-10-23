//
//  ProximiMap.swift
//  ProximiioGADKit
//
//  The package's entry point for a host app that leaves the SDK to the package (Nagarro, 2026-10-16:
//  "a single exposed wrapper component that encapsulates all internal UI components and logic").
//  `ProximiMapView` is the journey screen alone, on the host app's SDK.
//
//  The host app creates one `ProximiMap`, starts it, attaches `.proximiMap(_:)` to a view that is
//  on screen, opens screens with `open(_:)` and receives `events`. `ProximiMap` owns the SDK, the
//  wristband session, the geofence notifications, the stored journey and every screen and sheet of
//  the package. The host app scans the wristband's QR code itself and passes the code to
//  `connectWristband(code:)`.
//
import CoreLocation
import Foundation
import Observation
import Proximiio
import ProximiioMap
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

@MainActor
@Observable
public final class ProximiMap {
    /// The screens and sheets `open(_:)` shows.
    public enum Screen: String, Equatable, Sendable, CaseIterable {
        /// The museum map with the gallery legend, search and routes to amenities.
        case museumMap
        /// Journey ready (02.10A): the journey's title, "Start the Journey" at the museum, "Go to
        /// Museum" away from it. "Start the Journey" opens `journey`.
        case journeyReady
        /// The journey: map and list, guidance from stop to stop, Journey Complete.
        case journey
        /// The stop picker for a personalised journey ("Plan your visit"). "Start" stores the
        /// journey and opens `journeyReady`.
        case planJourney
        /// Manage journey (02.11): edit the stops, craft a new journey, delete the journey.
        case manageJourney
    }

    public enum Status: Equatable, Sendable {
        case idle
        case starting
        case ready
        case failed(ProximiMapError)
    }

    public let configuration: GADConfiguration
    public private(set) var status: Status = .idle
    /// The stored journey, or `nil`. It survives app launches.
    public private(set) var journey: JourneySummary?
    /// The accessibility needs for routes, on top of the accessible routes button the visitor can
    /// turn on.
    public var routeAccessibility: RouteAccessibility = .none

    /// `true` once the visitor is at the museum (`ProximiMapEvent.arrivedAtMuseum`).
    public var isAtMuseum: Bool { arrival.isAtMuseum }
    /// `true` when the visitor denied location for the app. The package needs it for the arrival and
    /// for a wristband take-over; the host app can show its own "Location is required" screen.
    public var isLocationDenied: Bool {
        arrival.authorization == .denied || arrival.authorization == .restricted
    }
    public var wristband: WristbandStatus { Self.wristbandStatus(of: session.state) }
    /// The screen or sheet on screen, or `nil`.
    public var screen: Screen? { sheetScreen ?? coverScreen }

    // Internal state, read by `ProximiMapPresenter`.

    enum Cover: String, Identifiable {
        case museumMap, ready, visit
        #if DEBUG
        /// `-hostedMap`: the visit in `ProximiMapView`.
        case hosted
        #endif
        var id: String { rawValue }
    }

    enum Sheet: String, Identifiable {
        case planJourney, manageJourney
        var id: String { rawValue }
    }

    var cover: Cover?
    var sheet: Sheet?
    private(set) var venue: VenueService?
    private(set) var places: [VenuePlace] = []
    private(set) var galleries: [Gallery] = []
    let session: WristbandSession
    let arrival = ArrivalDetector()

    @ObservationIgnored private var coverScreen: Screen?
    @ObservationIgnored private var sheetScreen: Screen?
    /// Runs when the cover or sheet on screen has been dismissed: the next one. Presenting while a
    /// presentation is still dismissing can fail and keep its state set with nothing on screen
    /// (Monday "UI gets stuck", 2026-10-15).
    @ObservationIgnored private var afterDismiss: (() -> Void)?
    @ObservationIgnored private var continuations: [UUID: AsyncStream<ProximiMapEvent>.Continuation] = [:]
    @ObservationIgnored private var startTask: Task<Void, Error>?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let notifier = GeofenceNotifier()
    @ObservationIgnored private var lastWristband: WristbandStatus?
    #if DEBUG
    /// `-hostedMap`: the journey of the `ProximiMapView` the debug launch opens.
    var hostedJourney = ProximiJourney(stops: [])
    #endif

    public init(configuration: GADConfiguration) {
        self.configuration = configuration
        session = WristbandSession(configuration: configuration)
        journey = Self.summary(of: VisitStore.load(), meta: VisitStore.loadMeta())
        arrival.onArrival = { [weak self] in
            FieldLog.log("map: at the museum")
            self?.emit(.arrivedAtMuseum)
        }
        session.onStateChange = { [weak self] _ in self?.wristbandStateChanged() }
        #if DEBUG
        if DebugLaunch.current.routeAccessibility != .none {
            routeAccessibility = DebugLaunch.current.routeAccessibility
        }
        #endif
    }

    /// Every `ProximiMapEvent` from now on. Each call returns a new stream; a stream ends when its
    /// task is cancelled.
    public var events: AsyncStream<ProximiMapEvent> {
        let (stream, continuation) = AsyncStream<ProximiMapEvent>.makeStream(bufferingPolicy: .bufferingNewest(100))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    // MARK: Start

    /// Starts the SDK, the wristband session and the geofence notifications, and loads the venue.
    /// Asks for "While Using the App" location. A second call while starting waits for the first;
    /// after a failure it starts again.
    /// - Throws: `ProximiMapError.startFailed`.
    public func start() async throws {
        if status == .ready { return }
        if let startTask {
            try await startTask.value
            return
        }
        let task = Task { try await self.performStart() }
        startTask = task
        do {
            try await task.value
        } catch {
            startTask = nil
            throw error
        }
    }

    private func performStart() async throws {
        status = .starting
        runSession()
        do {
            let venue = try await VenueService.start(configuration: configuration, binding: session.binding)
            self.venue = venue
            await session.forwardPrivacy(to: venue.sdk)
            await loadPlaces(from: venue)
            reconcileStoredJourney()
            arrival.check(places: places)
            venue.data.onChange = { [weak self] in
                Task { await self?.venueDataChanged() }
            }
            tasks.append(Task { [weak self] in
                // One position from the wristband or playback means the visitor is inside.
                for await _ in await venue.sdk.positions() {
                    self?.arrival.positionReceived()
                    return
                }
            })
            tasks.append(Task { [weak self] in
                for await event in await venue.sdk.geofenceEvents() {
                    guard let self else { return }
                    if let mapped = Self.event(for: event) { self.emit(mapped) }
                }
            })
            if configuration.settings.postsGeofenceNotifications {
                tasks.append(Task { [notifier] in await notifier.run(sdk: venue.sdk) })
            }
            status = .ready
            FieldLog.log("map: ready · \(places.count) places")
            #if DEBUG
            await runDebugLaunch(venue: venue)
            #endif
        } catch {
            FieldLog.log("map: start failed: \(error)")
            let failure = ProximiMapError.startFailed(String(describing: error))
            status = .failed(failure)
            throw failure
        }
    }

    private func loadPlaces(from venue: VenueService) async {
        let features = await venue.sdk.features()
        places = VenuePlace.all(in: features)
        galleries = await Gallery.load(from: venue.sdk, features: features, places: places)
    }

    /// The venue data changed on the backend.
    private func venueDataChanged() async {
        guard let venue else { return }
        await loadPlaces(from: venue)
        reconcileStoredJourney()
    }

    /// Follows the wristband session for the life of the object: confirms a session stored by the
    /// SDK with the relay-api and follows the binding state.
    private func runSession() {
        guard sessionTask == nil else { return }
        sessionTask = Task { [session] in await session.run() }
    }

    // MARK: Wristband

    /// Connects the phone to the wristband with `code`: the scanned QR payload or the code printed on
    /// the wristband. The relay-api resolves every label format. When the relay-api needs the phone's
    /// location for a take-over, the iOS dialog for it comes first. Returns when the session is
    /// active; it replaces any current one.
    /// - Throws: `ProximiMapError.wristband` with the text for the visitor.
    public func connectWristband(code: String) async throws {
        runSession()
        do {
            try await session.connect(code: code)
        } catch {
            FieldLog.log("map: wristband not connected: \(error)")
            throw ProximiMapError.wristband(WristbandCopy.message(for: error))
        }
    }

    /// Ends the wristband session on the relay-api, for example when the visitor returns the
    /// wristband. `wristband` becomes `.notConnected`.
    /// - Throws: `ProximiMapError.wristband` when the relay-api cannot be reached; the session is
    ///   kept.
    public func endVisit() async throws {
        do {
            try await session.end()
        } catch {
            throw ProximiMapError.wristband(WristbandCopy.message(for: error))
        }
    }

    private func wristbandStateChanged() {
        let status = wristband
        guard status != lastWristband else { return }
        lastWristband = status
        emit(.wristbandChanged(status))
        if status == .connected, configuration.settings.postsGeofenceNotifications {
            Task { [notifier] in await notifier.requestAuthorization() }
        }
    }

    // MARK: Journey

    /// Stores a journey; it replaces the stored one. Opens nothing: open `journeyReady` or `journey`.
    /// - Returns: The stored journey.
    /// - Throws: `ProximiMapError.notStarted` before `start()` has finished,
    ///   `.noKnownArtworks` when no artwork of `plan` is a POI of the venue.
    @discardableResult
    public func setJourney(_ plan: JourneyPlan) throws -> JourneySummary {
        guard status == .ready else { throw ProximiMapError.notStarted }
        let ids = Self.poiIDs(for: plan.artworks, in: places)
        guard !ids.isEmpty else { throw ProximiMapError.noKnownArtworks }
        let journey = VisitPlan.journey(poiIDs: ids, places: places, galleries: galleries)
        let meta = VisitMeta(
            title: plan.title,
            summary: plan.summary ?? String(localized: "\(journey.stops.count) stops", bundle: .module),
            kind: plan.kind
        )
        store(journey, meta: meta)
        FieldLog.log("map: journey \(plan.kind.rawValue) · \(ids.count) of \(plan.artworks.count) artworks")
        return Self.summary(of: journey, meta: meta)!
    }

    /// Deletes the stored journey.
    public func deleteJourney() {
        store(nil, meta: nil)
    }

    private func store(_ journey: Journey?, meta: VisitMeta?) {
        VisitStore.save(journey)
        VisitStore.saveMeta(meta)
        refreshJourney()
    }

    /// Updates the stored journey with the current places (`VisitPlan.reconciled`). While the journey
    /// screen is open, the screen updates its journey and stores it.
    private func reconcileStoredJourney() {
        guard coverScreen != .journey, let stored = VisitStore.load() else { return }
        let journey = VisitPlan.reconciled(stored, places: places, galleries: galleries)
        guard journey != stored else { return }
        FieldLog.log("map: stored journey updated · \(stored.stops.count) → \(journey.stops.count) stops")
        VisitStore.save(journey)
        if journey.stops.isEmpty { VisitStore.saveMeta(nil) }
        refreshJourney()
    }

    /// Reads the stored journey again; the journey screen updates it as the visitor walks.
    private func refreshJourney() {
        let summary = Self.summary(of: VisitStore.load(), meta: VisitStore.loadMeta())
        guard summary != journey else { return }
        journey = summary
        emit(.journeyChanged(summary))
    }

    // MARK: Screens

    /// Shows `screen` over the view with `.proximiMap(_:)`. A screen already on screen closes first.
    /// Nothing opens before `start()` has finished, and `journeyReady`, `journey` and
    /// `manageJourney` open only with a stored journey.
    ///
    /// Call it after a sheet of the host app has been dismissed (its `onDismiss`): presenting while
    /// another presentation is dismissing can fail.
    public func open(_ screen: Screen) {
        guard status == .ready else {
            FieldLog.log("map: open \(screen.rawValue) before the start")
            return
        }
        switch screen {
        case .journeyReady, .journey, .manageJourney:
            guard VisitStore.load() != nil else {
                FieldLog.log("map: open \(screen.rawValue) without a journey")
                return
            }
        case .museumMap, .planJourney:
            break
        }
        FieldLog.log("map: open \(screen.rawValue) · on screen \(self.screen?.rawValue ?? "-")")
        replace { [weak self] in self?.show(screen) }
    }

    /// Closes the screen or sheet on screen.
    public func close() {
        afterDismiss = nil
        cover = nil
        sheet = nil
    }

    private func show(_ screen: Screen) {
        switch screen {
        case .museumMap: cover = .museumMap
        case .journeyReady: cover = .ready
        case .journey: cover = .visit
        case .planJourney: sheet = .planJourney
        case .manageJourney: sheet = .manageJourney
        }
        switch screen {
        case .planJourney, .manageJourney: sheetScreen = screen
        case .museumMap, .journeyReady, .journey: coverScreen = screen
        }
        emit(.opened(screen))
    }

    /// Runs `next` now, or after the cover or sheet on screen has been dismissed. A presentation that
    /// is set but never reached the screen gets no `onDismiss`, so `next` also runs after 0.7 s.
    private func replace(then next: @escaping () -> Void) {
        guard cover != nil || sheet != nil else { return next() }
        let token = UUID()
        pendingToken = token
        afterDismiss = next
        cover = nil
        sheet = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.pendingToken == token, let next = self.afterDismiss else { return }
            FieldLog.log("map: no dismissal after 0.7 s")
            self.afterDismiss = nil
            self.coverScreen = nil
            self.sheetScreen = nil
            next()
        }
    }

    @ObservationIgnored private var pendingToken: UUID?

    // Called by `ProximiMapPresenter`.

    func coverDismissed() {
        if let screen = coverScreen { emit(.closed(screen)) }
        coverScreen = nil
        reconcileStoredJourney()
        refreshJourney()
        runAfterDismiss()
    }

    func sheetDismissed() {
        if let screen = sheetScreen { emit(.closed(screen)) }
        sheetScreen = nil
        runAfterDismiss()
    }

    private func runAfterDismiss() {
        let next = afterDismiss
        afterDismiss = nil
        pendingToken = nil
        next?()
    }

    /// Journey ready → "Start the Journey".
    func visitStarted() {
        coverScreen = .journey
        emit(.opened(.journey))
    }

    /// "Start" in the stop picker: stores the personalised journey and opens Journey ready.
    func planned(poiIDs: [String]) {
        let journey = VisitPlan.journey(poiIDs: poiIDs, places: places, galleries: galleries)
        store(journey, meta: .standard(stopCount: journey.stops.count))
        afterDismiss = { [weak self] in self?.show(.journeyReady) }
        sheet = nil
    }

    /// Manage journey → "Edit stops": the stop picker, or the host app's tour choice for a curated
    /// tour.
    func editJourney() {
        if journey?.kind == .curated {
            afterDismiss = { [weak self] in self?.emit(.curatedTourChangeRequested) }
        } else {
            afterDismiss = { [weak self] in self?.show(.planJourney) }
        }
        sheet = nil
    }

    /// Manage journey → "Craft a new journey".
    func craftNewJourney() {
        afterDismiss = { [weak self] in self?.emit(.craftNewJourneyRequested) }
        sheet = nil
    }

    // MARK: Events

    func handle(_ event: VisitEvent) {
        FieldLog.log("visit event: \(event)")
        guard let mapped = Self.event(for: event, places: places) else { return }
        emit(mapped)
    }

    private func emit(_ event: ProximiMapEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    // MARK: Debug launch

    #if DEBUG
    /// Runs the launch arguments of `DebugLaunch` after the start: journey playback, a wristband
    /// bind, `-openMap` and `-visit`.
    private func runDebugLaunch(venue: VenueService) async {
        let launch = DebugLaunch.current
        await launch.run(with: venue, wristband: session)
        if launch.openMap { open(.museumMap) }
        let ids = launch.visitStops.compactMap { VenuePlace.matching($0, in: places).first?.id }
        if launch.hostedMap {
            // Without `-visit` the view shows the map alone.
            DebugLaunch.log("hosted map: \(ids.count) stops")
            hostedJourney = ProximiJourney(kind: launch.visitKind, artworks: ids)
            cover = .hosted
            return
        }
        guard !ids.isEmpty else { return }
        DebugLaunch.log("visit: \(ids.count) stops")
        let journey = VisitPlan.journey(poiIDs: ids, places: places, galleries: galleries)
        store(journey, meta: .standard(stopCount: journey.stops.count, kind: launch.visitKind))
        open(.journey)
    }
    #endif
}

// MARK: - Pure rules

extension ProximiMap {
    /// The POI ids of `artworks`: each id is a POI id or an artwork's collection id (`remote_id`).
    /// Ids that match no place are left out. Pure; covered by tests.
    nonisolated static func poiIDs(for artworks: [String], in places: [VenuePlace]) -> [String] {
        let byID = Set(places.map(\.id))
        var byRemoteID: [String: String] = [:]
        for place in places {
            if let remoteID = place.remoteID, byRemoteID[remoteID] == nil { byRemoteID[remoteID] = place.id }
        }
        return artworks.compactMap { id in byID.contains(id) ? id : byRemoteID[id] }
    }

    /// The summary of a stored journey, or `nil` without one. Pure; covered by tests.
    nonisolated static func summary(of journey: Journey?, meta: VisitMeta?) -> JourneySummary? {
        guard let journey else { return nil }
        let meta = meta ?? .standard(stopCount: VisitPlan.artworks(in: journey).count)
        return JourneySummary(
            title: meta.title,
            summary: meta.summary,
            kind: meta.kind,
            stopCount: VisitPlan.artworks(in: journey).count,
            remainingStopCount: VisitPlan.remainingStopCount(in: journey),
            isStarted: journey.stops.contains { $0.state != .pending }
        )
    }

    /// The wristband status for a binding state. Pure; covered by tests.
    nonisolated static func wristbandStatus(of state: BlueiotBindingState?) -> WristbandStatus {
        switch state {
        case .active?: .connected
        case .binding?: .connecting
        case .ended(let reason)?: .notConnected(notice: WristbandCopy.notice(for: reason))
        case .unbound?, nil: .notConnected(notice: nil)
        @unknown default: .notConnected(notice: nil)
        }
    }

    /// The host event for a geofence enter or exit of the SDK, or `nil` for another event. Pure;
    /// covered by tests.
    nonisolated static func event(for event: GeofenceEvent) -> ProximiMapEvent? {
        func geofence(_ geofence: ProximiioGeofence) -> ProximiGeofence {
            ProximiGeofence(
                id: geofence.id,
                name: geofence.name,
                type: geofence.metadata?["geofence_type"]?.stringValue,
                artworkID: geofence.isArtwork ? geofence.remoteId : nil
            )
        }
        switch event {
        case .entered(let entered): return .geofenceEntered(geofence(entered))
        case .exited(let exited, _): return .geofenceExited(geofence(exited))
        default: return nil
        }
    }

    /// The host event for a `VisitEvent`, or `nil` for a navigator event the host app does not get.
    /// Pure; covered by tests.
    nonisolated static func event(for event: VisitEvent, places: [VenuePlace]) -> ProximiMapEvent? {
        func stop(_ stop: JourneyStop) -> ProximiStop {
            let id = stop.poiID ?? stop.id
            return ProximiStop(
                id: id,
                title: stop.title,
                artworkID: places.first { $0.id == id }?.remoteID,
                level: stop.floor.map { Int($0.level.rounded()) }
            )
        }
        func place(_ place: VenuePlace) -> ProximiStop {
            ProximiStop(id: place.id, title: place.title, artworkID: place.isArtwork ? place.remoteID : nil, level: Int(place.level.rounded()))
        }
        switch event {
        case .modeChanged(let mode): return .modeChanged(mode)
        case .skipRequested(let s): return .skipRequested(stop(s))
        case .stopSkipped(let s): return .stopSkipped(stop(s))
        case .skipCancelled(let s): return .skipCancelled(stop(s))
        case .skipUndone(let s): return .skipUndone(stop(s))
        case .amenitySelected(let p): return .amenitySelected(place(p))
        case .detourStarted(let p): return .detourStarted(place(p))
        case .journeyResumed: return .journeyResumed
        case .recentred: return .recentred
        case .accessibleRoutesChanged(let on): return .accessibleRoutesChanged(on)
        case .exitRequested: return .exitRequested
        case .exitConfirmed: return .exitConfirmed
        case .exitCancelled: return .exitCancelled
        case .stopNearby(let s): return .stopNearby(stop(s))
        case .positionUncertain(let s): return .positionUncertain(stop(s))
        case .stopPlaceDeleted(let s): return .stopPlaceDeleted(stop(s))
        case .artworkReached(let s): return .artworkReached(stop(s))
        case .artworkVisitedOutOfOrder(let s): return .artworkVisitedOutOfOrder(stop(s))
        case .trackingChanged(let health): return .trackingChanged(health)
        case .floorWithoutPositioningEntered(let level): return .floorWithoutPositioningEntered(level: level)
        case .floorWithoutPositioningLeft(let level): return .floorWithoutPositioningLeft(level: level)
        case .journey(let journeyEvent):
            switch journeyEvent {
            case .legChanged(let to, _): return .nextStop(stop(to))
            case .detourEnded(let s, let completed): return .detourEnded(stop(s), completed: completed)
            case .offRouteTooLong(let duration): return .offRoute(duration: duration)
            case .returnedToRoute: return .backOnRoute
            case .journeyFinished: return .journeyFinished
            default: return nil
            }
        }
    }
}

// MARK: - The Guggenheim app

extension ProximiMap {
    /// The wristband pairing flow of the GAD app (`WristbandPairingView`). Host apps scan the QR code
    /// themselves and call `connectWristband(code:)`.
    @_spi(GADApp) public func makeWristbandPairing() -> WristbandPairing {
        runSession()
        return WristbandPairing(connector: session)
    }

    /// The wristband binding's state now, then every change. The GAD app reads the relay signal from
    /// it for a test notification in Debug and Staging builds.
    @_spi(GADApp) public func wristbandBindingStates() -> AsyncStream<BlueiotBindingState> {
        session.binding.stateChanges()
    }

    /// The started SDK. `nil` until `start()` succeeds. The GAD app logs the SDK's events from it in
    /// Debug and Staging builds.
    @_spi(GADApp) public var sdk: Proximiio? { venue?.sdk }
}
