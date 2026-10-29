//
//  VenueConeTests.swift
//  ProximiioGADKitTests
//
import CoreGraphics
import Foundation
import Proximiio
import Testing
import UIKit
@testable import ProximiioGADKit

/// The building's cones with the design's metal gradient (PM, Monday "Cone visualization", 2026-10-29).
struct VenueConeTests {
    private func feature(_ id: String, type: String, level: Double) -> ProximiioFeature {
        // A cone about 22 m wide and 89 m long, pointing north. GeoJSON pairs are longitude, latitude.
        let ring: JSONValue = .array([[54.3980, 24.5400], [54.3982, 24.5400], [54.3981, 24.5408]].map { .array($0.map { .number($0) }) })
        let properties: [String: JSONValue] = ["type": .string(type), "level": .number(level)]
        return ProximiioFeature(id: id, geometry: .init(type: "Polygon", coordinates: .array([ring])), properties: .object(properties))
    }

    @Test func onlyConePolygonsAreCones() {
        let cones = VenueCone.all(in: [feature("c1", type: "cone", level: 2), feature("g1", type: "gallery", level: 2)])
        #expect(cones.map(\.id) == ["c1"])
        #expect(cones.first?.level == 2)
        #expect(cones.first?.ring.first == ProximiioCoordinate(latitude: 24.54, longitude: 54.398))
    }

    /// A tall cone gets a gradient from side to side, not from tip to base.
    @Test func theGradientRunsAcrossTheCone() {
        let tall = [CGPoint(x: 0, y: 100), CGPoint(x: 20, y: 100), CGPoint(x: 10, y: 0)]
        let axis = ConeShading.gradientAxis(tall)
        #expect(abs(axis.end.x - axis.start.x) > abs(axis.end.y - axis.start.y))
        let wide = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: 100, y: 10)]
        let across = ConeShading.gradientAxis(wide)
        #expect(abs(across.end.y - across.start.y) > abs(across.end.x - across.start.x))
    }

    /// The image covers the cone's bounds at 4 px per metre.
    @MainActor @Test func theImageCoversTheConeBounds() throws {
        let cone = try #require(VenueCone.all(in: [feature("c1", type: "cone", level: 1)]).first)
        let shading = try #require(ConeShading.make(cone))
        #expect(shading.north == 24.5408 && shading.south == 24.54)
        #expect(shading.west == 54.398 && shading.east == 54.3982)
        #expect(shading.image.size.height > 300 && shading.image.size.height < 400)
        #expect(shading.image.size.width > 70 && shading.image.size.width < 100)
    }
}
