//
//  PlaceFramingTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import ProximiioMap
import Testing
@testable import ProximiioGADKit

struct PlaceFramingTests {
    private let metresPerDegree = 111_320.0

    @Test func aSpaceFarFromTheOthersIsLeftOutOfTheFrame() {
        let origin = ProximiioCoordinate(latitude: 24.54, longitude: 54.4)
        func space(north: Double) -> [ProximiioCoordinate] {
            [ProximiioCoordinate(latitude: origin.latitude + north / metresPerDegree, longitude: origin.longitude)]
        }
        let spaces = [space(north: 0), space(north: 20), space(north: 40), space(north: 60), space(north: 400)]
        let distances = PlaceFraming.distancesFromTheMedianCentre(of: spaces)
        #expect(abs(distances[4] - 360) < 0.01)
        #expect(PlaceFraming.nearTheMedianCentre(spaces, maximumMeters: 150).count == 4)
        // Without a limit every space is framed.
        #expect(PlaceFraming.nearTheMedianCentre(spaces, maximumMeters: nil).count == 5)
        #expect(PlaceFraming.nearTheMedianCentre([], maximumMeters: 150).isEmpty)
    }

    @Test func aNearAmenityIsShownInTheMinimumArea() throws {
        let visitor = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        let amenity = ProximiioCoordinate(latitude: 24.5 + 3 / metresPerDegree, longitude: 54.4)
        let bounds = try #require(PlaceFraming.bounds(of: [visitor, amenity], minimumMeters: 40))
        let height = (bounds.northEast.latitude - bounds.southWest.latitude) * metresPerDegree
        let width = (bounds.northEast.longitude - bounds.southWest.longitude) * metresPerDegree * cos(24.5 * .pi / 180)
        #expect(abs(height - 40) < 0.01)
        #expect(abs(width - 40) < 0.01)
        // The centre is between the visitor and the amenity.
        #expect(abs((bounds.northEast.latitude + bounds.southWest.latitude) / 2 - (visitor.latitude + amenity.latitude) / 2) < 1e-9)
    }

    @Test func aFarAmenityKeepsBothPointsInside() throws {
        let visitor = ProximiioCoordinate(latitude: 24.5, longitude: 54.4)
        let amenity = ProximiioCoordinate(latitude: 24.5005, longitude: 54.401)
        let bounds = try #require(PlaceFraming.bounds(of: [visitor, amenity], minimumMeters: 40))
        #expect(abs(bounds.southWest.latitude - visitor.latitude) < 1e-12)
        #expect(abs(bounds.northEast.latitude - amenity.latitude) < 1e-12)
        #expect(abs(bounds.southWest.longitude - visitor.longitude) < 1e-12)
        #expect(abs(bounds.northEast.longitude - amenity.longitude) < 1e-12)
    }

    @Test func noPointsNoArea() {
        #expect(PlaceFraming.bounds(of: [], minimumMeters: 40) == nil)
    }
}
