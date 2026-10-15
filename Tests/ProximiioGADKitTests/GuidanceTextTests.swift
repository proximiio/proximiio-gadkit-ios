//
//  GuidanceTextTests.swift
//  ProximiioGADKitTests
//
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct GuidanceTextTests {
    @Test(arguments: [(0.0, "<1 min"), (71.0, "<1 min"), (72.0, "1 min"), (73.0, "2 min"), (150.0, "3 min")])
    func walkingTimeRoundsUpWholeMinutes(_ metres: Double, _ expected: String) {
        #expect(GuidanceText.walkingTime(metres: metres) == expected)
    }

    @Test func remainingCombinesDistanceAndTime() {
        #expect(GuidanceText.remaining(metres: 70.4) == "70 m · <1 min")
    }

    @Test(arguments: [(0.0, "L0"), (1.0, "L1"), (-1.0, "L-1"), (2.4, "L2")])
    func floorLabel(_ level: Double, _ expected: String) {
        #expect(GuidanceText.floorLabel(level) == expected)
    }

    @Test func levelChangerNames() {
        #expect(GuidanceText.levelChanger("elevator") == "lift")
        #expect(GuidanceText.levelChanger("staircase") == "stairs")
        #expect(GuidanceText.levelChanger("unknown") == "unknown")
    }
}

struct AmenityKindTests {
    private func place(_ title: String, amenity: String? = nil, level: Double = 1, lat: Double = 0) -> VenuePlace {
        VenuePlace(id: title, title: title, coordinate: .init(latitude: lat, longitude: 0), level: level, amenityID: amenity)
    }

    @Test func restroomsAreNotConfused() {
        #expect(AmenityKind.womensRestroom.matches(place("Women's Restroom")))
        #expect(!AmenityKind.mensRestroom.matches(place("Women's Restroom")))
        #expect(AmenityKind.mensRestroom.matches(place("Men's Restroom")))
        #expect(!AmenityKind.womensRestroom.matches(place("Men's Restroom")))
    }

    @Test func matchesByAmenityID() {
        #expect(AmenityKind.cafe.matches(place("The Terrace", amenity: "food:cafe")))
        #expect(AmenityKind.prayerRoom.matches(place("Room 4", amenity: "services:prayer_room")))
        #expect(!AmenityKind.cafe.matches(place("Gallery 101")))
    }

    @Test func nearestPrefersTheVisitorsLevel() {
        let places = [place("Café A", level: 3, lat: 0.0001), place("Café B", level: 1, lat: 0.01)]
        #expect(AmenityKind.cafe.nearest(in: places, from: .init(latitude: 0, longitude: 0), level: 1)?.title == "Café B")
        #expect(AmenityKind.cafe.nearest(in: places, from: .init(latitude: 0, longitude: 0), level: 2)?.title == "Café A")
    }

    // MARK: Next stop on another floor

    private static func marker(_ type: String, from: Double, to: Double, completed: Bool = false) -> RouteGeometry.Marker {
        let point = MapCoordinate(latitude: 24.5, longitude: 54.4)
        return RouteGeometry.Marker(
            featureType: type, coordinate: point, from: FloorKey(level: from), to: FloorKey(level: to),
            departure: point, arrival: point, isCompleted: completed
        )
    }

    /// PM 2026-10-15: the route from level 1 to level 4 takes the stairs to level 3, then the lift.
    @Test func levelChangeTitleNamesTheRoutesFirstChangeFromTheVisitorsFloor() {
        let markers = [Self.marker("staircase", from: 1, to: 3), Self.marker("elevator", from: 3, to: 4)]
        #expect(GuidanceText.levelChangeTitle(markers: markers, visitorLevel: 1, stopLevel: 4) == "Take the stairs to level 3")
        #expect(GuidanceText.levelChangeTitle(markers: markers, visitorLevel: 3, stopLevel: 4) == "Take the lift to level 4")
    }

    @Test func levelChangeTitleSkipsCompletedChanges() {
        let markers = [Self.marker("staircase", from: 1, to: 3, completed: true), Self.marker("elevator", from: 3, to: 4)]
        #expect(GuidanceText.levelChangeTitle(markers: markers, visitorLevel: nil, stopLevel: 4) == "Take the lift to level 4")
    }

    @Test func levelChangeTitleWithoutARouteNamesTheStopsFloor() {
        #expect(GuidanceText.levelChangeTitle(markers: [], visitorLevel: 1, stopLevel: 4) == "Go to level 4")
    }
}
