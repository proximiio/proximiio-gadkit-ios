//
//  PositionLivenessTests.swift
//  ProximiioGADKitTests
//
import Foundation
import ProximiioMap
import Testing
@testable import ProximiioGADKit

/// The journey camera without a live position (field tests 2026-11-06).
struct PositionLivenessTests {
    @MainActor @Test func aPositionIsLiveWhilePositioningIsAvailable() {
        let settings = GADSettings.standard
        #expect(VisitView.isLive(health: .tracking, positionAge: 1, settings: settings))
        #expect(VisitView.isLive(health: .tracking, positionAge: 3600, settings: settings))
        #expect(VisitView.isLive(health: .privacyZone, positionAge: 600, settings: settings))
        #expect(!VisitView.isLive(health: .lostPlace, positionAge: 1, settings: settings))
        #expect(!VisitView.isLive(health: .stoppedResponding, positionAge: 1, settings: settings))
        #expect(!VisitView.isLive(health: .tracking, positionAge: nil, settings: settings))
    }

    /// The SDK hands a new map its last position at any age: the position of a wristband that another
    /// phone took over 44 min before does not count.
    @MainActor @Test func beforePositioningOnlyARecentPositionIsLive() {
        var settings = GADSettings.standard
        #expect(VisitView.isLive(health: .waiting, positionAge: 109, settings: settings))
        #expect(!VisitView.isLive(health: .waiting, positionAge: 110, settings: settings))
        #expect(!VisitView.isLive(health: .waiting, positionAge: 44 * 60, settings: settings))
        #expect(!VisitView.isLive(health: .waiting, positionAge: nil, settings: settings))
        settings.trackingLostAfter = 30
        #expect(!VisitView.isLive(health: .waiting, positionAge: 30, settings: settings))
    }

    @MainActor @Test func withoutAPositionTheCameraShowsTheNextStop() {
        func stop(_ id: String, state: JourneyStop.State, kind: JourneyStop.Kind = .planned) -> JourneyStop {
            JourneyStop(id: id, title: id, coordinate: .init(latitude: 24.54, longitude: 54.39), floor: FloorKey(level: 1), poiID: id, kind: kind, state: state)
        }
        let journey = Journey(stops: [stop("done", state: .done), stop("skipped", state: .skipped), stop("next", state: .pending), stop("last", state: .pending)])
        #expect(VisitView.stopWithoutPosition(detour: nil, active: nil, journey: journey)?.id == "next")
        let active = stop("active", state: .active)
        #expect(VisitView.stopWithoutPosition(detour: nil, active: active, journey: journey)?.id == "active")
        let cafe = stop("cafe", state: .active, kind: .detour)
        #expect(VisitView.stopWithoutPosition(detour: cafe, active: active, journey: journey)?.id == "cafe")
        let finished = Journey(stops: [stop("done", state: .done), stop("skipped", state: .skipped)])
        #expect(VisitView.stopWithoutPosition(detour: nil, active: nil, journey: finished) == nil)
    }
}
