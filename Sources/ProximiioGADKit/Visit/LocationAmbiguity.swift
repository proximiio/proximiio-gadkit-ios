//
//  LocationAmbiguity.swift
//  ProximiioGADKit
//
//  Decides when the visitor must confirm where they are (Figma "Other Use Cases",
//  Edge 04 — Ambiguous location, "a four-rung ladder; confidence decides which rung fires"):
//
//  - EC04a (two or more journey stops nearby) is not used: artworks are far enough apart that
//    the question is not needed (PM review 2026-10-12)
//  - EC04b ("Which one are you in?" between galleries) and EC04c (the visitor picks the stop
//    manually) are not used: the PM does not want these views (Monday 2026-10-15)
//  - EC04d: the position is uncertain near the active stop: a soft prompt
//
//  Pure; covered by tests.
//
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap

enum LocationAmbiguity: Equatable {
    /// EC04d: the visitor is probably at this stop, but the position is uncertain.
    case lowConfidence(JourneyStop)

    struct Input {
        var coordinate: ProximiioCoordinate
        var level: Double?
        var horizontalAccuracy: Double
        var activeStop: JourneyStop?
    }

    /// `settings`: positions less accurate than `uncertainAccuracyMeters` are uncertain.
    static func evaluate(_ input: Input, settings: GADSettings = .standard) -> LocationAmbiguity? {
        let here = CLLocation(latitude: input.coordinate.latitude, longitude: input.coordinate.longitude)

        func sameLevel(_ level: Double?) -> Bool {
            guard let level, let visitor = input.level else { return true }
            return VenueLevel.same(level, visitor)
        }

        if input.horizontalAccuracy > settings.uncertainAccuracyMeters, let active = input.activeStop,
           sameLevel(active.floor?.level),
           here.distance(from: CLLocation(latitude: active.coordinate.latitude, longitude: active.coordinate.longitude)) <= input.horizontalAccuracy {
            return .lowConfidence(active)
        }
        return nil
    }

    /// The kind, for suppressing a prompt the visitor has just answered.
    var kind: String {
        switch self {
        case .lowConfidence: "low"
        }
    }
}
