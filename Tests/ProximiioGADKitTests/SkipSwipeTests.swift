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

    @Test func aSwipeAsksForTheSkipAtOnceWhenSet() {
        let revealing = SkipSwipe.end(isRevealed: false, projected: -60, skipsAtSwipe: true)
        #expect(!revealing.revealed && revealing.skips)
        let short = SkipSwipe.end(isRevealed: false, projected: -20, skipsAtSwipe: true)
        #expect(!short.revealed && !short.skips)
        let button = SkipSwipe.end(isRevealed: false, projected: -60, skipsAtSwipe: false)
        #expect(button.revealed && !button.skips)
    }

    /// With both ways a swipe towards the trailing edge asks for the skip; without it, and
    /// without `skipsAtSwipe`, it does nothing.
    @Test func aSwipeTowardsTheTrailingEdgeAsksForTheSkipWhenSet() {
        let trailing = SkipSwipe.end(isRevealed: false, projected: 103, skipsAtSwipe: true, bothWays: true)
        #expect(!trailing.revealed && trailing.skips)
        let short = SkipSwipe.end(isRevealed: false, projected: 30, skipsAtSwipe: true, bothWays: true)
        #expect(!short.revealed && !short.skips)
        let oneWay = SkipSwipe.end(isRevealed: false, projected: 103, skipsAtSwipe: true, bothWays: false)
        #expect(!oneWay.revealed && !oneWay.skips)
        let button = SkipSwipe.end(isRevealed: false, projected: 103, skipsAtSwipe: false, bothWays: true)
        #expect(!button.revealed && !button.skips)
        // The row follows the finger towards the trailing edge, then rubber-bands.
        #expect(SkipSwipe.offset(isRevealed: false, drag: 50, bothWays: true) == 50)
        #expect(SkipSwipe.offset(isRevealed: false, drag: 172, bothWays: true) == 102)
        #expect(SkipSwipe.offset(isRevealed: false, drag: 50) == 10)
    }

    /// Nagarro's video, 2026-11-23: the row of the last artwork asked to skip an artwork that was
    /// skipped before. The list's pan takes the stop from the row under the finger, and only a
    /// stop the list names as one to skip.
    @MainActor @Test func theListsPanTakesTheRowUnderTheFinger() {
        let router = SwipeRouter()
        var began: [String] = []
        var ended: [(String, CGFloat, CGFloat)] = []
        router.update(skippable: ["active", "last"], onBegan: { began.append($0) }, onEnded: { ended.append(($0, $1, $2)) })
        router.frames["visited"] = CGRect(x: 20, y: 100, width: 350, height: 70)
        router.frames["active"] = CGRect(x: 20, y: 220, width: 350, height: 70)
        // The frame of a skipped row that is still stored lies where the last row is now.
        router.frames["skipped"] = CGRect(x: 20, y: 340, width: 350, height: 70)
        router.frames["last"] = CGRect(x: 20, y: 340, width: 350, height: 70)

        #expect(router.stopID(at: CGPoint(x: 300, y: 370)) == "last")
        #expect(router.stopID(at: CGPoint(x: 300, y: 250)) == "active")
        // A visited row, a header, the space between rows.
        #expect(router.stopID(at: CGPoint(x: 300, y: 130)) == nil)
        #expect(router.stopID(at: CGPoint(x: 300, y: 300)) == nil)

        router.begin(at: CGPoint(x: 300, y: 370))
        router.move(-80)
        #expect(router.dragID == "last" && router.dragX == -80)
        router.end(translation: -120, velocity: -400)
        #expect(began == ["last"])
        #expect(ended.count == 1 && ended[0].0 == "last" && ended[0].1 == -120 && ended[0].2 == -400)
        router.reset()
        #expect(router.dragID == nil && router.dragX == 0)

        // A drag that starts on no row to skip moves no row and ends without a call.
        router.begin(at: CGPoint(x: 300, y: 130))
        router.move(-80)
        router.end(translation: -120, velocity: 0)
        #expect(router.dragID == nil && router.dragX == 0 && ended.count == 1)
    }
}
