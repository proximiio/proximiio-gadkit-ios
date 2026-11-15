//
//  LevelChangerIconTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Testing
@_spi(GADApp) @testable import ProximiioGADKit

struct LevelChangerIconTests {
    @Test func aRampAndAHillAreLevelChangers() {
        #expect(LevelChangerPlace.featureTypes == ["elevator", "staircase", "escalator", "ramp", "hill"])
    }

    @Test func onlyAnAmenityThatIsNeitherStairsNorALiftShowsItsOwnIcon() {
        #expect(LevelChangerPlace.showsAmenityIcon(amenityID: "org:1", title: "Ramp"))
        #expect(LevelChangerPlace.showsAmenityIcon(amenityID: "org:2", title: "Escalator UP"))
        #expect(LevelChangerPlace.showsAmenityIcon(amenityID: "org:3", title: nil))
        #expect(!LevelChangerPlace.showsAmenityIcon(amenityID: "org:4", title: "Staircase"))
        #expect(!LevelChangerPlace.showsAmenityIcon(amenityID: "org:5", title: "Elevator"))
        #expect(!LevelChangerPlace.showsAmenityIcon(amenityID: "org:lift", title: nil))
    }
}
