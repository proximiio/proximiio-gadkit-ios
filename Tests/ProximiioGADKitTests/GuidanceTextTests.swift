//
//  GuidanceTextTests.swift
//  ProximiioGADKitTests
//
import Proximiio
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
}
