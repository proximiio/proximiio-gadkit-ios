//
//  LevelChangerPlace.swift
//  ProximiioGADKit
//
//  A staircase, lift or escalator POI: a point feature of type `staircase`, `elevator` or
//  `escalator`. It serves its own floor and the floors in `properties.levels`. The map library
//  draws a POI on its own floor only; GADKit hides these POIs and draws them on every floor they
//  serve (`JourneyMapLayers`), as the web map does (Monday "All level changers visible",
//  2026-10-15). In the GAD data the lifts are POIs on level 0 with `levels` [1, 2, 3, 4].
//
import Proximiio

struct LevelChangerPlace: Equatable {
    let id: String
    let featureType: String
    let coordinate: ProximiioCoordinate
    /// The POI's floor and the floors in `properties.levels`.
    let levels: [Double]

    static let featureTypes: Set<String> = ["elevator", "staircase", "escalator"]

    init(id: String, featureType: String, coordinate: ProximiioCoordinate, levels: [Double]) {
        self.id = id
        self.featureType = featureType
        self.coordinate = coordinate
        self.levels = levels
    }

    /// `nil` for every feature that is not a point of a level changer type.
    init?(feature: ProximiioFeature) {
        guard let type = feature.propertyType, Self.featureTypes.contains(type),
              let geometry = feature.geometry, geometry.type == "Point",
              let pair = geometry.coordinates.arrayValue, pair.count >= 2,
              // GeoJSON order is [longitude, latitude].
              let longitude = pair[0].doubleValue, let latitude = pair[1].doubleValue
        else { return nil }
        var levels = feature.level.map { [$0] } ?? []
        if case .array(let listed)? = feature.properties?["levels"] {
            levels += listed.compactMap(\.doubleValue)
        }
        self.init(id: feature.id, featureType: type, coordinate: ProximiioCoordinate(latitude: latitude, longitude: longitude), levels: levels)
    }

    static func all(in features: [ProximiioFeature]) -> [LevelChangerPlace] {
        features.compactMap(LevelChangerPlace.init(feature:))
    }

    func serves(_ level: Double) -> Bool {
        levels.contains { VenueLevel.same($0, level) }
    }
}
