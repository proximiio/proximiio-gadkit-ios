//
//  GADSettingsTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import Testing
@testable import ProximiioGADKit

struct GADSettingsTests {
    @Test func theConfigurationStartsWithTheDefaults() throws {
        let configuration = GADConfiguration(
            apiBaseURL: try #require(URL(string: "https://api.example.com")),
            applicationToken: "token",
            relayAPI: try #require(BlueiotCloudRelayEndpoint(text: "https://relay.example.com")),
            relayAPIAppToken: "relay"
        )
        #expect(configuration.settings == .standard)
        #expect(GADSettings.standard.trackingLostAfter == 110)
        #expect(GADSettings.standard.stopNearbyMeters == 5)
        #expect(GADSettings.standard.levelsWithoutPositioning == [0])
        #expect(GADSettings.standard.levelChangeViewSeconds == 5)
    }

    @Test func trackingAlertsFollowTheSettings() {
        var settings = GADSettings()
        settings.trackingLostAfter = 30
        settings.trackingStoppedAfter = 60
        let since = Date(timeIntervalSince1970: 0)
        func health(after seconds: TimeInterval) -> TrackingHealth {
            TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: since, now: since.addingTimeInterval(seconds), settings: settings)
        }
        #expect(health(after: 29) == .tracking)
        #expect(health(after: 30) == .lostPlace)
        #expect(health(after: 60) == .stoppedResponding)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: since, now: since.addingTimeInterval(60)) == .tracking)
    }

    @Test func stopNearbyFollowsTheSettings() {
        let stop = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        let eightMetresNorth = ProximiioCoordinate(latitude: 24.5 + 8 / 111_320, longitude: 54.4)
        #expect(!StopNearbyNotifier.isNearby(eightMetresNorth, level: 1, stop: stop, stopLevel: 1))
        #expect(StopNearbyNotifier.isNearby(eightMetresNorth, level: 1, stop: stop, stopLevel: 1, within: 10))
        #expect(StopNearbyNotifier.isNearby(eightMetresNorth, level: 1, stop: stop, stopLevel: 1, routeMeters: 9, within: 10))
    }
}
