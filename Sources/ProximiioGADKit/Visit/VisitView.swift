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
import CoreLocation
import Proximiio
import ProximiioMap
import SwiftUI

public struct VisitView: View {
    @Environment(\.visitEventHandler) private var emit
    @Environment(\.wristbandConnectionScreen) private var connectionScreen
    @Environment(\.routeAccessibility) private var hostAccessibility
    @AppStorage(RouteAccessibility.accessibleRoutesKey) private var accessibleRoutes = false
    @State private var controller: VisitController
    @State private var mode: VisitMode = .map
    @State private var stopToSkip: JourneyStop?
    @State private var monitor: TrackingMonitor
    @State private var places: [VenuePlace] = []
    /// The alert the visitor dismissed. It is shown again only after tracking recovers.
    @State private var dismissedHealth: TrackingHealth?
    /// Name of the geofence (gallery) the visitor is in, from `sdk.geofenceEvents()`.
    @State private var currentGallery: String?
    @State private var liveActivity = VisitLiveActivity()
    @State private var isShowingAmenities = false
    /// The amenity picked from search, shown on a card before it becomes a detour.
    @State private var selectedAmenity: VenuePlace?
    /// The amenity whose detour waits for "Change your route?".
    @State private var amenityToConfirm: VenuePlace?
    /// EC04a–c: the full-screen "Where are you?" choice.
    @State private var locationChoice: LocationChoice?
    /// EC04d: the soft prompt for an uncertain position near the active stop.
    @State private var lowConfidenceStop: JourneyStop?
    /// Prompt kinds the visitor answered, and when; they stay quiet for a while.
    @State private var answeredAmbiguity: [String: Date] = [:]
    @State private var isConfirmingExit = false
    @State private var galleries: [Gallery] = []
    /// Galleries the visitor has been in during this visit.
    @State private var visitedGalleries: Set<String> = []
    @State private var mapLayers = JourneyMapLayers()
    @State private var isShowingWrapUp = false
    /// The pairing flow, opened from `WristbandEndedSheet`: the host app's
    /// `wristbandConnectionScreen`, else `WristbandPairingView`.
    @State private var pairing: WristbandPairing?
    /// `true` from "Connect a wristband" until the pairing flow closes. Hides the alert sheet.
    @State private var isPairing = false
    @State private var stopNotifier = StopNearbyNotifier()
    private let venue: VenueService
    private let wristband: WristbandSession
    private let kind: JourneyKind
    let onClose: () -> Void

    private var accessibility: RouteAccessibility {
        RouteAccessibility.effective(hostNeeds: hostAccessibility, accessibleRoutes: accessibleRoutes)
    }

    public init(
        venue: VenueService,
        wristband: WristbandSession,
        journey: Journey,
        kind: JourneyKind = .personalised,
        onClose: @escaping () -> Void
    ) {
        self.venue = venue
        self.wristband = wristband
        self.kind = kind
        _monitor = State(initialValue: TrackingMonitor(sdk: venue.sdk))
        let session = ProximiioMapSession(
            sdk: venue.sdk,
            // The leg keeps its shape until the arrival; the walked part is translucent (PM review
            // 2026-10-12). No separate trail.
            options: MapStyle.options(routeMarkers: false)
        )
        var rules = JourneyRules.visit
        #if DEBUG
        if DebugLaunch.current.visitAutoAdvance { rules.advance = .onDeparture(meters: 5) }
        #endif
        _controller = State(initialValue: VisitController(session: session, journey: journey, rules: rules))
        self.onClose = onClose
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenBackground.map.view
                VisitLiveActivityDriver(navigator: controller.navigator, session: controller.session, liveActivity: liveActivity)
                VStack(spacing: 10) {
                    MapGlassFrame {
                        ProximiioMapView(session: controller.session)
                            .clearBackground()
                        if mode == .list {
                            VisitStopList(controller: controller, galleries: kind.listsGalleries ? galleries : [], places: places, allowsSkip: kind.allowsSkip, onSkip: { stop in
                                stopToSkip = stop
                                emit(.skipRequested(stop))
                            })
                                .background(Palette.white.opacity(0.92))
                                .transition(.opacity)
                        }
                    } overlay: {
                        cardOverlay
                    }
                    BottomGlassBar {
                        Button(action: requestClose) {
                            Image(systemName: "chevron.backward").font(.system(size: 18, weight: .medium))
                        }
                        .buttonStyle(RoundGlassButtonStyle())
                        .accessibilityLabel(Text("Back", bundle: .module))
                    } trailing: {
                        Button { withAnimation { mode = mode == .map ? .list : .map } } label: {
                            Image(systemName: mode == .map ? "list.bullet" : "map").font(.system(size: 18, weight: .medium))
                        }
                        .buttonStyle(RoundGlassButtonStyle())
                        .accessibilityLabel(mode == .map ? Text("List", bundle: .module) : Text("Map", bundle: .module))
                    }
                }
                // The map ignores the safe area; the card starts below the status bar as in the design.
                .padding(.top, geometry.safeAreaInsets.top + 8)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom - 14, 4))
            }
            .ignoresSafeArea()
        }
        .animation(.default, value: mode)
        .onChange(of: mode) { _, mode in emit(.modeChanged(mode)) }
        .onChange(of: accessibility) { _, accessibility in
            Task { await controller.setAccessibility(accessibility) }
        }
        .task {
            controller.onArtworkDone = { [emit] stop, isActiveStop in
                emit(isActiveStop ? .artworkReached(stop) : .artworkVisitedOutOfOrder(stop))
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
            let features = await venue.sdk.features()
            places = VenuePlace.all(in: features)
            controller.artworkRemoteIDs = Dictionary(
                places.compactMap { place in place.remoteID.map { (place.id, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
            // The journey map shows artworks only as the numbered stop markers. Amenities,
            // galleries and level changers stay (PM review 2026-10-12).
            controller.session.hiddenFeatureIDs = Set(places.filter(\.isArtwork).map(\.id))
            controller.artworkAreas = Dictionary(
                await venue.sdk.geofences().compactMap { geofence in
                    geofence.isArtwork ? geofence.remoteId.map { ($0, ArtworkArea(geofence)) } : nil
                },
                uniquingKeysWith: { first, _ in first }
            )
            galleries = await Gallery.load(from: venue.sdk, features: features, places: places)
            FieldLog.log("galleries: \(galleries.map { "\($0.name) L\(Int($0.level))" }.joined(separator: ", "))")
            await MapStyle.waitForCanvas(of: controller.session)
            controller.session.journeyStopMarkerStyle = MapStyle.journeyStops
            // No walked legs: the map shows the trail of the current leg only (PM review 2026-10-12).
            mapLayers.attach(to: controller.session)
            refreshMapLayers()
            await controller.start(accessibility: accessibility)
            // Starts the heading-up follow once the journey is drawn (PM review 2026-10-12: the
            // map did not turn until "Centre on me").
            if controller.session.position != nil { recentre(withHeading: true, reason: "journey started") }
        }
        .task {
            for await event in await venue.sdk.geofenceEvents() {
                FieldLog.log("geofence: \(event)")
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
            if isFinished { isShowingWrapUp = true }
        }
        .fullScreenCover(isPresented: $isShowingWrapUp) {
            JourneyCompleteView(venue: venue) {
                isShowingWrapUp = false
                controller.end()
                onClose()
            }
        }
        .sheet(isPresented: $isConfirmingExit) {
            let stops = controller.navigator.journey.stops.filter { $0.state != .skipped }
            ExitConfirmationSheet(
                visited: stops.filter { $0.state == .done }.count,
                total: stops.count,
                onLeave: {
                    isConfirmingExit = false
                    emit(.exitConfirmed)
                    onClose()
                },
                onCarryOn: {
                    isConfirmingExit = false
                    emit(.exitCancelled)
                }
            )
        }
        .fullScreenCover(item: $locationChoice) { choice in
            LocationChoiceView(
                choice: choice,
                level: controller.session.position?.floor.map { String(localized: "Level \(Int($0.level.rounded()))", bundle: .module) },
                gallery: currentGallery,
                onPick: { option in pick(option, in: choice) },
                onClose: {
                    answeredAmbiguity[choice.kind] = .now
                    locationChoice = nil
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
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    locationChoice = manualChoice()
                }
            }
        }
        .onDisappear {
            monitor.stop()
            liveActivity.end()
        }
        .onChange(of: monitor.health) { _, health in
            if health == .tracking { dismissedHealth = nil }
        }
        .sheet(isPresented: isShowingTrackingAlert) {
            if let notice = wristband.endNotice {
                WristbandEndedSheet(notice: notice, onConnect: connectWristband, onBackToHub: onClose)
                    .interactiveDismissDisabled()
                    .onAppear {
                        FieldLog.log("sheet: wristband ended (\(wristband.state.map(WristbandCopy.logLine) ?? "-")), last fix \(monitor.lastFix?.formatted(.iso8601) ?? "-")")
                    }
            } else {
                TrackingAlertSheet(
                    health: monitor.health,
                    lastSeen: monitor.lastSeen(in: places),
                    activeStopNumber: controller.navigator.activeStop.flatMap { VisitPlan.numbers(for: controller.navigator.journey)[$0.id] },
                    canRouteToDesk: VenuePlace.welcomeDesk(in: places) != nil,
                    onSearchAgain: searchAgain,
                    onRouteToDesk: routeToDesk,
                    onPickStop: {
                        dismissedHealth = monitor.health
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            locationChoice = manualChoice()
                        }
                    },
                    onDismiss: { dismissedHealth = monitor.health }
                )
                .interactiveDismissDisabled()
                .onAppear {
                    FieldLog.log("sheet: tracking \(monitor.health), last fix \(monitor.lastFix?.formatted(.iso8601) ?? "-")")
                }
            }
        }
        .fullScreenCover(item: $pairing, onDismiss: pairingClosed) { pairing in
            if let connectionScreen {
                connectionScreen { self.pairing = nil }
            } else {
                WristbandPairingView(pairing: pairing) { self.pairing = nil }
            }
        }
        .onChange(of: controller.session.position == nil) { _, hasNoPosition in
            if !hasNoPosition { recentre(reason: "first position") }
        }
        .levelChangeAnimation(for: controller.session, venue: venue)
        .onReceive(controller.session.$guidance) { _ in
            Task { @MainActor in
                refreshConnector()
                controller.checkArtworkGeofences()
            }
        }
        // The session updates the guidance after the position on every fix; a fix without guidance
        // is checked on the position.
        .onReceive(controller.session.$position) { position in
            checkStopNearby(position: position, guidance: controller.navigator.guidance)
        }
        .onReceive(controller.navigator.$guidance) { guidance in
            checkStopNearby(position: controller.session.position, guidance: guidance)
        }
        .onChange(of: controller.navigator.activeStop?.id) { _, _ in
            checkStopNearby(position: controller.session.position, guidance: controller.navigator.guidance)
        }
        .onChange(of: controller.navigator.journey) { _, journey in VisitStore.save(journey) }
        .onReceive(controller.navigator.$journey) { _ in Task { @MainActor in refreshMapLayers() } }
        .onReceive(controller.session.$selectedFloor) { _ in
            Task { @MainActor in
                refreshMapLayers()
                refreshConnector()
            }
        }
        .sheet(item: $stopToSkip) { stop in
            SkipConfirmation(stop: stop) {
                stopToSkip = nil
                Task { await controller.skip(stopID: stop.id) }
                emit(.stopSkipped(stop))
            } onKeep: {
                stopToSkip = nil
                emit(.skipCancelled(stop))
            }
        }
        .sheet(item: $amenityToConfirm) { place in
            ChangeRouteConfirmation(place: place, nextStop: nextStopName) {
                amenityToConfirm = nil
                Task { await controller.detour(to: place) }
                emit(.detourStarted(place))
            } onClose: {
                amenityToConfirm = nil
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

    /// The tracking alert, or `WristbandEndedSheet` while the wristband session is ended. An
    /// ended session delivers no positions, so the tracking alert would not clear.
    private var isShowingTrackingAlert: Binding<Bool> {
        Binding(
            get: {
                guard !isPairing, stopToSkip == nil else { return false }
                if wristband.endNotice != nil { return true }
                return (monitor.health == .lostPlace || monitor.health == .stoppedResponding)
                    && monitor.health != dismissedHealth
            },
            set: { if !$0 { dismissedHealth = monitor.health } }
        )
    }

    /// The off-route warning, unless another prompt is up.
    private var isShowingOffRouteWarning: Binding<Bool> {
        Binding(
            get: { controller.isOffRoute && stopToSkip == nil && amenityToConfirm == nil && !isShowingTrackingAlert.wrappedValue },
            set: { if !$0 { controller.dismissOffRoute() } }
        )
    }

    // MARK: Map layers

    /// Posts the "next stop nearby" notification and reports `stopNearby` once per stop.
    private func checkStopNearby(position: VenuePosition?, guidance: RouteGuidance?) {
        if let stop = stopNotifier.update(position: position, stop: controller.navigator.activeStop, guidance: guidance) {
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
        let fills = galleries.compactMap { gallery -> JourneyMapLayers.GalleryFill? in
            if gallery.id == destination?.id { return .init(gallery: gallery, isDestination: true) }
            return visited.contains(gallery.id) ? .init(gallery: gallery, isDestination: false) : nil
        }
        mapLayers.update(fills: fills, level: controller.session.selectedFloor.level)
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

    /// Back: a visit in progress asks first (03.10); a visit not started or finished closes.
    private func requestClose() {
        let journey = controller.navigator.journey
        let started = journey.stops.contains { $0.state == .done || $0.state == .skipped }
        if started && !controller.navigator.isFinished {
            isConfirmingExit = true
            emit(.exitRequested)
        } else {
            onClose()
        }
    }

    // MARK: Ambiguous location (EC04)

    /// Prompts stay quiet this long after the visitor answered one of the same kind.
    private static let ambiguityQuietPeriod: TimeInterval = 120

    private var isPresentingSomething: Bool {
        locationChoice != nil || lowConfidenceStop != nil || stopToSkip != nil || isConfirmingExit || controller.isOffRoute
            || amenityToConfirm != nil
            || isShowingWrapUp || isShowingTrackingAlert.wrappedValue
    }

    private func evaluateAmbiguity() {
        guard !isPresentingSomething, monitor.health == .tracking, let coordinate = monitor.lastCoordinate else { return }
        let navigator = controller.navigator
        let input = LocationAmbiguity.Input(
            coordinate: coordinate,
            level: monitor.lastLevel,
            horizontalAccuracy: max(0, monitor.lastAccuracy ?? 0),
            activeStop: navigator.hasArrived ? nil : navigator.activeStop,
            galleries: LocationAmbiguity.galleries(in: places),
            currentGallery: currentGallery
        )
        guard let ambiguity = LocationAmbiguity.evaluate(input) else { return }
        if let answered = answeredAmbiguity[ambiguity.kind], Date.now.timeIntervalSince(answered) < Self.ambiguityQuietPeriod {
            return
        }
        FieldLog.log("ambiguous location: \(ambiguity.kind)")
        switch ambiguity {
        case .betweenGalleries(let galleries):
            locationChoice = LocationChoice(
                kind: ambiguity.kind,
                questionLight: "You're between galleries.",
                questionBold: "Which one are you in?",
                options: galleries.map { .init(id: $0.id, title: $0.title, action: .gallery($0.title)) } + [.somewhereElse]
            )
        case .lowConfidence(let stop):
            lowConfidenceStop = stop
        }
    }

    /// EC04c: the visitor picks the stop they are at.
    private func manualChoice() -> LocationChoice {
        let open = controller.navigator.journey.stops.filter { $0.state == .pending || $0.state == .active }
        return LocationChoice(
            kind: "manual",
            questionBold: "Where are you?",
            caption: "Pick the artwork you are at",
            options: open.map { stop in
                .init(id: stop.id, title: stop.title, subtitle: stop.floor.map { String(localized: "Level \(Int($0.level.rounded()))", bundle: .module) },
                      action: .activateStop(stop.id))
            } + [.somewhereElse]
        )
    }

    private func pick(_ option: LocationChoice.Option, in choice: LocationChoice) {
        answeredAmbiguity[choice.kind] = .now
        locationChoice = nil
        switch option.action {
        case .activateStop(let id):
            Task { await controller.activate(stopID: id) }
            mode = .map
            if let stop = controller.navigator.journey.stops.first(where: { $0.id == id }) { emit(.stopChosen(stop)) }
        case .gallery(let name):
            currentGallery = name
            emit(.galleryChosen(name))
        case .somewhereElse:
            break
        }
    }

    /// Re-attaches the wristband binding's provider, which reopens its relay-api stream.
    /// Closes `WristbandEndedSheet` and opens the pairing flow once the sheet is gone.
    private func connectWristband() {
        isPairing = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            pairing = WristbandPairing(connector: wristband)
        }
    }

    /// After a bind, re-attaching the provider reopens the relay-api position stream.
    /// Without a session, `WristbandEndedSheet` shows again.
    private func pairingClosed() {
        isPairing = false
        guard wristband.isActive else { return }
        dismissedHealth = nil
        Task { await venue.attachBinding() }
    }

    private func searchAgain() {
        dismissedHealth = monitor.health
        Task { await venue.attachBinding() }
    }

    /// Adds the Welcome Desk as a detour, so the route leads there and then back to the journey.
    private func routeToDesk() {
        dismissedHealth = monitor.health
        guard let desk = VenuePlace.welcomeDesk(in: places) else { return }
        Task { await controller.detour(to: desk) }
        mode = .map
        emit(.detourStarted(desk))
    }

    /// Controls inside the map card: toggle and search at the top, compass and floor at the
    /// trailing edge, the stop card at the bottom.
    private var cardOverlay: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                MapListToggle(showsList: Binding(get: { mode == .list }, set: { mode = $0 ? .list : .map }))
                Spacer()
                // In List mode the design hides search.
                if mode == .map {
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
            if mode == .map {
                HStack {
                    Spacer()
                    VStack(spacing: 5) {
                        GlassSquareButton(action: {
                            controller.session.followMyFloor()
                            recentre(reason: "Centre on me")
                            emit(.recentred)
                        }) {
                            GADIcon.compass.image.resizable().scaledToFit().frame(width: 24, height: 24)
                        }
                        .accessibilityLabel(Text("Centre on me", bundle: .module))
                        AccessibleRoutesButton(isOn: $accessibleRoutes) { emit(.accessibleRoutesChanged($0)) }
                        GlassSquareButton(action: { controller.session.followMyFloor() }) {
                            Text(GuidanceText.floorLabel(controller.session.selectedFloor.level)).textStyle(.largeBodyBold)
                        }
                        .accessibilityLabel(Text("Floor \(GuidanceText.floorLabel(controller.session.selectedFloor.level))", bundle: .module))
                    }
                }
                if let place = selectedAmenity {
                    PlaceInfoCard(
                        title: place.title,
                        subtitle: place.cardSubtitle,
                        primary: "Go here",
                        onPrimary: {
                            selectedAmenity = nil
                            amenityToConfirm = place
                        },
                        onClose: { selectedAmenity = nil }
                    )
                } else {
                    VisitCard(
                        navigator: controller.navigator,
                        session: controller.session,
                        // Without galleries the card names the artwork at once.
                        galleries: kind.guidesToGalleryFirst ? galleries : [],
                        places: places,
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

/// "Change your route?" bottom sheet before an amenity becomes a detour (PM review 2026-10-12).
private struct ChangeRouteConfirmation: View {
    let place: VenuePlace
    let nextStop: String?
    let onGo: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Change your route?", bundle: .module).textStyle(.h1Bold)
            Group {
                if let nextStop {
                    Text("Navigating to \(place.title) adds a stop to your route to \(nextStop). Your journey progress is kept.", bundle: .module)
                } else {
                    Text("Navigating to \(place.title) adds a stop to your route. Your journey progress is kept.", bundle: .module)
                }
            }
            .textStyle(.bodySmallRegular)
            .padding(.bottom, 20)
            Button(String(localized: "Go here", bundle: .module), action: onGo).buttonStyle(.primary)
            Button(String(localized: "Close", bundle: .module), action: onClose).buttonStyle(.textAction)
        }
        .overlaySheetStyle()
    }
}

/// The card at the bottom of the map (Figma "Stop Info"): an icon in a white circle, the
/// caption, the stop, and the instruction with distance and time.
///
/// Gallery first (DAILY-CALL R2): while the visitor is outside the gallery of the next stop, the
/// card names the gallery and shows no stop number. After the visitor enters that gallery, the
/// card names the artwork until the stop changes. The route always leads to the artwork.
private struct VisitCard: View {
    @ObservedObject var navigator: JourneyNavigator
    @ObservedObject var session: ProximiioMapSession
    let galleries: [Gallery]
    let places: [VenuePlace]
    let onResume: () -> Void
    /// The stop whose gallery the visitor has entered.
    @State private var stopWithGalleryReached: String?

    private var stopGallery: Gallery? {
        navigator.activeStop.flatMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries) }
    }

    private var visitorGallery: Gallery? {
        session.position.flatMap { Gallery.containing($0.coordinate.proximiio, level: $0.floor?.level, in: galleries) }
    }

    /// The gallery the card names instead of the artwork.
    private var galleryAhead: Gallery? {
        GalleryFirst.galleryAhead(activeStopID: navigator.activeStop?.id, stopGallery: stopGallery, reachedStopID: stopWithGalleryReached)
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
            }
            .onReceive(session.$position) { _ in markGalleryReached() }
            .onChange(of: navigator.activeStop?.id) { _, _ in markGalleryReached() }
        }
    }

    private var showsStopNumber: Bool {
        GalleryFirst.showsStopNumber(state: state, galleryAhead: galleryAhead)
    }

    private func markGalleryReached() {
        stopWithGalleryReached = GalleryFirst.reachedStopID(
            activeStopID: navigator.activeStop?.id, stopGallery: stopGallery,
            visitorGallery: visitorGallery, reachedStopID: stopWithGalleryReached
        )
    }

    private var caption: LocalizedStringKey {
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
        switch state {
        case .starting: String(localized: "Your journey", bundle: .module)
        case .walking(let stop): galleryAhead?.name ?? stop
        case .atStop(let stop): stop
        case .nextStopOnOtherLevel(_, let level): String(localized: "Take the lift to level \(level)", bundle: .module)
        case .finished: String(localized: "You've walked your route", bundle: .module)
        }
    }

    private var instruction: String? {
        // The navigator keeps a stop that no route with the visitor's accessibility needs reaches,
        // with no route line. In a personalised journey the visitor can skip it in the list.
        if let stop = navigator.activeStop, case .noAccessibleRoute = navigator.noRouteReasons[stop.id] {
            return String(localized: "No route to this stop with your accessibility settings.", bundle: .module)
        }
        switch state {
        case .walking, .nextStopOnOtherLevel:
            if let guidance = navigator.guidance { return GuidanceText.instruction(for: guidance) }
            if case .nextStopOnOtherLevel = state { return String(localized: "Go to the lift", bundle: .module) }
            return nil
        default: return nil
        }
    }

    private var remaining: String? {
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
