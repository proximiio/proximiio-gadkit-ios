//
//  VenueCone.swift
//  ProximiioGADKit
//
//  The building's cones: the polygon features of type `cone`, nine on each floor. The maps draw each
//  cone as in the design (Figma "0 - DPT Map Kiosk", "Spaces - level 3", layers
//  `L3-architectural-cones`; PM, Monday "Cone visualization", 2026-10-29). A map style fills a polygon
//  with one colour only, so the package draws each cone as an image in the cone's coordinates
//  (`JourneyMapLayers`), and draws the outline with the venue style's `proximiio-cones` line.
//
//  The image: the design's floor colour #FAFAFB under the cone, the gradient across the cone,
//  perpendicular to its long axis (#D4DEE6, #F8FAFC at 22 %, #E8EEF2 at 46 %, #CBD6DF at 78 %,
//  #AEBCC9, at 32 % opacity), and a white edge at 18 % opacity inside the outline. The design's
//  1 px is about 0.21 m (its longest cone on level 3 is 610 px, 130 m in the venue data).
//
import CoreGraphics
import Proximiio
import UIKit

struct VenueCone: Equatable, Sendable {
    let id: String
    let level: Double
    /// Outline as (latitude, longitude) pairs.
    let ring: [ProximiioCoordinate]

    /// The polygon features whose type is `cone`. Pure; covered by tests.
    static func all(in features: [ProximiioFeature]) -> [VenueCone] {
        features.compactMap { feature in
            guard feature.propertyType == "cone", let geometry = feature.geometry, let level = feature.level,
                  let ring = Gallery.outerRing(type: geometry.type, coordinates: geometry.coordinates) else { return nil }
            return VenueCone(id: feature.id, level: level, ring: ring)
        }
    }
}

/// The cone's gradient image and where it lies on the map.
struct ConeShading {
    /// The image, its top-left corner at (`north`, `west`) and its bottom-right at (`south`, `east`).
    let image: UIImage
    let north: Double, south: Double, west: Double, east: Double

    static let stops: [(color: UInt32, location: CGFloat)] = [
        (0xD4DEE6, 0), (0xF8FAFC, 0.22), (0xE8EEF2, 0.46), (0xCBD6DF, 0.78), (0xAEBCC9, 1),
    ]
    /// The design's floor under the cones.
    static let base: UInt32 = 0xFAFAFB
    static let opacity: CGFloat = 0.32
    static let edgeOpacity: CGFloat = 0.18
    /// The visible width of the white edge inside the outline: half the design's 3.2 px line.
    static let edgeMeters: Double = 0.34
    /// The outline of the design: #95A6B5 at 48 % opacity, a hairline. The kiosk's 1.28 px on its
    /// 2160 px screen is about 0.2 m; the map draws it 0.3 pt wide at zoom 16, 0.6 pt at 19 and
    /// 1.2 pt at 21 (the user's comparison of 2026-10-29: 1.28 pt was far too strong).
    static let outlineColor: UInt32 = 0x95A6B5
    static let outlineOpacity: Double = 0.48
    static let outlineWidths: [Double: Double] = [16: 0.3, 19: 0.6, 21: 1.2]

    /// Draws `cone` at `pixelsPerMeter`, at most `maxPixels` on the longer side. `nil` for a cone
    /// without an area.
    static func make(_ cone: VenueCone, pixelsPerMeter: Double = 4, maxPixels: Double = 1024) -> ConeShading? {
        let latitudes = cone.ring.map(\.latitude), longitudes = cone.ring.map(\.longitude)
        guard let north = latitudes.max(), let south = latitudes.min(), let west = longitudes.min(), let east = longitudes.max(),
              north > south, east > west else { return nil }
        let metersPerDegreeLatitude = 110_574.0
        let metersPerDegreeLongitude = 111_320.0 * cos((north + south) / 2 * .pi / 180)
        let widthMeters = (east - west) * metersPerDegreeLongitude
        let heightMeters = (north - south) * metersPerDegreeLatitude
        let scale = min(pixelsPerMeter, maxPixels / max(widthMeters, heightMeters))
        let size = CGSize(width: ceil(widthMeters * scale), height: ceil(heightMeters * scale))
        let points = cone.ring.map { coordinate in
            CGPoint(x: (coordinate.longitude - west) * metersPerDegreeLongitude * scale,
                    y: (north - coordinate.latitude) * metersPerDegreeLatitude * scale)
        }
        let axis = gradientAxis(points)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            cg.addPath(path)
            cg.clip()
            cg.setFillColor(UIColor(hex: base).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            let colors = stops.map { UIColor(hex: $0.color).cgColor } as CFArray
            var locations = stops.map(\.location)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: &locations) {
                cg.setAlpha(opacity)
                cg.drawLinearGradient(gradient, start: axis.start, end: axis.end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                cg.setAlpha(1)
            }
            // Clipped to the cone: half the line width shows inside the outline.
            cg.addPath(path)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(edgeOpacity).cgColor)
            cg.setLineWidth(max(2, 2 * edgeMeters * scale))
            cg.setLineJoin(.round)
            cg.strokePath()
        }
        return ConeShading(image: image, north: north, south: south, west: west, east: east)
    }

    /// The gradient's start and end: across the long axis of `points` (their principal axis),
    /// from the outermost point on one side to the outermost on the other. Pure; covered by tests.
    static func gradientAxis(_ points: [CGPoint]) -> (start: CGPoint, end: CGPoint) {
        guard !points.isEmpty else { return (.zero, .zero) }
        let count = CGFloat(points.count)
        let center = CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for point in points {
            let dx = point.x - center.x, dy = point.y - center.y
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let across = CGPoint(x: -sin(angle), y: cos(angle))
        let projections = points.map { ($0.x - center.x) * across.x + ($0.y - center.y) * across.y }
        let low = projections.min() ?? 0, high = projections.max() ?? 0
        return (CGPoint(x: center.x + across.x * low, y: center.y + across.y * low),
                CGPoint(x: center.x + across.x * high, y: center.y + across.y * high))
    }
}
