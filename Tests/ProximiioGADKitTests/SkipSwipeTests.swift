//
//  SkipSwipeTests.swift
//  ProximiioGADKitTests
//
import Foundation
import ProximiioMap
import SwiftUI
import Testing
@testable import ProximiioGADKit

struct SkipSwipeTests {
    private let places = [
        VenuePlace(id: "a", title: "Artwork 1", coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1),
        VenuePlace(id: "b", title: "Artwork 2", coordinate: .init(latitude: 24.6, longitude: 54.5), level: 1),
    ]

    @Test func aDragToTheLeftRevealsThePanelInALeftToRightLayout() {
        let sign = SkipSwipe.sign(.leftToRight)
        #expect(SkipSwipe.reveals(isRevealed: false, projected: -60 * sign))
        #expect(!SkipSwipe.reveals(isRevealed: false, projected: 60 * sign))
        #expect(SkipSwipe.offset(isRevealed: false, drag: -40 * sign) == -40)
    }

    @Test func aDragToTheRightRevealsThePanelInARightToLeftLayout() {
        let sign = SkipSwipe.sign(.rightToLeft)
        #expect(SkipSwipe.reveals(isRevealed: false, projected: 60 * sign))
        #expect(!SkipSwipe.reveals(isRevealed: false, projected: -60 * sign))
        // Towards the leading edge, which is right on the screen.
        #expect(SkipSwipe.offset(isRevealed: false, drag: 40 * sign) == -40)
        #expect(SkipSwipe.offset(isRevealed: true, drag: 0) == -SkipSwipe.revealWidth)
    }

    @Test func aDragBackClosesARevealedPanel() {
        #expect(!SkipSwipe.reveals(isRevealed: true, projected: 60))
        #expect(SkipSwipe.reveals(isRevealed: true, projected: 10))
    }

    @Test func theRowRubberBandsPastBothEnds() {
        #expect(SkipSwipe.offset(isRevealed: false, drag: 50) == 10)
        #expect(SkipSwipe.offset(isRevealed: false, drag: -172) == -102)
    }

    @Test func onlyAStopStillAheadCanBeSkipped() {
        var journey = VisitPlan.journey(poiIDs: ["a", "b"], places: places)
        #expect(journey.stops.allSatisfy(SkipSwipe.canSkip))
        journey = VisitPlan.setting(.skipped, forStop: "a", in: journey)
        journey = VisitPlan.setting(.done, forStop: "b", in: journey)
        #expect(!journey.stops.contains(where: SkipSwipe.canSkip))
    }
}
