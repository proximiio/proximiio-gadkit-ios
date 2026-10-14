//
//  JourneyKindTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Testing
@testable import ProximiioGADKit

struct JourneyKindTests {
    @Test func personalisedShowsGalleriesAndAllowsSkip() {
        #expect(JourneyKind.personalised.guidesToGalleryFirst)
        #expect(JourneyKind.personalised.listsGalleries)
        #expect(JourneyKind.personalised.allowsSkip)
        #expect(!JourneyKind.personalised.keepsOrder)
    }

    @Test func curatedGoesStraightToTheArtworkWithoutSkip() {
        #expect(!JourneyKind.curated.guidesToGalleryFirst)
        #expect(!JourneyKind.curated.listsGalleries)
        #expect(!JourneyKind.curated.allowsSkip)
        #expect(JourneyKind.curated.keepsOrder)
    }

    @Test func storedMetaWithoutKindIsPersonalised() throws {
        let old = Data(#"{"title":"Light & Perception","summary":"8 stops"}"#.utf8)
        #expect(try JSONDecoder().decode(VisitMeta.self, from: old).kind == .personalised)
        let curated = VisitMeta.standard(stopCount: 3, kind: .curated)
        let decoded = try JSONDecoder().decode(VisitMeta.self, from: JSONEncoder().encode(curated))
        #expect(decoded == curated)
    }

    #if DEBUG
    @Test func launchArgumentSetsTheKind() {
        #expect(DebugLaunch(arguments: ["app", "-visitKind", "curated"]).visitKind == .curated)
        #expect(DebugLaunch(arguments: ["app"]).visitKind == .personalised)
    }
    #endif
}
