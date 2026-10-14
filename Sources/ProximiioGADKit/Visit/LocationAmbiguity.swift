//
//  LocationAmbiguity.swift
//  ProximiioGADKit
//
//  Decides when the visitor must confirm where they are (Figma "Other Use Cases",
//  Edge 04 — Ambiguous location, "a four-rung ladder; confidence decides which rung fires"):
//
//  - EC04a (two or more journey stops nearby) is not used: artworks are far enough apart that
//    the question is not needed (PM review 2026-10-12)
//  - EC04b: the visitor is between galleries and no gallery geofence is entered
//  - EC04c: manual confirmation, opened by the visitor ("Pick my stop manually", "Not here")
//  - EC04d: the position is uncertain near the active stop: a soft prompt
//
//  Pure; covered by tests.
//
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap

enum LocationAmbiguity: Equatable {
    /// EC04b: galleries the visitor could be in, nearest first.
    case betweenGalleries([VenuePlace])
    /// EC04d: the visitor is probably at this stop, but the position is uncertain.
    case lowConfidence(JourneyStop)

    struct Input {
        var coordinate: ProximiioCoordinate
        var level: Double?
        var horizontalAccuracy: Double
        var activeStop: JourneyStop?
        /// Gallery places of the venue (title contains "Gallery").
        var galleries: [VenuePlace]
        /// The gallery geofence the visitor is in, if any.
        var currentGallery: String?
    }

    /// `settings`: positions less accurate than `uncertainAccuracyMeters` are uncertain; galleries
    /// whose centre lies within `nearbyGalleryMeters` count as candidates.
    static func evaluate(_ input: Input, settings: GADSettings = .standard) -> LocationAmbiguity? {
        let here = CLLocation(latitude: input.coordinate.latitude, longitude: input.coordinate.longitude)

        func sameLevel(_ level: Double?) -> Bool {
            guard let level, let visitor = input.level else { return true }
            return VenueLevel.same(level, visitor)
        }

        if input.currentGallery == nil {
            let nearbyGalleries = input.galleries
                .filter { sameLevel($0.level) }
                .map { ($0, here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))) }
                .filter { $0.1 <= settings.nearbyGalleryMeters }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
            if nearbyGalleries.count >= 2 {
                return .betweenGalleries(nearbyGalleries)
            }
        }

        if input.horizontalAccuracy > settings.uncertainAccuracyMeters, let active = input.activeStop,
           sameLevel(active.floor?.level),
           here.distance(from: CLLocation(latitude: active.coordinate.latitude, longitude: active.coordinate.longitude)) <= input.horizontalAccuracy {
            return .lowConfidence(active)
        }
        return nil
    }

    /// Gallery places: the venue's places whose title names a gallery.
    static func galleries(in places: [VenuePlace]) -> [VenuePlace] {
        places.filter { $0.title.localizedCaseInsensitiveContains("gallery") }
    }

    /// The kind, for suppressing a prompt the visitor has just answered.
    var kind: String {
        switch self {
        case .betweenGalleries: "galleries"
        case .lowConfidence: "low"
        }
    }
}
