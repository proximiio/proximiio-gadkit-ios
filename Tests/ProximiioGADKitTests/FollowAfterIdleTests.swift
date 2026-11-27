//
//  FollowAfterIdleTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Testing
@testable import ProximiioGADKit

struct FollowAfterIdleTests {
    private let here = FollowAfterIdle.Camera(latitude: 24.5398, longitude: 54.3992, zoom: 19, direction: 0)
    private let moved = FollowAfterIdle.Camera(latitude: 24.5399, longitude: 54.3992, zoom: 19, direction: 0)

    private final class Reader {
        var idle = FollowAfterIdle()

        func read(_ camera: FollowAfterIdle.Camera?, isFree: Bool, isAllowed: Bool, seconds: TimeInterval, now: TimeInterval) -> Bool {
            idle.reading(camera, isFree: isFree, isAllowed: isAllowed, seconds: seconds, now: now)
        }
    }

    @Test func aFreeCameraFollowsAgainAfterTheSecondsWithoutAMove() {
        let idle = Reader()
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 100))
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 104.5))
        #expect(idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 105))
        // The next follow needs a new still time.
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 105.5))
    }

    @Test func aMoveOfTheCameraStartsTheTimeAgain() {
        let idle = Reader()
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 100))
        #expect(!idle.read(moved, isFree: true, isAllowed: true, seconds: 5, now: 104))
        #expect(!idle.read(moved, isFree: true, isAllowed: true, seconds: 5, now: 108.5))
        #expect(idle.read(moved, isFree: true, isAllowed: true, seconds: 5, now: 109))
    }

    @Test func zeroSecondsNeverFollows() {
        let idle = Reader()
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 0, now: 100))
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 0, now: 1000))
    }

    @Test func aFollowingCameraAndAConditionStartTheTimeAgain() {
        let idle = Reader()
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 100))
        #expect(!idle.read(here, isFree: false, isAllowed: true, seconds: 5, now: 110))
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 111))
        #expect(!idle.read(here, isFree: true, isAllowed: false, seconds: 5, now: 120))
        #expect(!idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 121))
        #expect(idle.read(here, isFree: true, isAllowed: true, seconds: 5, now: 126))
    }

    @Test func aCameraWithoutAReadingDoesNotFollow() {
        let idle = Reader()
        #expect(!idle.read(nil, isFree: true, isAllowed: true, seconds: 5, now: 100))
        #expect(!idle.read(nil, isFree: true, isAllowed: true, seconds: 5, now: 110))
    }

    @Test func theFollowNeedsTheVisitorsFloorAndNoOtherView() {
        func allowed(isPaused: Bool = false, guide: Bool = false, start: Bool = false, place: Bool = false,
                     visitor: Double? = 1, shown: Double = 1) -> Bool {
            VisitView.followsAgainAfterIdle(isPaused: isPaused, isFloorGuideActive: guide, isStartZoomPending: start,
                                            showsPlace: place, visitorLevel: visitor, shownLevel: shown)
        }
        #expect(allowed())
        #expect(!allowed(isPaused: true))
        #expect(!allowed(guide: true))
        #expect(!allowed(start: true))
        #expect(!allowed(place: true))
        #expect(!allowed(visitor: nil))
        #expect(!allowed(shown: 0))
    }

    @Test func theDefaultIsFiveSeconds() {
        #expect(GADSettings.standard.followsAgainAfterSeconds == 5)
    }
}
