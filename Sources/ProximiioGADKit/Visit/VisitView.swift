//
//  VisitView.swift
//  ProximiioGADKit
//
//  The journey screen ("MAP Functionality Approach 02", node 10889:108085): the map in a
//  glass card over the map background, Map / List toggle, compass and floor buttons, the
//  stop card, and the bottom bar.
//
//  Every visitor action and every journey event is also reported to the host app as a
//  `VisitEvent` (`onVisitEvent(_:)`).
//
//  A personalised and a curated journey differ in the stop card, the list, skipping and the
//  background (`JourneyKind`).
//
//  `ProximiMapView.Options` turns the bottom bar, the background, the prompts, the journey logic
//  (`VisitController.managesProgress`) and the Live Activity on. `ProximiMap` uses all of them;
//  `ProximiMapView` none by default. A journey without stops shows the map alone.
//
import CoreLocation
import Proximiio
import ProximiioMap
import SwiftUI

struct VisitView: View {
    @Environment(\.visitEventHandler) private var emit
    @Environment(\.routeAccessibility) private var hostAccessibility
    @AppStorage(RouteAccessibility.accessibleRoutesKey) private var accessibleRoutes = false
    @State private var controller: VisitController
    @State private var mode: VisitMode = .map
    @State private var stopToSkip: JourneyStop?
    @State private var monitor: TrackingMonitor
    @State private var places: [VenuePlace] = []
    /// The search shortcuts' choice and order (`in_search`, `search_order`).
    /// The amenity shortcuts of the search, from the amenities' `in_search` and `search_order`.
    @State private var searchShortcuts: [AmenityShortcut] = []
    /// Name of the geofence (gallery) the visitor is in, from `sdk.geofenceEvents()`.
    @State private var currentGallery: String?
    @State private var liveActivity: VisitLiveActivity
    @State private var isShowingAmenities = false
    /// The amenity picked from search, shown on a card before it becomes a detour.
    @State private var selectedAmenity: VenuePlace?
    /// "Rerouting you…" shows when the journey is routed again for longer than 0.5 s.
    @State private var showsRerouting = false
    /// EC04d: the soft prompt for an uncertain position near the active stop.
    @State private var lowConfidenceStop: JourneyStop?
    /// Prompt kinds the visitor answered, and when; they stay quiet for a while.
    @State private var answeredAmbiguity: [String: Date] = [:]
    @State private var isConfirmingExit = false
    @State private var galleries: [Gallery] = []
    /// Gallery names by gallery id, for the list's headers (`Gallery.names(places:)`).
    @State private var galleryNames: [String: String] = [:]
    /// The artworks and level changers, which the map draws itself. The gallery that a leg leads to
    /// first is hidden too (gallery first).
    @State private var hiddenFeatureIDs: Set<String> = []
    /// The galleries of gallery first (`Gallery.destinations`).
    @State private var galleryDestinations: [GalleryDestination] = []
    /// The amenity icons of the venue data, by amenity id: the gallery's icon on the stop card and
    /// the gallery markers.
    @State private var amenityIcons: [String: UIImage] = [:]
    /// The lifts and stairs, for the way back from a floor without positioning.
    @State private var levelChangerPlaces: [LevelChangerPlace] = []
    /// The destination on the floor without positioning, where the way back starts.
    @State private var returnOrigin: ProximiioCoordinate?
    /// The POI of the gallery the visitor is in, which the map does not draw (PM, Monday "Navigation
    /// to a gallery", 2026-10-26).
    @State private var visitorGalleryPlaceID: String?
    /// The gallery of `galleries` the visitor is in. Its artworks and furniture show; every other
    /// gallery has a fill (PM, Monday "Artwork + furniture polygons", 2026-10-29).
    @State private var visitorGalleryID: String?
    /// The follow that starts after `GADSettings.startZoomSeconds` at `startZoom`.
    @State private var startZoomFollow: Task<Void, Never>?
    /// The last field-log line of the gallery fills.
    @State private var galleryFillLine: String?
    /// The ride whose end floor the map shows after the lift or stairs view (`holdFloor(of:)`).
    @State private var rideFloor: FloorWithoutPositioningGuide.Change?
    /// The lift or stairs view of a ride to a floor with positioning (PM, Monday "Elevator/Staircase
    /// animation", 2026-10-28: at every ride).
    @State private var ride: FloorWithoutPositioningGuide.Change?
    /// The rides whose view showed, by lift or stairs and floors: each shows once.
    @State private var shownRides: Set<String> = []
    @State private var mapLayers = JourneyMapLayers()
    @State private var isShowingWrapUp = false
    /// Set by a button in a sheet or cover that leaves the visit: `onClose` runs after that
    /// presentation is dismissed. Closing the visit while its own sheet is still dismissing can
    /// leave the screen below without taps (Monday "UI gets stuck", 2026-10-15).
    @State private var leavesAfterDismiss = false
    @State private var stopNearby: StopNearbyDetector
    /// The lift or stairs view and the map of a floor without positioning.
    @State private var floorGuide: FloorWithoutPositioningGuide
    private let venue: VenueService
    private let kind: JourneyKind
    private let options: ProximiMapView.Options
    /// The host app's journey after a change, applied to the open screen (`VisitController.apply`).
    private let incoming: IncomingJourney?
    /// The amenity routed to from search on a map without a journey (no navigator).
    @State private var routedAmenity: VenuePlace?
    @State private var amenityRouteError: String?
    /// The host app's destination (`ProximiMapView`'s `destination`). The view sets it back to `nil`
    /// when the route to it ends.
    private let destination: Binding<ProximiDestination?>
    /// The destination the view routes to.
    @State private var routedDestination: RoutedDestination?
    /// The host app's pause (`ProximiMapView`'s `isPaused`). "Resume your Journey" on the card of a
    /// paused journey sets it back to `false`.
    private let isPaused: Binding<Bool>
    /// The places are loaded and the journey started: a destination can be routed to.
    @State private var isReady = false
    /// `venue.settings` when the view was created.
    private let settings: GADSettings
    /// Back, "Leave the tour" and the close button of Journey Complete. `nil`: no Back and no "Leave
    /// the tour here"; Journey Complete's close button returns to the map.
    let onClose: (() -> Void)?
    /// Gets the navigator before the journey starts (`ProximiMapView`'s `onNavigator`).
    private let onNavigator: (@MainActor (JourneyNavigator) -> Void)?

    private var accessibility: RouteAccessibility {
        RouteAccessibility.effective(hostNeeds: hostAccessibility, accessibleRoutes: accessibleRoutes)
    }

    /// - Parameters:
    ///   - options: What the screen does beyond drawing the journey.
    ///   - mode: Map or List when the screen opens.
    ///   - incoming: The host app's journey after a change (`ProximiMapView`).
    ///   - destination: See `destination`.
    ///   - isPaused: See `isPaused`.
    ///   - onClose: See `onClose`.
    ///   - persist: Stores the journey after each change (`VisitController.persist`).
    ///   - onNavigator: See `onNavigator`.
    init(
        venue: VenueService,
        journey: Journey,
        kind: JourneyKind = .personalised,
        options: ProximiMapView.Options = .all,
        mode: VisitMode = .map,
        incoming: IncomingJourney? = nil,
        destination: Binding<ProximiDestination?> = .constant(nil),
        isPaused: Binding<Bool> = .constant(false),
        persist: @escaping @MainActor (Journey?) -> Void = VisitStore.persist,
        onClose: (() -> Void)?,
        onNavigator: (@MainActor (JourneyNavigator) -> Void)? = nil
    ) {
        self.venue = venue
        self.kind = kind
        self.options = options
        self.incoming = incoming
        self.destination = destination
        self.isPaused = isPaused
        _mode = State(initialValue: mode)
        let settings = venue.settings
        self.settings = settings
        _monitor = State(initialValue: TrackingMonitor(sdk: venue.sdk, settings: settings))
        _stopNearby = State(initialValue: StopNearbyDetector(nearbyMeters: settings.stopNearbyMeters))
        _liveActivity = State(initialValue: VisitLiveActivity(minimumUpdateInterval: settings.liveActivityMinimumInterval))
        _floorGuide = State(initialValue: FloorWithoutPositioningGuide(settings: settings))
        let session = MapStyle.session(
            sdk: venue.sdk,
            // The leg keeps its shape until the arrival; the walked part is translucent (PM review
            // 2026-10-12). No separate trail.
            options: MapStyle.options(routeMarkers: false, settings: settings)
        )
        var rules = JourneyRules.visit
        #if DEBUG
        if DebugLaunch.current.visitAutoAdvance { rules.advance = .onDeparture(meters: 5) }
        #endif
        _controller = State(initialValue: VisitController(
            session: session, journey: journey, rules: rules, keepsOrder: kind.keepsOrder,
            countsOutOfOrder: kind.countsOutOfOrder,
            managesProgress: options.contains(.progress),
            // Off the route a personalised journey keeps the leg; a curated tour is routed again
            // (PM, Monday, 2026-10-26).
            // With the warning the navigator routes nothing by itself: the warning comes first (PM,
            // Monday "Curated tour: off-route and recalculation", 2026-10-28).
            deviationPolicy: options.contains(.offRoutePrompt) ? .askApp : .automatic,
            settings: settings, persist: persist
        ))
        self.onClose = onClose
        self.onNavigator = onNavigator
    }

    var body: some View {
        presenting(observing(screen))
    }

    /// The map card, the bottom bar, the spinner and the lift or stairs view.
    private var screen: some View {
        GeometryReader { geometry in
            ZStack {
                if options.contains(.background) { ScreenBackground.map.view }
                if options.contains(.liveActivity) && hasStops {
                    VisitLiveActivityDriver(navigator: controller.navigator, session: controller.session, liveActivity: liveActivity)
                }
                VStack(spacing: 10) {
                    mapCard
                    bottomBar
                }
                // The map ignores the safe area; the card starts below the status bar as in the design.
                .padding(.top, geometry.safeAreaInsets.top + 8)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom - 14, 4))
                StartingSpinner(navigator: controller.navigator, session: controller.session, timeout: settings.mapLoadingTimeout, hasStops: hasStops)
                if case .changing(let change) = floorGuide.phase {
                    FloorChangeView(change: change)
                        .onTapGesture { floorGuide.showFloor() }
                        .transition(.opacity)
                } else if let ride {
                    FloorChangeView(change: ride, showsNoPositionNote: false)
                        .onTapGesture { withAnimation { self.ride = nil } }
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
    }

    /// The map in its glass card, with the list, "Rerouting you…" and the controls over it.
    private var mapCard: some View {
        MapGlassFrame(onPullDown: pullDownAction) {
            ProximiioMapView(session: controller.session)
            if showsList {
                VisitStopList(controller: controller, galleries: galleries, galleryNames: galleryNames, groupsByGallery: kind.listsGalleries, places: places, allowsSkip: kind.allowsSkip, onSkip: requestSkip)
                    .background(Palette.white.opacity(0.92))
                    .transition(.opacity)
            }
            if showsRerouting {
                // "Rerouting you…" fades the map (PM, Monday "Rerouting calculation view").
                Palette.white.opacity(0.5).transition(.opacity)
                ReroutingCard().transition(.opacity)
            }
        } overlay: {
            cardOverlay
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if options.contains(.bottomBar) {
            BottomGlassBar {
                if onClose != nil {
                    Button(action: requestClose) {
                        Image(systemName: "chevron.backward").font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(RoundGlassButtonStyle())
                    .accessibilityLabel(Text("Back", bundle: .module))
                }
            } trailing: {
                if hasStops {
                    Button { withAnimation { mode = showsList ? .map : .list } } label: {
                        Image(systemName: showsList ? "map" : "list.bullet").font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(RoundGlassButtonStyle())
                    .accessibilityLabel(showsList ? Text("Map", bundle: .module) : Text("List", bundle: .module))
                }
            }
        }
    }

    /// The tasks and the reactions to the journey, the map and the venue data.
    private func observing(_ content: some View) -> some View {
        content
            .animation(.default, value: mode)
            .animation(.easeInOut(duration: 0.2), value: floorGuide.phase)
            .onChange(of: floorGuide.phase) { _, _ in floorGuidePhaseChanged() }
            .onChange(of: mode) { _, mode in emit(.modeChanged(mode)) }
            .onChange(of: accessibility) { _, accessibility in
                Task { await controller.setAccessibility(accessibility) }
            }
            .task {
                controller.onArtworkDone = { [emit] stop, isActiveStop in
                    emit(isActiveStop ? .artworkReached(stop) : .artworkVisitedOutOfOrder(stop))
                }
                floorGuide.onEnter = { [emit, controller] change in
                    // Under the Map / List toggle, beside the map buttons, above the stop card.
                    FloorWithoutPositioningGuide.show(change, on: controller.session, padding: UIEdgeInsets(top: 100, left: 40, bottom: 220, right: 90))
                    emit(.floorWithoutPositioningEntered(level: change.level))
                }
                floorGuide.onLeave = { [emit, controller] change in
                    controller.session.followMyFloor()
                    FieldLog.log("recentre (floor without positioning left) · heading true")
                    controller.session.recentre(withHeading: true)
                    emit(.floorWithoutPositioningLeft(level: change.level))
                }
                for await event in controller.navigator.events {
                    // The navigator walks to an artwork visited out of order for a moment.
                    if case .legChanged(let stop, _) = event, stop.id == controller.passingStopID { continue }
                    if controller.isPaused, Self.isRouteDeviation(event) { continue }
                    emit(.journey(event))
                    if case .detourEnded(let stop, _) = event, routedDestination?.placeID == (stop.poiID ?? stop.id) {
                        clearDestination()
                    }
                }
            }
            .task {
                // Before `controller.start` below: the host app's streams get the journey's first events.
                onNavigator?(controller.navigator)
                #if DEBUG
                if DebugLaunch.current.visitList { mode = .list }
                #endif
                monitor.start()
                await placeCameraAtLastPosition()
                await loadVenueData()
                await MapStyle.waitForCanvas(of: controller.session)
                applyStopMarkers()
                // No walked legs: the map shows the trail of the current leg only (PM review 2026-10-12).
                mapLayers.attach(to: controller.session)
                refreshMapLayers()
                // A journey without stops shows the map alone; the navigator would report it finished.
                if hasStops {
                    if isPaused.wrappedValue { controller.pause() }
                    await controller.start(accessibility: accessibility)
                    // A visitor who opens the journey inside the first artwork's geofence.
                    checkArrival()
                }
                // Starts the heading-up follow once the journey is drawn (PM review 2026-10-12: the
                // map did not turn until "Centre on me").
                if controller.session.position != nil { showVisitorThenFollow(withHeading: true, reason: "journey started") }
                isReady = true
                destinationChanged(destination.wrappedValue)
            }
            .onChange(of: destination.wrappedValue) { _, destination in destinationChanged(destination) }
            .onChange(of: isPaused.wrappedValue) { _, paused in
                if paused {
                    controller.pause()
                } else {
                    Task { await controller.resumeFromPause() }
                }
            }
            .task {
                let events = await venue.sdk.geofenceEvents()
                // The stream does not repeat the geofences entered before it started.
                controller.enteredGeofenceIDs = await venue.sdk.enteredGeofenceIds
                checkArrival()
                for await event in events {
                    switch event {
                    case .entered(let geofence): controller.enteredGeofenceIDs.insert(geofence.id)
                    case .exited(let geofence, _): controller.enteredGeofenceIDs.remove(geofence.id)
                    default: break
                    }
                    // Artwork geofences lie inside the gallery geofences, so only galleries set the
                    // current gallery.
                    switch event {
                    case .entered(let geofence) where geofence.isGallery:
                        currentGallery = geofence.name
                        refreshMapLayers()
                        applyFollowZoom()
                    case .exited(let geofence, _) where geofence.isGallery:
                        if currentGallery == geofence.name {
                            currentGallery = nil
                            applyFollowZoom()
                        }
                    case .entered(let geofence) where geofence.isArtwork:
                        controller.artworkGeofenceEntered(remoteID: geofence.remoteId)
                    default: break
                    }
                }
            }
            .onChange(of: amenityOnMap) { _, place in show(amenity: place) }
            // Field log only. Camera diagnostics for the map library: why the heading-up follow does not start on a
            // device (PM review 2026-10-12).
            .onReceive(controller.session.$cameraMode) { mode in
                FieldLog.log("camera mode \(mode) · ready \(controller.session.isCameraReady) · heading available \(CLLocationManager.headingAvailable())")
            }
            .task {
                guard FieldLog.isEnabled else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let navigator = controller.navigator
                    let position = controller.session.position
                    let guidance = navigator.guidance
                    let stop = navigator.activeStop
                    // Typed: as a `CVarArg` argument, `optional ?? -1` is an Int when the optional is nil,
                    // which does not match `%.1f`.
                    let accuracy: Double = position?.horizontalAccuracy ?? -1
                    let remaining: Double = guidance?.remainingMeters ?? -1
                    let dwell: Double = guidance?.arrivalProgress ?? 0
                    let offRoute: Double = guidance?.offRouteMeters ?? -1
                    FieldLog.log(String(
                        format: "guidance stop %@ L%@ · visitor L%@ acc %.1f · remaining %.1f arrived %@ dwell %.2f offRoute %@ (%.1f m) · gallery %@",
                        stop?.title ?? "-", stop?.floor.map { String(Int($0.level.rounded())) } ?? "-",
                        position?.floor.map { String(Int($0.level.rounded())) } ?? "-", accuracy,
                        remaining, String(navigator.hasArrived), dwell,
                        String(guidance?.isOffRoute ?? false), offRoute, currentGallery ?? "-"
                    ))
                }
            }
            .task {
                guard FieldLog.isEnabled else { return }
                for await event in controller.navigator.events {
                    let overview = controller.navigator.overview
                    FieldLog.log("journey event: \(event) · active \(controller.navigator.activeStop?.title ?? "none") · unreachable \(overview.unreachableStopIDs.count)")
                }
            }
            .task {
                // Ambiguity is checked every few seconds, not on every position.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(4))
                    evaluateAmbiguity()
                }
            }
            .onChange(of: controller.navigator.isFinished) { _, isFinished in
                if isFinished && options.contains(.journeyComplete) { isShowingWrapUp = true }
            }
            .onChange(of: incoming) { _, incoming in
                guard let incoming else { return }
                Task { await controller.apply(incoming.journey) }
            }
            .fullScreenCover(isPresented: $isShowingWrapUp, onDismiss: leaveIfAsked) {
                JourneyCompleteView(venue: venue) {
                    controller.end()
                    leave(dismissing: { isShowingWrapUp = false })
                }
            }
    }

    /// The rest of the reactions, the sheets and the prompts.
    private func presenting(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isConfirmingExit, onDismiss: leaveIfAsked) {
                let stops = controller.navigator.journey.stops.filter { $0.state != .skipped }
                ExitConfirmationSheet(
                    visited: stops.filter { $0.state == .done }.count,
                    total: stops.count,
                    onLeave: {
                        emit(.exitConfirmed)
                        leave(dismissing: { isConfirmingExit = false })
                    },
                    onCarryOn: {
                        isConfirmingExit = false
                        emit(.exitCancelled)
                    }
                )
            }
            .sheet(item: $lowConfidenceStop) { stop in
                LowConfidencePrompt(stop: stop.title) {
                    answeredAmbiguity["low"] = .now
                    lowConfidenceStop = nil
                } onNotHere: {
                    answeredAmbiguity["low"] = .now
                    lowConfidenceStop = nil
                }
            }
            .onDisappear {
                monitor.stop()
                liveActivity.end()
                startZoomFollow?.cancel()
            }
            // No tracking or wristband alerts: the host app handles the wristband states
            // (PM 2026-10-15).
            .onChange(of: monitor.health) { _, health in
                emit(.trackingChanged(health))
                applyPositionStyle(for: health)
            }
            .onChange(of: controller.session.position == nil) { _, hasNoPosition in
                if !hasNoPosition { showVisitorThenFollow(reason: "first position") }
            }
            .followsVisitorFloor(controller.session, venue: venue, isPaused: floorGuide.isActive || rideFloor != nil)
            .onChange(of: ride) { shown, now in
                if now == nil, let shown { holdFloor(of: shown) }
            }
            .onReceive(controller.session.$guidance) { _ in
                Task { @MainActor in
                    refreshConnector()
                    refreshLevelChanger()
                    let session = controller.session
                    let navigator = controller.navigator
                    floorGuide.update(
                        coordinate: session.position?.coordinate, level: session.position?.floor?.level,
                        markers: session.routeRenderer?.geometry?.markers ?? [],
                        destinationID: navigator.detourStop?.id ?? navigator.activeStop?.id
                    )
                    checkRide()
                }
            }
            // The session updates the guidance after the position on every fix; a fix without guidance
            // is checked on the position. The map publishes guidance only on a leg with a route, so the
            // arrival is checked on the position (field test 2026-10-19).
            .onReceive(controller.session.$position) { position in
                checkStopNearby(position: position, guidance: controller.navigator.guidance)
                // `$position` publishes before the session stores the fix.
                Task { @MainActor in
                    checkArrival()
                    controller.checkCloserArtwork()
                    controller.checkWrongFloor(isFloorGuideActive: floorGuide.isActive)
                    updateVisitorGallery(controller.session.position)
                    releaseRideFloor(controller.session.position)
                    if let fix = controller.session.position { floorGuide.positionReceived(at: fix.timestamp) }
                }
            }
            .onReceive(controller.navigator.$guidance) { guidance in
                checkStopNearby(position: controller.session.position, guidance: guidance)
                controller.checkLegDeviation(guidance, isFloorGuideActive: floorGuide.isActive)
            }
            .onChange(of: controller.navigator.activeStop?.id) { _, _ in
                checkStopNearby(position: controller.session.position, guidance: controller.navigator.guidance)
                checkArrival()
                applyStopMarkers()
            }
            .onChange(of: controller.navigator.journey) { _, journey in controller.persist(journey) }
            .onChange(of: venue.data.version) { _, _ in
                let routeNetworkChanged = venue.data.changedKinds.contains(.features)
                Task {
                    await loadVenueData()
                    refreshMapLayers()
                    let withoutPlace = await controller.venueChanged(places: places, galleries: galleries, routeNetworkChanged: routeNetworkChanged)
                    for stop in withoutPlace {
                        emit(.stopPlaceDeleted(stop))
                    }
                }
            }
            .onReceive(controller.navigator.$journey) { _ in
                Task { @MainActor in
                    refreshMapLayers()
                    refreshLevelChanger()
                }
            }
            .onChange(of: controller.galleryAhead) { _, gallery in galleryAheadChanged(gallery) }
            .onReceive(controller.session.$selectedFloor) { _ in
                Task { @MainActor in
                    refreshMapLayers()
                    refreshConnector()
                    refreshLevelChanger()
                }
            }
            .sheet(item: $stopToSkip) { stop in
                SkipConfirmation(stop: stop) {
                    stopToSkip = nil
                    // Without `.progress` the host app skips the stop.
                    if options.contains(.progress) { Task { await controller.skip(stopID: stop.id) } }
                    emit(.stopSkipped(stop))
                } onKeep: {
                    stopToSkip = nil
                    emit(.skipCancelled(stop))
                }
            }
            .task(id: controller.isRerouting) { await followRerouting() }
            .task { await MapDiagnostics.follow(controller.session, name: "journey") }
    }

    /// "Rerouting you…" after 0.5 s of routing; hidden when the routing ends.
    private func followRerouting() async {
        guard controller.isRerouting else {
            withAnimation(.easeInOut(duration: 0.2)) { showsRerouting = false }
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, controller.isRerouting else { return }
        withAnimation(.easeInOut(duration: 0.2)) { showsRerouting = true }
    }

    /// No dot while a privacy zone holds it (`MapStyle.hidingPosition(_:)`).
    private func applyPositionStyle(for health: TrackingHealth) {
        let position = MapStyle.options(routeMarkers: false, settings: settings).position
        controller.session.options.position = health == TrackingHealth.privacyZone ? MapStyle.hidingPosition(position) : position
    }

    /// A drag down on the handle of the map card: Back, with the bottom bar and `onClose`.
    private var pullDownAction: (() -> Void)? {
        guard options.contains(.bottomBar), onClose != nil else { return nil }
        return { requestClose() }
    }

    /// "Looks like you've left your route" on the stop card's place, unless another card is up.
    private var showsOffRouteCard: Bool {
        options.contains(.offRoutePrompt) && controller.isOffRoute && hasStops && !floorGuide.isActive
    }

    /// The zoom of "Centre on me" and of the follow: `GADSettings.galleryFollowZoom` inside a gallery
    /// in a personalised journey, else `followZoom` (PM, Monday "Navigation to a gallery" and
    /// "Curated tours: zoom level", 2026-10-27). A camera that follows the visitor zooms to it; one
    /// the visitor moved stays.
    private func applyFollowZoom() {
        let zoom = Self.followZoom(inGallery: currentGallery != nil, kind: kind, settings: settings)
        guard controller.session.options.recentreZoom != zoom else { return }
        controller.session.options.recentreZoom = zoom
        if controller.session.cameraMode == .follow, !floorGuide.isActive {
            FieldLog.log("follow zoom \(zoom) · in a gallery \(currentGallery ?? "-")")
            controller.session.recentre(zoom: zoom)
        }
    }

    /// Pure; covered by tests.
    static func followZoom(inGallery: Bool, kind: JourneyKind, settings: GADSettings) -> Double {
        guard inGallery, kind.guidesToGalleryFirst, let zoom = settings.galleryFollowZoom else { return settings.followZoom }
        return zoom
    }

    /// Arrival at an artwork, out of order and gallery first. On a floor without positioning the
    /// fixes come from the floor the visitor left, so nothing is checked.
    private func checkArrival() {
        guard !floorGuide.isActive else { return }
        controller.checkArtworkGeofences()
        controller.checkGalleryFirst()
    }

    /// Places, artwork areas, galleries and level changers, at the start and after a change of the
    /// venue data.
    private func loadVenueData() async {
        let features = await venue.data.features()
        let amenities = await venue.data.amenities()
        places = VenuePlace.all(in: features, amenities: amenities)
        let scale = UIScreen.main.scale
        amenityIcons = Dictionary(amenities.compactMap { amenity in amenity.icon.flatMap { AmenityIcon.rasterImage($0, scale: scale) }.map { (amenity.id, $0) } },
                                  uniquingKeysWith: { first, _ in first })
        searchShortcuts = AmenityListing.search(amenities).searchShortcuts(places: places, amenities: amenities, icons: amenityIcons)
        controller.artworkRemoteIDs = Dictionary(
            places.compactMap { place in place.remoteID.map { (place.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        // The journey map shows artworks only as the numbered stop markers. Amenities,
        // galleries and level changers stay (PM review 2026-10-12). `mapLayers` draws the
        // level changers on every floor they serve.
        let levelChangers = LevelChangerPlace.all(in: features)
        levelChangerPlaces = levelChangers
        mapLayers.updateLevelChangers(levelChangers)
        mapLayers.updateCones(VenueCone.all(in: features))
        hiddenFeatureIDs = Set(places.filter(\.isArtwork).map(\.id) + levelChangers.map(\.id))
        let geofences = await venue.data.geofences()
        controller.artworkAreas = VisitController.artworkAreas(of: geofences)
        let destinations = Gallery.destinations(geofences: geofences, places: places, features: features)
        galleryDestinations = Array(destinations.values)
        applyHiddenFeatures()
        controller.setGalleryFirst(isEnabled: kind.guidesToGalleryFirst, places: places, destinations: destinations)
        galleries = await Gallery.load(from: venue.sdk, features: features, geofences: geofences, places: places)
        galleryNames = Gallery.names(places: places)
        FieldLog.log("galleries: \(galleries.map { "\($0.name) L\(Int($0.level))" }.joined(separator: ", ")) · \(galleryNames.count) named by id · \(destinations.count) for gallery first")
    }

    // MARK: Map layers

    /// The amenity picked in the menu while its card or route is on screen.
    private var amenityOnMap: VenuePlace? {
        selectedAmenity ?? routedAmenity
    }

    /// Highlights `place` and shows it with the visitor (`PlaceFraming`); `nil` removes the highlight.
    private func show(amenity place: VenuePlace?) {
        mapLayers.updateHighlight(JourneyMapLayers.highlight(of: place))
        guard let place else { return }
        // Under the Map / List toggle, beside the map buttons, above the place card.
        PlaceFraming.show(place, on: controller.session, padding: UIEdgeInsets(top: 100, left: 40, bottom: 220, right: 90),
                          minimumMeters: settings.amenityFramingMinimumMeters)
    }

    /// The leg now ends at `gallery`, or at the artwork for `nil` (gallery first).
    private func galleryAheadChanged(_ gallery: GalleryDestination?) {
        refreshMapLayers()
        applyHiddenFeatures()
        applyStopMarkers()
        FieldLog.log("gallery first: \(gallery.map { "route ends at \($0.gallery.name)" } ?? "route ends at the artwork")")
    }

    /// The features the map does not draw: the artworks and level changers (`hiddenFeatureIDs`) and
    /// the galleries' POIs, whose names `galleryMarkers` draws.
    private func applyHiddenFeatures() {
        var hidden = hiddenFeatureIDs
        hidden.formUnion(galleryDestinations.map(\.placeID))
        if let gallery = controller.galleryAhead { hidden.insert(gallery.placeID) }
        if controller.session.hiddenFeatureIDs != hidden { controller.session.hiddenFeatureIDs = hidden }
    }

    /// The galleries whose artworks of the journey are all visited or skipped, at least one visited
    /// (the customer, Monday "Visited gallery visualization", 2026-10-28), once the visitor is out of
    /// them (PM, 2026-10-29).
    private var visitedGalleryIDs: Set<String> {
        let stops = controller.navigator.journey.stops.filter { $0.kind != .detour }.map { stop in
            (gallery: Gallery.containing(stop.coordinate.proximiio, level: stop.floor?.level, in: galleries)?.id, state: stop.state)
        }
        return Self.visitedGalleries(stops.compactMap { stop in stop.gallery.map { ($0, stop.state) } }, visitorGallery: visitorGalleryID)
    }

    /// The galleries of `stops` whose stops are all done or skipped, at least one done, except
    /// `visitorGallery`. Pure; covered by tests.
    static func visitedGalleries(_ stops: [(gallery: String, state: JourneyStop.State)], visitorGallery: String?) -> Set<String> {
        Set(Dictionary(grouping: stops, by: \.gallery).compactMap { gallery, stops in
            let states = stops.map(\.state)
            guard gallery != visitorGallery else { return nil }
            return states.allSatisfy { $0 == .done || $0 == .skipped } && states.contains(.done) ? gallery : nil
        })
    }

    /// The gallery of the active stop, unless the visitor is in it.
    private var activeStopGallery: Gallery? {
        let gallery = controller.navigator.activeStop.flatMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries) }
        return gallery?.id == visitorGalleryID ? nil : gallery
    }

    /// The fill of a gallery on the journey map: none for the gallery the visitor is in, so its
    /// artworks and furniture show, else destination, visited or the standard gallery colour. Pure;
    /// covered by tests.
    static func fillStyle(of gallery: String, destination: String?, visited: Set<String>, visitorGallery: String?) -> JourneyMapLayers.GalleryFill.Style? {
        if gallery == visitorGallery { return nil }
        if gallery == destination { return .destination }
        return visited.contains(gallery) ? .visited : .standard
    }

    /// Each gallery's name at its POI, but not the gallery the visitor is in (PM, Monday "Navigation
    /// to a gallery", 2026-10-26): the gallery the leg ends at is the destination, a visited gallery is
    /// visited. A curated tour shows them as a personalised journey does (PM, Monday "Gallery numbers
    /// in gallery navigation", 2026-10-29).
    private var galleryMarkers: [JourneyMapLayers.GalleryMarker] {
        let visited = galleries.filter { visitedGalleryIDs.contains($0.id) }
        let ahead = controller.galleryAhead?.placeID
        let destinationGallery = ahead == nil ? activeStopGallery : nil
        return galleryDestinations.filter { $0.placeID != visitorGalleryPlaceID }.map { destination in
            let isGallery = { (gallery: Gallery) in
                gallery.id == destination.shown.id || gallery.contains(destination.entry, level: destination.gallery.level)
            }
            let isDestination = destination.placeID == ahead || destinationGallery.map(isGallery) == true
            let style: JourneyMapLayers.GalleryMarker.Style = isDestination ? .destination : visited.contains(where: isGallery) ? .visited : .standard
            return JourneyMapLayers.GalleryMarker(coordinate: destination.entry, level: destination.gallery.level,
                                                  name: destination.gallery.name, style: style)
        }
    }

    /// The numbered stop markers. With gallery first they are hidden while the leg ends at a
    /// gallery, and while the visitor is outside every gallery and the active artwork is in one
    /// (PM, Monday "Navigation to a gallery", 2026-10-26 and 2026-10-27).
    private func applyStopMarkers() {
        var style = Self.showsArtworkMarkers(
            guidesToGalleryFirst: kind.guidesToGalleryFirst && !galleryDestinations.isEmpty,
            hasGalleryAhead: controller.galleryAhead != nil,
            isInGallery: visitorGalleryPlaceID != nil,
            isActiveStopInGallery: controller.navigator.activeStop?.group != nil
        ) ? MapStyle.journeyStops : MapStyle.journeyStopsHidden
        if !settings.groupsStopMarkers { style.groupsOverlapping = false }
        if controller.session.journeyStopMarkerStyle != style { controller.session.journeyStopMarkerStyle = style }
    }

    /// The navigator's reports of leaving and rejoining the route, which a paused journey does not
    /// pass on. Pure; covered by tests.
    static func isRouteDeviation(_ event: JourneyEvent) -> Bool {
        switch event {
        case .leftRoute, .farFromRoute, .offRouteTooLong, .returnedToRoute: true
        default: false
        }
    }

    /// Whether the artworks' markers show. Pure; covered by tests.
    static func showsArtworkMarkers(guidesToGalleryFirst: Bool, hasGalleryAhead: Bool, isInGallery: Bool, isActiveStopInGallery: Bool) -> Bool {
        guard guidesToGalleryFirst else { return true }
        return !hasGalleryAhead && (isInGallery || !isActiveStopInGallery)
    }

    /// Finds the gallery the visitor is in, on every fix.
    private func updateVisitorGallery(_ position: VenuePosition?) {
        let placeID = position.flatMap { position in
            galleryDestinations.first { $0.gallery.contains(position.coordinate.proximiio, level: position.floor?.level) }?.placeID
        }
        let galleryID = position.flatMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries)?.id }
        guard placeID != visitorGalleryPlaceID || galleryID != visitorGalleryID else { return }
        visitorGalleryPlaceID = placeID
        visitorGalleryID = galleryID
        refreshMapLayers()
        applyStopMarkers()
    }

    /// Shows the lift or stairs view for `GADSettings.levelChangeViewSeconds` when the visitor reaches
    /// the lift or stairs of the route's next level change. A ride to a floor without positioning is
    /// the floor guide's (`FloorWithoutPositioningGuide`).
    private func checkRide() {
        let session = controller.session
        guard ride == nil, !floorGuide.isActive, let position = session.position,
              let change = FloorWithoutPositioningGuide.reachedRide(
                  coordinate: position.coordinate, level: position.floor?.level,
                  markers: session.routeRenderer?.geometry?.markers ?? [], settings: settings
              ),
              !settings.levelsWithoutPositioning.contains(change.level),
              shownRides.insert("\(change.coordinate.latitude),\(change.coordinate.longitude),\(change.from),\(change.level)").inserted
        else { return }
        FieldLog.log("ride: at the \(change.featureType) to L\(change.level)")
        withAnimation { ride = change }
        let seconds = settings.levelChangeViewSeconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if ride == change { withAnimation { ride = nil } }
        }
    }

    /// After the lift or stairs view the map shows the floor the ride ends on, and keeps it while the
    /// visitor's fixes are still on the ride's floor near the lift or stairs (PM, Monday
    /// "Elevator/Staircase animation", 2026-10-28). The lifts and stairs are privacy zones: during
    /// the ride the dot is hidden.
    private func holdFloor(of change: FloorWithoutPositioningGuide.Change) {
        rideFloor = change
        controller.session.select(floor: FloorKey(level: Double(change.level)))
        FieldLog.log("ride: map shows L\(change.level) until a fix off L\(change.from) or \(Int(settings.rideFloorHoldMeters)) m from the \(change.featureType)")
    }

    /// Follows the visitor's floor again after `holdFloor(of:)` on a fix that ends it.
    private func releaseRideFloor(_ position: VenuePosition?) {
        guard let change = rideFloor, let position,
              FloorWithoutPositioningGuide.releasesRideFloor(change, coordinate: position.coordinate, level: position.floor?.level,
                                                             meters: settings.rideFloorHoldMeters)
        else { return }
        rideFloor = nil
        FieldLog.log("ride: map follows the visitor again, fix on L\(position.floor.map { "\(Int($0.level))" } ?? "?")")
        controller.session.followMyFloor()
    }

    /// Reports `stopNearby` once per stop.
    private func checkStopNearby(position: VenuePosition?, guidance: RouteGuidance?) {
        if let stop = stopNearby.update(position: position, stop: controller.navigator.activeStop, guidance: guidance) {
            emit(.stopNearby(stop))
        }
    }

    /// Stop markers and gallery fills for the current journey and floor.
    private func refreshMapLayers() {
        let visited = visitedGalleryIDs
        // Gallery first: the outline of the gallery geofence the leg ends at, in place of the
        // outline that holds the artwork. The gallery the visitor is in has no fill: the venue's own
        // gallery colour, under the artworks and furniture, with the artwork numbers (PM, Monday
        // "Navigation to a gallery", 2026-10-28).
        let galleryAhead = controller.galleryAhead
        let destination = galleryAhead?.shown.id ?? activeStopGallery?.id
        var fills = galleries.compactMap { gallery in
            Self.fillStyle(of: gallery.id, destination: destination, visited: visited, visitorGallery: visitorGalleryID)
                .map { JourneyMapLayers.GalleryFill(gallery: gallery, style: $0) }
        }
        if let galleryAhead, !galleries.contains(where: { $0.id == galleryAhead.shown.id }) {
            fills.append(.init(gallery: galleryAhead.shown, style: .destination))
        }
        let line = "gallery fills: visitor in \(galleries.first { $0.id == visitorGalleryID }?.name ?? "none") · destination "
            + "\(fills.first { $0.style == .destination }?.gallery.name ?? "none") · \(fills.filter { $0.style == .visited }.count) visited · "
            + "\(fills.filter { $0.style == .standard }.count) standard"
        if line != galleryFillLine {
            galleryFillLine = line
            FieldLog.log(line)
        }
        mapLayers.update(fills: fills, level: controller.session.selectedFloor.level)
        mapLayers.updateGalleryMarkers(galleryMarkers)
        applyHiddenFeatures()
    }

    /// The line from the visitor to the start of the route ahead, on the visitor's floor only.
    /// The session updates the guidance on every fix, after the position. Within
    /// `connectorEndMeters` of the route's end there is no line: it would lead straight to the
    /// stop, through walls (PM review 2026-10-12). Off while `showsConnector` is false.
    private func refreshConnector() {
        let session = controller.session
        guard Self.showsConnector, let guidance = session.guidance, !guidance.hasArrived,
              guidance.remainingMeters >= Self.connectorEndMeters,
              let start = guidance.progress.point,
              let position = session.position,
              position.floor.map({ VenueLevel.same($0.level, session.selectedFloor.level) }) ?? true
        else {
            mapLayers.updateConnector(from: nil, to: nil)
            return
        }
        mapLayers.updateConnector(from: position.coordinate.proximiio, to: start.proximiio)
    }

    /// The lift or stairs of the route's next level change from the shown floor (PM 2026-10-15,
    /// "Level changer highlighting").
    private func refreshLevelChanger() {
        let session = controller.session
        let level = session.selectedFloor.level
        if case .returning(let change) = floorGuide.phase {
            mapLayers.updateLevelChanger(exitChanger(from: change).map {
                .init(coordinate: $0.coordinate, level: Double(change.level), featureType: $0.featureType)
            })
            return
        }
        let next = session.routeRenderer?.geometry?.markers.first {
            !$0.isCompleted && VenueLevel.same($0.from.level, level)
        }
        mapLayers.updateLevelChanger(next.map {
            .init(coordinate: $0.coordinate.proximiio, level: level, featureType: $0.featureType)
        })
    }

    // MARK: Floor without positioning

    /// The leg's destination: the detour's place, else the active stop's.
    private var floorDestination: VenuePlace? {
        let navigator = controller.navigator
        guard let stop = navigator.detourStop ?? navigator.activeStop else { return nil }
        return places.first { $0.id == (stop.poiID ?? stop.id) }
    }

    /// The next stop's floor on the way back.
    private var returningToLevel: Int? {
        guard case .returning = floorGuide.phase, let level = controller.navigator.activeStop?.floor?.level else { return nil }
        return Int(level.rounded())
    }

    /// The lift or stairs to the next stop's floor, nearest the destination the visitor went to.
    private func exitChanger(from change: FloorWithoutPositioningGuide.Change) -> LevelChangerPlace? {
        guard let origin = returnOrigin, let target = returningToLevel else { return nil }
        return FloorWithoutPositioningGuide.exitChanger(from: origin, level: change.level, to: target, in: levelChangerPlaces)
    }

    /// On a floor without positioning the route is not drawn (PM, Monday "POIs on floors with no
    /// positioning", 2026-10-26). On the way there the destination is highlighted; on the way back
    /// the lift or stairs to take.
    private func floorGuidePhaseChanged() {
        let hidesRoute: Bool
        switch floorGuide.phase {
        case .onFloor:
            hidesRoute = true
            mapLayers.updateHighlight(JourneyMapLayers.highlight(of: floorDestination))
        case .returning:
            hidesRoute = true
            mapLayers.updateHighlight(nil)
        case .idle, .changing:
            hidesRoute = false
            mapLayers.updateHighlight(JourneyMapLayers.highlight(of: amenityOnMap))
        }
        controller.session.options.routeLineStyle = hidesRoute ? MapStyle.hiddenRoute : MapStyle.route
        refreshLevelChanger()
    }

    /// `recentre` with a field-log line naming the caller. Ends a pending `showVisitorThenFollow`.
    private func recentre(withHeading: Bool? = nil, reason: String) {
        startZoomFollow?.cancel()
        startZoomFollow = nil
        FieldLog.log("recentre (\(reason)) · heading \(withHeading.map(String.init) ?? "default") · mode before \(controller.session.cameraMode)")
        controller.session.recentre(withHeading: withHeading)
    }

    /// Before the venue's features are on the map: the camera at the SDK's last position, at the start
    /// zoom, without animation, and the floor of that position. The map then draws the venue once, at
    /// the right place and floor; an animated move and a floor change after the features arrived drew it
    /// again (proximiio-ios-sdk measurement, 2026-10-29). A position older than
    /// `GADSettings.trackingLostAfter` is not used.
    private func placeCameraAtLastPosition() async {
        guard let last = await venue.sdk.lastPosition else { return }
        let age = Date().timeIntervalSince(last.timestamp)
        guard age < settings.trackingLostAfter else { return }
        let zoom = settings.startZoom ?? settings.followZoom
        let centre = CLLocationCoordinate2D(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        controller.session.camera.setCenter(centre, zoom: zoom, animated: false)
        if let level = last.floor?.level { controller.session.select(floor: FloorKey(level: level)) }
        FieldLog.log(String(format: "camera at the last position before the venue · L%@ · %.1f s old",
                            last.floor.map { "\(Int($0.level))" } ?? "?", age))
    }

    /// Shows the visitor at `GADSettings.startZoom` for `startZoomSeconds`, then follows them at the
    /// follow zoom: when the journey starts, on the first fix and when the position comes back (PM,
    /// Monday "Zoom level at start + navigation", 2026-10-29). Without `startZoom` it follows at once.
    private func showVisitorThenFollow(withHeading: Bool? = nil, reason: String) {
        guard let zoom = settings.startZoom, let position = controller.session.position else {
            return recentre(withHeading: withHeading, reason: reason)
        }
        startZoomFollow?.cancel()
        FieldLog.log("start zoom (\(reason)) · zoom \(zoom) for \(settings.startZoomSeconds) s")
        // The camera write lets go of the follow; `recentre` takes it again.
        let centre = CLLocationCoordinate2D(latitude: position.coordinate.latitude, longitude: position.coordinate.longitude)
        // Without animation: an animated move delayed the first fully drawn frame.
        controller.session.camera.setCenter(centre, zoom: zoom, animated: false)
        let seconds = settings.startZoomSeconds
        startZoomFollow = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            recentre(withHeading: withHeading, reason: "\(reason), after the start zoom")
        }
    }

    private static let connectorEndMeters = 2.0
    /// False: no connector. Its bend moved with every fix, so the route looked redrawn "like a
    /// snake" (PM review 2026-10-12, screen recording 21-26-05).
    private static let showsConnector = false

    // MARK: Leaving

    /// Dismisses the sheet or cover the visitor left the visit from; `leaveIfAsked` closes the
    /// visit after the dismissal.
    private func leave(dismissing dismiss: () -> Void) {
        FieldLog.log("visit: leave after dismissal")
        leavesAfterDismiss = true
        dismiss()
    }

    private func leaveIfAsked() {
        guard leavesAfterDismiss else { return }
        leavesAfterDismiss = false
        FieldLog.log("visit: close")
        onClose?()
    }

    /// Whether the journey has a stop. Without one the screen shows the map alone.
    private var hasStops: Bool { !controller.navigator.journey.stops.isEmpty }

    /// List mode with a journey. Without stops the map shows, whatever `mode` is.
    private var showsList: Bool { mode == .list && hasStops }

    /// A swipe on a stop in the list: "Skip this artwork?" with `skipPrompt`, else only the event.
    private func requestSkip(_ stop: JourneyStop) {
        if options.contains(.skipPrompt) { stopToSkip = stop }
        emit(.skipRequested(stop))
    }

    /// Back: a visit in progress asks first (03.10) with `leaveTourPrompt`; otherwise Back closes.
    private func requestClose() {
        let journey = controller.navigator.journey
        let started = journey.stops.contains { $0.state == .done || $0.state == .skipped }
        if options.contains(.leaveTourPrompt) && started && !controller.navigator.isFinished {
            isConfirmingExit = true
            emit(.exitRequested)
        } else {
            onClose?()
        }
    }

    // MARK: Ambiguous location (EC04)

    private var isPresentingSomething: Bool {
        // Without `offRoutePrompt` the off-route state shows nothing and does not hold the report back.
        lowConfidenceStop != nil || stopToSkip != nil || isConfirmingExit
            || (options.contains(.offRoutePrompt) && controller.isOffRoute)
            || isShowingWrapUp || floorGuide.isActive || controller.isPaused
    }

    private func evaluateAmbiguity() {
        guard !isPresentingSomething, monitor.health == .tracking, let coordinate = monitor.lastCoordinate else { return }
        let navigator = controller.navigator
        let input = LocationAmbiguity.Input(
            coordinate: coordinate,
            level: monitor.lastLevel,
            horizontalAccuracy: max(0, monitor.lastAccuracy ?? 0),
            activeStop: navigator.hasArrived ? nil : navigator.activeStop
        )
        guard let ambiguity = LocationAmbiguity.evaluate(input, settings: settings) else { return }
        if let answered = answeredAmbiguity[ambiguity.kind], Date.now.timeIntervalSince(answered) < settings.locationQuestionQuietPeriod {
            return
        }
        FieldLog.log("ambiguous location: \(ambiguity.kind)")
        switch ambiguity {
        case .lowConfidence(let stop):
            if options.contains(.uncertainPositionPrompt) {
                lowConfidenceStop = stop
            } else {
                // Reported once per quiet period, as an answered prompt.
                answeredAmbiguity[ambiguity.kind] = .now
                emit(.positionUncertain(stop))
            }
        }
    }

    /// Controls inside the map card: toggle and search at the top, compass and floor at the
    /// trailing edge, the stop card at the bottom.
    private var cardOverlay: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                if hasStops {
                    MapListToggle(showsList: Binding(get: { mode == .list }, set: { mode = $0 ? .list : .map }))
                }
                Spacer()
                // In List mode the design hides search.
                if !showsList {
                VStack(alignment: .trailing, spacing: 10) {
                    GlassSquareButton(isSelected: isShowingAmenities, action: { withAnimation { isShowingAmenities.toggle() } }) {
                        GADIcon.search.image.resizable().scaledToFit().frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(Text("Search", bundle: .module))
                    if isShowingAmenities {
                        AmenityChipList(shortcuts: searchShortcuts) { shortcut in
                            isShowingAmenities = false
                            detour(to: shortcut)
                        }
                    }
                }
                }
            }
            // 32 pt below the card's top edge, 17 pt below the drag handle (Figma 10889:108085;
            // Nagarro, 2026-10-30: the controls sat too close to the handle).
            .padding(.top, 32)
            // A long amenity list takes the free height before the spacer; it scrolls past that.
            .layoutPriority(1)
            Spacer()
            if !showsList {
                HStack {
                    Spacer()
                    VStack(spacing: 5) {
                        GlassSquareButton(action: {
                            floorGuide.leave()
                            controller.session.followMyFloor()
                            recentre(reason: "Centre on me")
                            emit(.recentred)
                        }) {
                            GADIcon.compass.image.resizable().scaledToFit().frame(width: 24, height: 24)
                        }
                        .accessibilityLabel(Text("Centre on me", bundle: .module))
                        AccessibleRoutesButton(isOn: $accessibleRoutes) { emit(.accessibleRoutesChanged($0)) }
                        // The shown floor, a label and no button (PM, Monday "Current level button",
                        // 2026-10-28).
                        Text(GuidanceText.floorLabel(controller.session.selectedFloor.level))
                            .textStyle(.largeBodyBold)
                            .foregroundStyle(Palette.ink)
                            .frame(width: 50, height: 50)
                            .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Floor \(GuidanceText.floorLabel(controller.session.selectedFloor.level))", bundle: .module))
                            .accessibilityIdentifier("visitFloor")
                    }
                }
                if let place = selectedAmenity {
                    // During a journey "Add a stop" starts the detour at once (PM, Monday "Add stop
                    // confirmation", 2026-10-26: no second confirmation), and the map goes back to
                    // the visitor (Monday "Adding amenity -> focus back on my location", 2026-10-27).
                    PlaceInfoCard(
                        title: place.title,
                        subtitle: place.cardSubtitle,
                        primary: hasStops ? "Add a stop" : "Go here",
                        onPrimary: {
                            selectedAmenity = nil
                            if !hasStops {
                                Task { await route(to: place) }
                            } else {
                                Task { await controller.detour(to: place) }
                                emit(.detourStarted(place))
                                emit(.journeyPaused)
                                controller.session.followMyFloor()
                                recentre(reason: "stop added")
                            }
                        },
                        onClose: { selectedAmenity = nil }
                    )
                } else if let place = routedAmenity {
                    PlaceInfoCard(
                        title: place.title,
                        subtitle: amenityRouteError ?? place.cardSubtitle,
                        primary: "Close",
                        onPrimary: endAmenityRoute
                    )
                } else if showsOffRouteCard {
                    // PM, Monday "Personalized tour: off-route and re-route behaviour", 2026-10-26.
                    PlaceInfoCard(
                        title: String(localized: "Looks like you’ve left your route", bundle: .module),
                        subtitle: offRouteText,
                        primary: "Dismiss",
                        onPrimary: { controller.dismissOffRoute() }
                    )
                } else if hasStops {
                    VisitCard(
                        navigator: controller.navigator,
                        session: controller.session,
                        galleries: galleries,
                        galleryAhead: controller.galleryAhead?.gallery,
                        galleryIcon: controller.galleryAhead
                            .flatMap { ahead in places.first { $0.id == ahead.placeID }?.amenityID }
                            .flatMap { amenityIcons[$0] },
                        places: places,
                        isOnFloorWithoutPositioning: floorGuide.isActive,
                        returningToLevel: returningToLevel,
                        pausedText: controller.isPaused ? nextStopText ?? "" : nil,
                        onResumeFromPause: {
                            if isPaused.wrappedValue { isPaused.wrappedValue = false }
                            Task { await controller.resumeFromPause() }
                            emit(.journeyResumed)
                        },
                        onResume: {
                            if case .onFloor = floorGuide.phase {
                                returnOrigin = floorDestination?.coordinate
                                floorGuide.returnFromFloor()
                            }
                            Task { await controller.resumeJourney() }
                            emit(.journeyResumed)
                        }
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.2), value: isShowingAmenities)
        .animation(.easeInOut(duration: 0.2), value: showsOffRouteCard)
    }

    /// "Go here" on a map without a journey: the route from the visitor to `place`, as on the museum
    /// map. There is no navigator to add a detour to.
    private func route(to place: VenuePlace) async {
        if let routed = routedDestination, routed.placeID != place.id { clearDestination() }
        routedAmenity = place
        guard let here = controller.session.position else {
            amenityRouteError = String(localized: "Waiting for your position.", bundle: .module)
            controller.session.clearRoute()
            return
        }
        do {
            let route = try await venue.sdk.computeRoute(
                from: here.coordinate.proximiio,
                fromLevel: here.floor?.level ?? 0,
                to: place.coordinate,
                toLevel: place.level,
                options: accessibility.routeOptions
            )
            guard routedAmenity?.id == place.id else { return }
            controller.session.setRoute(route)
            amenityRouteError = nil
        } catch {
            FieldLog.log("route to \(place.title) failed: \(error)")
            controller.session.clearRoute()
            if case WayfindingRoutingError.noRoute(.noAccessibleRoute) = error {
                amenityRouteError = String(localized: "No route from here with your accessibility settings.", bundle: .module)
            } else {
                amenityRouteError = String(localized: "No route from here.", bundle: .module)
            }
        }
    }

    private func endAmenityRoute() {
        routedAmenity = nil
        amenityRouteError = nil
        controller.session.clearRoute()
        if routedDestination != nil { clearDestination() }
    }

    // MARK: Destination

    /// The host app set `destination`, or set it back to `nil`. A new destination replaces the route
    /// of the previous one; `nil` ends it.
    private func destinationChanged(_ destination: ProximiDestination?) {
        guard isReady, destination?.poiID != routedDestination?.requested else { return }
        if routedDestination != nil, destination == nil {
            routedDestination = nil
            Task { await endDestinationRoute() }
            return
        }
        guard let destination else { return }
        Task { await route(to: destination) }
    }

    /// Routes to the host app's destination at once, as "Go here" does without "Change your
    /// route?": the visitor agreed with the host app (the audio guide). A stop of the journey still
    /// to visit becomes the next stop instead.
    private func route(to destination: ProximiDestination) async {
        guard let place = VenuePlace.place(withID: destination.poiID, in: places) else {
            return destinationFailed(destination.poiID, .unknownPlace)
        }
        // The feature id; the host app can give `properties.id`.
        let id = place.id
        let routed = RoutedDestination(requested: destination.poiID, placeID: id)
        FieldLog.log("destination: \(place.title)")
        selectedAmenity = nil
        isShowingAmenities = false
        routedDestination = routed
        guard hasStops else {
            await route(to: place)
            guard routedDestination == routed, routedAmenity?.id == id else { return }
            if controller.session.position == nil {
                endAmenityRoute()
                destinationFailed(routed.requested, .noPosition)
            } else if amenityRouteError != nil {
                endAmenityRoute()
                destinationFailed(routed.requested, .noRoute)
            }
            return
        }
        if let stop = controller.navigator.journey.stops.first(where: { ($0.poiID ?? $0.id) == id && $0.kind != .detour }),
           stop.state == .pending || stop.state == .active || stop.state == .reached {
            if stop.state == .pending { await controller.activate(stopID: stop.id) }
            clearDestination()
            return
        }
        let stopID = await controller.detour(to: place)
        emit(.detourStarted(place))
        guard routedDestination == routed else { return }
        if controller.navigator.noRouteReasons[stopID] != nil {
            await controller.cancelDetour()
            destinationFailed(routed.requested, .noRoute)
        }
    }

    /// Ends the route the destination started, after the host app set it to `nil`.
    private func endDestinationRoute() async {
        if hasStops {
            if controller.navigator.detourStop != nil { await controller.cancelDetour() }
        } else {
            endAmenityRoute()
        }
    }

    private func destinationFailed(_ id: String, _ reason: ProximiDestination.Failure) {
        FieldLog.log("destination \(id) unavailable: \(reason)")
        clearDestination()
        emit(.destinationUnavailable(poiID: id, reason: reason))
    }

    /// A destination the view routes to: the id the host app gave and the place's feature id.
    private struct RoutedDestination: Equatable {
        let requested: String
        let placeID: String
    }

    /// The route to the destination ended: the binding goes back to `nil`.
    private func clearDestination() {
        routedDestination = nil
        if destination.wrappedValue != nil { destination.wrappedValue = nil }
    }

    /// "Your next stop is Gallery 103." The gallery the leg ends at, else the next stop.
    private var nextStopText: String? {
        guard let next = controller.galleryAhead?.gallery.name ?? controller.navigator.activeStop?.title else { return nil }
        return String(localized: "Your next stop is \(next).", bundle: .module)
    }

    private var offRouteText: String {
        nextStopText ?? String(localized: "Head back to your route.", bundle: .module)
    }

    /// Shows the nearest place of `kind` on a card. "Add a stop" adds it as a journey detour (PM
    /// review 2026-10-12).
    private func detour(to shortcut: AmenityShortcut) {
        let here = controller.session.position
        let from = here.map { ProximiioCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        selectedAmenity = shortcut.nearest(in: places, from: from, level: here?.floor?.level)
        if let selectedAmenity { emit(.amenitySelected(selectedAmenity)) }
    }

}

/// The card at the bottom of the map (Figma "Stop Info"): an icon in a white circle, the
/// caption, the stop, and the instruction with distance and time.
///
/// Gallery first (DAILY-CALL R2; PM, Monday "Navigation to a gallery"): while the leg ends at the
/// gallery of the next artwork (`VisitController.galleryAhead`), the card names the gallery, with the
/// gallery icon and no stop number. Once the visitor is in that gallery, the card names the artwork.
private struct VisitCard: View {
    @ObservedObject var navigator: JourneyNavigator
    @ObservedObject var session: ProximiioMapSession
    /// The gallery outlines, for "GALLERY · <name>".
    let galleries: [Gallery]
    /// The gallery the card names instead of the artwork.
    let galleryAhead: Gallery?
    /// The icon of the gallery's amenity in the venue data (PM, Monday "Gallery icons missing from
    /// instructions", 2026-10-28).
    var galleryIcon: UIImage?
    let places: [VenuePlace]
    /// The map shows a floor without positioning: the card names the stop, with no instruction
    /// from fixes of another floor.
    var isOnFloorWithoutPositioning = false
    /// The next stop's floor on the way back from a floor without positioning: "NEXT STOP IS LEVEL 1"
    /// and "Head to Level 1 by lift or stairs".
    var returningToLevel: Int?
    /// The subtitle of the card of a paused journey; `nil` while the journey is not paused.
    var pausedText: String?
    /// "Resume your Journey" on the card of a paused journey.
    var onResumeFromPause: () -> Void = {}
    let onResume: () -> Void

    private var visitorGallery: Gallery? {
        session.position.flatMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries) }
    }

    private var state: VisitCardState {
        VisitCardState.make(
            activeStop: navigator.activeStop,
            hasArrived: navigator.hasArrived,
            isFinished: navigator.isFinished,
            visitorLevel: session.position?.floor?.level
        )
    }

    private var stopNumber: Int? {
        navigator.activeStop.flatMap { VisitPlan.numbers(for: navigator.journey)[$0.id] }
    }

    var body: some View {
        if let pausedText {
            PlaceInfoCard(
                title: String(localized: "Journey paused", bundle: .module),
                subtitle: pausedText,
                primary: "Resume your Journey",
                onPrimary: onResumeFromPause
            )
        } else if let detour = navigator.detourStop {
            // An amenity detour (PM review 2026-10-12): no number, "Amenity · Level 1".
            PlaceInfoCard(
                title: detour.title,
                subtitle: places.first { $0.id == detour.id }?.cardSubtitle
                    ?? detour.floor.map { String(localized: "Level \(Int($0.level.rounded()))", bundle: .module) } ?? "",
                primary: "Resume your Journey",
                onPrimary: onResume
            )
        } else {
            stopCard
        }
    }

    private var stopCard: some View {
        VStack(spacing: 10) {
            StopInfoCard(caption: caption, title: title, instruction: instruction, remaining: remaining, keepsInstructionLine: keepsInstructionLine) {
                icon
            } trailing: {
                if case .nextStopOnOtherLevel(_, let level) = state {
                    OutlineBadge(text: "L\(level)").accessibilityLabel(Text("Level \(level)", bundle: .module))
                }
            } badges: {
                if let artwork = namedArtwork { ArtworkBadges(place: artwork) }
            }
        }
    }

    private var showsStopNumber: Bool {
        GalleryFirst.showsStopNumber(state: state, galleryAhead: galleryAhead)
    }

    /// The place of the active stop while the title names it.
    private var namedArtwork: VenuePlace? {
        guard let stop = navigator.activeStop else { return nil }
        let namesStop = switch state {
        case .walking: isOnFloorWithoutPositioning || galleryAhead == nil
        case .atStop: true
        default: isOnFloorWithoutPositioning
        }
        return namesStop ? places.first { $0.id == (stop.poiID ?? stop.id) } : nil
    }

    private var caption: LocalizedStringKey {
        if let returningToLevel { return "NEXT STOP IS LEVEL \(returningToLevel)" }
        if isOnFloorWithoutPositioning { return "NEXT STOP" }
        switch state {
        case .nextStopOnOtherLevel(let stop, _):
            return "NEXT STOP IS \(galleryAhead?.name ?? stop)"
        case .starting, .walking:
            if galleryAhead != nil { return "NEXT STOP" }
            if let stop = navigator.activeStop, VisitPlan.isLastOpenStop(stop, in: navigator.journey) { return "LAST STOP" }
            if let gallery = visitorGallery { return "GALLERY · \(gallery.name)" }
            return "NEXT STOP"
        case .atStop: return "CURRENT ARTWORK"
        case .finished: return "JOURNEY COMPLETE"
        }
    }

    private var title: String {
        if isOnFloorWithoutPositioning, let stop = navigator.activeStop { return galleryAhead?.name ?? stop.title }
        return switch state {
        case .starting: String(localized: "Your journey", bundle: .module)
        case .walking(let stop): galleryAhead?.name ?? stop
        case .atStop(let stop): stop
        case .nextStopOnOtherLevel(_, let level): levelChangeTitle(stopLevel: level)
        case .finished: String(localized: "You've walked your route", bundle: .module)
        }
    }

    /// The route's level changes.
    private var markers: [RouteGeometry.Marker] {
        session.routeRenderer?.geometry?.markers ?? []
    }

    private func levelChangeTitle(stopLevel: Int) -> String {
        GuidanceText.levelChangeTitle(
            markers: markers,
            visitorLevel: session.position?.floor?.level,
            stopLevel: stopLevel
        )
    }

    private var instruction: String? {
        // The navigator keeps a stop that no route with the visitor's accessibility needs reaches,
        // with no route line. In a personalised journey the visitor can skip it in the list.
        if let returningToLevel {
            return String(localized: "Head to Level \(returningToLevel) by lift or stairs", bundle: .module)
        }
        if isOnFloorWithoutPositioning {
            return String(localized: "Your position is not shown on this level.", bundle: .module)
        }
        if let stop = navigator.activeStop, case .noAccessibleRoute = navigator.noRouteReasons[stop.id] {
            return String(localized: "No route to this stop with your accessibility settings.", bundle: .module)
        }
        switch state {
        case .walking:
            return navigator.guidance.map { GuidanceText.instruction(for: $0, markers: markers) }
        case .nextStopOnOtherLevel(_, let level):
            // At the level change the instruction repeats the title; the card shows it once.
            guard let guidance = navigator.guidance else { return nil }
            let text = GuidanceText.instruction(for: guidance, markers: markers)
            return text == levelChangeTitle(stopLevel: level) ? nil : text
        default: return nil
        }
    }

    /// On the way to a stop the card keeps the instruction line, also while the route is routed again.
    private var keepsInstructionLine: Bool {
        switch state {
        case .walking, .nextStopOnOtherLevel: true
        default: false
        }
    }

    private var remaining: String? {
        if isOnFloorWithoutPositioning { return nil }
        switch state {
        case .walking, .nextStopOnOtherLevel:
            guard let guidance = navigator.guidance, !guidance.isOffRoute, !guidance.hasArrived else { return nil }
            return GuidanceText.remaining(metres: guidance.remainingMeters)
        default: return nil
        }
    }

    /// The lift or stairs of the next level change, while the next stop is on another floor (PM,
    /// Monday "Stairs&elevator icon disappeared from instructions", 2026-10-27).
    private var levelChangeIcon: GADIcon? {
        guard case .nextStopOnOtherLevel = state,
              let change = GuidanceText.levelChange(markers: markers, visitorLevel: session.position?.floor?.level)
        else { return nil }
        return GADIcon.levelChanger(featureType: change.featureType)
    }

    @ViewBuilder private var icon: some View {
        if let levelChangeIcon {
            levelChangeIcon.image.resizable().scaledToFit().frame(width: 20, height: 20)
        } else {
            stateIcon
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch state {
        case .walking, .atStop, .nextStopOnOtherLevel:
            if let stopNumber, showsStopNumber {
                Text("\(stopNumber)", bundle: .module).textStyle(.bodyMedium)
            } else if galleryAhead != nil {
                if let galleryIcon {
                    Image(uiImage: galleryIcon).resizable().scaledToFit().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "photo.artframe")
                }
            } else {
                Image(systemName: "arrow.up")
            }
        case .starting: Image(systemName: "arrow.up")
        case .finished: Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold))
        }
    }
}

/// The spinner in the middle of the screen while the map draws the venue and, with stops, until the
/// first leg is routed (PM, Monday "Spinner on map loading center", 2026-10-26). The stop card shows
/// "Your journey" meanwhile.
private struct StartingSpinner: View {
    @ObservedObject var navigator: JourneyNavigator
    let session: ProximiioMapSession
    let timeout: TimeInterval
    let hasStops: Bool

    var body: some View {
        MapLoadingSpinner(session: session, timeout: timeout, isBusy: hasStops && navigator.activeStop == nil && !navigator.isFinished)
    }
}

/// "Skip this artwork?" bottom sheet.
private struct SkipConfirmation: View {
    let stop: JourneyStop
    let onSkip: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Skip this artwork?", bundle: .module).textStyle(.h1Bold)
            Text(stop.title).textStyle(.largeBodyRegular)
            Text("It will be removed from your route. Artworks you have visited stay saved.", bundle: .module)
                .textStyle(.bodySmallRegular)
                .padding(.bottom, 20)
            Button(String(localized: "Skip artwork", bundle: .module), action: onSkip).buttonStyle(.primary)
            Button(String(localized: "Keep it", bundle: .module), action: onKeep).buttonStyle(.textAction)
        }
        // Less space under "Keep it" (PM, Monday "Skip artwork popup too large", 2026-10-28).
        .overlaySheetStyle(bottomPadding: 12)
    }
}

/// "Rerouting you…" in the middle of the map (PM, Monday "Rerouting calculation view", 2026-10-26).
private struct ReroutingCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Rerouting you…", bundle: .module).textStyle(.bodyMedium)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

extension MapCoordinate {
    var proximiio: ProximiioCoordinate { ProximiioCoordinate(latitude: latitude, longitude: longitude) }
}
