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

    /// Journey stop markers, drawn by the map library. Skipped stops have no marker and no number.
    static let journeyStops: JourneyStopMarkerStyle = {
        let ink = MapColor(hex: 0x2B2B2B)
        let white = MapColor(hex: 0xFFFFFF)
        let visited = JourneyStopMarkerStyle.Appearance(fillColor: white, strokeColor: marker, strokeWidthPoints: 2, labelColor: ink)
        return JourneyStopMarkerStyle(
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

    /// Route line without the traveled part, for a map that draws the walked trail.
    static let routeAhead = RouteLineStyle(
        remaining: .gradient(from: location, to: marker),
        remainingOpacity: 1,
        completedColor: location,
        completedOpacity: 0,
        widthPoints: 6,
        cap: .round
    )

    /// A map session that draws amenities with the design's icons (`amenityImage(for:scale:)`).
    @MainActor static func session(sdk: Proximiio, options: MapOptions) -> ProximiioMapSession {
        let session = ProximiioMapSession(sdk: sdk, options: options)
        let scale = UIScreen.main.scale
        session.amenityImageDecoder = { amenityImage(for: $0, scale: scale) }
        return session
    }

    /// The map icon of an amenity. A kind the design draws (`AmenityKind`) gets its 30 pt marker,
    /// the size of the stop markers and the position arrow (PM 2026-10-14, "Amenity icons
    /// larger"): the data's icons are 30 px, which the map library draws at the screen scale, 10 pt
    /// on a 3x screen. Other amenities, such as artworks and gallery labels, keep their icon.
    static func amenityImage(for amenity: ProximiioAmenity, scale: CGFloat) -> UIImage? {
        if let kind = AmenityKind.kind(forAmenityID: amenity.id, title: amenity.title),
           let name = kind.icon.markerImageName,
           let image = UIImage(named: name, in: .module, compatibleWith: nil) {
            return image
        }
        return amenity.icon.flatMap { AmenityIcon.rasterImage($0, scale: scale) }
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
