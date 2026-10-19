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
    /// Name of the geofence (gallery) the visitor is in, from `sdk.geofenceEvents()`.
    @State private var currentGallery: String?
    @State private var liveActivity: VisitLiveActivity
    @State private var isShowingAmenities = false
    /// The amenity picked from search, shown on a card before it becomes a detour.
    @State private var selectedAmenity: VenuePlace?
    /// The amenity whose detour waits for "Change your route?".
    @State private var amenityToConfirm: VenuePlace?
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
    /// Galleries the visitor has been in during this visit.
    @State private var visitedGalleries: Set<String> = []
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
    /// `venue.settings` when the view was created.
    private let settings: GADSettings
    /// Back, "Leave the tour" and the close button of Journey Complete. `nil`: no Back and no "Leave
    /// the tour here"; Journey Complete's close button returns to the map.
    let onClose: (() -> Void)?

    private var accessibility: RouteAccessibility {
        RouteAccessibility.effective(hostNeeds: hostAccessibility, accessibleRoutes: accessibleRoutes)
    }

    /// - Parameters:
    ///   - options: What the screen does beyond drawing the journey.
    ///   - mode: Map or List when the screen opens.
    ///   - incoming: The host app's journey after a change (`ProximiMapView`).
    ///   - onClose: See `onClose`.
    ///   - persist: Stores the journey after each change (`VisitController.persist`).
    init(
        venue: VenueService,
        journey: Journey,
        kind: JourneyKind = .personalised,
        options: ProximiMapView.Options = .all,
        mode: VisitMode = .map,
        incoming: IncomingJourney? = nil,
        persist: @escaping @MainActor (Journey?) -> Void = VisitStore.persist,
        onClose: (() -> Void)?
    ) {
        self.venue = venue
        self.kind = kind
        self.options = options
        self.incoming = incoming
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
            options: MapStyle.options(routeMarkers: false, followZoom: settings.followZoom)
        )
        var rules = JourneyRules.visit
        #if DEBUG
        if DebugLaunch.current.visitAutoAdvance { rules.advance = .onDeparture(meters: 5) }
        #endif
        _controller = State(initialValue: VisitController(
            session: session, journey: journey, rules: rules, keepsOrder: kind.keepsOrder,
            managesProgress: options.contains(.progress),
            deviationPolicy: options.contains(.prompts) ? .askApp : .automatic,
            settings: settings, persist: persist
        ))
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if options.contains(.background) { ScreenBackground.map.view }
                if options.contains(.liveActivity) && hasStops {
                    VisitLiveActivityDriver(navigator: controller.navigator, session: controller.session, liveActivity: liveActivity)
                }
                VStack(spacing: 10) {
                    MapGlassFrame {
                        ProximiioMapView(session: controller.session)
                        if showsList {
                            VisitStopList(controller: controller, galleries: galleries, galleryNames: galleryNames, groupsByGallery: kind.listsGalleries, places: places, allowsSkip: kind.allowsSkip, onSkip: requestSkip)
                                .background(Palette.white.opacity(0.92))
                                .transition(.opacity)
                        }
                        if amenityToConfirm != nil {
                            // "Change your route?" fades the map (Figma node 10889:112476).
                            Palette.white.opacity(0.5).transition(.opacity)
                        }
                    } overlay: {
                        cardOverlay
                    }
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
                // The map ignores the safe area; the card starts below the status bar as in the design.
                .padding(.top, geometry.safeAreaInsets.top + 8)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom - 14, 4))
                if case .changing(let change) = floorGuide.phase {
                    FloorChangeView(change: change)
                        .onTapGesture { floorGuide.showFloor() }
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.default, value: mode)
        .animation(.easeInOut(duration: 0.2), value: floorGuide.phase)
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
                emit(.journey(event))
            }
        }
        .task {
            #if DEBUG
            if DebugLaunch.current.visitList { mode = .list }
            #endif
            monitor.start()
            await loadVenueData()
            await MapStyle.waitForCanvas(of: controller.session)
            controller.session.journeyStopMarkerStyle = MapStyle.journeyStops
            if let canvas = controller.session.canvas { MapStyle.registerStopIcons(on: canvas) }
            // No walked legs: the map shows the trail of the current leg only (PM review 2026-10-12).
            mapLayers.attach(to: controller.session)
            refreshMapLayers()
            // A journey without stops shows the map alone; the navigator would report it finished.
            if hasStops {
                await controller.start(accessibility: accessibility)
                // A visitor who opens the journey inside the first artwork's geofence.
                checkArrival()
            }
            // Starts the heading-up follow once the journey is drawn (PM review 2026-10-12: the
            // map did not turn until "Centre on me").
            if controller.session.position != nil { recentre(withHeading: true, reason: "journey started") }
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
                    visitedGalleries.insert(galleries.first { $0.name == geofence.name }?.id ?? geofence.id)
                    refreshMapLayers()
                case .exited(let geofence, _) where geofence.isGallery:
                    if currentGallery == geofence.name { currentGallery = nil }
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
            if isFinished && options.contains(.prompts) { isShowingWrapUp = true }
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
        }
        // No tracking or wristband alerts: the host app handles the wristband states
        // (PM 2026-10-15).
        .onChange(of: monitor.health) { _, health in emit(.trackingChanged(health)) }
        .onChange(of: controller.session.position == nil) { _, hasNoPosition in
            if !hasNoPosition { recentre(reason: "first position") }
        }
        .followsVisitorFloor(controller.session, venue: venue, isPaused: floorGuide.isActive)
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
            }
        }
        // The session updates the guidance after the position on every fix; a fix without guidance
        // is checked on the position. The map publishes guidance only on a leg with a route, so the
        // arrival is checked on the position (field test 2026-10-19).
        .onReceive(controller.session.$position) { position in
            checkStopNearby(position: position, guidance: controller.navigator.guidance)
            // `$position` publishes before the session stores the fix.
            Task { @MainActor in checkArrival() }
        }
        .onReceive(controller.navigator.$guidance) { guidance in
            checkStopNearby(position: controller.session.position, guidance: guidance)
        }
        .onChange(of: controller.navigator.activeStop?.id) { _, _ in
            checkStopNearby(position: controller.session.position, guidance: controller.navigator.guidance)
            checkArrival()
        }
        .onChange(of: controller.navigator.journey) { _, journey in controller.persist(journey) }
        .onChange(of: venue.data.version) { _, _ in
            Task {
                await loadVenueData()
                refreshMapLayers()
                for stop in await controller.stopsWithoutPlace(places: places) {
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
        .sheet(isPresented: isShowingOffRouteWarning) {
            OffRouteWarning {
                Task { await controller.resumeJourney() }
                emit(.journeyResumed)
            } onClose: {
                controller.dismissOffRoute()
            }
        }
    }

    /// The off-route warning, unless another prompt is up.
    private var isShowingOffRouteWarning: Binding<Bool> {
        Binding(
            get: { options.contains(.prompts) && controller.isOffRoute && stopToSkip == nil && amenityToConfirm == nil && !floorGuide.isActive },
            set: { if !$0 { controller.dismissOffRoute() } }
        )
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
        let features = await venue.sdk.features()
        places = VenuePlace.all(in: features)
        controller.artworkRemoteIDs = Dictionary(
            places.compactMap { place in place.remoteID.map { (place.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        // The journey map shows artworks only as the numbered stop markers. Amenities,
        // galleries and level changers stay (PM review 2026-10-12). `mapLayers` draws the
        // level changers on every floor they serve.
        let levelChangers = LevelChangerPlace.all(in: features)
        mapLayers.updateLevelChangers(levelChangers)
        hiddenFeatureIDs = Set(places.filter(\.isArtwork).map(\.id) + levelChangers.map(\.id))
        controller.session.hiddenFeatureIDs = hiddenFeatureIDs.union(controller.galleryAhead.map { [$0.placeID] } ?? [])
        let geofences = await venue.sdk.geofences()
        controller.artworkAreas = VisitController.artworkAreas(of: geofences)
        let destinations = Gallery.destinations(geofences: geofences, places: places)
        controller.setGalleryFirst(isEnabled: kind.guidesToGalleryFirst, places: places, destinations: destinations)
        galleries = await Gallery.load(from: venue.sdk, features: features, places: places)
        galleryNames = Gallery.names(places: places)
        FieldLog.log("galleries: \(galleries.map { "\($0.name) L\(Int($0.level))" }.joined(separator: ", ")) · \(galleryNames.count) named by id · \(destinations.count) for gallery first")
    }

    // MARK: Map layers

    /// The amenity picked in the menu while its card or route is on screen.
    private var amenityOnMap: VenuePlace? {
        selectedAmenity ?? amenityToConfirm ?? routedAmenity
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
        // The red gallery marker takes the place of the gallery's own POI.
        controller.session.hiddenFeatureIDs = hiddenFeatureIDs.union(gallery.map { [$0.placeID] } ?? [])
        FieldLog.log("gallery first: \(gallery.map { "route ends at \($0.gallery.name)" } ?? "route ends at the artwork")")
    }

    /// Reports `stopNearby` once per stop.
    private func checkStopNearby(position: VenuePosition?, guidance: RouteGuidance?) {
        if let stop = stopNearby.update(position: position, stop: controller.navigator.activeStop, guidance: guidance) {
            emit(.stopNearby(stop))
        }
    }

    /// Stop markers and gallery fills for the current journey and floor.
    private func refreshMapLayers() {
        let journey = controller.navigator.journey
        let active = controller.navigator.activeStop
        let destination = active.flatMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries) }
        let visitedByStops = journey.stops.filter { $0.state == .done }
            .compactMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries)?.id }
        let visited = visitedGalleries.union(visitedByStops)
        // Gallery first: the outline of the gallery geofence the leg ends at, in place of the
        // outline that holds the artwork.
        let galleryAhead = controller.galleryAhead
        var fills = galleries.compactMap { gallery -> JourneyMapLayers.GalleryFill? in
            if gallery.id == destination?.id, galleryAhead == nil { return .init(gallery: gallery, isDestination: true) }
            return visited.contains(gallery.id) ? .init(gallery: gallery, isDestination: false) : nil
        }
        if let galleryAhead { fills.append(.init(gallery: galleryAhead.gallery, isDestination: true)) }
        mapLayers.update(fills: fills, level: controller.session.selectedFloor.level)
        mapLayers.updateGalleryMarker(galleryAhead.map {
            .init(coordinate: $0.entry, level: $0.gallery.level, label: $0.label)
        })
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
        let next = session.routeRenderer?.geometry?.markers.first {
            !$0.isCompleted && VenueLevel.same($0.from.level, level)
        }
        mapLayers.updateLevelChanger(next.map {
            .init(coordinate: $0.coordinate.proximiio, level: level, featureType: $0.featureType)
        })
    }

    /// `recentre` with a field-log line naming the caller.
    private func recentre(withHeading: Bool? = nil, reason: String) {
        FieldLog.log("recentre (\(reason)) · heading \(withHeading.map(String.init) ?? "default") · mode before \(controller.session.cameraMode)")
        controller.session.recentre(withHeading: withHeading)
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

    /// A swipe on a stop in the list: "Skip this artwork?" with `prompts`, else only the event.
    private func requestSkip(_ stop: JourneyStop) {
        if options.contains(.prompts) { stopToSkip = stop }
        emit(.skipRequested(stop))
    }

    /// Back: a visit in progress asks first (03.10) with `prompts`; otherwise Back closes.
    private func requestClose() {
        let journey = controller.navigator.journey
        let started = journey.stops.contains { $0.state == .done || $0.state == .skipped }
        if options.contains(.prompts) && started && !controller.navigator.isFinished {
            isConfirmingExit = true
            emit(.exitRequested)
        } else {
            onClose?()
        }
    }

    // MARK: Ambiguous location (EC04)

    private var isPresentingSomething: Bool {
        // Without prompts the off-route state shows nothing and does not hold the report back.
        lowConfidenceStop != nil || stopToSkip != nil || isConfirmingExit
            || (options.contains(.prompts) && controller.isOffRoute)
            || amenityToConfirm != nil || isShowingWrapUp || floorGuide.isActive
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
            if options.contains(.prompts) {
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
                        AmenityChipList(kinds: AmenityKind.shortcuts.filter { kind in places.contains(where: kind.matches) }) { kind in
                            isShowingAmenities = false
                            detour(to: kind)
                        }
                    }
                }
                }
            }
            .padding(.top, 22)
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
                        GlassSquareButton(action: {
                            floorGuide.leave()
                            controller.session.followMyFloor()
                        }) {
                            Text(GuidanceText.floorLabel(controller.session.selectedFloor.level)).textStyle(.largeBodyBold)
                        }
                        .accessibilityLabel(Text("Floor \(GuidanceText.floorLabel(controller.session.selectedFloor.level))", bundle: .module))
                    }
                }
                if let place = amenityToConfirm {
                    // "Change your route?" (Figma node 10889:112477): a card over the faded map
                    // with "Go here" and "Close" side by side (PM 2026-10-15).
                    PlaceInfoCard(
                        title: String(localized: "Change your route?", bundle: .module),
                        subtitle: changeRouteText(to: place),
                        primary: "Go here",
                        onPrimary: {
                            amenityToConfirm = nil
                            Task { await controller.detour(to: place) }
                            emit(.detourStarted(place))
                        },
                        onClose: { amenityToConfirm = nil }
                    )
                } else if let place = selectedAmenity {
                    PlaceInfoCard(
                        title: place.title,
                        subtitle: place.cardSubtitle,
                        primary: "Go here",
                        onPrimary: {
                            selectedAmenity = nil
                            if !hasStops {
                                Task { await route(to: place) }
                            } else if options.contains(.prompts) {
                                amenityToConfirm = place
                            } else {
                                Task { await controller.detour(to: place) }
                                emit(.detourStarted(place))
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
                } else if hasStops {
                    VisitCard(
                        navigator: controller.navigator,
                        session: controller.session,
                        galleries: galleries,
                        galleryAhead: controller.galleryAhead?.gallery,
                        places: places,
                        isOnFloorWithoutPositioning: floorGuide.isActive,
                        onResume: {
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
        .animation(.easeInOut(duration: 0.2), value: amenityToConfirm)
    }

    /// "Go here" on a map without a journey: the route from the visitor to `place`, as on the museum
    /// map. There is no navigator to add a detour to.
    private func route(to place: VenuePlace) async {
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
    }

    private func changeRouteText(to place: VenuePlace) -> String {
        if let nextStop = nextStopName {
            return String(localized: "Navigating to \(place.title) adds a stop to your route to \(nextStop). Your journey progress is kept.", bundle: .module)
        }
        return String(localized: "Navigating to \(place.title) adds a stop to your route. Your journey progress is kept.", bundle: .module)
    }

    /// Shows the nearest place of `kind` on a card. "Go here" and "Change your route?" add it as
    /// a journey detour (PM review 2026-10-12).
    private func detour(to kind: AmenityKind) {
        let here = controller.session.position
        let from = here.map { ProximiioCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        selectedAmenity = kind.nearest(in: places, from: from, level: here?.floor?.level)
        if let selectedAmenity { emit(.amenitySelected(selectedAmenity)) }
    }

    /// The gallery of the next artwork, or the artwork, for "Change your route?".
    private var nextStopName: String? {
        guard let stop = controller.navigator.journey.stops.first(where: { $0.kind != .detour && ($0.state == .active || $0.state == .pending) })
        else { return nil }
        return Gallery.containing(stop.coordinate.proximiio, level: stop.floor?.level, in: galleries)?.name ?? stop.title
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
    let places: [VenuePlace]
    /// The map shows a floor without positioning: the card names the stop, with no instruction
    /// from fixes of another floor.
    var isOnFloorWithoutPositioning = false
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
        if let detour = navigator.detourStop {
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
            StopInfoCard(caption: caption, title: title, instruction: instruction, remaining: remaining) {
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
        if isOnFloorWithoutPositioning, let stop = navigator.activeStop { return stop.title }
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

    private var remaining: String? {
        if isOnFloorWithoutPositioning { return nil }
        switch state {
        case .walking, .nextStopOnOtherLevel:
            guard let guidance = navigator.guidance, !guidance.isOffRoute, !guidance.hasArrived else { return nil }
            return GuidanceText.remaining(metres: guidance.remainingMeters)
        default: return nil
        }
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .walking, .atStop, .nextStopOnOtherLevel:
            if let stopNumber, showsStopNumber {
                Text("\(stopNumber)", bundle: .module).textStyle(.bodyMedium)
            } else if galleryAhead != nil {
                Image(systemName: "photo.artframe")
            } else {
                Image(systemName: "arrow.up")
            }
        case .starting: ProgressView()
        case .finished: Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold))
        }
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
        .overlaySheetStyle()
    }
}

/// "You've left your route" bottom sheet. The route is not redrawn while the visitor walks
/// elsewhere (PM review 2026-10-12); "Show the route from here" redraws it.
private struct OffRouteWarning: View {
    let onReroute: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("You've left your route", bundle: .module).textStyle(.h1Bold)
            Text("The route stays as it is until you return to it.", bundle: .module)
                .textStyle(.bodySmallRegular)
                .padding(.bottom, 20)
            Button(String(localized: "Show the route from here", bundle: .module), action: onReroute).buttonStyle(.primary)
            Button(String(localized: "Close", bundle: .module), action: onClose).buttonStyle(.textAction)
        }
        .overlaySheetStyle()
    }
}

extension MapCoordinate {
    var proximiio: ProximiioCoordinate { ProximiioCoordinate(latitude: latitude, longitude: longitude) }
}
