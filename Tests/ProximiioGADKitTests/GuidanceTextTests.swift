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

    private func cafe(_ title: String, level: Double, lat: Double) -> VenuePlace {
        var place = place(title, amenity: "a-cafe", level: level, lat: lat)
        place.amenityKind = .cafe
        return place
    }

    @Test func restroomsAreNotConfused() {
        #expect(AmenityKind.kind(forAmenityID: "a1", title: "Women's Restroom") == .womensRestroom)
        #expect(AmenityKind.kind(forAmenityID: "a2", title: "Men's Restroom") == .mensRestroom)
        #expect(AmenityKind.kind(forAmenityID: "a3", title: "Womens restroom visited") == nil)
    }

    /// A place matches by its amenity, never by its title (PM, Monday "Amenity search & Map legend
    /// views", 2026-10-28: the prayer room shortcut led to the artwork "Endless Prayers XIII").
    @Test func aPlaceMatchesByItsAmenityNotItsTitle() {
        let amenities = [ProximiioAmenity(id: "a-prayer", title: "Prayer Room"), ProximiioAmenity(id: "a-art", title: "Artwork"),
                         ProximiioAmenity(id: "a-cafe", title: "Cafe")]
        let places = VenuePlace.withAmenityKinds(
            [place("Endless Prayers XIII", amenity: "a-art"), place("Room 4", amenity: "a-prayer"),
             place("The Terrace", amenity: "a-cafe"), place("Prayer room", amenity: nil)],
            amenities: amenities
        )
        #expect(places.filter(AmenityKind.prayerRoom.matches).map(\.title) == ["Room 4"])
        #expect(places.filter(AmenityKind.cafe.matches).map(\.title) == ["The Terrace"])
        #expect(AmenityKind.kinds(of: amenities) == ["a-prayer": .prayerRoom, "a-cafe": .cafe])
    }

    @Test func nearestPrefersTheVisitorsLevel() {
        let places = [cafe("Café A", level: 3, lat: 0.0001), cafe("Café B", level: 1, lat: 0.01)]
        #expect(AmenityKind.cafe.nearest(in: places, from: .init(latitude: 0, longitude: 0), level: 1)?.title == "Café B")
        #expect(AmenityKind.cafe.nearest(in: places, from: .init(latitude: 0, longitude: 0), level: 2)?.title == "Café A")
    }

    /// GAD data 2026-10-15: from level 1 of the Guggenheim the café chip chose the DCT office café,
    /// on level 1 but 11 km away, over the Guggenheim café on level 0.
    @Test func nearestStaysInTheVenueOfTheNearestPlace() {
        var guggenheim = cafe("Café", level: 0, lat: 0.0001)
        guggenheim.placeID = "guggenheim"
        var dct = cafe("DCT Cafe", level: 1, lat: 0.1)
        dct.placeID = "dct"
        #expect(AmenityKind.cafe.nearest(in: [dct, guggenheim], from: .init(latitude: 0, longitude: 0), level: 1)?.title == "Café")
        #expect(AmenityKind.cafe.nearest(in: [dct, guggenheim], from: .init(latitude: 0.1, longitude: 0), level: 0)?.title == "DCT Cafe")
    }

    // MARK: Next stop on another floor

    private static func marker(_ type: String, from: Double, to: Double, completed: Bool = false,
                               at point: MapCoordinate = MapCoordinate(latitude: 24.5, longitude: 54.4)) -> RouteGeometry.Marker {
        RouteGeometry.Marker(
            featureType: type, coordinate: point, from: FloorKey(level: from), to: FloorKey(level: to),
            departure: point, arrival: point, isCompleted: completed
        )
    }

    /// Monday "Stairs&elevator icon disappeared from instructions", 2026-10-27: the card shows the
    /// icon of the next level change from the visitor's floor.
    @Test func theNextLevelChangeStartsOnTheVisitorsFloor() {
        let markers = [Self.marker("staircase", from: 1, to: 3), Self.marker("elevator", from: 3, to: 4)]
        #expect(GuidanceText.levelChange(markers: markers, visitorLevel: 3)?.featureType == "elevator")
        #expect(GuidanceText.levelChange(markers: markers, visitorLevel: 2)?.featureType == "staircase")
        #expect(GuidanceText.levelChange(markers: [Self.marker("staircase", from: 1, to: 3, completed: true)], visitorLevel: 1) == nil)
        #expect(GADIcon.levelChanger(featureType: "elevator") == .elevator)
        #expect(GADIcon.levelChanger(featureType: "staircase") == .stairs)
        #expect(GADIcon.levelChanger(featureType: "escalator") == .stairs)
    }

    /// PM 2026-10-15: the route from level 1 to level 4 takes the stairs to level 3, then the lift.
    @Test func levelChangeTitleNamesTheRoutesFirstChangeFromTheVisitorsFloor() {
        let markers = [Self.marker("staircase", from: 1, to: 3), Self.marker("elevator", from: 3, to: 4)]
        #expect(GuidanceText.levelChangeTitle(markers: markers, visitorLevel: 1, stopLevel: 4) == "Take the stairs to level 3")
        #expect(GuidanceText.levelChangeTitle(markers: markers, visitorLevel: 3, stopLevel: 4) == "Take the lift to level 4")
    }

    /// Monday 2026-10-15: the SDK router splits one ride into a change per floor with paths at the
    /// staircase or lift (stairs 1→3, 3→4; the lift 1→2, 2→3, 3→4). The card names the end of the ride.
    @Test func levelChangesInTheSameStaircaseOrLiftAreOneRide() {
        let stairs = [Self.marker("staircase", from: 1, to: 3), Self.marker("staircase", from: 3, to: 4)]
        #expect(GuidanceText.levelChangeTitle(markers: stairs, visitorLevel: 1, stopLevel: 4) == "Take the stairs to level 4")
        let lift = [Self.marker("elevator", from: 1, to: 2), Self.marker("elevator", from: 2, to: 3), Self.marker("elevator", from: 3, to: 4)]
        #expect(GuidanceText.levelChangeTitle(markers: lift, visitorLevel: 1, stopLevel: 4) == "Take the lift to level 4")
        let other = MapCoordinate(latitude: 24.5003, longitude: 54.4)
        let twoStaircases = [Self.marker("staircase", from: 1, to: 3), Self.marker("staircase", from: 3, to: 4, at: other)]
        #expect(GuidanceText.levelChangeTitle(markers: twoStaircases, visitorLevel: 1, stopLevel: 4) == "Take the stairs to level 3")
        let point = MapCoordinate(latitude: 24.5, longitude: 54.4)
        #expect(GuidanceText.rideEnd(featureType: "staircase", coordinate: point, from: 1, to: 3, markers: stairs) == 4)
        #expect(GuidanceText.rideEnd(featureType: "staircase", coordinate: point, from: 1, to: 3, markers: []) == 3)
    }

    @Test func levelChangeTitleSkipsCompletedChanges() {
        let markers = [Self.marker("staircase", from: 1, to: 3, completed: true), Self.marker("elevator", from: 3, to: 4)]
        #expect(GuidanceText.levelChangeTitle(markers: markers, visitorLevel: nil, stopLevel: 4) == "Take the lift to level 4")
    }

    @Test func levelChangeTitleWithoutARouteNamesTheStopsFloor() {
        #expect(GuidanceText.levelChangeTitle(markers: [], visitorLevel: 1, stopLevel: 4) == "Go to level 4")
    }
}
