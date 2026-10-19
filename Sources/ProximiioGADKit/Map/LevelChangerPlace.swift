//
//  LevelChangerPlace.swift
//  ProximiioGADKit
//
//  A staircase, lift or escalator POI: a point feature of type `staircase`, `elevator` or
//  `escalator`. The map library draws a POI on its own floor only; GADKit hides these POIs and
//  draws them on every floor they serve (`JourneyMapLayers`), as the web map does (Monday "All
//  level changers visible", 2026-10-15).
//
//  The floors served follow the SDK router (`LevelChangerExtractor.levelChangers(from:)`,
//  6.0.0-beta.60): exactly the floors in `properties.levels`, without the POI's own floor. In the
//  GAD data lift 9f411e5a is a POI on level 0 with `levels` [1, 2, 3, 4]; the router does not use
//  it on level 0, so GADKit does not draw it there. Without usable `levels` the POI serves its own
//  floor.
//
import Proximiio

struct LevelChangerPlace: Equatable {
    let id: String
    let featureType: String
    let coordinate: ProximiioCoordinate
    /// The floors in `properties.levels`, or the POI's own floor when `levels` is missing, empty or
    /// unreadable.
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
        let listed = feature.properties?["levels"].flatMap(Self.levels(from:))
        let levels = listed ?? feature.level.map { [$0] } ?? []
        self.init(id: feature.id, featureType: type, coordinate: ProximiioCoordinate(latitude: latitude, longitude: longitude), levels: levels)
    }

    /// The finite levels in a `properties.levels` value, or `nil` when it holds none. Entries may
    /// be numbers or numeric strings; a single number or string counts as a one-entry list. Same
    /// rule as the SDK's `LevelChangerExtractor.levels(from:)`.
    static func levels(from value: JSONValue) -> [Double]? {
        let entries = value.arrayValue ?? [value]
        let levels = entries.compactMap { entry -> Double? in
            let level: Double?
            switch entry {
            case .number(let number): level = number
            case .string(let string): level = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            default: level = nil
            }
            return level.flatMap { $0.isFinite ? $0 : nil }
        }
        return levels.isEmpty ? nil : levels
    }

    static func all(in features: [ProximiioFeature]) -> [LevelChangerPlace] {
        features.compactMap(LevelChangerPlace.init(feature:))
    }

    func serves(_ level: Double) -> Bool {
        levels.contains { VenueLevel.same($0, level) }
    }
}
