//
//  LevelChangeTests.swift
//  ProximiioGADKitTests
//
import Foundation
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
}
