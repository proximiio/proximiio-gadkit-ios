//
//  AmenityShortcut.swift
//  ProximiioGADKit
//
//  One amenity of the maps' search: a kind of `AmenityKind`, with the design's title and icon, or an
//  amenity the data puts in the search (`metadata.in_search`) that is none of the kinds, with the
//  amenity's own title and icon. The galleries, the artworks and Learning & Engagement had the flag
//  and did not show (PM, 2026-10-29).
//
import Proximiio
import SwiftUI

struct AmenityShortcut: Identifiable, Equatable {
    enum Source: Equatable {
        case kind(AmenityKind)
        /// An amenity of the venue data: its id, its title in the app language and its icon.
        case amenity(id: String, title: String, icon: UIImage?)
    }

    let source: Source

    init(_ kind: AmenityKind) {
        source = .kind(kind)
    }

    init(amenityID: String, title: String, icon: UIImage?) {
        source = .amenity(id: amenityID, title: title, icon: icon)
    }

    var id: String {
        switch source {
        case .kind(let kind): "kind:\(kind.rawValue)"
        case .amenity(let id, _, _): id
        }
    }

    var title: String {
        switch source {
        case .kind(let kind): kind.title
        case .amenity(_, let title, _): title
        }
    }

    var kind: AmenityKind? {
        if case .kind(let kind) = source { return kind }
        return nil
    }

    /// The design's icon of a kind, else the amenity's icon from the data.
    var image: Image? {
        switch source {
        case .kind(let kind): kind.icon.image
        case .amenity(_, _, let icon): icon.map { Image(uiImage: $0) }
        }
    }

    /// A place of a kind matches by its amenity's kind; a place of an amenity from the data by its
    /// amenity id.
    func matches(_ place: VenuePlace) -> Bool {
        switch source {
        case .kind(let kind): kind.matches(place)
        case .amenity(let id, _, _): place.amenityID == id
        }
    }

    /// The nearest matching place, as `AmenityKind.nearest(in:from:level:)`.
    func nearest(in places: [VenuePlace], from coordinate: ProximiioCoordinate?, level: Double?) -> VenuePlace? {
        Self.nearest(of: places.filter(matches), from: coordinate, level: level)
    }

    /// The nearest of `matching` in the venue of the nearest one (`place_id`). In that venue, places
    /// on the visitor's level come first; distance is straight-line. The route gives the walking
    /// distance. The venue comes first because the GAD data has a café on level 1 of the DCT office,
    /// 11 km away, and the Guggenheim café on level 0 (2026-10-15).
    static func nearest(of matching: [VenuePlace], from coordinate: ProximiioCoordinate?, level: Double?) -> VenuePlace? {
        guard let coordinate else { return matching.first }
        guard let closest = TrackingMonitor.nearest(to: coordinate, level: nil, in: matching) else { return nil }
        let venue = matching.filter { $0.placeID == closest.placeID }
        let sameLevel = level.map { level in venue.filter { VenueLevel.same($0.level, level) } } ?? []
        return TrackingMonitor.nearest(to: coordinate, level: nil, in: sameLevel.isEmpty ? venue : sameLevel)
    }
}
