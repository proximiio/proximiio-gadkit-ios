//
//  LevelChangeTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct LevelChangeTests {
    @Test func firstFloorIsNoChange() {
        var detector = LevelChangeDetector()
        #expect(detector.update(level: 1) == nil)
        #expect(detector.level == 1)
    }

    @Test func defaultChangesOnTheFirstFixOnTheNewFloor() {
        var detector = LevelChangeDetector()
        _ = detector.update(level: 1)
        #expect(detector.update(level: 2) == LevelChange(from: 1, to: 2))
        #expect(detector.update(level: 2) == nil)
    }

    @Test func changeNeedsTwoFixesOnTheNewFloor() {
        var detector = LevelChangeDetector(confirmations: 2)
        _ = detector.update(level: 1)
        #expect(detector.update(level: 2) == nil)
        #expect(detector.update(level: 2) == LevelChange(from: 1, to: 2))
        #expect(detector.update(level: 2) == nil)
    }

    @Test func singleFixOnAnotherFloorIsIgnored() {
        var detector = LevelChangeDetector(confirmations: 2)
        _ = detector.update(level: 1)
        #expect(detector.update(level: 2) == nil)
        #expect(detector.update(level: 1) == nil)
        #expect(detector.update(level: 2) == nil)
        #expect(detector.level == 1)
    }

    @Test func directionAndMissingFloor() {
        var detector = LevelChangeDetector()
        _ = detector.update(level: 4)
        #expect(detector.update(level: nil) == nil)
        let change = detector.update(level: 2.0001)
        #expect(change == LevelChange(from: 4, to: 2))
        #expect(change?.isUp == false)
    }

    // MARK: Lift

    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    /// Field log 2026-10-08 16:03:39–16:03:50: 1 s fixes inside the lift on L1, then L2.
    @Test func standingInTheLiftBoardsAfterTheDwell() {
        var lift = LiftDetector()
        #expect(lift.update(inLift: false, at: Self.start) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 1) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 2) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 3) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 4) == .boarded)
        #expect(lift.update(inLift: true, at: Self.start + 5) == nil)
        #expect(lift.isRiding)
    }

    /// Field log 16:03:54–16:03:55: two fixes inside another lift while walking on L2.
    @Test func walkingThroughALiftIsNoRide() {
        var lift = LiftDetector()
        #expect(lift.update(inLift: true, at: Self.start) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 1) == nil)
        #expect(lift.update(inLift: false, at: Self.start + 2) == nil)
        #expect(lift.update(inLift: false, at: Self.start + 3) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 4) == nil)
        #expect(!lift.isRiding)
    }

    @Test func leavingTheLiftEndsTheRideAfterTwoFixesOutside() {
        var lift = LiftDetector()
        _ = lift.update(inLift: true, at: Self.start)
        #expect(lift.update(inLift: true, at: Self.start + 3) == .boarded)
        #expect(lift.update(inLift: false, at: Self.start + 4) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 5) == nil)
        #expect(lift.update(inLift: false, at: Self.start + 6) == nil)
        #expect(lift.update(inLift: false, at: Self.start + 7) == .left)
        #expect(!lift.isRiding)
    }

    // MARK: Ride target

    private static let lift = LiftArea(outline: Gallery(
        id: "lift", name: "", level: 0,
        ring: [(24.0, 54.0), (24.0, 54.001), (24.001, 54.001), (24.001, 54.0)].map { ProximiioCoordinate(latitude: $0.0, longitude: $0.1) }
    ))

    private static func change(_ type: String, from: Double, to: Double, inLift: Bool = true) -> RouteLevelChange {
        let point = inLift ? MapCoordinate(latitude: 24.0005, longitude: 54.0005) : MapCoordinate(latitude: 24.01, longitude: 54.01)
        return RouteLevelChange(featureType: type, fromLevel: from, toLevel: to, coordinate: point)
    }

    @Test func rideTargetIsTheRoutesLevelChangeByThisLift() {
        #expect(Self.lift.rideTarget(of: Self.change("elevator", from: 1, to: 4), from: 1) == 4)
    }

    /// PM 2026-10-15: the route took the stairs to level 3; the visitor rode a lift to level 4 and
    /// saw "Level 3".
    @Test func rideTargetIgnoresStairsAnotherLiftAndAnotherFloor() {
        #expect(Self.lift.rideTarget(of: Self.change("staircase", from: 1, to: 3), from: 1) == nil)
        #expect(Self.lift.rideTarget(of: Self.change("elevator", from: 1, to: 3, inLift: false), from: 1) == nil)
        #expect(Self.lift.rideTarget(of: Self.change("elevator", from: 3, to: 4), from: 1) == nil)
        #expect(Self.lift.rideTarget(of: nil, from: 1) == nil)
    }

    @Test func liftDetectorTakesTheSettings() {
        var settings = GADSettings()
        settings.liftRideDwell = 1
        var lift = LiftDetector(dwell: settings.liftRideDwell, exitFixes: settings.liftExitFixes)
        #expect(lift.update(inLift: true, at: Self.start) == nil)
        #expect(lift.update(inLift: true, at: Self.start + 1) == .boarded)
    }
}
