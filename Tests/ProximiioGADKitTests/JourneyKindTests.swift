//
//  JourneyKindTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Testing
@_spi(GADApp) @testable import ProximiioGADKit

struct JourneyKindTests {
    @Test func personalisedShowsGalleriesAndAllowsSkip() {
        #expect(JourneyKind.personalised.guidesToGalleryFirst)
        #expect(JourneyKind.personalised.listsGalleries)
        #expect(JourneyKind.personalised.allowsSkip)
        #expect(!JourneyKind.personalised.keepsOrder)
        #expect(JourneyKind.personalised.countsOutOfOrder)
    }

    @Test func curatedGoesStraightToTheArtworkWithoutSkip() {
        #expect(!JourneyKind.curated.guidesToGalleryFirst)
        #expect(!JourneyKind.curated.listsGalleries)
        #expect(!JourneyKind.curated.allowsSkip)
        #expect(JourneyKind.curated.keepsOrder)
        #expect(!JourneyKind.curated.countsOutOfOrder)
    }

    @Test func storedMetaWithoutKindIsPersonalised() throws {
        let old = Data(#"{"title":"Light & Perception","summary":"8 stops"}"#.utf8)
        #expect(try JSONDecoder().decode(VisitMeta.self, from: old).kind == .personalised)
        let curated = VisitMeta.standard(stopCount: 3, kind: .curated)
        let decoded = try JSONDecoder().decode(VisitMeta.self, from: JSONEncoder().encode(curated))
        #expect(decoded == curated)
    }

    @Test func anArtworkEnteredOutOfOrderWaitsForTheVisitRules() {
        var settings = GADSettings()
        #expect(VisitController.arrivesOutOfOrder(settings: settings))
        settings.visitsOutOfOrderAtEntry = true
        #expect(!VisitController.arrivesOutOfOrder(settings: settings))
        settings.visitsOutOfOrderAtEntry = false
        settings.advancesOnArtworkExit = false
        #expect(!VisitController.arrivesOutOfOrder(settings: settings))
    }

    /// Overlapping artwork geofences: the artwork the visitor arrived at stays the current one while
    /// they are inside its geofence (operator, 2026-11-17).
    @Test func anotherArtworkEndsTheVisitOnlyOutsideTheArrivedOne() {
        #expect(!VisitController.leavesForAnotherArtwork(isInsideAnother: true, activeDistance: 0))
        #expect(VisitController.leavesForAnotherArtwork(isInsideAnother: true, activeDistance: 0.5))
        #expect(VisitController.leavesForAnotherArtwork(isInsideAnother: true, activeDistance: .infinity))
        #expect(!VisitController.leavesForAnotherArtwork(isInsideAnother: false, activeDistance: 3))
    }

    #if DEBUG
    @Test func launchArgumentSetsTheKind() {
        #expect(DebugLaunch(arguments: ["app", "-visitKind", "curated"]).visitKind == .curated)
        #expect(DebugLaunch(arguments: ["app"]).visitKind == .personalised)
    }
    #endif
}
