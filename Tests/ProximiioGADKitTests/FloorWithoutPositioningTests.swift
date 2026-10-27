//
//  FloorWithoutPositioningTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct FloorWithoutPositioningTests {
    /// The "Staircase" POI on GAD level 1; the route to the café on level 0 takes it.
    static let stairs = MapCoordinate(latitude: 24.539731557560017, longitude: 54.39908686117707)
    /// 0.00001° of latitude is about 1.1 m.
    static func north(_ metres: Double) -> MapCoordinate {
        MapCoordinate(latitude: stairs.latitude + metres / 111_000, longitude: stairs.longitude)
    }

    static func marker(_ type: String, from: Double, to: Double, at point: MapCoordinate = stairs, completed: Bool = false) -> RouteGeometry.Marker {
        RouteGeometry.Marker(
            featureType: type, coordinate: point, from: FloorKey(level: from), to: FloorKey(level: to),
            departure: point, arrival: point, isCompleted: completed
        )
    }

    private let toCafe = [Self.marker("staircase", from: 1, to: 0)]

    @Test func theRideToAFloorWithoutPositioningIsReachedNearTheStairs() throws {
        let change = try #require(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(3), level: 1, markers: toCafe, settings: .standard))
        #expect(change.level == 0)
        #expect(change.featureType == "staircase")
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(8), level: 1, markers: toCafe, settings: .standard) == nil)
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(3), level: 2, markers: toCafe, settings: .standard) == nil)
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(3), level: nil, markers: toCafe, settings: .standard) == nil)
    }

    @Test func aFloorWithPositioningIsNoChange() {
        let toLevel4 = [Self.marker("staircase", from: 1, to: 3), Self.marker("staircase", from: 3, to: 4)]
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(1), level: 1, markers: toLevel4, settings: .standard) == nil)
        var settings = GADSettings()
        settings.levelsWithoutPositioning = []
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(1), level: 1, markers: toCafe, settings: settings) == nil)
        settings.levelsWithoutPositioning = [4]
        settings.levelChangerReachedMeters = 2
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(1), level: 1, markers: toLevel4, settings: settings)?.level == 4)
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(3), level: 1, markers: toLevel4, settings: settings) == nil)
    }

    @Test func aCompletedChangeIsNoChange() {
        let done = [Self.marker("staircase", from: 1, to: 0, completed: true)]
        #expect(FloorWithoutPositioningGuide.reachedChange(coordinate: Self.north(1), level: 1, markers: done, settings: .standard) == nil)
    }

    @MainActor @Test func theViewThenTheFloorThenTheVisitorAgain() throws {
        var settings = GADSettings()
        settings.levelChangeViewSeconds = 3600
        let guide = FloorWithoutPositioningGuide(settings: settings)
        var entered: [Int] = []
        var left: [Int] = []
        guide.onEnter = { entered.append($0.level) }
        guide.onLeave = { left.append($0.level) }

        guide.update(coordinate: Self.north(10), level: 1, markers: toCafe, destinationID: "cafe")
        #expect(guide.phase == .idle)
        guide.update(coordinate: Self.north(2), level: 1, markers: toCafe, destinationID: "cafe")
        guard case .changing(let change) = guide.phase else { Issue.record("no lift or stairs view"); return }
        #expect(change.level == 0)
        #expect(guide.isActive)

        guide.showFloor()
        #expect(guide.phase == .onFloor(change))
        #expect(entered == [0])

        // "Resume your Journey": the leg goes to the next artwork.
        guide.update(coordinate: Self.north(2), level: 1, markers: [], destinationID: "artwork")
        #expect(guide.phase == .idle)
        #expect(left == [0])
    }

    @MainActor @Test func aDestinationLeftOnceGetsNoSecondView() {
        let guide = FloorWithoutPositioningGuide(settings: .standard)
        guide.update(coordinate: Self.north(2), level: 1, markers: toCafe, destinationID: "cafe")
        guide.showFloor()
        // "Centre on me" near the stairs.
        guide.leave()
        guide.update(coordinate: Self.north(2), level: 1, markers: toCafe, destinationID: "cafe")
        #expect(guide.phase == .idle)
        // A new route to the prayer room by the same stairs.
        guide.update(coordinate: Self.north(2), level: 1, markers: toCafe, destinationID: "prayer")
        #expect(guide.isActive)
    }

    /// PM, Monday "POIs on floors with no positioning", 2026-10-26: on the way back the lift or stairs
    /// to the next stop's floor nearest the destination is highlighted.
    @Test func theWayBackTakesTheNearestLiftOrStairsToTheNextFloor() {
        let origin = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        let changers = [
            LevelChangerPlace(id: "far-lift", featureType: "elevator", coordinate: ProximiioCoordinate(latitude: 24.502, longitude: 54.4), levels: [0, 1, 2]),
            LevelChangerPlace(id: "near-stairs", featureType: "staircase", coordinate: ProximiioCoordinate(latitude: 24.5001, longitude: 54.4), levels: [0, 1]),
            LevelChangerPlace(id: "nearest-other", featureType: "elevator", coordinate: ProximiioCoordinate(latitude: 24.50001, longitude: 54.4), levels: [2, 3]),
        ]
        #expect(FloorWithoutPositioningGuide.exitChanger(from: origin, level: 0, to: 1, in: changers)?.id == "near-stairs")
        #expect(FloorWithoutPositioningGuide.exitChanger(from: origin, level: 0, to: 2, in: changers)?.id == "far-lift")
        #expect(FloorWithoutPositioningGuide.exitChanger(from: origin, level: 0, to: 4, in: changers) == nil)
    }
}

