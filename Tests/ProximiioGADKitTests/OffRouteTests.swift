//
//  OffRouteTests.swift
//  ProximiioGADKitTests
//
//  The wrong floor counts as off the route, the off-route warning's time, and the stop markers with
//  gallery first (PM, Monday 2026-10-27).
//
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

    /// The markers are hidden with an invisible style, never `nil`: the detour keeps its marker.
    @Test @MainActor func theHiddenStyleKeepsTheDetour() {
        let hidden = MapStyle.journeyStopsHidden
        #expect(hidden.pending.opacity == 0)
        #expect(hidden.active.opacity == 0)
        #expect(hidden.done.opacity == 0)
        #expect(hidden.passed.opacity == 0)
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
}
