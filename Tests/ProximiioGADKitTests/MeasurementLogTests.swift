//
//  MeasurementLogTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct MeasurementLogTests {
    private let cafe = VenuePlace(id: "cafe", title: "Café", coordinate: ProximiioCoordinate(latitude: 24.5398, longitude: 54.3992), level: 0)

    @Test func aCategoryLineNamesTheCountTheNearestPlaceAndTheTime() {
        #expect(MeasurementLog.categoryLine(title: "Café", screen: "journey", results: 3, nearest: cafe, milliseconds: 2)
            == "search category Café (journey): 3 places · nearest Café L0 · 2 ms")
        #expect(MeasurementLog.categoryLine(title: "Lockers", screen: "museum", results: 0, nearest: nil, milliseconds: 0)
            == "search category Lockers (museum): 0 places · nearest none · 0 ms")
    }

    @Test func aTextLineHoldsTheLengthOfTheQueryNotItsText() {
        #expect(MeasurementLog.textLine(characters: 5, screen: "museum", results: 12, places: 247, milliseconds: 1)
            == "search text 5 chars (museum): 12 of 247 places · 1 ms")
    }

    @Test func aLoggedSearchGivesThePlacesOfTheUnloggedOne() {
        let places = [cafe, VenuePlace(id: "shop", title: "Shop", coordinate: cafe.coordinate, level: 1)]
        #expect(MeasurementLog.places(matching: "caf", in: places, screen: "test") == VenuePlace.matching("caf", in: places))
        #expect(MeasurementLog.places(matching: "", in: places, screen: "test") == places)
    }

    @Test func aLoggedCategoryGivesThePlaceOfTheUnloggedOne() {
        let shortcut = AmenityShortcut(amenityID: "a", title: "Café", icon: nil)
        let near = VenuePlace(id: "cafe", title: "Café", coordinate: cafe.coordinate, level: 0, amenityID: "a")
        #expect(MeasurementLog.nearest(of: shortcut, in: [near], from: nil, level: nil, screen: "test")
            == shortcut.nearest(in: [near], from: nil, level: nil))
    }

    @Test func theListAndDestinationLines() {
        #expect(MeasurementLog.listLine(tab: "spaces", items: 19, milliseconds: 84) == "explore list spaces: 19 items · shown in 84 ms")
        #expect(MeasurementLog.destinationLine(title: "Café", outcome: "routed", milliseconds: 412) == "destination Café: routed in 412 ms")
    }

    @Test func aDrawnLineHoldsTheDotItsPositionAndTheRelayPositionWithTheirTimes() {
        var sample = MeasurementLog.DrawnSample(drawn: MapCoordinate(latitude: 24.53980721, longitude: 54.39921712))
        let now = Date(timeIntervalSince1970: 1_794_822_001.123)
        #expect(MeasurementLog.drawnLine(sample, map: "journey", now: now)
            == "drawn position journey: 24.5398072,54.3992171 L- · at 1794822001123 · fix - · relay -")
        sample.fix = MapCoordinate(latitude: 24.539808, longitude: 54.399218)
        sample.level = 1
        sample.fixTime = Date(timeIntervalSince1970: 1_794_822_000.5)
        sample.relay = ProximiioCoordinate(latitude: 24.539808, longitude: 54.399218)
        sample.relayTime = Date(timeIntervalSince1970: 1_794_822_000.4)
        #expect(MeasurementLog.drawnLine(sample, map: "journey", now: now)
            == "drawn position journey: 24.5398072,54.3992171 L1 · at 1794822001123"
            + " · fix 24.5398080,54.3992180 ts 1794822000500 · relay 24.5398080,54.3992180 ts 1794822000400")
    }

    @Test func theRateLineCountsThePositionsOfAMinute() {
        var rate = MeasurementLog.RateLog()
        #expect(rate.position(at: 100) == nil)
        for second in 1..<60 { #expect(rate.position(at: 100 + Double(second)) == nil) }
        #expect(rate.position(at: 160.4) == "relay positions: 60 in 60.4 s")
        // The next minute counts from the position that ended the last one.
        #expect(rate.position(at: 161) == nil)
        #expect(rate.position(at: 250) == "relay positions: 2 in 89.6 s")
    }
}
