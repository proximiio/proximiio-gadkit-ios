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

    /// PM, Monday "Navigation to a gallery" and "Curated tours: zoom level", 2026-10-27; RPR, "Need to
    /// determine correct zoom levels on-site", 2026-10-28.
    @Test @MainActor func theFollowZoomIs18Point8And20InAGalleryOfAPersonalisedJourney() {
        let settings = GADSettings.standard
        #expect(VisitView.followZoom(inGallery: false, kind: .personalised, settings: settings) == 18.8)
        #expect(VisitView.followZoom(inGallery: true, kind: .personalised, settings: settings) == 20)
        #expect(VisitView.followZoom(inGallery: true, kind: .curated, settings: settings) == 18.8)
        var withoutGalleryZoom = settings
        withoutGalleryZoom.galleryFollowZoom = nil
        #expect(VisitView.followZoom(inGallery: true, kind: .personalised, settings: withoutGalleryZoom) == 18.8)
    }

    @Test func theRelayAPICanBeAURL() throws {
        let api = try #require(URL(string: "https://api.example.com"))
        let relay = try #require(URL(string: "https://relay.example.com"))
        let configuration = GADConfiguration(apiBaseURL: api, applicationToken: "token", relayAPIBaseURL: relay, relayAPIAppToken: "relay")
        #expect(configuration?.relayAPI.baseURL.host() == "relay.example.com")
        let file = try #require(URL(string: "file:///tmp"))
        #expect(GADConfiguration(apiBaseURL: api, applicationToken: "token", relayAPIBaseURL: file, relayAPIAppToken: "relay") == nil)
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
        #expect(!StopNearbyDetector.isNearby(eightMetresNorth, level: 1, stop: stop, stopLevel: 1))
        #expect(StopNearbyDetector.isNearby(eightMetresNorth, level: 1, stop: stop, stopLevel: 1, within: 10))
        #expect(StopNearbyDetector.isNearby(eightMetresNorth, level: 1, stop: stop, stopLevel: 1, routeMeters: 9, within: 10))
    }
}
