//
//  RoutePreferencesTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import Testing
@testable import ProximiioGADKit

struct RoutePreferencesTests {
    @Test func stepFreeUsesTheWheelchairProfile() throws {
        let defaults = try #require(UserDefaults(suiteName: "RoutePreferencesTests-\(UUID().uuidString)"))
        #expect(!RoutePreferences.isStepFree(in: defaults))
        #expect(RoutePreferences.options(in: defaults).profile == .pedestrian)
        RoutePreferences.setStepFree(true, in: defaults)
        #expect(RoutePreferences.options(in: defaults).profile == .wheelchair)
        #expect(RoutePreferences.options(in: defaults).profile.avoidances.contains(.staircases))
    }
}
