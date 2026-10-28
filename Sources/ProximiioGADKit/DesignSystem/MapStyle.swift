//
//  MapStyle.swift
//  ProximiioGADKit
//
//  Map colours of the design (page "3. App Design - In-Gallery Map (Proximi)", section `Colors`,
//  node 10930:60509):
//
//  - current location `#3F69FF`, with a white arrow for the heading. The dot is 30 pt across,
//    the size of a journey stop marker (PM review 2026-10-12).
//  - path ahead: gradient `#3F69FF` → `#ED3731`, 6 pt, round cap
//  - path traveled: `#3F69FF` at 30 %: the part of the computed leg behind the visitor. The leg
//    keeps its shape until the arrival (PM review 2026-10-12).
//  - markers `#ED3731` with a `#EEEDED` stroke
//  - journey stop markers (section `Markers`, node 10930:60881): a 30 pt circle with the stop
//    number. Next stop: red fill, white stroke. Visited: white, red stroke. Default: white,
//    `#EEEDED` stroke. An amenity detour: red fill, white stroke, the amenity's icon and no
//    number (PM review 2026-10-12).
//
//  The gradient runs per floor: on the floor after a lift, it starts at the lift.
//
import Proximiio
import MapLibre
import ProximiioMap
import UIKit

enum MapStyle {
    static let location = MapColor(hex: 0x3F69FF)
    static let marker = MapColor(hex: 0xED3731)
    static let markerStroke = MapColor(hex: 0xEEEDED)

    /// Map options shared by the map screens. The journey screen draws its own stop markers
    /// (`JourneyMapLayers`), turns the SDK's route markers off and shows the walked trail.
    ///
    /// The camera follows the visitor and turns the map with the phone's compass. The compass
    /// needs no permission. Before the first compass reading the map uses the walking direction.
    /// The map stays top-down: tilting is off (PM review 2026-10-12).
    ///
    /// "Centre on me" and the first position zoom to `followZoom` (`GADSettings.followZoom`; PM
    /// review 2026-10-12: the library default 18.5 is too far out).
    ///
    /// POI labels, floor names and `session.guidanceText` use the app language.
    ///
    /// With `walkedTrail`, the route behind the visitor is not drawn. On arrival the SDK marks
    /// the whole leg as traveled, and the computed leg differs from the path the visitor
    /// walked; the trail shows the walked path instead.
    static func options(routeMarkers: Bool = true, walkedTrail: Bool = false, settings: GADSettings = .standard) -> MapOptions {
        var position = PositionStyle.venue
        position.smoothing = settings.smoothsPosition ? .adaptive : .none
        position.dot.color = location
        position.dot.radiusPoints = 15
        // The library sizes the arrow at about 1.1 × the dot radius.
        position.heading = .arrow(.init(lengthPoints: 16.5))
        position.trail = walkedTrail
            ? PositionTrailStyle(isVisible: true, color: location, widthPoints: 6, opacity: 0.3)
            : PositionTrailStyle()
        // The dot disappears when the position does (PM, Monday "Privacy zone to have the same position
        // marker as position disappearing", 2026-10-26). `hidingPosition(_:)` hides it in a privacy zone.
        position.freshness.staleOpacity = 0
        position.freshness.lostOpacity = 0
        var options = MapOptions(
            camera: .followWithHeading,
            floorSelector: .none,
            trail: walkedTrail ? .lastMinutes(15) : .off,
            route: .automatic,
            routeMarkers: routeMarkers
                ? RouteMarkerStyle(color: marker, strokeColor: markerStroke, completedColor: MapColor(hex: 0xC3D3FF))
                : .off,
            position: position,
            fallbackStyleURL: nil
        )
        .with(heading: .compass)
        .with(language: AppLanguage.current)
        .with(routeLineStyle: walkedTrail ? routeAhead : route)
        // The MapLibre attribution is hidden until the app has a place for licence notices
        // (DAILY-CALL R16).
        .with(chrome: MapOptions.Chrome(showsAttribution: false, allowsTilting: false))
        options.recentreZoom = settings.followZoom
        return options.with(minimumZoom: settings.minimumZoom, maximumZoom: settings.maximumZoom)
    }

    /// The Explore Museum map: no position dot and a camera that never follows. The visitor is not
    /// at the museum there (user, 2026-10-23).
    static func exploreOptions(settings: GADSettings = .standard) -> MapOptions {
        var options = options(routeMarkers: false, settings: settings)
        options.camera = .free
        let clear = MapColor(hex: 0xFFFFFF, alpha: 0)
        options.position.dot.color = clear
        options.position.dot.staleColor = clear
        options.position.dot.strokeColor = clear
        options.position.dot.shadowOpacity = 0
        options.position.accuracy = .none
        options.position.heading = .none
        // The dot a privacy zone holds is clear too (as on Android).
        options.position.privacy = PositionPrivacyStyle(color: clear, showsAccuracy: false)
        return options
    }

    /// `position` with nothing drawn while a privacy zone holds the dot. The map library draws a held
    /// dot at full opacity; its fill, stroke, shadow and ring are made clear.
    static func hidingPosition(_ position: PositionStyle) -> PositionStyle {
        var position = position
        let clear = MapColor(hex: 0xFFFFFF, alpha: 0)
        position.dot.strokeColor = clear
        position.dot.shadowOpacity = 0
        position.privacy = PositionPrivacyStyle(color: clear, showsAccuracy: false)
        return position
    }

    /// Journey stop markers, drawn by the map library. Skipped stops have no marker and no number.
    static let journeyStops: JourneyStopMarkerStyle = {
        let ink = MapColor(hex: 0x2B2B2B)
        let white = MapColor(hex: 0xFFFFFF)
        let visited = JourneyStopMarkerStyle.Appearance(fillColor: white, strokeColor: marker, strokeWidthPoints: 2, labelColor: ink)
        var style = JourneyStopMarkerStyle(
            done: visited,
            active: .init(fillColor: marker, strokeColor: white, strokeWidthPoints: 2, labelColor: white),
            pending: .init(fillColor: white, strokeColor: markerStroke, strokeWidthPoints: 1, labelColor: ink),
            passed: visited,
            detour: .init(fillColor: marker, strokeColor: white, strokeWidthPoints: 2, labelColor: white),
            diameterPoints: 30,
            activeDiameterPoints: 30,
            detourDiameterPoints: 30,
            labelFontSize: 14,
            labelWeight: .medium,
            labelFontName: "GuggenheimSansDisplay-Medium"
        )
        // The visitor's dot under the stop numbers (RPR, Monday "Stop markers.", 2026-10-28; map
        // 6.0.0-beta.56).
        style.drawsAbovePosition = true
        return style
    }()

    /// `journeyStops` with the artworks' markers invisible; the detour keeps its marker. A stop marker
    /// style of `nil` would take the detour's marker off too.
    static let journeyStopsHidden: JourneyStopMarkerStyle = {
        var style = journeyStops
        style.done.opacity = 0
        style.active.opacity = 0
        style.pending.opacity = 0
        style.passed.opacity = 0
        style.skipped.opacity = 0
        return style
    }()

    /// Route line. It replaces the organisation style's route line layers on any style.
    static let route = RouteLineStyle(
        remaining: .gradient(from: location, to: marker),
        remainingOpacity: 1,
        completedColor: location,
        completedOpacity: 0.3,
        widthPoints: 6,
        cap: .round
    )

    /// No route line: the map of a floor without positioning (`FloorWithoutPositioningGuide`).
    static let hiddenRoute = RouteLineStyle(
        remaining: .gradient(from: location, to: marker),
        remainingOpacity: 0,
        completedColor: location,
        completedOpacity: 0,
        widthPoints: 6,
        cap: .round
    )

    /// Route line without the traveled part, for a map that draws the walked trail.
    static let routeAhead = RouteLineStyle(
        remaining: .gradient(from: location, to: marker),
        remainingOpacity: 1,
        completedColor: location,
        completedOpacity: 0,
        widthPoints: 6,
        cap: .round
    )

    /// A map session that draws amenities with the design's icons (`amenityImage(for:scale:)`), or
    /// with `galleryIcons` the icons of the Explore Museum map (`exploreAmenityImage(for:scale:)`).
    @MainActor static func session(sdk: Proximiio, options: MapOptions, galleryIcons: Bool = false) -> ProximiioMapSession {
        let session = ProximiioMapSession(sdk: sdk, options: options)
        let scale = UIScreen.main.scale
        session.amenityImageDecoder = galleryIcons
            ? { exploreAmenityImage(for: $0, scale: scale) }
            : { amenityImage(for: $0, scale: scale) }
        AppLanguage.follow(session)
        return session
    }

    /// The map icon of an amenity, one point per pixel of the venue data's icon, as the portal and
    /// MapTap draw it (MapLibre GL JS registers an image at pixel ratio 1). The style's `icon-size`
    /// then gives the same size here and in MapTap: 120 px at 0.2 is 24 pt (PM, 2026-10-27: the
    /// gallery icons were 8 pt at 0.2, with the icon at the screen's scale).
    ///
    /// A kind the design draws (`AmenityKind`) gets its marker (PM 2026-10-14, "Amenity icons
    /// larger") at the size of the data's icon it replaces. Other amenities, such as artworks and
    /// galleries, keep their icon.
    static func amenityImage(for amenity: ProximiioAmenity, scale: CGFloat) -> UIImage? {
        let icon = amenity.icon.flatMap { AmenityIcon.rasterImage($0, scale: 1) }
        if let kind = AmenityKind.kind(forAmenityID: amenity.id, title: amenity.title),
           let name = kind.icon.markerImageName,
           let marker = UIImage(named: name, in: .module, compatibleWith: nil) {
            let size = styleIconSize(of: icon)
            return render(size: size, scale: scale) { marker.draw(in: CGRect(origin: .zero, size: size)) }
        }
        return icon
    }

    /// The map icon of an amenity on the Explore Museum map. A gallery's icon from the venue data on
    /// a circle of white at 30 % with a white border, the icon at 22/30 of the circle (PM, Monday
    /// "Explore museum view: default map view", 2026-10-26). The circle has the data icon's size in
    /// points, as `amenityImage(for:scale:)`. An icon without a circle of its own shows the design
    /// best.
    static func exploreAmenityImage(for amenity: ProximiioAmenity, scale: CGFloat) -> UIImage? {
        if AmenityKind.kind(forAmenityID: amenity.id, title: amenity.title) != nil {
            return amenityImage(for: amenity, scale: scale)
        }
        guard let icon = amenity.icon.flatMap({ AmenityIcon.rasterImage($0, scale: 1) }) else { return nil }
        let side = max(icon.size.width, icon.size.height)
        let size = CGSize(width: side, height: side)
        let unit = side / 30
        return render(size: size, scale: scale) {
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: unit / 2, dy: unit / 2))
            UIColor.white.withAlphaComponent(0.3).setFill()
            circle.fill()
            UIColor.white.setStroke()
            circle.lineWidth = unit
            circle.stroke()
            icon.draw(in: CGRect(x: 4 * unit, y: 4 * unit, width: 22 * unit, height: 22 * unit))
        }
    }

    /// The size in points of a map icon made from the data's `icon`: its size in pixels, 120 × 120
    /// without one (the venue data's icons on 2026-10-27). Pure; covered by tests.
    static func styleIconSize(of icon: UIImage?) -> CGSize {
        guard let icon else { return CGSize(width: 120, height: 120) }
        return CGSize(width: icon.size.width * icon.scale, height: icon.size.height * icon.scale)
    }

    private static func render(size: CGSize, scale: CGFloat, _ draw: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw() }
    }

    /// Registers the design's glyphs under their `GADIcon` raw value, the `iconName` of an amenity
    /// detour stop (`VisitController.detour(to:)`). The library draws the glyph in the detour's
    /// label colour, white on the red marker (PM 2026-10-15: the marker had no icon).
    @MainActor static func registerStopIcons(on canvas: ProximiioMapCanvas) {
        for icon in GADIcon.allCases where icon.markerImageName != nil {
            guard let image = UIImage(named: icon.rawValue, in: .module, compatibleWith: nil) else { continue }
            canvas.floors.register(image.withRenderingMode(.alwaysTemplate), named: icon.rawValue)
        }
    }

    /// Waits up to 5 s until the map view has created its canvas.
    @MainActor static func waitForCanvas(of session: ProximiioMapSession) async {
        for _ in 0..<50 where session.canvas == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
