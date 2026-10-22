//
//  ProximiMapTests.swift
//  ProximiioGADKitTests
//
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct ProximiMapTests {
    private static let places: [VenuePlace] = [
        VenuePlace(id: "poi-a", title: "Cloud Canyons", coordinate: .init(latitude: 24.5, longitude: 54.4), level: 1, remoteID: "GAD.2010.00033"),
        VenuePlace(id: "poi-b", title: "Tongari-kun", coordinate: .init(latitude: 24.5001, longitude: 54.4001), level: 3, remoteID: "GAD.2018.00034"),
        VenuePlace(id: "poi-cafe", title: "Café", coordinate: .init(latitude: 24.5002, longitude: 54.4), level: 0),
    ]

    @Test func artworksMatchACollectionIDOrAPOIIDAndKeepTheirOrder() {
        let ids = ProximiMap.poiIDs(for: ["GAD.2018.00034", "poi-a", "GAD.0000.00000", "poi-cafe"], in: Self.places)
        #expect(ids == ["poi-b", "poi-a", "poi-cafe"])
        #expect(ProximiMap.poiIDs(for: ["unknown"], in: Self.places).isEmpty)
    }

    @Test func summaryCountsArtworksNotDetours() {
        #expect(ProximiMap.summary(of: nil, meta: nil) == nil)
        let journey = Journey(stops: [
            stop("poi-a", state: .done),
            stop("poi-b"),
            stop("poi-cafe", kind: .detour, state: .active),
        ])
        let meta = VisitMeta(title: "Highlights Tour", summary: "2 stops", kind: .curated)
        let summary = ProximiMap.summary(of: journey, meta: meta)
        #expect(summary == JourneySummary(title: "Highlights Tour", summary: "2 stops", kind: .curated, stopCount: 2, remainingStopCount: 1, isStarted: true))
        let fresh = ProximiMap.summary(of: Journey(stops: [stop("poi-a")]), meta: nil)
        #expect(fresh?.kind == .personalised)
        #expect(fresh?.isStarted == false)
        #expect(fresh?.remainingStopCount == 1)
    }

    @Test func wristbandStatusFollowsTheBindingState() {
        #expect(ProximiMap.wristbandStatus(of: nil) == .notConnected(notice: nil))
        #expect(ProximiMap.wristbandStatus(of: .unbound) == .notConnected(notice: nil))
        #expect(ProximiMap.wristbandStatus(of: .binding) == .connecting)
        let ended = ProximiMap.wristbandStatus(of: .ended(.superseded))
        guard case .notConnected(let notice?) = ended else {
            Issue.record("no notice for a superseded session")
            return
        }
        #expect(notice.contains("another phone"))
    }

    @Test func visitEventsBecomeHostEventsWithTheArtworkID() {
        let reached = ProximiMap.event(for: .artworkReached(stop("poi-a")), places: Self.places)
        #expect(reached == .artworkReached(ProximiStop(id: "poi-a", title: "poi-a", artworkID: "GAD.2010.00033", level: 1)))
        let detour = ProximiMap.event(for: .detourStarted(Self.places[2]), places: Self.places)
        #expect(detour == .detourStarted(ProximiStop(id: "poi-cafe", title: "Café", artworkID: nil, level: 0)))
        #expect(ProximiMap.event(for: .journey(.journeyFinished), places: Self.places) == .journeyFinished)
        #expect(ProximiMap.event(for: .journey(.offRouteTooLong(duration: 300)), places: Self.places) == .offRoute(duration: 300))
        #expect(ProximiMap.event(for: .journey(.legChanged(to: stop("poi-b"), reason: .started)), places: Self.places) == .nextStop(ProximiStop(id: "poi-b", title: "poi-b", artworkID: "GAD.2018.00034", level: 1)))
        // The skip comes from the visitor's confirmation; the navigator's copy is not repeated.
        #expect(ProximiMap.event(for: .journey(.stopSkipped(stop("poi-a"))), places: Self.places) == nil)
        #expect(ProximiMap.event(for: .trackingChanged(.lostPlace), places: Self.places) == .trackingChanged(.lostPlace))
    }

    @Test func geofenceEventsNameTheArtwork() {
        let artwork = ProximiioGeofence(id: "g1", name: "Cloud Canyons", metadata: .object(["geofence_type": .string("artwork")]), remoteId: "GAD.2010.00033")
        #expect(ProximiMap.event(for: .entered(artwork)) == .geofenceEntered(ProximiGeofence(id: "g1", name: "Cloud Canyons", type: "artwork", artworkID: "GAD.2010.00033")))
        let gallery = ProximiioGeofence(id: "g2", name: "G403 Weaving", metadata: .object(["geofence_type": .string("gallery")]), remoteId: "G403")
        #expect(ProximiMap.event(for: .exited(gallery, dwellTime: 12)) == .geofenceExited(ProximiGeofence(id: "g2", name: "G403 Weaving", type: "gallery", artworkID: nil)))
    }

    @Test func arrivalCountsAFixNearAnyPlaceOfEitherVenue() {
        let guggenheim = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        // About 11 km east, like the DCT office.
        let office = ProximiioCoordinate(latitude: 24.5, longitude: 54.5)
        let nearOffice = CLLocation(latitude: 24.5, longitude: 54.501)
        #expect(ArrivalDetector.isNear(nearOffice, places: [guggenheim, office]))
        #expect(!ArrivalDetector.isNear(CLLocation(latitude: 24.5, longitude: 54.45), places: [guggenheim, office]))
    }

    @Test @MainActor func nothingOpensBeforeTheStart() throws {
        let map = ProximiMap(configuration: try Self.configuration())
        map.open(.museumMap)
        #expect(map.screen == nil)
        #expect(throws: ProximiMapError.notStarted) { try map.setJourney(JourneyPlan(title: "T", artworks: ["poi-a"])) }
    }

    @Test @MainActor func theSDKReportsVisitorsToTheConfiguredHostOnly() throws {
        let configuration = VenueService.configuration(for: try Self.configuration())
        #expect(configuration.visitorReportingEnabled)
        #expect(configuration.apiBaseURL.host() == "api.example.com")
        #expect(configuration.fallbackAPIBaseURLs.isEmpty)
    }

    @Test @MainActor func theSDKReportsAGeofenceExitAfterTheSettingsDelay() throws {
        #expect(VenueService.configuration(for: try Self.configuration()).geofenceExitDelay == 5)
        var backend = try Self.configuration()
        backend.settings.geofenceExitDelay = 0
        #expect(VenueService.configuration(for: backend).geofenceExitDelay == 0)
    }

    private static func configuration() throws -> GADConfiguration {
        GADConfiguration(
            apiBaseURL: try #require(URL(string: "https://api.example.com")),
            applicationToken: "token",
            relayAPI: try #require(BlueiotCloudRelayEndpoint(text: "https://relay.example.com")),
            relayAPIAppToken: "relay"
        )
    }

    private func stop(_ id: String, kind: JourneyStop.Kind = .planned, state: JourneyStop.State = .pending) -> JourneyStop {
        JourneyStop(id: id, title: id, coordinate: MapCoordinate(latitude: 24.5, longitude: 54.4), floor: FloorKey(level: 1), poiID: id, kind: kind, state: state)
    }
}
