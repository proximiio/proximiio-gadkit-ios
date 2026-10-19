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
//  - the lift or stairs of the route's next level change: the red marker with a white glyph, as
//    an amenity detour (PM 2026-10-15, "Level changer highlighting")
//  - every other lift, staircase and escalator that serves the shown floor, with its amenity icon
//    (`LevelChangerPlace`; Monday "All level changers visible", 2026-10-15)
//  - the amenity picked in the menu: the red marker with its white icon (`PlaceFraming`)
//
//  The stop markers are the map library's (`MapStyle.journeyStops`).
//
//  The layers are added after each style load and show the selected floor only. The layers go
//  through `ProximiioMapCanvas.addLayer(_:at:)`.
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

    /// A lift, stairs or escalator where the route changes floor.
    struct LevelChanger: Equatable {
        var coordinate: ProximiioCoordinate
        var level: Double
        /// The route's feature type: `elevator`, `staircase`, `escalator`.
        var featureType: String

        var imageName: String { Self.imageName(for: featureType) }

        static func imageName(for featureType: String) -> String { "gad-level-changer-\(featureType)" }

        /// The amenity icon of a level changer that is not on the route.
        static func standardImageName(for featureType: String) -> String { "gad-level-changer-standard-\(featureType)" }
    }

    /// The amenity picked in the menu.
    struct Highlight: Equatable {
        var coordinate: ProximiioCoordinate
        var level: Double
        var icon: GADIcon

        var imageName: String { Self.imageName(for: icon) }

        static func imageName(for icon: GADIcon) -> String { "gad-highlight-\(icon.rawValue)" }
    }

    /// The gallery a leg leads to first (gallery first): a red label with the gallery's short name
    /// at its POI (PM, Monday "Navigation to a gallery").
    struct GalleryMarker: Equatable {
        var coordinate: ProximiioCoordinate
        var level: Double
        /// "G303".
        var label: String

        var imageName: String { "gad-gallery-\(label)" }
    }

    /// `place` with the icon of its amenity kind; `nil` for a place of no `AmenityKind`.
    static func highlight(of place: VenuePlace?) -> Highlight? {
        guard let place, let kind = AmenityKind.allCases.first(where: { $0.matches(place) }) else { return nil }
        return Highlight(coordinate: place.coordinate, level: place.level, icon: kind.icon)
    }

    private static let gallerySource = "gad-journey-galleries"
    private static let destinationLayer = "gad-gallery-destination"
    private static let visitedLayer = "gad-gallery-visited"
    private static let connectorSource = "gad-route-connector"
    private static let connectorLayer = "gad-route-connector"
    private static let changerSource = "gad-level-changer"
    private static let changerLayer = "gad-level-changer"

    private weak var session: ProximiioMapSession?
    private var styleToken: MapCanvasToken?
    private var fills: [GalleryFill] = []
    private var level: Double = 0
    private var connector: [ProximiioCoordinate] = []
    private var changer: LevelChanger?
    private var changers: [LevelChangerPlace] = []
    private var highlight: Highlight?
    private var galleryMarker: GalleryMarker?

    func attach(to session: ProximiioMapSession) {
        self.session = session
        styleToken = session.onStyleLoaded { [weak self] _, style in
            MainActor.assumeIsolated { self?.install(on: style) }
        }
    }

    /// The gallery fills and the shown floor.
    func update(fills: [GalleryFill], level: Double) {
        guard fills != self.fills || level != self.level else { return }
        let levelChanged = level != self.level
        self.fills = fills
        self.level = level
        guard let style = session?.canvas?.style else { return }
        apply(on: style)
        if levelChanged { applyLevelChanger(on: style) }
    }

    /// The line from the visitor to the start of the route ahead. An empty array removes it.
    func updateConnector(from start: ProximiioCoordinate?, to end: ProximiioCoordinate?) {
        let points = start.flatMap { start in end.map { [start, $0] } } ?? []
        guard points != connector else { return }
        connector = points
        guard let style = session?.canvas?.style else { return }
        applyConnector(on: style)
    }

    /// The venue's lifts, staircases and escalators. Each shows on the floors it serves.
    func updateLevelChangers(_ changers: [LevelChangerPlace]) {
        guard changers != self.changers else { return }
        self.changers = changers
        guard let style = session?.canvas?.style else { return }
        applyLevelChanger(on: style)
    }

    /// The highlighted level changer, or `nil` for none.
    func updateLevelChanger(_ changer: LevelChanger?) {
        guard changer != self.changer else { return }
        self.changer = changer
        guard let style = session?.canvas?.style else { return }
        applyLevelChanger(on: style)
    }

    /// The amenity picked in the menu, or `nil` for none.
    func updateHighlight(_ highlight: Highlight?) {
        guard highlight != self.highlight else { return }
        self.highlight = highlight
        guard let style = session?.canvas?.style else { return }
        applyLevelChanger(on: style)
    }

    /// The gallery a leg leads to first, or `nil` for none.
    func updateGalleryMarker(_ marker: GalleryMarker?) {
        guard marker != galleryMarker else { return }
        galleryMarker = marker
        guard let style = session?.canvas?.style else { return }
        applyLevelChanger(on: style)
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
        if style.source(withIdentifier: Self.changerSource) == nil {
            for type in LevelChangerPlace.featureTypes {
                if let image = Self.changerImage(featureType: type) { canvas.floors.register(image, named: LevelChanger.imageName(for: type)) }
                if let image = UIImage(named: Self.icon(featureType: type).markerImageName ?? "", in: .module, compatibleWith: nil) {
                    canvas.floors.register(image, named: LevelChanger.standardImageName(for: type))
                }
            }
            for icon in Set(AmenityKind.allCases.map(\.icon)) {
                if let image = Self.redMarker(glyph: icon) { canvas.floors.register(image, named: Highlight.imageName(for: icon)) }
            }
            let source = MLNShapeSource(identifier: Self.changerSource, shape: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: Self.changerLayer, source: source)
            layer.iconImageName = NSExpression(forKeyPath: "image")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            // The highlighted level changer over the others.
            layer.symbolSortKey = NSExpression(forKeyPath: "sort")
            canvas.addLayer(layer, at: .above(.route))
        }
        apply(on: style)
        applyConnector(on: style)
        applyLevelChanger(on: style)
    }

    private func applyLevelChanger(on style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.changerSource) as? MLNShapeSource else { return }
        let highlighted = changer.flatMap { sameLevel($0.level) ? $0 : nil }
        var features = changers
            .filter { $0.serves(level) && $0.coordinate != highlighted?.coordinate }
            .map { Self.point($0.coordinate, image: LevelChanger.standardImageName(for: $0.featureType), sort: 0) }
        if let highlighted {
            features.append(Self.point(highlighted.coordinate, image: highlighted.imageName, sort: 1))
        }
        if let highlight, sameLevel(highlight.level) {
            features.append(Self.point(highlight.coordinate, image: highlight.imageName, sort: 2))
        }
        if let galleryMarker, sameLevel(galleryMarker.level) {
            if style.image(forName: galleryMarker.imageName) == nil, let image = Self.galleryLabel(galleryMarker.label) {
                session?.canvas?.floors.register(image, named: galleryMarker.imageName)
            }
            features.append(Self.point(galleryMarker.coordinate, image: galleryMarker.imageName, sort: 3))
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    /// The red label of a gallery that a leg leads to first: white text, 28 pt high, like the white
    /// gallery labels of the venue style (Figma, Monday "Navigation to a gallery").
    static func galleryLabel(_ text: String) -> UIImage? {
        let font = UIFont(name: "GuggenheimSansDisplay-SemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let pill = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 13)
            UIColor(hex: 0xED3731).setFill()
            pill.fill()
            UIColor.white.setStroke()
            pill.lineWidth = 2
            pill.stroke()
            (text as NSString).draw(at: CGPoint(x: 14, y: (size.height - textSize.height) / 2), withAttributes: attributes)
        }
    }

    private static func point(_ coordinate: ProximiioCoordinate, image: String, sort: Int) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        feature.attributes = ["image": image, "sort": NSNumber(value: sort)]
        return feature
    }

    /// The design's icon of a level changer type.
    private static func icon(featureType: String) -> GADIcon {
        featureType == "elevator" ? .elevator : .stairs
    }

    /// The 30 pt red marker of the journey's active stop and detour (`MapStyle.journeyStops`) with
    /// the design's lift or stairs glyph in white.
    private static func changerImage(featureType: String) -> UIImage? {
        redMarker(glyph: icon(featureType: featureType))
    }

    /// The 30 pt red marker with `glyph` in white.
    private static func redMarker(glyph icon: GADIcon) -> UIImage? {
        guard let glyph = UIImage(named: icon.rawValue, in: .module, compatibleWith: nil)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1))
            UIColor(hex: 0xED3731).setFill()
            circle.fill()
            UIColor.white.setStroke()
            circle.lineWidth = 2
            circle.stroke()
            glyph.draw(in: CGRect(x: 6, y: 6, width: 18, height: 18))
        }
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
