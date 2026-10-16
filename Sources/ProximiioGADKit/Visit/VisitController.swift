//
//  VisitController.swift
//  ProximiioGADKit
//
//  Owns the map session and the `JourneyNavigator` of a visit, persists the journey, and
//  implements skip and undo.
//
//  Arrival at an artwork: entering the geofence of the active artwork (`artworkGeofenceEntered`).
//  Nagarro's audio guide reacts to the same enter event, so the map and the guide name the same
//  artwork at the same time. The geofence and the artwork POI share `remote_id`. A visitor already
//  inside the geofence when the leg starts gets no enter event, so every fix is also checked
//  against the artwork geofences (`checkArtworkGeofences`). The journey moves to the next
//  artwork `GADSettings.artworkAdvanceDelay` after the arrival. There is no fallback by distance: an artwork
//  the visitor walks past without entering its geofence stays unvisited until it is skipped.
//  Out of order: a visitor inside the geofence of another open artwork for
//  `GADSettings.outOfOrderDwell` (0 s while testing) marks it visited, and the stops still ahead are
//  ordered again from the visitor (PM review 2026-10-12).
//  An amenity has no geofence. A detour is reached within 5–10 m for 5 s (`GADSettings`)
//  and the journey continues only after "Resume your Journey" (`JourneyRules.visit`).
//
//  Skip, undo and "choose this stop" edit the running navigator. Its route cache, event streams
//  and deviation state are kept.
//
//  Every leg uses the visitor's accessibility needs (`RouteAccessibility`). A new journey is ordered
//  floor by floor and gallery by gallery (`JourneyOrderStrategy.floorThenGallery`): the stop
//  nearest the visitor first, then the rest of its gallery, then the rest of its floor. Without a
//  fix the first stop stays first, and the first fix within `GADSettings.lateOrderWindow` orders the journey
//  again while no stop is reached. A restored journey keeps its order. After a detour the stops
//  still ahead are ordered again from the visitor. A curated tour (`keepsOrder`) is never ordered.
//
//  Leaving the route does not re-route the leg (`JourneyDeviationPolicy.askApp`). The visitor
//  gets a warning (`isOffRoute`) once they are far from the route or off it for too long, and
//  "Back to my route" re-routes from where they are.
//
import Foundation
import Observation
import Proximiio
import ProximiioMap

@MainActor
@Observable
final class VisitController {
    let session: ProximiioMapSession
    let navigator: JourneyNavigator
    /// The last skipped stop, for "Undo". Cleared by the next skip or by undo.
    private(set) var lastSkippedStopID: String?
    /// `true` after `farFromRoute` or `offRouteTooLong`, until the visitor returns to the route
    /// or answers the warning.
    private(set) var isOffRoute = false
    /// Called after an artwork stop is marked done: `true` for the active stop, `false` for an
    /// artwork visited out of order. `VisitView` reports `VisitEvent.artworkReached` and
    /// `artworkVisitedOutOfOrder`.
    @ObservationIgnored var onArtworkDone: ((JourneyStop, _ isActiveStop: Bool) -> Void)?
    private var tasks: [Task<Void, Never>] = []
    private var isStarted = false

    /// Times and distances (`GADSettings`): the move to the next artwork after an arrival, the
    /// wait for a fix before ordering, the out-of-order dwell, the detour arrival, the off-route
    /// alert and the route snapping.
    private let settings: GADSettings

    /// Guidance on a leg to an artwork. The infinite dwell turns the SDK's arrival by distance
    /// off; the artwork geofence is the only arrival.
    static let artworkGuidanceRules = RouteFollowRules(arrivalDwellSeconds: .infinity)

    /// Guidance on a leg to an amenity detour: arrival within 2.5 × the fix accuracy, between
    /// `amenityArrivalMinimumMeters` and `amenityArrivalMaximumMeters`, for `amenityArrivalDwell`.
    /// The SDK default (at least 3 m, 2 s) missed visitors who walked past a stop with relay fixes.
    private var detourGuidanceRules: RouteFollowRules {
        RouteFollowRules(
            arrival: .fromAccuracy(
                multiplier: 2.5,
                minimumMeters: settings.amenityArrivalMinimumMeters,
                maximumMeters: settings.amenityArrivalMaximumMeters
            ),
            arrivalDwellSeconds: settings.amenityArrivalDwell
        )
    }

    /// `remote_id` of each artwork POI, by POI id. Set once the venue's features are loaded.
    var artworkRemoteIDs: [String: String] = [:]
    /// Artwork geofence shapes, by `remote_id`. Set once the venue's geofences are loaded.
    var artworkAreas: [String: [ArtworkArea]] = [:]
    /// Stops whose move to the next artwork is scheduled.
    private var scheduledDone: Set<String> = []
    /// Time inside the geofence of each open artwork that is not the active stop.
    private var outOfOrderDwell = GeofenceDwell()
    /// Out-of-order artworks being marked visited.
    private var markingOutOfOrder: Set<String> = []

    /// A curated tour keeps the curators' order: no ordering at the start, after a detour or
    /// after an artwork visited out of order.
    private let keepsOrder: Bool

    /// Stores the journey after each change; `nil` after Journey Complete. `ProximiMap` writes
    /// `VisitStore`, `ProximiMapView` the host app's journey.
    @ObservationIgnored let persist: @MainActor (Journey?) -> Void

    init(
        session: ProximiioMapSession,
        journey: Journey,
        rules: JourneyRules = .visit,
        keepsOrder: Bool = false,
        settings: GADSettings = .standard,
        persist: @escaping @MainActor (Journey?) -> Void = VisitStore.persist
    ) {
        self.keepsOrder = keepsOrder
        self.settings = settings
        self.persist = persist
        self.session = session
        self.navigator = JourneyNavigator(session: session, journey: journey, rules: rules, guidanceRules: Self.artworkGuidanceRules)
        var deviation = navigator.deviationRules
        deviation.farFromRouteMeters = settings.offRouteMeters
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
        navigator.deviationPolicy = .askApp
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
        switch event {
        case .stopReached(let stop) where stop.kind != .detour:
            scheduleDone(stop.id)
        case .detourEnded(_, completed: true):
            tasks.append(Task { [weak self] in await self?.orderRemaining() })
        case .farFromRoute, .offRouteTooLong:
            isOffRoute = true
        case .returnedToRoute:
            isOffRoute = false
        default:
            break
        }
    }

    /// The visitor entered an artwork geofence. The active artwork moves on after
    /// `GADSettings.artworkAdvanceDelay`. The geofence of any other artwork is ignored, and every artwork
    /// geofence is ignored during a detour.
    func artworkGeofenceEntered(remoteID: String?) {
        guard navigator.detourStop == nil, let id = Self.activeStopID(forRemoteID: remoteID, in: navigator.journey, remoteIDs: artworkRemoteIDs) else { return }
        FieldLog.log("artwork geofence arrival: \(id) remote \(remoteID ?? "-")")
        scheduleDone(id)
    }

    /// Checks the fix against the geofences of the open artworks on the visitor's floor. Inside
    /// the active artwork's geofence: the arrival, which also covers a leg that starts inside it,
    /// where the SDK sends no enter event. Inside another open artwork's geofence for
    /// `GADSettings.outOfOrderDwell`: that artwork is visited out of order. During a detour to an
    /// amenity no artwork counts (PM review 2026-10-12).
    func checkArtworkGeofences() {
        guard navigator.detourStop == nil else {
            _ = outOfOrderDwell.update(inside: [], now: .now, dwell: settings.outOfOrderDwell)
            return
        }
        guard let position = session.position else { return }
        let point = position.coordinate.proximiio
        let level = position.floor?.level
        let activeID = navigator.activeStop?.id
        var inside: Set<String> = []
        for stop in navigator.journey.stops
        where stop.kind != .detour && (stop.state == .pending || stop.state == .active || stop.state == .reached) {
            guard let remoteID = artworkRemoteIDs[stop.poiID ?? stop.id],
                  let areas = artworkAreas[remoteID]
            else { continue }
            if !VenueLevel.matches(stop.floor?.level, level) { continue }
            guard areas.contains(where: { $0.contains(point) }) else { continue }
            if stop.id == activeID {
                artworkGeofenceEntered(remoteID: remoteID)
            } else {
                inside.insert(stop.id)
            }
        }
        for id in outOfOrderDwell.update(inside: inside, now: .now, dwell: settings.outOfOrderDwell) {
            markOutOfOrder(id)
        }
    }

    /// Marks a pending artwork visited out of order and orders the stops still ahead again from
    /// the visitor. The leg to the active stop is then drawn from the visitor: the navigator draws
    /// a new leg only when the active stop changes, and the old leg started where the visitor was
    /// before (PM 2026-10-14: the old route stayed on the map).
    private func markOutOfOrder(_ stopID: String) {
        guard markingOutOfOrder.insert(stopID).inserted else { return }
        tasks.append(Task { [weak self] in
            guard let self else { return }
            defer { self.markingOutOfOrder.remove(stopID) }
            guard !Task.isCancelled,
                  self.navigator.journey.stops.first(where: { $0.id == stopID })?.state == .pending
            else { return }
            FieldLog.log("artwork visited out of order: \(stopID)")
            let activeStopID = self.navigator.activeStop?.id
            if await self.navigator.markDone(stopID: stopID), let stop = self.stop(stopID) {
                self.onArtworkDone?(stop, false)
            }
            await self.orderRemaining()
            if let activeStopID, self.navigator.activeStop?.id == activeStopID {
                FieldLog.log("leg to \(activeStopID) drawn again from the visitor")
                self.isOffRoute = false
                await self.navigator.resumeJourney()
            }
            self.persist(self.navigator.journey)
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

    /// Marks `stopID` visited after `GADSettings.artworkAdvanceDelay` if it is still the active stop. The leg to
    /// the next artwork is drawn.
    private func scheduleDone(_ stopID: String) {
        guard scheduledDone.insert(stopID).inserted else { return }
        let delay = settings.artworkAdvanceDelay
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.scheduledDone.remove(stopID)
            guard !Task.isCancelled, self.navigator.activeStop?.id == stopID else { return }
            let changed = await self.navigator.markDone(stopID: stopID)
            self.persist(self.navigator.journey)
            if changed, let stop = self.stop(stopID) { self.onArtworkDone?(stop, true) }
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
        lastSkippedStopID = stopID
        persist(navigator.journey)
    }

    /// Skips the stops whose POI is no longer a place after a change of the venue data. The
    /// navigator has no call that removes or changes a stop (map 6.0.0-beta.44). When the journey
    /// screen closes, the stored journey drops these stops and takes the changed places
    /// (`VisitPlan.reconciled`).
    func skipStopsWithoutPlace(places: [VenuePlace]) async {
        let stops = VisitPlan.stopsWithoutPlace(in: navigator.journey, places: places).filter { $0.state != .skipped }
        guard !stops.isEmpty else { return }
        for stop in stops {
            FieldLog.log("journey: \(stop.title) is no longer a place · skipped")
            await navigator.skip(stopID: stop.id)
        }
        persist(navigator.journey)
    }

    func undoSkip() async {
        guard let id = lastSkippedStopID else { return }
        lastSkippedStopID = nil
        await navigator.reopen(stopID: id)
        persist(navigator.journey)
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
    func detour(to place: VenuePlace) async {
        var stop = VisitPlan.stop(for: place)
        stop.iconName = AmenityKind.allCases.first { $0.matches(place) }?.icon.rawValue
        // The navigator applies guidance rules to each new leg: the detour leg is reached by
        // distance, the legs after it by the artwork geofence only.
        navigator.guidanceRules = detourGuidanceRules
        await navigator.detour(to: stop)
        navigator.guidanceRules = Self.artworkGuidanceRules
    }

    /// "Resume your Journey" after a detour and "Back to my route" after leaving the route.
    ///
    /// A detour reached is recorded as visited; one not reached is dropped. After a detour the
    /// stops still ahead are ordered again from the visitor. The leg is drawn from here.
    func resumeJourney() async {
        isOffRoute = false
        let hadDetour = navigator.detourStop != nil
        await navigator.resumeJourney()
        if hadDetour { await orderRemaining() }
        persist(navigator.journey)
    }

    /// Closes the off-route warning without re-routing. It opens again on the next episode.
    func dismissOffRoute() {
        isOffRoute = false
    }

    func end() {
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
    var center: ProximiioCoordinate?
    var radius: Double
    /// `[longitude, latitude]` pairs.
    var polygon: [[Double]]?

    init(center: ProximiioCoordinate?, radius: Double, polygon: [[Double]]? = nil) {
        self.center = center
        self.radius = radius
        self.polygon = polygon
    }

    init(_ geofence: ProximiioGeofence) {
        self.init(center: geofence.area, radius: geofence.radius, polygon: geofence.polygon)
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
