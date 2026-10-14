//
//  JourneyMapLayers.swift
//  ProximiioGADKit
//
//  Journey content drawn by the app on top of the SDK's map (page 3, sections `Markers` and
//  `Colors`):
//
//  - the destination gallery filled with the level colour; visited galleries with its tint
//  - a connector from the visitor to the start of the route ahead, in the route's start colour.
//    The route ahead starts where the visitor projects onto the route, so a visitor beside the
//    route has no line from the dot to the route without it.
//
//  The stop markers are the map library's (`MapStyle.journeyStops`).
//
//  The layers are added after each style load and show the selected floor only. The connector goes
//  and the gallery fills go through `ProximiioMapCanvas.addLayer(_:at:)`.
//
import MapLibre
import Proximiio
import ProximiioMap
import UIKit

@MainActor
final class JourneyMapLayers {
    struct GalleryFill: Equatable {
        var gallery: Gallery
        var isDestination: Bool
    }

    private static let gallerySource = "gad-journey-galleries"
    private static let destinationLayer = "gad-gallery-destination"
    private static let visitedLayer = "gad-gallery-visited"
    private static let connectorSource = "gad-route-connector"
    private static let connectorLayer = "gad-route-connector"

    private weak var session: ProximiioMapSession?
    private var styleToken: MapCanvasToken?
    private var fills: [GalleryFill] = []
    private var level: Double = 0
    private var connector: [ProximiioCoordinate] = []

    func attach(to session: ProximiioMapSession) {
        self.session = session
        styleToken = session.onStyleLoaded { [weak self] _, style in
            MainActor.assumeIsolated { self?.install(on: style) }
        }
    }

    func update(fills: [GalleryFill], level: Double) {
        guard fills != self.fills || level != self.level else { return }
        self.fills = fills
        self.level = level
        guard let style = session?.canvas?.style else { return }
        apply(on: style)
    }

    /// The line from the visitor to the start of the route ahead. An empty array removes it.
    func updateConnector(from start: ProximiioCoordinate?, to end: ProximiioCoordinate?) {
        let points = start.flatMap { start in end.map { [start, $0] } } ?? []
        guard points != connector else { return }
        connector = points
        guard let style = session?.canvas?.style else { return }
        applyConnector(on: style)
    }

    // MARK: Style

    private func install(on style: MLNStyle) {
        guard let canvas = session?.canvas else { return }
        if style.source(withIdentifier: Self.gallerySource) == nil {
            let source = MLNShapeSource(identifier: Self.gallerySource, shape: nil)
            style.addSource(source)
            // Over the floor plan, under walls, labels, POI icons, the route and the stop markers.
            // `.aboveVenueFills` puts each layer directly over the venue fills, so the destination
            // layer is anchored to the visited layer.
            for (id, isDestination) in [(Self.visitedLayer, false), (Self.destinationLayer, true)] {
                let layer = MLNFillStyleLayer(identifier: id, source: source)
                layer.predicate = NSPredicate(format: "destination == %@", NSNumber(value: isDestination))
                canvas.addLayer(layer, at: isDestination ? .above(layerID: Self.visitedLayer) : .aboveVenueFills)
            }
        }
        if style.source(withIdentifier: Self.connectorSource) == nil {
            let source = MLNShapeSource(identifier: Self.connectorSource, shape: nil)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: Self.connectorLayer, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor(hex: 0x3F69FF))
            layer.lineWidth = NSExpression(forConstantValue: 6)
            layer.lineCap = NSExpression(forConstantValue: "round")
            canvas.addLayer(layer, at: .below(.route))
        }
        apply(on: style)
        applyConnector(on: style)
    }

    private func applyConnector(on style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.connectorSource) as? MLNShapeSource else { return }
        guard connector.count == 2 else {
            source.shape = nil
            return
        }
        var points = connector.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        source.shape = MLNPolylineFeature(coordinates: &points, count: UInt(points.count))
    }

    private func apply(on style: MLNStyle) {
        let colors = Gallery.colors(forLevel: level)
        if let destination = style.layer(withIdentifier: Self.destinationLayer) as? MLNFillStyleLayer {
            destination.fillColor = NSExpression(forConstantValue: UIColor(hex: colors.destination))
        }
        if let visited = style.layer(withIdentifier: Self.visitedLayer) as? MLNFillStyleLayer {
            visited.fillColor = NSExpression(forConstantValue: UIColor(hex: colors.visited))
        }
        if let source = style.source(withIdentifier: Self.gallerySource) as? MLNShapeSource {
            let features = fills.filter { sameLevel($0.gallery.level) }.map { fill -> MLNPolygonFeature in
                var points = fill.gallery.ring.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let feature = MLNPolygonFeature(coordinates: &points, count: UInt(points.count))
                feature.attributes = ["destination": NSNumber(value: fill.isDestination)]
                return feature
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
    }

    private func sameLevel(_ other: Double) -> Bool {
        VenueLevel.same(other, level)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
