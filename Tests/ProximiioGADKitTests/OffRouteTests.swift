//
//  OffRouteTests.swift
//  ProximiioGADKitTests
//
//  The wrong floor counts as off the route, the off-route warning's time, and the stop markers with
//  gallery first (PM, Monday 2026-10-27).
//
import Foundation
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct OffRouteTests {
    private static func leg(_ level: Double, completed: Bool = false, order: Int = 0) -> RouteGeometry.Leg {
        RouteGeometry.Leg(
            floor: FloorKey(level: level),
            points: [MapCoordinate(latitude: 24.5, longitude: 54.4), MapCoordinate(latitude: 24.5001, longitude: 54.4)],
            isCompleted: completed,
            order: order
        )
    }

    /// Monday "Wrong floor to trigger off-route and re-routing": on floor 2 with the route on floor 1.
    @Test func aFloorTheRouteAheadDoesNotTakeIsOffTheRoute() {
        let legs = [Self.leg(1, order: 0)]
        #expect(VisitController.isOnRouteFloor(level: 1, legs: legs))
        #expect(!VisitController.isOnRouteFloor(level: 2, legs: legs))
    }

    /// A ride from level 1 to level 4: both floors are on the route, the floors in between are not.
    @Test func bothEndsOfARideAreOnTheRoute() {
        let legs = [Self.leg(1, order: 0), Self.leg(4, order: 1)]
        #expect(VisitController.isOnRouteFloor(level: 1, legs: legs))
        #expect(VisitController.isOnRouteFloor(level: 4, legs: legs))
        #expect(!VisitController.isOnRouteFloor(level: 2, legs: legs))
    }

    /// A floor the visitor has left behind is no longer on the route.
    @Test func aCompletedLegIsNotOnTheRoute() {
        let legs = [Self.leg(1, completed: true, order: 0), Self.leg(4, order: 1)]
        #expect(!VisitController.isOnRouteFloor(level: 1, legs: legs))
        #expect(VisitController.isOnRouteFloor(level: 4, legs: legs))
    }

    /// No route still to walk: no wrong floor.
    @Test func noRouteAheadIsNoWrongFloor() {
        #expect(VisitController.isOnRouteFloor(level: 2, legs: []))
        #expect(VisitController.isOnRouteFloor(level: 2, legs: [Self.leg(1, completed: true)]))
    }

    /// Monday "Personalized tour: off-route and re-route behaviour", 2026-10-27: the warning shows for
    /// 10 s; the wrong floor counts after 10 s.
    @Test func theWarningShowsFor10Seconds() {
        #expect(GADSettings.standard.offRouteWarningSeconds == 10)
        #expect(GADSettings.standard.wrongFloorSeconds == 10)
    }

    /// Monday "Navigation to a gallery", 2026-10-27: outside every gallery the numbers of the
    /// artworks in galleries are hidden. A curated tour shows them.
    @Test @MainActor func artworkMarkersShowInAGalleryWithGalleryFirst() {
        func shows(_ galleryFirst: Bool, ahead: Bool = false, inGallery: Bool, activeInGallery: Bool = true) -> Bool {
            VisitView.showsArtworkMarkers(
                guidesToGalleryFirst: galleryFirst, hasGalleryAhead: ahead,
                isInGallery: inGallery, isActiveStopInGallery: activeInGallery
            )
        }
        #expect(shows(true, inGallery: true))
        #expect(!shows(true, inGallery: false))
        #expect(!shows(true, ahead: true, inGallery: true))
        // The active artwork is outside every gallery: its number shows.
        #expect(shows(true, inGallery: false, activeInGallery: false))
        #expect(shows(false, ahead: true, inGallery: false))
    }

    /// The markers are hidden with an invisible style, never `nil`: the detour and the visited artworks
    /// keep their markers.
    @Test @MainActor func theHiddenStyleKeepsTheDetour() {
        let hidden = MapStyle.journeyStopsHidden
        #expect(hidden.pending.opacity == 0)
        #expect(hidden.active.opacity == 0)
        #expect(hidden.done.opacity == 1)
        #expect(hidden.passed.opacity == 1)
        #expect(hidden.detour.opacity == 1)
        #expect(hidden != MapStyle.journeyStops)
    }

    /// A paused journey passes on no report of leaving or rejoining the route (Nagarro, 2026-10-28).
    @Test func aPausedJourneyDropsTheRouteDeviationReports() {
        #expect(VisitView.isRouteDeviation(.leftRoute(distance: 13)))
        #expect(VisitView.isRouteDeviation(.farFromRoute(distance: 31)))
        #expect(VisitView.isRouteDeviation(.offRouteTooLong(duration: 60)))
        #expect(VisitView.isRouteDeviation(.returnedToRoute))
        #expect(!VisitView.isRouteDeviation(.journeyFinished))
    }

    /// Inside the gallery of the current artwork the route is refreshed beyond 3 m off the leg, at
    /// most every 3 s (PM's field test, 2026-11-17).
    @Test func theRouteInTheGalleryIsRefreshedOffTheLeg() {
        var settings = GADSettings.standard
        #expect(settings.refreshesRouteInGallery)
        #expect(settings.galleryRouteRefreshMeters == 3)
        #expect(settings.galleryRouteRefreshSeconds == 3)
        #expect(VisitController.refreshesGalleryRoute(meters: 3.5, sinceLast: 10, settings: settings))
        #expect(!VisitController.refreshesGalleryRoute(meters: 3, sinceLast: 10, settings: settings))
        #expect(!VisitController.refreshesGalleryRoute(meters: 8, sinceLast: 2, settings: settings))
        settings.galleryRouteRefreshMeters = 6
        settings.galleryRouteRefreshSeconds = 1
        #expect(!VisitController.refreshesGalleryRoute(meters: 5, sinceLast: 10, settings: settings))
        #expect(VisitController.refreshesGalleryRoute(meters: 7, sinceLast: 1, settings: settings))
        settings.refreshesRouteInGallery = false
        #expect(!VisitController.refreshesGalleryRoute(meters: 30, sinceLast: 60, settings: settings))
    }

    /// The order at a gallery entry is checked once the visitor has been in the gallery for
    /// `galleryEntryOrderSeconds` (PM's field tests, 2026-11-17 and 2026-11-18).
    @Test func theOrderIsCheckedAfterTheVisitorStayedInTheGallery() {
        var settings = GADSettings.standard
        #expect(settings.ordersAtGalleryEntry)
        #expect(settings.galleryEntryOrderSeconds == 3)
        #expect(!VisitController.checksGalleryEntry(seconds: 0, settings: settings))
        #expect(!VisitController.checksGalleryEntry(seconds: 2.9, settings: settings))
        #expect(VisitController.checksGalleryEntry(seconds: 3, settings: settings))
        settings.galleryEntryOrderSeconds = 0
        #expect(VisitController.checksGalleryEntry(seconds: 0, settings: settings))
        settings.ordersAtGalleryEntry = false
        #expect(!VisitController.checksGalleryEntry(seconds: 60, settings: settings))
    }

    private func proposal(order: [String], current: [String], currentMeters: Double, proposedMeters: Double, pinned: [String] = []) -> JourneyOrderProposal {
        JourneyOrderProposal(order: order, currentOrder: current, pinnedStopIDs: pinned, currentMeters: currentMeters, proposedMeters: proposedMeters)
    }

    /// The artworks of the visitor's gallery go first, also when the map's order is no improvement:
    /// the current artwork in gallery 104 was 12.5 m away, the open artwork of the entered gallery
    /// 101 was 49 m away, and the order stayed (PM's log, 2026-11-18 05:38 UTC).
    @Test func theArtworksOfTheVisitorsGalleryGoFirst() throws {
        let kept = proposal(order: ["a104", "b104", "c101", "d101"], current: ["a104", "b104", "c101", "d101"], currentMeters: 100, proposedMeters: 100)
        #expect(!kept.isImprovement)
        #expect(VisitController.galleryFirst(kept, inVisitorGallery: []) == nil)
        let first = try #require(VisitController.galleryFirst(kept, inVisitorGallery: ["c101", "d101"]))
        #expect(first.order == ["c101", "d101", "a104", "b104"])
        // The current artwork is in the visitor's gallery already: the order stays.
        #expect(VisitController.galleryFirst(kept, inVisitorGallery: ["a104", "b104"]) == nil)
    }

    /// Between two artworks at about the same distance the current stop stays.
    @Test func anotherArtworkTakesTheStopOnlyWhenItIsClearlyNearer() {
        var settings = GADSettings()
        #expect(settings.orderSwitchMinimumMeters == 3)
        #expect(!VisitController.switchesStop(nearerMeters: 0.4, entersVisitorGallery: false, settings: settings))
        #expect(!VisitController.switchesStop(nearerMeters: -2, entersVisitorGallery: false, settings: settings))
        #expect(VisitController.switchesStop(nearerMeters: 3, entersVisitorGallery: false, settings: settings))
        // An artwork of the visitor's gallery takes the place of one outside it at any distance.
        #expect(VisitController.switchesStop(nearerMeters: -20, entersVisitorGallery: true, settings: settings))
        settings.orderSwitchMinimumMeters = 0
        #expect(VisitController.switchesStop(nearerMeters: 0, entersVisitorGallery: false, settings: settings))
    }

    /// The leg to an artwork 16.5 m away passed an open artwork of the same gallery 3.7 m away
    /// (PM's field test, 2026-11-18 15:42 UTC).
    @Test func theNearestArtworkOfTheGalleryTakesTheStop() throws {
        var settings = GADSettings()
        #expect(settings.ordersNearestArtworkInGalleryFirst)
        let nearest = try #require(VisitController.nearestStop([("watan", 16.5), ("jand", 3.7)], active: "watan", settings: settings))
        #expect(nearest.id == "jand")
        #expect(abs(nearest.nearerMeters - 12.8) < 0.001)
        // The current stop is the nearest, or the other one is less than 3 m nearer: no change.
        #expect(VisitController.nearestStop([("watan", 3.7), ("jand", 16.5)], active: "watan", settings: settings) == nil)
        #expect(VisitController.nearestStop([("watan", 6), ("jand", 4)], active: "watan", settings: settings) == nil)
        // The current stop is not in the visitor's gallery: this check changes nothing.
        #expect(VisitController.nearestStop([("jand", 3.7)], active: "watan", settings: settings) == nil)
        settings.orderSwitchMinimumMeters = 0
        #expect(VisitController.nearestStop([("watan", 6), ("jand", 6)], active: "watan", settings: settings) == nil)
    }

    /// An improvement of the map keeps its order inside and outside the visitor's gallery.
    @Test func anImprovedOrderKeepsItsOrderBehindTheVisitorsGallery() throws {
        let improved = proposal(order: ["b104", "d101", "a104", "c101"], current: ["a104", "b104", "c101", "d101"], currentMeters: 100, proposedMeters: 60)
        #expect(improved.isImprovement)
        #expect(VisitController.galleryFirst(improved, inVisitorGallery: []) == improved)
        let first = try #require(VisitController.galleryFirst(improved, inVisitorGallery: ["c101", "d101"]))
        #expect(first.order == ["d101", "c101", "b104", "a104"])
        // An improvement that gives the journey's own order after the gallery goes first changes nothing.
        let back = proposal(order: ["c101", "a104", "b104", "d101"], current: ["a104", "b104", "c101", "d101"], currentMeters: 100, proposedMeters: 60)
        #expect(VisitController.galleryFirst(back, inVisitorGallery: ["a104", "b104"]) == nil)
        // Pinned stops keep the map's order.
        let pinned = proposal(order: ["b104", "d101", "a104", "c101"], current: ["a104", "b104", "c101", "d101"], currentMeters: 100, proposedMeters: 60, pinned: ["b104"])
        #expect(VisitController.galleryFirst(pinned, inVisitorGallery: ["c101"]) == pinned)
    }

    /// The map applies an order that is no improvement by walking time.
    @Test func theMapAppliesAGalleryFirstOrder() throws {
        func stop(_ id: String, _ state: JourneyStop.State = .pending) -> JourneyStop {
            JourneyStop(id: id, title: id, coordinate: .init(latitude: 24.54, longitude: 54.39), floor: FloorKey(level: 1), poiID: id, kind: .planned, state: state)
        }
        var plan = ProximiioMap.JourneyPlan(journey: Journey(stops: [stop("x", .done), stop("a104"), stop("b104"), stop("c101"), stop("d101")]))
        _ = plan.start()
        _ = plan.positionChanged(to: .init(latitude: 24.54, longitude: 54.39), floor: FloorKey(level: 1))
        let ids = ["a104", "b104", "c101", "d101"]
        var durations: [JourneyEdge: TimeInterval] = [:]
        for (i, from) in ids.enumerated() {
            durations[JourneyEdge(from: nil, to: from)] = Double(i + 1) * 10
            for (j, to) in ids.enumerated() where i != j { durations[JourneyEdge(from: from, to: to)] = Double(abs(i - j)) * 10 }
        }
        let base = try #require(plan.proposeOrder(durations: durations, from: .visitor))
        #expect(!base.isImprovement)
        let first = try #require(VisitController.galleryFirst(base, inVisitorGallery: ["c101", "d101"]))
        #expect(plan.canApply(first))
        plan.apply(first)
        #expect(plan.activeStop?.id == "c101")
        #expect(plan.journey.stops.map(\.id) == ["x", "c101", "d101", "a104", "b104"])
    }

    @Test func anArtworkIsVisitedAtAnotherArtworkByDefault() {
        #expect(GADSettings.standard.visitsArtworkAtAnotherArtwork)
        #expect(GADSettings.standard.ordersVisitorGalleryFirst)
    }

    /// The warning follows the leg to the current destination: 13 m off it warns also where a later
    /// leg passes, once per episode; back within 8 m the episode ends (PM's log of 2026-10-28, 22:39 UTC).
    @Test func theLegOffRouteWarnsOncePerEpisode() {
        #expect(VisitController.legDeviation(isOffRoute: true, meters: 13, threshold: 12, isEpisode: false, isLegEpisode: false) == .warns)
        #expect(VisitController.legDeviation(isOffRoute: true, meters: 40, threshold: 12, isEpisode: true, isLegEpisode: true) == .none)
        #expect(VisitController.legDeviation(isOffRoute: false, meters: 10, threshold: 12, isEpisode: true, isLegEpisode: true) == .none)
        #expect(VisitController.legDeviation(isOffRoute: false, meters: 7, threshold: 12, isEpisode: true, isLegEpisode: true) == .ends)
        // An episode of the whole journey ends with the navigator's `returnedToRoute`, not here.
        #expect(VisitController.legDeviation(isOffRoute: false, meters: 2, threshold: 12, isEpisode: true, isLegEpisode: false) == .none)
    }

    @Test func offTheLegWithoutTheWarningEveryJourneyIsRoutedAgain() {
        #expect(VisitController.reroutesOffTheLeg(asksApp: false, keepsOrder: false))
        #expect(VisitController.reroutesOffTheLeg(asksApp: false, keepsOrder: true))
        #expect(VisitController.reroutesOffTheLeg(asksApp: true, keepsOrder: true))
        #expect(!VisitController.reroutesOffTheLeg(asksApp: true, keepsOrder: false))
    }
}
