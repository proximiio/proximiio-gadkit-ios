//
//  VenuePlace.swift
//  ProximiioGADKit
//
//  A point of interest the visitor can open and route to. Built from
//  `Proximiio.features()`, the local cache that `loadRouteNetwork()` fills. Same rules as
//  proximiio-blueiot-minimal-ios `VenuePOI`. Title and description are read from
//  `title_i18n` and `description_i18n` for the app's language when the feature has them.
//
import Foundation
import Proximiio

public struct VenuePlace: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Feature `description`, if set in Proximi.io Portal.
    public let details: String?
    public let coordinate: ProximiioCoordinate
    /// Floor level. `computeRoute` takes it as `toLevel`.
    public let level: Double
    /// Amenity id, `<category>:<amenity>`, or `nil`.
    public let amenityID: String?
    /// The customer's id (`remote_id`): an artwork's collection id such as "GAD.2010.00033".
    /// The artwork's geofence holds the same value.
    public var remoteID: String?
    /// True for an artwork: the artwork amenity, an `artwork_id` in `metadata`, or a collection id
    /// in `remote_id`.
    public var isArtwork = false
    /// First entry of the feature's `images` property, if it is an absolute URL.
    public var imageURL: URL?

    /// Every point POI in `features`, sorted by title.
    public static func all(in features: [ProximiioFeature]) -> [VenuePlace] {
        features
            .compactMap(VenuePlace.init(feature:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The place under a map tap. `identifiers` are the feature ids from
    /// `ProximiioMapSession.onFeatureTap`, topmost first. The first id that matches wins.
    static func place(under identifiers: [String], in places: [VenuePlace]) -> VenuePlace? {
        for identifier in identifiers {
            if let place = places.first(where: { $0.id == identifier }) { return place }
        }
        return nil
    }

    /// The visitor service desk: an amenity id or title naming the help, welcome or information desk.
    static func welcomeDesk(in places: [VenuePlace]) -> VenuePlace? {
        let names = ["welcome desk", "help desk", "information", "front desk", "info desk"]
        return places.first { place in
            let title = place.title.lowercased()
            let amenity = place.amenityID?.lowercased() ?? ""
            return names.contains { title.contains($0) } || amenity.contains("help") || amenity.contains("info")
        }
    }

    /// Case- and diacritic-insensitive substring match on the title. An empty query matches all.
    public static func matching(_ query: String, in places: [VenuePlace]) -> [VenuePlace] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return places }
        return places.filter { $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The amenity of artwork POIs in the GAD organisation (PM, Monday 2026-10-12).
    static let artworkAmenityID = "7405e6e6-d9f6-4146-adda-de6adbf4a8a1:f2d78fac-23be-4f24-b5aa-571809e9e99d"

    /// True for a POI with the artwork amenity, an `artwork_id` in `metadata`, or a collection id
    /// ("GAD.2018.00034") in `remote_id`. Test artworks have no `artwork_id`. Gallery and amenity
    /// POIs have none of the three.
    static func isArtwork(amenityID: String? = nil, metadata: JSONValue?, remoteID: String? = nil) -> Bool {
        if amenityID == artworkAmenityID { return true }
        if let remoteID, remoteID.wholeMatch(of: /GAD\.\d{4}\.\d+/) != nil { return true }
        guard case .object(let metadata)? = metadata else { return false }
        return text(metadata["artwork_id"]) != nil
    }

    /// `nil` for every feature that is not a point POI.
    init?(feature: ProximiioFeature) {
        guard feature.propertyType == "poi",
              let geometry = feature.geometry,
              geometry.type == "Point",
              let pair = geometry.coordinates.arrayValue,
              pair.count >= 2,
              // GeoJSON order is [longitude, latitude].
              let longitude = pair[0].doubleValue,
              let latitude = pair[1].doubleValue,
              longitude.isFinite, latitude.isFinite
        else { return nil }

        id = feature.id
        let properties = feature.properties
        title = Self.localized(properties?["title_i18n"])
            ?? Self.text(properties?["title"])
            ?? Self.text(properties?["name"])
            ?? feature.id
        details = Self.localized(properties?["description_i18n"]) ?? Self.text(properties?["description"])
        coordinate = ProximiioCoordinate(latitude: latitude, longitude: longitude)
        level = feature.level ?? 0
        amenityID = Self.text(feature.properties?["amenity"])
        remoteID = Self.text(properties?["remote_id"])
        isArtwork = Self.isArtwork(amenityID: amenityID, metadata: properties?["metadata"], remoteID: remoteID)
        if case .array(let images)? = properties?["images"], let first = images.first.flatMap(Self.text),
           let url = URL(string: first), url.scheme != nil {
            imageURL = url
        }
    }

    init(id: String, title: String, details: String? = nil, coordinate: ProximiioCoordinate, level: Double,
         amenityID: String? = nil, remoteID: String? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.coordinate = coordinate
        self.level = level
        self.amenityID = amenityID
        self.remoteID = remoteID
    }

    /// The value for the app's current language from an i18n object such as
    /// `{"en": "Café", "ar": "المقهى"}`. `nil` when the object has no non-empty value for it.
    static func localized(_ value: JSONValue?, language: String? = Bundle.main.preferredLocalizations.first) -> String? {
        guard case .object(let translations)? = value, let language else { return nil }
        let base = String(language.prefix(while: { $0 != "-" }))
        return text(translations[language]) ?? text(translations[base])
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue, !text.isEmpty else { return nil }
        return text
    }
}
