//
//  JourneyMapLayers.swift
//  ProximiioGADKit
//
//  Journey content drawn by the app on top of the SDK's map (page 3, sections `Markers` and
//  `Colors`):
//
//  - the destination gallery filled with the level colour; visited galleries with its tint
//  - each gallery's name in a pill at its POI: red for the gallery a leg leads to, white with a red
//    outline for a visited gallery, white with a black outline for the others (PM, Monday "Gallery
//    numbers in gallery navigation", 2026-10-28)
//  - a connector from the visitor to the start of the route ahead, in the route's start colour.
//    The route ahead starts where the visitor projects onto the route, so a visitor beside the
//    route has no line from the dot to the route without it.
//  - the lift or stairs of the route's next level change: the red marker with a white glyph, as
//    an amenity detour (PM 2026-10-15, "Level changer highlighting")
//  - every other lift, staircase and escalator that serves the shown floor, with its amenity icon
//    (`LevelChangerPlace`; Monday "All level changers visible", 2026-10-15)
//  - the amenity picked in the menu: the red marker with its white icon (`PlaceFraming`)
//  - the building's cones on the shown floor, each an image of the design's metal gradient
//    (`VenueCone`, `ConeShading`; PM, Monday "Cone visualization", 2026-10-29), over the floors and
//    under the galleries; the venue style's cone outlines in the design's colour
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
        enum Style: String {
            /// The venue style's gallery colour, over the artworks and furniture.
            case standard
            case visited
            case destination
        }

        var gallery: Gallery
        var style: Style
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

        /// The venue data icon of a level changer's amenity.
        static func amenityImageName(for amenityID: String) -> String { "gad-level-changer-amenity-\(amenityID)" }
    }

    /// The amenity picked in the menu.
    struct Highlight: Equatable {
        var coordinate: ProximiioCoordinate
        var level: Double
        var icon: GADIcon

        var imageName: String { Self.imageName(for: icon) }

        static func imageName(for icon: GADIcon) -> String { "gad-highlight-\(icon.rawValue)" }
    }

    /// A gallery's name at its POI.
    struct GalleryMarker: Equatable {
        enum Style: String, Equatable {
            /// The gallery a leg leads to first (gallery first).
            case destination
            /// A gallery whose artworks of the journey are done.
            case visited
            case standard
        }

        var coordinate: ProximiioCoordinate
        var level: Double
        /// The POI's title, such as "G303 Language".
        var name: String
        var style: Style

        var imageName: String { "gad-gallery-\(style.rawValue)-\(name)" }
    }

    /// `place` with the icon of its amenity kind; `nil` for a place of no `AmenityKind`.
    /// The dot of a journey artwork that has no numbered marker (`VisitView.stopDots`).
    struct StopDot: Equatable {
        enum Style: String, CaseIterable {
            /// Still to visit: white with the grey ring of a pending stop marker.
            case pending
            /// Visited: white with the red ring of a visited stop marker.
            case visited
            /// The active stop: red with a white ring.
            case active
            /// Skipped: grey with a white ring.
            case skipped
        }
        let coordinate: ProximiioCoordinate
        let level: Double
        let style: Style

        static func imageName(for style: Style) -> String { "gad-stop-dot-\(style.rawValue)" }
    }

    /// The pin in the marker of a journey artwork (`VisitView.stopIcons`).
    struct StopIcon: Equatable {
        let coordinate: ProximiioCoordinate
        let level: Double
        /// The current artwork: a white pin on the red marker. Else a dark pin on a white marker.
        let isCurrent: Bool

        static func imageName(isCurrent: Bool) -> String { isCurrent ? "gad-stop-pin-current" : "gad-stop-pin" }
    }

    static func highlight(of place: VenuePlace?) -> Highlight? {
        guard let place, let kind = AmenityKind.allCases.first(where: { $0.matches(place) }) else { return nil }
        return Highlight(coordinate: place.coordinate, level: place.level, icon: kind.icon)
    }

    private static let gallerySource = "gad-journey-galleries"
    private static let destinationLayer = "gad-gallery-destination"
    private static let visitedLayer = "gad-gallery-visited"
    private static let standardLayer = "gad-gallery-standard"
    /// The organisation style's furniture, above its artworks.
    private static let furnitureLayer = "proximiio-furniture"
    /// The organisation style's inner walls, above its artworks and furniture.
    private static let innerWallLayer = "proximiio-inner_wall"
    private static let connectorSource = "gad-route-connector"
    private static let connectorLayer = "gad-route-connector"
    private static let changerSource = "gad-level-changer"
    private static let changerLayer = "gad-level-changer"
    private static let stopDotSource = "gad-stop-dots"
    private static let stopDotLayer = "gad-stop-dots"
    private static let stopIconSource = "gad-stop-icons"
    private static let stopIconLayer = "gad-stop-icons"
    /// The standard and visited gallery names. They give way to each other, to the destination's
    /// name and to the stop markers (Monday, the PM's crowded map of 2026-10-29).
    private static let galleryNameLayer = "gad-gallery-names"
    /// The destination gallery's name, always shown.
    private static let destinationNameLayer = "gad-gallery-destination-name"

    private weak var session: ProximiioMapSession?
    private var styleToken: MapCanvasToken?
    private var fills: [GalleryFill] = []
    private var level: Double = 0
    private var connector: [ProximiioCoordinate] = []
    private var changer: LevelChanger?
    private var changers: [LevelChangerPlace] = []
    /// The venue data icons level changers show, by amenity id.
    private var changerAmenityIcons: [String: UIImage] = [:]
    private var highlight: Highlight?
    private var galleryMarkers: [GalleryMarker] = []
    private var stopDots: [StopDot] = []
    private var stopIcons: [StopIcon] = []
    private var cones: [VenueCone] = []
    /// The cones' images, drawn when their floor first shows.
    private var coneShadings: [String: ConeShading] = [:]
    /// The image each cone's source on the map was given, by cone id.
    private var coneImagesOnMap: [String: ObjectIdentifier] = [:]

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
        if levelChanged {
            applyLevelChanger(on: style)
            applyStopDots(on: style)
            applyStopIcons(on: style)
            applyCones(on: style)
        }
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
    /// `amenityIcons` are the venue data icons level changers show, by amenity id
    /// (`LevelChangerPlace.amenityIcons(of:icons:)`).
    func updateLevelChangers(_ changers: [LevelChangerPlace], amenityIcons: [String: UIImage] = [:]) {
        let sameIcons = Set(amenityIcons.keys) == Set(changerAmenityIcons.keys)
        guard changers != self.changers || !sameIcons else { return }
        self.changers = changers
        changerAmenityIcons = amenityIcons
        guard let canvas = session?.canvas, let style = canvas.style else { return }
        registerChangerAmenityIcons(on: canvas)
        applyLevelChanger(on: style)
    }

    private func registerChangerAmenityIcons(on canvas: ProximiioMapCanvas) {
        for (amenityID, image) in changerAmenityIcons {
            canvas.floors.register(image, named: LevelChanger.amenityImageName(for: amenityID))
        }
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

    /// The galleries' names.
    func updateGalleryMarkers(_ markers: [GalleryMarker]) {
        guard markers != galleryMarkers else { return }
        galleryMarkers = markers
        guard let style = session?.canvas?.style else { return }
        applyLevelChanger(on: style)
    }

    /// The dots of the journey artworks without a numbered marker.
    func updateStopDots(_ dots: [StopDot]) {
        guard dots != stopDots else { return }
        stopDots = dots
        guard let style = session?.canvas?.style else { return }
        applyStopDots(on: style)
    }

    /// The pins in the markers of the journey artworks.
    func updateStopIcons(_ icons: [StopIcon]) {
        guard icons != stopIcons else { return }
        stopIcons = icons
        guard let style = session?.canvas?.style else { return }
        applyStopIcons(on: style)
    }

    // MARK: Style

    private func install(on style: MLNStyle) {
        guard let canvas = session?.canvas else { return }
        // The amenity glyphs of the detour markers, on every style: added once before the style had
        // loaded, they were missing (PM, Monday "Amenity icon disappears sometimes", 2026-10-28).
        MapStyle.registerStopIcons(on: canvas)
        if style.source(withIdentifier: Self.gallerySource) == nil {
            let source = MLNShapeSource(identifier: Self.gallerySource, shape: nil)
            style.addSource(source)
            // The visited and the destination galleries over the venue's artworks, furniture and inner
            // walls (PM, Monday "Navigation to a gallery", 2026-10-27, and "Visited gallery
            // visualization", 2026-10-28), under labels, POI icons, the route and the stop markers. On
            // a style without inner walls the visited galleries are over the floor plan.
            let visited = MLNFillStyleLayer(identifier: Self.visitedLayer, source: source)
            visited.predicate = NSPredicate(format: "style == %@", GalleryFill.Style.visited.rawValue)
            if style.layer(withIdentifier: Self.innerWallLayer) == nil {
                canvas.addLayer(visited, at: .aboveVenueFills)
            } else {
                canvas.addLayer(visited, at: .above(layerID: Self.innerWallLayer))
            }
            let destination = MLNFillStyleLayer(identifier: Self.destinationLayer, source: source)
            destination.predicate = NSPredicate(format: "style == %@", GalleryFill.Style.destination.rawValue)
            canvas.addLayer(destination, at: .above(layerID: Self.visitedLayer))
            // The other galleries in the venue style's gallery colour over their artworks and
            // furniture, under the inner walls (PM, Monday "Artwork + furniture polygons",
            // 2026-10-29).
            let standard = MLNFillStyleLayer(identifier: Self.standardLayer, source: source)
            standard.predicate = NSPredicate(format: "style == %@", GalleryFill.Style.standard.rawValue)
            let venueGallery = style.layer(withIdentifier: Self.venueGalleryLayer) as? MLNFillStyleLayer
            standard.fillColor = venueGallery?.fillColor ?? NSExpression(forConstantValue: UIColor(hex: 0xE6E6E6))
            standard.fillOpacity = venueGallery?.fillOpacity ?? NSExpression(forConstantValue: 1)
            if style.layer(withIdentifier: Self.furnitureLayer) == nil {
                canvas.addLayer(standard, at: .below(layerID: Self.visitedLayer))
            } else {
                canvas.addLayer(standard, at: .above(layerID: Self.furnitureLayer))
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
            registerChangerAmenityIcons(on: canvas)
            for icon in Set(AmenityKind.allCases.map(\.icon)) {
                if let image = Self.redMarker(glyph: icon) { canvas.floors.register(image, named: Highlight.imageName(for: icon)) }
            }
            let source = MLNShapeSource(identifier: Self.changerSource, shape: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: Self.changerLayer, source: source)
            layer.predicate = NSPredicate(format: "kind == %@", PointKind.changer.rawValue)
            layer.iconImageName = NSExpression(forKeyPath: "image")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            // The highlighted level changer over the others.
            layer.symbolSortKey = NSExpression(forKeyPath: "sort")
            canvas.addLayer(layer, at: .above(.route))
            // MapLibre places the symbols of the upper layers first: the stop markers, then the
            // destination's name, then the other names, each where nothing placed before it is.
            let names = MLNSymbolStyleLayer(identifier: Self.galleryNameLayer, source: source)
            names.predicate = NSPredicate(format: "kind == %@", PointKind.galleryName.rawValue)
            names.iconImageName = NSExpression(forKeyPath: "image")
            names.iconAllowsOverlap = NSExpression(forConstantValue: false)
            // The visited galleries' names before the others.
            names.symbolSortKey = NSExpression(forKeyPath: "sort")
            canvas.addLayer(names, at: .above(layerID: Self.changerLayer))
            let destination = MLNSymbolStyleLayer(identifier: Self.destinationNameLayer, source: source)
            destination.predicate = NSPredicate(format: "kind == %@", PointKind.destinationName.rawValue)
            destination.iconImageName = NSExpression(forKeyPath: "image")
            destination.iconAllowsOverlap = NSExpression(forConstantValue: true)
            canvas.addLayer(destination, at: .above(layerID: Self.galleryNameLayer))
        }
        if style.source(withIdentifier: Self.stopDotSource) == nil {
            for dot in StopDot.Style.allCases {
                canvas.floors.register(Self.stopDotImage(style: dot), named: StopDot.imageName(for: dot))
            }
            let source = MLNShapeSource(identifier: Self.stopDotSource, shape: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: Self.stopDotLayer, source: source)
            layer.iconImageName = NSExpression(forKeyPath: "image")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            // The active stop's dot over the others.
            layer.symbolSortKey = NSExpression(forKeyPath: "sort")
            // Above the route, below the level changers, the gallery names and the numbered markers.
            canvas.addLayer(layer, at: .below(layerID: Self.changerLayer))
        }
        if style.source(withIdentifier: Self.stopIconSource) == nil {
            for isCurrent in [false, true] {
                canvas.floors.register(Self.stopPinImage(isCurrent: isCurrent), named: StopIcon.imageName(isCurrent: isCurrent))
            }
            let source = MLNShapeSource(identifier: Self.stopIconSource, shape: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: Self.stopIconLayer, source: source)
            layer.iconImageName = NSExpression(forKeyPath: "image")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            // Over the stop markers the map library draws.
            canvas.addLayer(layer, at: .top)
        }
        apply(on: style)
        applyConnector(on: style)
        applyLevelChanger(on: style)
        applyStopDots(on: style)
        applyStopIcons(on: style)
        applyCones(on: style)
        styleConeOutlines(on: style)
    }

    private func applyStopDots(on style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.stopDotSource) as? MLNShapeSource else { return }
        let features = stopDots.filter { sameLevel($0.level) }.map { dot -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: dot.coordinate.latitude, longitude: dot.coordinate.longitude)
            feature.attributes = ["image": StopDot.imageName(for: dot.style), "sort": NSNumber(value: dot.style == .active ? 1 : 0)]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    private func applyStopIcons(on style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.stopIconSource) as? MLNShapeSource else { return }
        let features = stopIcons.filter { sameLevel($0.level) }.map { icon -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: icon.coordinate.latitude, longitude: icon.coordinate.longitude)
            feature.attributes = ["image": StopIcon.imageName(isCurrent: icon.isCurrent)]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    /// The size of the pin in a stop marker of 30 points, in points: 0.4 of the marker's height, as
    /// in RPR's picture of the three markers (PM, Monday "Icons for personalized routes",
    /// 2026-11-20). RPR's `Pin.svg` is 10.33 × 15.83.
    static let stopPinSize = CGSize(width: 8, height: 12)

    /// RPR's pin (`Pin.svg`): a drop with a round hole. White for the current artwork, else
    /// `#2B2B2B`.
    static func stopPinImage(isCurrent: Bool, size: CGSize = stopPinSize) -> UIImage {
        let scale = size.height / 15.8333
        return UIGraphicsImageRenderer(size: size).image { _ in
            let radius = 5.16667 * scale
            let centre = CGPoint(x: size.width / 2, y: radius)
            let tip = CGPoint(x: centre.x, y: size.height)
            let shoulder = 9.08333 * scale
            let pin = UIBezierPath()
            pin.move(to: CGPoint(x: centre.x - radius, y: centre.y))
            pin.addArc(withCenter: centre, radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
            pin.addCurve(to: tip, controlPoint1: CGPoint(x: centre.x + radius, y: shoulder), controlPoint2: tip)
            pin.addCurve(to: CGPoint(x: centre.x - radius, y: centre.y), controlPoint1: tip,
                         controlPoint2: CGPoint(x: centre.x - radius, y: shoulder))
            pin.close()
            let hole = 2 * scale
            pin.append(UIBezierPath(ovalIn: CGRect(x: centre.x - hole, y: centre.y - hole, width: 2 * hole, height: 2 * hole)))
            pin.usesEvenOddFillRule = true
            (isCurrent ? UIColor.white : UIColor(hex: 0x2B2B2B)).setFill()
            pin.fill()
        }
    }

    /// The diameter of a stop dot, in points.
    static let stopDotDiameter: CGFloat = 14

    /// A circle of `stopDotDiameter` in the colours of the stop marker of the same state
    /// (`MapStyle.journeyStops`), without the number.
    static func stopDotImage(style: StopDot.Style) -> UIImage {
        let fill: UIColor, stroke: UIColor, width: CGFloat
        switch style {
        case .pending: (fill, stroke, width) = (.white, UIColor(hex: 0xEEEDED), 1)
        case .visited: (fill, stroke, width) = (.white, UIColor(hex: 0xED3731), 2)
        case .active: (fill, stroke, width) = (UIColor(hex: 0xED3731), .white, 2)
        case .skipped: (fill, stroke, width) = (UIColor(hex: 0xBDBDBD), .white, 1)
        }
        let size = CGSize(width: stopDotDiameter, height: stopDotDiameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: width / 2, dy: width / 2))
            fill.setFill()
            circle.fill()
            stroke.setStroke()
            circle.lineWidth = width
            circle.stroke()
        }
    }

    private func applyLevelChanger(on style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.changerSource) as? MLNShapeSource else { return }
        let highlighted = changer.flatMap { sameLevel($0.level) ? $0 : nil }
        var features = changers
            .filter { $0.serves(level) && $0.coordinate != highlighted?.coordinate }
            .map { changer in
                let amenityID = changer.amenityID.flatMap { changerAmenityIcons[$0] == nil ? nil : $0 }
                let image = amenityID.map(LevelChanger.amenityImageName(for:)) ?? LevelChanger.standardImageName(for: changer.featureType)
                return Self.point(changer.coordinate, image: image, sort: 0)
            }
        if let highlighted {
            features.append(Self.point(highlighted.coordinate, image: highlighted.imageName, sort: 1))
        }
        if let highlight, sameLevel(highlight.level) {
            features.append(Self.point(highlight.coordinate, image: highlight.imageName, sort: 2))
        }
        for marker in galleryMarkers where sameLevel(marker.level) {
            let name = marker.imageName
            if style.image(forName: name) == nil {
                session?.canvas?.floors.register(Self.galleryMarkerImage(name: marker.name, style: marker.style), named: name)
            }
            let kind: PointKind = marker.style == .destination ? .destinationName : .galleryName
            features.append(Self.point(marker.coordinate, image: name, sort: marker.style == .visited ? 0 : 1, kind: kind))
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    /// A gallery's name in a 30 pt pill, its middle on the POI (PM, Monday "Gallery numbers in gallery
    /// navigation", 2026-10-28): the destination red with a white border and white text, a visited
    /// gallery white with a red outline, the others white with a black outline.
    static func galleryMarkerImage(name: String, style: GalleryMarker.Style) -> UIImage {
        let red = UIColor(hex: 0xED3731)
        let ink = UIColor(hex: 0x2B2B2B)
        let (fill, outline, outlineWidth, text): (UIColor, UIColor, CGFloat, UIColor) = switch style {
        case .destination: (red, .white, 2, .white)
        case .visited: (.white, red, 2, ink)
        case .standard: (.white, ink, 1.5, ink)
        }
        let font = UIFont(name: "GuggenheimSansDisplay-SemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: text]
        let title = name as NSString
        let textSize = title.size(withAttributes: attributes)
        let inset: CGFloat = 12, height: CGFloat = 30
        let textWidth = min(ceil(textSize.width), 220)
        let size = CGSize(width: inset + textWidth + inset + 2, height: height)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let pill = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: height / 2 - 1)
            fill.setFill()
            pill.fill()
            outline.setStroke()
            pill.lineWidth = outlineWidth
            pill.stroke()
            title.draw(with: CGRect(x: inset + 1, y: (height - ceil(textSize.height)) / 2, width: textWidth, height: ceil(textSize.height)),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
        }
    }

    /// The layer a point of the level changer source goes to.
    private enum PointKind: String {
        case changer
        case galleryName
        case destinationName
    }

    private static func point(_ coordinate: ProximiioCoordinate, image: String, sort: Int, kind: PointKind = .changer) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        feature.attributes = ["image": image, "sort": NSNumber(value: sort), "kind": kind.rawValue]
        return feature
    }

    /// The design's icon of a level changer type.
    private static func icon(featureType: String) -> GADIcon {
        GADIcon.levelChanger(featureType: featureType)
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
                feature.attributes = ["style": fill.style.rawValue]
                return feature
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
    }

    /// The venue's cones, at the start and after a change of the venue data.
    func updateCones(_ cones: [VenueCone]) {
        guard cones != self.cones else { return }
        let removed = Set(self.cones.map(\.id)).subtracting(cones.map(\.id))
        let unchanged = Set(cones.filter { self.cones.contains($0) }.map(\.id))
        coneShadings = coneShadings.filter { unchanged.contains($0.key) }
        let style = session?.canvas?.style
        for id in removed {
            if let layer = style?.layer(withIdentifier: Self.coneID(id)) { style?.removeLayer(layer) }
            if let source = style?.source(withIdentifier: Self.coneID(id)) { style?.removeSource(source) }
        }
        self.cones = cones
        if let style { applyCones(on: style) }
    }

    private static func coneID(_ id: String) -> String { "gad-cone-\(id)" }
    /// The venue style's gallery fill; the cone images go under it.
    private static let venueGalleryLayer = "proximiio-gallery"
    /// The venue style's cone outlines.
    private static let coneOutlineLayer = "proximiio-cones"

    /// The cones' outline in the design's colour and width, on each style.
    private func styleConeOutlines(on style: MLNStyle) {
        guard let outline = style.layer(withIdentifier: Self.coneOutlineLayer) as? MLNLineStyleLayer else { return }
        outline.lineColor = NSExpression(forConstantValue: UIColor(hex: ConeShading.outlineColor))
        outline.lineOpacity = NSExpression(forConstantValue: ConeShading.outlineOpacity)
        outline.lineWidth = NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            ConeShading.outlineWidths as NSDictionary
        )
    }

    /// Puts the cones of the shown floor on the map and takes the others off. A cone's image is made
    /// when its floor first shows and kept; a changed cone gets a new image. The other floors' cones are
    /// removed, not hidden: MapLibre does not load an image source whose layer is hidden, and an unloaded
    /// source keeps every frame from counting as fully rendered, so `venueDrawing` never became `.drawn`
    /// (GADKit 1.22.0 to 1.22.2).
    private func applyCones(on style: MLNStyle) {
        guard let canvas = session?.canvas else { return }
        for cone in cones {
            let id = Self.coneID(cone.id)
            let layer = style.layer(withIdentifier: id)
            guard sameLevel(cone.level) else {
                if let layer { style.removeLayer(layer) }
                if let source = style.source(withIdentifier: id) { style.removeSource(source) }
                coneImagesOnMap[cone.id] = nil
                continue
            }
            if coneShadings[cone.id] == nil { coneShadings[cone.id] = ConeShading.make(cone) }
            guard let shading = coneShadings[cone.id] else { continue }
            let quad = MLNCoordinateQuadMake(
                CLLocationCoordinate2D(latitude: shading.north, longitude: shading.west),
                CLLocationCoordinate2D(latitude: shading.south, longitude: shading.west),
                CLLocationCoordinate2D(latitude: shading.south, longitude: shading.east),
                CLLocationCoordinate2D(latitude: shading.north, longitude: shading.east)
            )
            if let source = style.source(withIdentifier: id) as? MLNImageSource {
                if coneImagesOnMap[cone.id] != ObjectIdentifier(shading.image) {
                    source.coordinates = quad
                    source.image = shading.image
                }
            } else {
                style.addSource(MLNImageSource(identifier: id, coordinateQuad: quad, image: shading.image))
            }
            coneImagesOnMap[cone.id] = ObjectIdentifier(shading.image)
            if layer == nil, let source = style.source(withIdentifier: id) {
                let raster = MLNRasterStyleLayer(identifier: id, source: source)
                raster.rasterFadeDuration = NSExpression(forConstantValue: 0)
                // Over the floors, under the venue's galleries and the gallery fills of `apply(on:)`:
                // a cone that is a gallery keeps the gallery's colour.
                if style.layer(withIdentifier: Self.venueGalleryLayer) == nil {
                    canvas.addLayer(raster, at: .aboveVenueFills)
                } else {
                    canvas.addLayer(raster, at: .below(layerID: Self.venueGalleryLayer))
                }
            }
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
