//
//  VisitController.swift
//  ProximiioGADKit
//
//  Owns the map session and the `JourneyNavigator` of a visit, persists the journey, and
//  implements skip.
//
//  Arrival at an artwork: entering the geofence of the active artwork (`artworkGeofenceEntered`).
//  Nagarro's audio guide reacts to the same enter event, so the map and the guide name the same
//  artwork at the same time. The geofence and the artwork POI share `remote_id`. A visitor already
//  inside the geofence when the leg starts gets no enter event, so every fix is also checked
//  against the artwork geofences (`checkArtworkGeofences`). A geofence the SDK counts the visitor
//  inside (`enteredGeofenceIDs`) counts too: the SDK exits a geofence only beyond 1.2 × its radius,
//  and its event stream does not repeat the geofences entered before the screen opened (field test
//  2026-10-19). Since SDK 6.0.0-beta.63 the SDK also exits a geofence only
//  `ProximiioConfiguration.geofenceExitDelay` after the position left it (`ProximiMap`:
//  `GADSettings.geofenceExitDelay`, 5 s; the SDK default is 3 s), so an artwork counts as inside up
//  to that long after the visitor left it. The journey moves to the next stop when the visitor
//  leaves the artwork's geofence (`GADSettings.advancesOnArtworkExit`; Nagarro, 2026-10-30): on the
//  SDK's exit event (`artworkGeofenceExited`), after `geofenceExitDelay` outside it without one, or
//  at once when the visitor is in another open artwork's geofence. Until then the artwork is reached
//  (`JourneyNavigator.markReached(stopID:)`): it stays the active stop with the destination marker,
//  and the navigator draws the leg to the next stop from the visitor (`drawsNextLegWhileReached`;
//  GAD PM and Nagarro, 2026-10-30). A reached artwork that the navigator moves past (a detour, a
//  chosen stop) is reported visited too. Without the setting the journey moves on
//  `GADSettings.artworkAdvanceDelay` after the arrival. There is no fallback by distance: an artwork
//  the visitor walks past without entering its geofence stays unvisited until it is skipped.
//  Out of order: a visitor inside the geofence of another open artwork for
//  `GADSettings.outOfOrderDwell` (0 s while testing) marks it visited, and the stops still ahead are
//  ordered again from the visitor (PM review 2026-10-12). A curated tour ignores such an artwork: it
//  stays open (`countsOutOfOrder`; PM, Monday "Curated tours: ignore other artworks", 2026-10-23).
//  An amenity has no geofence. A detour is reached within 5–10 m for 5 s (`GADSettings`)
//  and the journey continues only after "Resume your Journey" (`JourneyRules.visit`).
//
//  Skip and "choose this stop" edit the running navigator. Its route cache, event streams
//  and deviation state are kept. The arrival, out of order, gallery first and "Resume your Journey"
//  each read the journey before they change it, so they run one after another (`serially`).
//
//  Every leg uses the visitor's accessibility needs (`RouteAccessibility`). A new journey is ordered
//  floor by floor and gallery by gallery (`JourneyOrderStrategy.floorThenGallery`): the stop
//  nearest the visitor first, then the rest of its gallery, then the rest of its floor. Without a
//  fix the first stop stays first, and the first fix within `GADSettings.lateOrderWindow` orders the journey
//  again while no stop is reached. A restored journey keeps its order. After a detour the stops
//  still ahead are ordered again from the visitor. A curated tour (`keepsOrder`) is never ordered.
//
//  Off the route (PM, Monday "Personalized tour: off-route and re-route behaviour" and "Curated tour:
//  off-route and recalculation", 2026-10-26 and 2026-10-28): the visitor gets a warning (`isOffRoute`)
//  once they are `GADSettings.offRouteMeters` (12 m) off the leg to the current destination
//  (`checkLegDeviation`), also where a later leg of the journey passes, or off the whole journey
//  (`leftRoute`), far from it, or off it for too long. The navigator's `leftRoute` measures against
//  every leg still to walk, so a visitor heading to another artwork got no warning (PM's log of
//  2026-10-28, 22:39 UTC: 56 m off the leg). The warning comes before any routing: with
//  `ProximiMapView.Options.offRoutePrompt` the navigator routes nothing by itself
//  (`JourneyDeviationPolicy.askApp`). After the warning a personalised journey keeps the leg where the
//  visitor left it; when another open artwork is now the nearest stop, the stops ahead are ordered
//  again from the visitor and the leg leads to it (`checkCloserArtwork`). A curated tour is routed
//  again from the visitor after the warning (`reroutesAfterWarning`). A journey without the prompt is
//  routed again by the navigator (`.automatic`).
//
//  The warning stays open for `GADSettings.offRouteWarningSeconds`, unless the visitor closes it; the
//  routing after it does not close it (PM, Monday "Personalized tour: off-route and re-route behaviour",
//  2026-10-27). A visitor on a floor the route does not take for `GADSettings.wrongFloorSeconds` is
//  off the route too: the warning shows, and the journey is routed again from the visitor, a
//  personalised journey to the nearest open artwork, a curated tour to its next stop (PM, Monday
//  "Wrong floor to trigger off-route and re-routing", 2026-10-27).
//
//  An artwork visited out of order moves before the stops still to visit, so the numbers in the list
//  and on the map follow the visit order (PM, Monday "Personalized tour: renumbering artworks",
//  2026-10-26).
//
//  Without `managesProgress` (`ProximiMapView.Options.progress`) the host app moves the journey on:
//  no arrival by geofence, no ordering, and `apply(_:)` takes the host app's changes.
//
//  Gallery first, personalised journeys only (PM, Monday "Navigation to a gallery", 2026-10-15): a
//  leg to an artwork in another gallery ends at that gallery's POI (`GalleryFirstRouting`). When a
//  fix is in that gallery, the leg is drawn again from the visitor, to the artwork
//  (`checkGalleryFirst`).
//
//  Paused (`pause()`, the host app's `ProximiMapView` `isPaused`): the dot moves and the route stays,
//  but no artwork is visited, no off-route warning or wrong floor shows and the leg is not routed
//  again. `resumeFromPause()` draws the leg again from the visitor; a personalised journey is ordered
//  again from the visitor first, as after a detour.
//
import Combine
import Foundation
import Proximiio
import ProximiioMap

@MainActor
final class VisitController: ObservableObject {
    let session: ProximiioMapSession
    let navigator: JourneyNavigator
    /// `true` for `GADSettings.offRouteWarningSeconds` after `farFromRoute`, `offRouteTooLong` or a
    /// wrong floor, until the visitor closes the warning, resumes the journey or adds a stop.
    @Published private(set) var isOffRoute = false
    /// `pause()` until `resumeFromPause()`.
    @Published private(set) var isPaused = false
    private var offRouteWarning: Task<Void, Never>?
    /// Since when the fixes have been on a floor the route does not take.
    private var wrongFloorSince: Date?
    /// The journey was routed again for the wrong floor the visitor is still on.
    private var isRoutedForWrongFloor = false
    /// `true` while the controller routes the journey again: the order after an artwork visited out
    /// of order or a closer artwork, the leg from the visitor, the end of a detour.
    @Published private(set) var isRerouting = false
    private var reroutes = 0 {
        didSet { isRerouting = reroutes > 0 }
    }
    /// From `farFromRoute` or `offRouteTooLong` until the visitor is back on the route or a new leg
    /// starts. The warning can be closed meanwhile.
    private var isOffRouteEpisode = false {
        didSet { if !isOffRouteEpisode { isLegOffRouteEpisode = false } }
    }
    /// The episode started off the leg (`checkLegDeviation`); it ends when the visitor is back on it.
    private var isLegOffRouteEpisode = false
    private var lastCloserArtworkCheck = Date.distantPast
    /// The stop the navigator walks to for a moment while an artwork visited out of order moves
    /// ahead. `VisitView` reports no `nextStop` for it.
    @Published private(set) var passingStopID: String?
    /// Called after an artwork stop is marked done: `true` for the active stop, `false` for an
    /// artwork visited out of order. `VisitView` reports `VisitEvent.artworkReached` and
    /// `artworkVisitedOutOfOrder`.
    var onArtworkDone: ((JourneyStop, _ isActiveStop: Bool) -> Void)?
    private var tasks: [Task<Void, Never>] = []
    private var isStarted = false
    /// `true` once `navigator.start()` has returned.
    private var isNavigating = false
    /// The host app's latest journey while `apply` runs.
    private var pendingTarget: Journey?
    private var isApplying = false
    /// Stops whose POI is no longer a place, reported once (`stopsWithoutPlace`).
    private var reportedWithoutPlace: Set<String> = []
    /// The navigator's legs (gallery first).
    private let galleryRouting: GalleryFirstRouting
    /// The gallery the leg to the active artwork ends at, or `nil` when it ends at the artwork.
    @Published private(set) var galleryAhead: GalleryDestination?

    /// Times and distances (`GADSettings`): the move to the next artwork after an arrival, the
    /// wait for a fix before ordering, the out-of-order dwell, the detour arrival, the off-route
    /// alert and the route snapping.
    private let settings: GADSettings

    /// Guidance on a leg to an artwork. The infinite dwell turns the SDK's arrival by distance
    /// off; the artwork geofence is the only arrival. Off the leg beyond `GADSettings.offRouteMeters`.
    /// The walked part of the route moves only within `GADSettings.progressCorridorMeters` of the leg.
    private var artworkGuidanceRules: RouteFollowRules {
        Self.artworkGuidanceRules(settings)
    }

    /// `artworkGuidanceRules` for `settings`. Pure; covered by tests.
    static func artworkGuidanceRules(_ settings: GADSettings) -> RouteFollowRules {
        var rules = RouteFollowRules(arrivalDwellSeconds: .infinity, offRouteMeters: settings.offRouteMeters)
        rules.progressCorridorMeters = settings.progressCorridorMeters
        return rules
    }

    /// Guidance on a leg to an amenity detour: arrival within 2.5 × the fix accuracy, between
    /// `amenityArrivalMinimumMeters` and `amenityArrivalMaximumMeters`, for `amenityArrivalDwell`.
    /// The SDK default (at least 3 m, 2 s) missed visitors who walked past a stop with relay fixes.
    private var detourGuidanceRules: RouteFollowRules {
        Self.detourGuidanceRules(settings)
    }

    /// `detourGuidanceRules` for `settings`. Pure; covered by tests.
    static func detourGuidanceRules(_ settings: GADSettings) -> RouteFollowRules {
        var rules = RouteFollowRules(
            arrival: .fromAccuracy(
                multiplier: 2.5,
                minimumMeters: settings.amenityArrivalMinimumMeters,
                maximumMeters: settings.amenityArrivalMaximumMeters
            ),
            arrivalDwellSeconds: settings.amenityArrivalDwell,
            offRouteMeters: settings.offRouteMeters
        )
        rules.progressCorridorMeters = settings.progressCorridorMeters
        return rules
    }

    /// `remote_id` of each artwork POI, by POI id. Set once the venue's features are loaded.
    var artworkRemoteIDs: [String: String] = [:]
    /// Artwork geofence shapes, by `remote_id`. Set once the venue's geofences are loaded.
    var artworkAreas: [String: [ArtworkArea]] = [:]
    /// The geofences the SDK counts the visitor inside (`Proximiio.enteredGeofenceIds`), kept up
    /// to date from the geofence events.
    var enteredGeofenceIDs: Set<String> = []
    /// The last of the journey changes that run one after another (`serially`).
    private var journeyEdit: Task<Void, Never>?
    /// Stops whose move to the next artwork is scheduled.
    private var scheduledDone: Set<String> = []
    /// With `GADSettings.advancesOnArtworkExit`: the active artwork whose geofence the visitor
    /// entered. The journey moves on when they leave it.
    private var arrivedStopID: String?
    /// The artwork the navigator holds reached (`markReached`) and that is not yet reported visited.
    private var reachedStopID: String?
    /// The first fix outside the geofence of `arrivedStopID`, for a leave without an exit event.
    private var outsideArrivedSince: Date?
    /// Time inside the geofence of each open artwork that is not the active stop.
    private var outOfOrderDwell = GeofenceDwell()
    /// Out-of-order artworks being marked visited.
    private var markingOutOfOrder: Set<String> = []

    /// A curated tour keeps the curators' order: no ordering at the start, after a detour or
    /// after an artwork visited out of order. So does a journey whose progress the host app
    /// manages.
    private let keepsOrder: Bool
    /// Whether an artwork further on that the visitor stays at counts as visited. Off in a curated
    /// tour: only the active artwork is visited.
    private let countsOutOfOrder: Bool
    /// `ProximiMapView.Options.progress`: artwork geofences mark stops visited, the journey is
    /// ordered, and a stop whose POI is deleted is skipped. Off, only `apply(_:)` changes the stops.
    private let managesProgress: Bool
    /// `.askApp`: the leg stays where the visitor left it (personalised journeys with
    /// `ProximiMapView.Options.offRoutePrompt`). `.automatic`: the navigator routes again from the
    /// visitor.
    private let deviationPolicy: JourneyDeviationPolicy

    /// Stores the journey after each change; `nil` after Journey Complete. `ProximiMap` writes
    /// `VisitStore`, `ProximiMapView` the host app's journey.
    let persist: @MainActor (Journey?) -> Void

    init(
        session: ProximiioMapSession,
        journey: Journey,
        rules: JourneyRules = .visit,
        keepsOrder: Bool = false,
        countsOutOfOrder: Bool = true,
        managesProgress: Bool = true,
        deviationPolicy: JourneyDeviationPolicy = .askApp,
        settings: GADSettings = .standard,
        persist: @escaping @MainActor (Journey?) -> Void = VisitStore.persist
    ) {
        self.keepsOrder = keepsOrder || !managesProgress
        self.countsOutOfOrder = countsOutOfOrder
        self.managesProgress = managesProgress
        self.deviationPolicy = deviationPolicy
        self.settings = settings
        self.persist = persist
        self.session = session
        let routing = GalleryFirstRouting(inner: ProximiioJourneyRouting(sdk: session.sdk))
        self.galleryRouting = routing
        self.navigator = JourneyNavigator(session: session, journey: journey, rules: rules,
                                          guidanceRules: Self.artworkGuidanceRules(settings),
                                          routing: routing)
        navigator.drawsNextLegWhileReached = settings.advancesOnArtworkExit
        var deviation = navigator.deviationRules
        deviation.leftRouteMeters = settings.offRouteMeters
        deviation.offRouteTooLongSeconds = settings.offRouteSeconds
        navigator.deviationRules = deviation
        // The dot is drawn on the route within `routeSnapMeters`. Display only: guidance and
        // arrival use the real position (PM review 2026-10-12).
        session.routeSnapping = RouteSnapRules(maximumOffsetMeters: settings.routeSnapMeters)
    }

    /// Routes the rest of the journey with `accessibility`. The navigator routes the current leg
    /// again. Nothing changes when the needs are the same.
    func setAccessibility(_ accessibility: RouteAccessibility) async {
        await navigator.setRouteOptions(accessibility.routeOptions)
    }

    /// Starts the journey once. A screen over the journey screen can end and restart its tasks.
    func start(accessibility: RouteAccessibility) async {
        guard !isStarted else { return }
        isStarted = true
        navigator.deviationPolicy = isPaused ? .askApp : deviationPolicy
        await navigator.setRouteOptions(accessibility.routeOptions)
        var isOrderedWithoutFix = false
        if !keepsOrder, navigator.journey.stops.allSatisfy({ $0.state == .pending }) {
            await waitForFix(upTo: .seconds(settings.firstFixWait))
            isOrderedWithoutFix = session.position == nil
            if let proposal = await proposedOrder(), proposal.isImprovement {
                await apply(proposal)
            }
        }
        await navigator.start()
        isNavigating = true
        await applyPendingTarget()
        tasks.append(Task { [weak self] in
            guard let events = self?.navigator.events else { return }
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        })
        if isOrderedWithoutFix {
            tasks.append(Task { [weak self] in await self?.orderOnFirstFix() })
        }
    }

    private func waitForFix(upTo limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while session.position == nil, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Orders the journey from the first fix while no stop is reached, done or skipped.
    private func orderOnFirstFix() async {
        await waitForFix(upTo: .seconds(settings.lateOrderWindow))
        guard session.position != nil, !navigator.hasArrived,
              navigator.journey.stops.allSatisfy({ $0.state == .pending || $0.state == .active }),
              let proposal = await navigator.proposeOrder(from: .visitor, strategy: .floorThenGallery),
              proposal.isImprovement
        else { return }
        await apply(proposal)
    }

    private func apply(_ proposal: JourneyOrderProposal) async {
        let applied = await navigator.apply(proposal)
        FieldLog.log("journey order: \(applied ? "applied" : "stale") · \(proposal.order.joined(separator: ", "))")
        persist(navigator.journey)
    }

    private func handle(_ event: JourneyEvent) {
        refreshGalleryAhead()
        switch event {
        case .stopReached(let stop) where stop.kind != .detour && !settings.advancesOnArtworkExit:
            scheduleDone(stop.id, after: settings.artworkAdvanceDelay)
        case .detourEnded(_, completed: true):
            tasks.append(Task { [weak self] in
                await self?.serially { [weak self] in
                    guard let self else { return }
                    await self.rerouting { await self.orderRemaining() }
                }
            })
        case .leftRoute, .farFromRoute, .offRouteTooLong:
            guard !isPaused else { break }
            let startsEpisode = !isOffRouteEpisode
            isOffRouteEpisode = true
            showOffRouteWarning()
            if startsEpisode, reroutesAfterWarning { rerouteFromVisitor() }
        case .returnedToRoute:
            isOffRouteEpisode = false
        case .legChanged:
            isOffRouteEpisode = false
            reportReachedStopDone()
        case .rerouted:
            isOffRouteEpisode = false
        case .journeyFinished:
            reportReachedStopDone()
        default:
            break
        }
    }

    /// Reports the reached artwork visited once the navigator has moved past it without
    /// `scheduleDone`: a detour or a chosen stop makes a reached stop done.
    private func reportReachedStopDone() {
        guard let id = reachedStopID, let stop = stop(id), stop.state == .done else { return }
        reachedStopID = nil
        FieldLog.log("artwork left (the journey moved on): \(id)")
        onArtworkDone?(stop, true)
    }

    /// The visitor entered an artwork geofence. With `GADSettings.advancesOnArtworkExit` the active
    /// artwork is reached, and moves on when the visitor leaves it; else it moves on after
    /// `GADSettings.artworkAdvanceDelay`. The geofence of any other artwork is ignored, and every
    /// artwork geofence is ignored during a detour.
    func artworkGeofenceEntered(remoteID: String?) {
        guard managesProgress, !isPaused, navigator.detourStop == nil, let id = Self.activeStopID(forRemoteID: remoteID, in: navigator.journey, remoteIDs: artworkRemoteIDs) else { return }
        guard settings.advancesOnArtworkExit else {
            FieldLog.log("artwork geofence arrival: \(id) remote \(remoteID ?? "-")")
            return scheduleDone(id, after: settings.artworkAdvanceDelay)
        }
        outsideArrivedSince = nil
        guard arrivedStopID != id else { return }
        arrivedStopID = id
        FieldLog.log("artwork geofence arrival: \(id) remote \(remoteID ?? "-") · next stop at the exit")
        tasks.append(Task { [weak self] in
            await self?.serially { [weak self] in
                guard let self, self.arrivedStopID == id, self.navigator.activeStop?.id == id else { return }
                // A detour turns it off (`detour(to:)`).
                self.navigator.drawsNextLegWhileReached = true
                guard await self.navigator.markReached(stopID: id) else { return }
                self.reachedStopID = id
                FieldLog.log("artwork reached: \(id) · route to \(self.navigator.upcomingStop?.title ?? "-")")
                self.persist(self.navigator.journey)
            }
        })
    }

    /// The SDK reports that the visitor left an artwork geofence. Leaving the active artwork they
    /// arrived at moves the journey to the next stop (`GADSettings.advancesOnArtworkExit`).
    func artworkGeofenceExited(remoteID: String?) {
        guard managesProgress, !isPaused, let arrived = arrivedStopID, let remoteID,
              artworkRemoteIDs[stop(arrived)?.poiID ?? arrived] == remoteID else { return }
        leaveArrivedArtwork(reason: "exit event")
    }

    /// The visitor left the active artwork they arrived at: the journey moves to the next stop.
    private func leaveArrivedArtwork(reason: String) {
        guard let id = arrivedStopID else { return }
        arrivedStopID = nil
        outsideArrivedSince = nil
        guard navigator.activeStop?.id == id else { return }
        FieldLog.log("artwork left (\(reason)): \(id) · next stop")
        scheduleDone(id, after: 0)
    }

    /// Checks the fix against the geofences of the open artworks on the visitor's floor, and
    /// against `enteredGeofenceIDs`. Inside
    /// the active artwork's geofence: the arrival, which also covers a leg that starts inside it,
    /// where the SDK sends no enter event. Inside another open artwork's geofence for
    /// `GADSettings.outOfOrderDwell`: that artwork is visited out of order, except in a curated tour
    /// (`countsOutOfOrder`). During a detour to an amenity no artwork counts (PM review 2026-10-12).
    func checkArtworkGeofences() {
        // Before the start the journey is still being ordered.
        guard managesProgress, isNavigating else { return }
        guard navigator.detourStop == nil, !isPaused else {
            _ = outOfOrderDwell.update(inside: [], now: .now, dwell: settings.outOfOrderDwell)
            return
        }
        guard let position = session.position else { return }
        let point = position.coordinate.proximiio
        let level = position.floor?.level
        let activeID = navigator.activeStop?.id
        if settings.advancesOnArtworkExit, arrivedStopID == nil, navigator.hasArrived {
            // A journey restored with the artwork reached: it moves on when the visitor is outside.
            arrivedStopID = activeID
            reachedStopID = activeID
        }
        var inside: Set<String> = []
        var isInsideActive = false
        for stop in navigator.journey.stops
        where stop.kind != .detour && (stop.state == .pending || stop.state == .active || stop.state == .reached) {
            guard let remoteID = artworkRemoteIDs[stop.poiID ?? stop.id],
                  let areas = artworkAreas[remoteID]
            else { continue }
            if !VenueLevel.matches(stop.floor?.level, level) { continue }
            guard areas.contains(where: { enteredGeofenceIDs.contains($0.id) || $0.contains(point) }) else { continue }
            if stop.id == activeID {
                isInsideActive = true
                artworkGeofenceEntered(remoteID: remoteID)
            } else if countsOutOfOrder {
                inside.insert(stop.id)
            }
        }
        if let arrived = arrivedStopID {
            if arrived != activeID {
                // Skipped, reordered or visited otherwise.
                arrivedStopID = nil
                outsideArrivedSince = nil
            } else if !inside.isEmpty {
                // In another open artwork: the visitor has moved on. That artwork counts from the
                // next fix, after the journey moved on.
                leaveArrivedArtwork(reason: "in another artwork")
                inside = []
            } else if !isInsideActive {
                // No exit event: the SDK did not count the visitor inside, or the event was missed.
                let since = outsideArrivedSince ?? .now
                outsideArrivedSince = since
                if Date.now.timeIntervalSince(since) >= settings.geofenceExitDelay {
                    leaveArrivedArtwork(reason: "outside for \(settings.geofenceExitDelay) s")
                }
            }
        }
        for id in outOfOrderDwell.update(inside: inside, now: .now, dwell: settings.outOfOrderDwell) {
            markOutOfOrder(id)
        }
    }

    /// Sets the gallery of each artwork among `places` for gallery first, from `metadata.gallery_id`
    /// (`GalleryDestination`). An artwork outside its gallery (`GADSettings.galleryFirstMarginMeters`)
    /// has none. Off with `isEnabled` false.
    func setGalleryFirst(isEnabled: Bool, places: [VenuePlace], destinations: [String: GalleryDestination]) {
        var galleries: [GalleryFirstRouting.Key: GalleryDestination] = [:]
        var outside: [String] = []
        for place in places where place.isArtwork {
            guard let id = place.galleryID, let destination = destinations[id] else { continue }
            guard GalleryFirstRouting.isInGallery(place, destination, marginMeters: settings.galleryFirstMarginMeters) else {
                outside.append(place.title)
                continue
            }
            galleries[GalleryFirstRouting.Key(MapCoordinate(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))] = destination
        }
        if !outside.isEmpty {
            FieldLog.log("gallery first: \(outside.count) artworks outside their gallery, routes end at the artwork: \(outside.sorted().joined(separator: ", "))")
        }
        galleryRouting.update(isEnabled: isEnabled, galleries: galleries)
        refreshGalleryAhead()
    }

    /// Called on every fix. A fix in the gallery that the leg to the active artwork ends at: the leg
    /// is drawn again from the visitor, to the artwork.
    func checkGalleryFirst() {
        defer { refreshGalleryAhead() }
        guard isNavigating, !isPaused, navigator.detourStop == nil, !navigator.hasArrived, let stop = navigator.activeStop,
              let gallery = galleryRouting.gallery(of: stop.coordinate), let position = session.position,
              gallery.gallery.contains(position.coordinate.proximiio, level: position.floor?.level)
        else { return }
        galleryRouting.markReached(stop.coordinate)
        FieldLog.log("gallery first: in \(gallery.gallery.name) · leg to \(stop.title)")
        tasks.append(Task { [weak self] in
            await self?.serially { [weak self] in
                guard let self else { return }
                await self.rerouting { await self.navigator.resumeJourney() }
            }
        })
    }

    /// Called on every fix. Personalised journeys off the route: when the nearest open artwork is no
    /// longer the active stop, the stops ahead are ordered again from the visitor and the leg leads
    /// to that artwork. At most every 5 s.
    func checkCloserArtwork() {
        guard managesProgress, !keepsOrder, isNavigating, !isPaused, isOffRouteEpisode, navigator.detourStop == nil, !navigator.hasArrived,
              let active = navigator.activeStop, Date.now.timeIntervalSince(lastCloserArtworkCheck) >= 5
        else { return }
        lastCloserArtworkCheck = .now
        tasks.append(Task { [weak self] in
            await self?.serially { [weak self] in
                guard let self, self.isOffRouteEpisode, self.navigator.activeStop?.id == active.id,
                      let proposal = await self.navigator.proposeOrder(from: .visitor, strategy: .floorThenGallery),
                      proposal.isImprovement, let first = proposal.order.first, first != active.id
                else { return }
                FieldLog.log("off route: \(first) is nearer than \(active.title) · journey ordered again")
                self.isOffRouteEpisode = false
                await self.rerouting { await self.apply(proposal) }
            }
        })
    }

    /// Called on every guidance update. The visitor `GADSettings.offRouteMeters` off the leg to the
    /// current destination (`RouteGuidance.isOffRoute`) gets the warning, as for the navigator's
    /// `leftRoute`, also where a later leg of the journey passes (PM, Monday "Personalized tour:
    /// off-route and re-route behaviour", 2026-10-28). Back within two thirds of that distance the
    /// episode ends. Only with the warning (`.askApp`); not while paused, during a detour, on a
    /// floor without positioning or at a reached artwork, whose guidance is the leg to the next stop.
    func checkLegDeviation(_ guidance: RouteGuidance?, isFloorGuideActive: Bool) {
        guard deviationPolicy == .askApp, isNavigating, !isPaused, !isFloorGuideActive, navigator.detourStop == nil,
              !navigator.hasArrived, let guidance, !guidance.hasArrived
        else { return }
        switch Self.legDeviation(isOffRoute: guidance.isOffRoute, meters: guidance.offRouteMeters, threshold: settings.offRouteMeters,
                                 isEpisode: isOffRouteEpisode, isLegEpisode: isLegOffRouteEpisode) {
        case .none:
            break
        case .ends:
            isOffRouteEpisode = false
        case .warns:
            FieldLog.log("off route: \(String(format: "%.1f", guidance.offRouteMeters)) m off the leg to \(navigator.activeStop?.title ?? "-")")
            isOffRouteEpisode = true
            isLegOffRouteEpisode = true
            showOffRouteWarning()
            if reroutesAfterWarning { rerouteFromVisitor() }
        }
    }

    enum LegDeviation: Equatable {
        case none
        /// A new episode: the warning shows.
        case warns
        /// The visitor is back on the leg: the episode `checkLegDeviation` started ends.
        case ends
    }

    /// What one guidance update off or on the leg does. An open episode, of the leg or of the whole
    /// journey, shows no second warning; the leg's episode ends within two thirds of `threshold`, so
    /// a visitor on the boundary gets one warning. Pure; covered by tests.
    nonisolated static func legDeviation(isOffRoute: Bool, meters: Double, threshold: Double, isEpisode: Bool, isLegEpisode: Bool) -> LegDeviation {
        if isOffRoute { return isEpisode ? .none : .warns }
        return isLegEpisode && meters <= threshold * 2 / 3 ? .ends : .none
    }

    /// Called on every fix. A visitor on a floor the route ahead does not take for
    /// `GADSettings.wrongFloorSeconds` is off the route: the warning shows, and the leg is drawn again
    /// from the visitor. A personalised journey is ordered again first, so the leg leads to the
    /// nearest open artwork; a curated tour keeps its next stop. Once per wrong floor: the next check
    /// starts when a fix is on a floor of the route again. Off on a floor without positioning
    /// (`isFloorGuideActive`).
    func checkWrongFloor(isFloorGuideActive: Bool) {
        guard isNavigating, !isPaused, !isFloorGuideActive, navigator.activeStop != nil, !navigator.hasArrived,
              let level = session.position?.floor?.level,
              let legs = session.routeRenderer?.geometry?.legs,
              !Self.isOnRouteFloor(level: level, legs: legs)
        else {
            wrongFloorSince = nil
            isRoutedForWrongFloor = false
            return
        }
        guard !isRoutedForWrongFloor else { return }
        let since = wrongFloorSince ?? .now
        wrongFloorSince = since
        guard Date.now.timeIntervalSince(since) >= settings.wrongFloorSeconds else { return }
        isRoutedForWrongFloor = true
        wrongFloorSince = nil
        FieldLog.log("wrong floor: L\(Int(level.rounded())) is not on the route · journey routed again from the visitor")
        isOffRouteEpisode = true
        showOffRouteWarning()
        let reorders = managesProgress && !keepsOrder
        tasks.append(Task { [weak self] in
            await self?.serially { [weak self] in
                guard let self else { return }
                await self.rerouting {
                    if reorders, let proposal = await self.navigator.proposeOrder(from: .visitor, strategy: .floorThenGallery),
                       proposal.isImprovement {
                        await self.apply(proposal)
                    }
                    await self.navigator.resumeJourney()
                }
                self.persist(self.navigator.journey)
            }
        })
    }

    /// Whether a route still to walk takes the floor at `level`. No route still to walk counts as on
    /// the route. Pure; covered by tests.
    nonisolated static func isOnRouteFloor(level: Double, legs: [RouteGeometry.Leg]) -> Bool {
        let ahead = legs.filter { !$0.isCompleted }
        return ahead.isEmpty || ahead.contains { VenueLevel.same($0.floor.level, level) }
    }

    /// A journey that keeps its order and shows the warning (`.askApp`, a curated tour) is routed
    /// again from the visitor after the warning. A personalised journey keeps its leg.
    private var reroutesAfterWarning: Bool {
        deviationPolicy == .askApp && keepsOrder
    }

    /// Draws the leg again from the visitor, after the warning.
    private func rerouteFromVisitor() {
        FieldLog.log("off route: warning shown · leg drawn again from the visitor")
        tasks.append(Task { [weak self] in
            await self?.serially { [weak self] in
                guard let self, self.isOffRouteEpisode else { return }
                await self.rerouting { await self.navigator.resumeJourney() }
                self.persist(self.navigator.journey)
            }
        })
    }

    /// Opens the off-route warning for `GADSettings.offRouteWarningSeconds`. A new episode while it
    /// is open starts the time again.
    private func showOffRouteWarning() {
        isOffRoute = true
        offRouteWarning?.cancel()
        let seconds = settings.offRouteWarningSeconds
        offRouteWarning = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.isOffRoute = false
        }
    }

    private func closeOffRouteWarning() {
        offRouteWarning?.cancel()
        offRouteWarning = nil
        isOffRoute = false
    }

    /// Runs `body` with `isRerouting` on.
    private func rerouting(_ body: () async -> Void) async {
        reroutes += 1
        await body()
        reroutes -= 1
    }

    /// Runs `edit` after the journey changes started before it. Out of order once proposed an order
    /// before it marked an artwork visited, and that order made the artwork active again (field
    /// test 2026-10-19). `edit` must not call `serially`.
    private func serially(_ edit: @escaping @MainActor () async -> Void) async {
        let previous = journeyEdit
        let current = Task { @MainActor in
            await previous?.value
            await edit()
        }
        journeyEdit = current
        await current.value
    }

    /// No gallery during a detour or at a reached artwork: the card names the stop.
    private func refreshGalleryAhead() {
        let gallery = navigator.detourStop == nil && !navigator.hasArrived
            ? navigator.activeStop.flatMap { galleryRouting.gallery(of: $0.coordinate) } : nil
        if gallery != galleryAhead { galleryAhead = gallery }
    }

    /// Marks a pending artwork visited out of order and orders the stops still ahead again from
    /// the visitor. The leg to the active stop is then drawn from the visitor: the navigator draws
    /// a new leg only when the active stop changes, and the old leg started where the visitor was
    /// before (PM 2026-10-14: the old route stayed on the map).
    private func markOutOfOrder(_ stopID: String) {
        guard markingOutOfOrder.insert(stopID).inserted else { return }
        tasks.append(Task { [weak self] in
            await self?.serially { [weak self] in
                guard let self else { return }
                defer { self.markingOutOfOrder.remove(stopID) }
                guard !Task.isCancelled,
                      self.navigator.journey.stops.first(where: { $0.id == stopID })?.state == .pending
                else { return }
                FieldLog.log("artwork visited out of order: \(stopID)")
                let activeStopID = self.navigator.activeStop?.id
                self.reroutes += 1
                defer { self.reroutes -= 1 }
                // The artwork moves before the stops still to visit: the numbers follow the visit
                // order. The navigator walks to it for a moment.
                self.passingStopID = stopID
                await self.navigator.move(stopID: stopID, toIndex: 0)
                let isDone = await self.navigator.markDone(stopID: stopID)
                self.passingStopID = nil
                if isDone, let stop = self.stop(stopID) {
                    self.onArtworkDone?(stop, false)
                }
                await self.orderRemaining()
                if let activeStopID, self.navigator.activeStop?.id == activeStopID {
                    FieldLog.log("leg to \(activeStopID) drawn again from the visitor")
                    await self.navigator.resumeJourney()
                }
                self.persist(self.navigator.journey)
            }
        })
    }

    /// The shapes of the artwork geofences, by `remote_id`. One artwork can have several geofences:
    /// on 2026-10-15 each DCT test artwork shares its `remote_id` with the Guggenheim artwork.
    /// Pure; covered by tests.
    nonisolated static func artworkAreas(of geofences: [ProximiioGeofence]) -> [String: [ArtworkArea]] {
        Dictionary(
            grouping: geofences.filter { $0.isArtwork && !($0.remoteId ?? "").isEmpty },
            by: { $0.remoteId ?? "" }
        ).mapValues { $0.map(ArtworkArea.init) }
    }

    /// The active artwork stop when its POI has `remoteID`, else `nil`. Pure; covered by tests.
    nonisolated static func activeStopID(forRemoteID remoteID: String?, in journey: Journey, remoteIDs: [String: String]) -> String? {
        guard let remoteID, !remoteID.isEmpty,
              let stop = journey.stops.first(where: { $0.state == .active || $0.state == .reached }),
              stop.kind != .detour, remoteIDs[stop.poiID ?? stop.id] == remoteID
        else { return nil }
        return stop.id
    }

    /// Marks `stopID` visited after `delay` seconds if it is still the active stop. The leg to the
    /// next artwork is drawn.
    private func scheduleDone(_ stopID: String, after delay: TimeInterval) {
        guard scheduledDone.insert(stopID).inserted else { return }
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.serially { [weak self] in
                guard let self else { return }
                self.scheduledDone.remove(stopID)
                guard !Task.isCancelled, self.navigator.activeStop?.id == stopID else { return }
                // Reported here, not by `reportReachedStopDone` on the leg change.
                if self.reachedStopID == stopID { self.reachedStopID = nil }
                let changed = await self.navigator.markDone(stopID: stopID)
                self.persist(self.navigator.journey)
                if changed, let stop = self.stop(stopID) { self.onArtworkDone?(stop, true) }
            }
        })
    }

    private func stop(_ id: String) -> JourneyStop? {
        navigator.journey.stops.first { $0.id == id }
    }

    /// Orders the stops still ahead from the visitor, floor by floor and gallery by gallery.
    private func orderRemaining() async {
        guard !keepsOrder, let proposal = await navigator.proposeOrder(from: .visitor, strategy: .floorThenGallery),
              proposal.isImprovement
        else { return }
        await apply(proposal)
    }

    /// The floor-then-gallery order from the visitor's fix, or from the first stop without a fix.
    private func proposedOrder() async -> JourneyOrderProposal? {
        if let proposal = await navigator.proposeOrder(from: .visitor, strategy: .floorThenGallery) {
            return proposal
        }
        return await navigator.proposeOrder(from: .activeStop, strategy: .floorThenGallery)
    }

    func advance() async {
        await navigator.advance()
        persist(navigator.journey)
    }

    func skip(stopID: String) async {
        guard await navigator.skip(stopID: stopID) else { return }
        persist(navigator.journey)
    }

    /// Takes a change of the venue data into the open journey, after the journey changes started
    /// before it (`serially`). Returns the stops whose POI is no longer a place, each once.
    /// - A planned stop that is not reached or done takes the title, coordinate, floor and gallery
    ///   of its POI (`JourneyNavigator.replace(_:)`). A moved stop being walked to is routed again.
    /// - A stop whose POI is no longer a place is skipped with `managesProgress`, so `ProximiMapView`
    ///   writes it to the host app's journey as skipped. Without `managesProgress` it stays; the
    ///   host app decides. When the journey screen of `ProximiMap` closes, the stored journey drops
    ///   it (`VisitPlan.reconciled`).
    /// - With `routeNetworkChanged` (changed features) the legs are routed again
    ///   (`JourneyNavigator.routeNetworkChanged()`). A leg on the line already drawn stays quietly.
    func venueChanged(places: [VenuePlace], galleries: [Gallery], routeNetworkChanged: Bool) async -> [JourneyStop] {
        let withoutPlace = VisitPlan.stopsWithoutPlace(in: navigator.journey, places: places)
            .filter { $0.state != .skipped && !reportedWithoutPlace.contains($0.id) }
        reportedWithoutPlace.formUnion(withoutPlace.map(\.id))
        let skipped = managesProgress ? withoutPlace : []
        await serially { [weak self] in
            guard let self else { return }
            var changed = false
            let current = Dictionary(self.navigator.journey.stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let reconciled = VisitPlan.reconciled(self.navigator.journey, places: places, galleries: galleries)
            for stop in reconciled.stops where current[stop.id] != stop {
                if await self.navigator.replace(stop) {
                    FieldLog.log("journey: \(stop.title) takes the changed place")
                    changed = true
                }
            }
            for stop in skipped {
                FieldLog.log("journey: \(stop.title) is no longer a place · skipped")
                if await self.navigator.skip(stopID: stop.id) { changed = true }
            }
            if routeNetworkChanged { await self.navigator.routeNetworkChanged() }
            if changed { self.persist(self.navigator.journey) }
        }
        return withoutPlace
    }

    /// Takes the host app's journey on the open screen (`ProximiMapView`): stops added, removed,
    /// visited, skipped, reopened and moved. The navigator, its route cache, its event streams and
    /// the camera stay. Calls run one after another; a call during another keeps only the latest
    /// journey, applied after it. Before the navigator has started, the latest journey waits for
    /// the start.
    func apply(_ target: Journey) async {
        pendingTarget = target
        await applyPendingTarget()
    }

    /// Applies the latest journey of the host app once the navigator has started.
    private func applyPendingTarget() async {
        guard isNavigating, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        while let next = pendingTarget {
            pendingTarget = nil
            await performApply(next)
        }
    }

    /// Hands the host app's whole journey to the navigator (`JourneyNavigator.update(to:)`). The
    /// navigator merges it with the list it got last and its own stops: a detour stays, and a step
    /// the navigator has already made stays. The navigator was created with the host app's list, so
    /// the first call merges against it.
    private func performApply(_ target: Journey) async {
        let taken = await navigator.update(to: target)
        FieldLog.log("journey applied · \(target.stops.count) stops · \(taken ? "taken" : "not taken: two stops with one id")")
    }

    /// Makes `stopID` the next stop (EC04a: the visitor picked the artwork they are at).
    func activate(stopID: String) async {
        guard navigator.activeStop?.id != stopID else { return }
        await navigator.activate(stopID: stopID)
        persist(navigator.journey)
    }

    /// Inserts `place` as a detour before the active stop. The journey continues after it.
    /// The map marker shows the app's glyph for the amenity (an asset catalog name). The style's
    /// amenity sprite is a filled circle and drew a white disk once tinted (PM review 2026-10-12).
    ///
    /// A place that is already a stop of the journey (a visited artwork) gets another stop id, so the
    /// journey has no two stops with one id; `poiID` stays the place's id.
    /// - Returns: The id of the detour stop.
    @discardableResult
    func detour(to place: VenuePlace) async -> String {
        var stop = VisitPlan.stop(for: place)
        if navigator.journey.stops.contains(where: { $0.id == stop.id }) { stop.id = "detour:\(place.id)" }
        stop.iconName = AmenityKind.allCases.first { $0.matches(place) }?.icon.rawValue
        closeOffRouteWarning()
        // The navigator applies guidance rules to each new leg: the detour leg is reached by
        // distance, the legs after it by the artwork geofence only. At the reached amenity the route
        // waits for "Resume your Journey"; the next artwork's arrival turns the next leg on again.
        navigator.guidanceRules = detourGuidanceRules
        navigator.drawsNextLegWhileReached = false
        await navigator.detour(to: stop)
        navigator.guidanceRules = artworkGuidanceRules
        return stop.id
    }

    /// Drops the detour without recording it, and the leg to the next stop follows.
    func cancelDetour() async {
        await serially { [weak self] in
            guard let self else { return }
            await self.navigator.cancelDetour()
            self.persist(self.navigator.journey)
        }
    }

    /// "Resume your Journey" after a detour.
    ///
    /// A detour reached is recorded as visited; one not reached is dropped. After a detour the
    /// stops still ahead are ordered again from the visitor. The leg is drawn from here.
    func resumeJourney() async {
        closeOffRouteWarning()
        await serially { [weak self] in
            guard let self else { return }
            let hadDetour = self.navigator.detourStop != nil
            await self.rerouting {
                await self.navigator.resumeJourney()
                if hadDetour { await self.orderRemaining() }
            }
            self.persist(self.navigator.journey)
        }
    }

    /// Pauses the guidance: no artwork is visited, no off-route warning or wrong floor shows, and
    /// the navigator leaves the leg where it is (`JourneyDeviationPolicy.askApp`). The dot moves and
    /// the route stays. A detour keeps its leg.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        FieldLog.log("journey paused")
        closeOffRouteWarning()
        isOffRouteEpisode = false
        wrongFloorSince = nil
        navigator.deviationPolicy = .askApp
    }

    /// Ends `pause()`. The leg is drawn again from the visitor; a personalised journey is ordered
    /// again from the visitor first. A detour keeps its leg.
    func resumeFromPause() async {
        guard isPaused else { return }
        isPaused = false
        FieldLog.log("journey resumed after a pause")
        navigator.deviationPolicy = deviationPolicy
        guard isNavigating, navigator.detourStop == nil else { return }
        await serially { [weak self] in
            guard let self else { return }
            await self.rerouting {
                await self.orderRemaining()
                await self.navigator.resumeJourney()
            }
            self.persist(self.navigator.journey)
        }
    }

    /// "Dismiss" on the off-route warning. The leg is not drawn again. The warning opens again on the
    /// next episode.
    func dismissOffRoute() {
        closeOffRouteWarning()
    }

    func end() {
        closeOffRouteWarning()
        tasks.forEach { $0.cancel() }
        tasks = []
        navigator.end()
        persist(nil)
    }
}

/// How long the visitor has been inside each geofence. Pure; covered by tests.
struct GeofenceDwell: Equatable {
    private(set) var insideSince: [String: Date] = [:]

    /// Records the stops whose geofence contains the visitor at `now` and returns those inside
    /// for at least `dwell` seconds without a break, sorted. Leaving a geofence resets its time.
    mutating func update(inside ids: Set<String>, now: Date, dwell: TimeInterval) -> [String] {
        insideSince = insideSince.filter { ids.contains($0.key) }
        for id in ids where insideSince[id] == nil { insideSince[id] = now }
        return insideSince.filter { now.timeIntervalSince($0.value) >= dwell }.map(\.key).sorted()
    }
}

/// The shape of an artwork geofence: a polygon, or a circle around `center`.
struct ArtworkArea: Equatable, Sendable {
    /// The geofence's id.
    var id: String
    var center: ProximiioCoordinate?
    var radius: Double
    /// `[longitude, latitude]` pairs.
    var polygon: [[Double]]?

    init(id: String = "", center: ProximiioCoordinate?, radius: Double, polygon: [[Double]]? = nil) {
        self.id = id
        self.center = center
        self.radius = radius
        self.polygon = polygon
    }

    init(_ geofence: ProximiioGeofence) {
        self.init(id: geofence.id, center: geofence.area, radius: geofence.radius, polygon: geofence.polygon)
    }

    /// Same containment as the SDK's geofence engine on enter: the polygon when it has three
    /// points or more, else the circle.
    func contains(_ point: ProximiioCoordinate) -> Bool {
        if let polygon, polygon.count >= 3 {
            return GeoMath.isPointInPolygon(point, polygon: polygon)
        }
        guard let center, center.latitude != 0 || center.longitude != 0, radius > 0 else { return false }
        return GeoMath.haversineDistance(from: center, to: point) <= radius
    }
}

extension JourneyRules {
    /// A reached detour waits for "Resume your Journey" (PM review 2026-10-12). Artworks are never
    /// reached by the navigator (`VisitController.artworkGuidanceRules`); `VisitController` marks
    /// them done after the geofence enter event. A stop the visitor walks past stays open.
    static let visit = JourneyRules(advance: .manual)
}

/// Persists the visit between launches. Stop states are restored; the leg is recomputed.
enum VisitStore {
    private static let key = "GuggenheimAbuDhabi.visit"

    static func load(from defaults: UserDefaults = .standard) -> Journey? {
        guard let data = defaults.data(forKey: key),
              let journey = try? JSONDecoder().decode(Journey.self, from: data),
              !journey.stops.isEmpty
        else { return nil }
        return journey
    }

    private static let metaKey = "GuggenheimAbuDhabi.visitMeta"

    static func loadMeta(from defaults: UserDefaults = .standard) -> VisitMeta? {
        defaults.data(forKey: metaKey).flatMap { try? JSONDecoder().decode(VisitMeta.self, from: $0) }
    }

    static func saveMeta(_ meta: VisitMeta?, to defaults: UserDefaults = .standard) {
        guard let meta, let data = try? JSONEncoder().encode(meta) else {
            defaults.removeObject(forKey: metaKey)
            return
        }
        defaults.set(data, forKey: metaKey)
    }

    /// Saves `journey`; `nil` removes the stored visit and its title.
    @MainActor static func persist(_ journey: Journey?) {
        save(journey)
        if journey == nil { saveMeta(nil) }
    }

    /// `nil` or an empty journey removes the stored visit.
    static func save(_ journey: Journey?, to defaults: UserDefaults = .standard) {
        guard let journey, !journey.stops.isEmpty, let data = try? JSONEncoder().encode(journey) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
