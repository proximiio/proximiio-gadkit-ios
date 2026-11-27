//
//  ExploreRevealTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Testing
@testable import ProximiioGADKit

struct ExploreRevealTests {
    private func reason(elapsed: TimeInterval, isIdle: Bool = false, wasIdle: Bool = false, hasError: Bool = false, maximum: TimeInterval = 4) -> String? {
        ExploreMuseumView.revealReason(elapsed: elapsed, isIdle: isIdle, wasIdleAtFrame: wasIdle, hasError: hasError, maximumSeconds: maximum)
    }

    @Test func theMapWaitsForTheIdleMap() {
        #expect(reason(elapsed: 0.1) == nil)
        #expect(reason(elapsed: 3.9) == nil)
        #expect(reason(elapsed: 0.1, isIdle: true) == "venue drawn")
    }

    @Test func theMapShowsAfterTheLongestWait() {
        #expect(reason(elapsed: 4) == "after the longest wait")
        #expect(reason(elapsed: 1, maximum: 1) == "after the longest wait")
    }

    @Test func aMapIdleBeforeTheCameraGetsTheSettleTime() {
        #expect(reason(elapsed: 0.2, isIdle: true, wasIdle: true) == nil)
        #expect(reason(elapsed: 0.5, isIdle: true, wasIdle: true) == "drawn before the camera was set")
    }

    @Test func aMapErrorShowsTheMap() {
        #expect(reason(elapsed: 0, hasError: true) == "map error")
    }

    @Test func theDefaultWaitIsFourSeconds() {
        #expect(GADSettings.standard.exploreMapRevealMaximumSeconds == 4)
    }
}
