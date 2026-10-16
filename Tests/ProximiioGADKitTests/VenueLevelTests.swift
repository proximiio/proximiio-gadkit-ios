//
//  VenueLevelTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import Testing
@testable import ProximiioGADKit

struct VenueLevelTests {
    @Test func aMezzanineIsItsOwnLevel() {
        #expect(VenueLevel.same(1.5, 1.5))
        #expect(!VenueLevel.same(1.5, 2))
        #expect(!VenueLevel.same(1.5, 1))
        #expect(!VenueLevel.same(-0.5, -1))
    }

    @Test func floatingPointNoiseIsTheSameLevel() {
        #expect(VenueLevel.same(1, 1.000_001))
        #expect(VenueLevel.same(0, -0.000_001))
    }

    @Test func anUnknownLevelMatchesAnyLevel() {
        #expect(VenueLevel.matches(nil, 1.5))
        #expect(VenueLevel.matches(2, nil))
        #expect(!VenueLevel.matches(2, 1.5))
    }

    @Test func aStopOnAMezzanineIsNotNearbyFromTheLevelAbove() {
        let stop = ProximiioCoordinate(latitude: 24.464, longitude: 54.329)
        #expect(StopNearbyDetector.isNearby(stop, level: 1.5, stop: stop, stopLevel: 1.5))
        #expect(!StopNearbyDetector.isNearby(stop, level: 2, stop: stop, stopLevel: 1.5))
    }
}
