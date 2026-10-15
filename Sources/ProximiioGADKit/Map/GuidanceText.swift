//
//  GuidanceText.swift
//  ProximiioGADKit
//
//  Text and symbols for the navigation card ("MAP Functionality Approach 02",
//  node 10889:108082): "Head straight for 70 m", "70 m · <1 min", "Take the lift to level 2".
//  `RouteGuidance` carries no display strings; they are defined here.
//
import Foundation
import ProximiioMap

enum GuidanceText {
    /// Walking speed for the time estimate, in metres per second. 1.2 m/s gives the
    /// design's "70 m · <1 min".
    static let walkingSpeed = 1.2

    /// The instruction line, e.g. "Turn left in 50 m". `markers`: the route's level changes
    /// (`RouteGeometry.markers`), which give the floor a ride ends on (`rideEnd`).
    static func instruction(for guidance: RouteGuidance, markers: [RouteGeometry.Marker] = []) -> String {
        if guidance.hasArrived { return String(localized: "You have arrived", bundle: .module) }
        if guidance.isOffRoute { return String(localized: "You have left the route", bundle: .module) }
        let metres = Int(guidance.distanceToManoeuvreMeters.rounded())
        switch guidance.manoeuvre?.kind {
        case .turnLeft, .turnSharpLeft: return String(localized: "Turn left in \(metres) m", bundle: .module)
        case .turnSlightLeft: return String(localized: "Bear left in \(metres) m", bundle: .module)
        case .turnRight, .turnSharpRight: return String(localized: "Turn right in \(metres) m", bundle: .module)
        case .turnSlightRight: return String(localized: "Bear right in \(metres) m", bundle: .module)
        case .levelChange(let change):
            let level = rideEnd(featureType: change.featureType, coordinate: change.coordinate, from: change.fromLevel, to: change.toLevel, markers: markers)
            return String(localized: "Take the \(levelChanger(change.featureType)) to level \(level)", bundle: .module)
        case .arrive: return String(localized: "Arrive in \(metres) m", bundle: .module)
        default: return String(localized: "Head straight for \(metres) m", bundle: .module)
        }
    }

    /// The card title while the next stop is on another floor: the route's first level change
    /// that leaves the visitor's floor, e.g. "Take the stairs to level 3". A route from level 1 to
    /// level 4 can take the stairs to level 3 and then the lift. Without a level change on the
    /// route: "Go to level 4". Pure; covered by tests.
    static func levelChangeTitle(markers: [RouteGeometry.Marker], visitorLevel: Double?, stopLevel: Int) -> String {
        let pending = markers.filter { !$0.isCompleted }
        let fromHere = visitorLevel.flatMap { level in
            pending.first { Int($0.from.level.rounded()) == Int(level.rounded()) }
        }
        guard let change = fromHere ?? pending.first else {
            return String(localized: "Go to level \(stopLevel)", bundle: .module)
        }
        let level = rideEnd(featureType: change.featureType, coordinate: change.coordinate, from: change.from.level, to: change.to.level, markers: pending)
        return String(localized: "Take the \(levelChanger(change.featureType)) to level \(level)", bundle: .module)
    }

    /// The floor a ride in one staircase or lift ends on. The SDK router splits a ride into one
    /// level change per floor with paths near the staircase or lift: from level 1 to level 4 the
    /// stairs go to level 3, then from level 3 to level 4, at the same coordinate (Monday
    /// "Instructions guide first to level 3, then level 4", 2026-10-15). The level changes in
    /// `markers` that follow the one from `from` to `to`, with the same type and coordinate, are
    /// the same ride. Pure; covered by tests.
    static func rideEnd(featureType: String, coordinate: MapCoordinate, from: Double, to: Double, markers: [RouteGeometry.Marker]) -> Int {
        func isSameChanger(_ marker: RouteGeometry.Marker) -> Bool {
            marker.featureType == featureType && marker.coordinate == coordinate
        }
        var end = Int(to.rounded())
        guard let start = markers.firstIndex(where: {
            isSameChanger($0) && Int($0.from.level.rounded()) == Int(from.rounded()) && Int($0.to.level.rounded()) == end
        }) else { return end }
        for marker in markers[(start + 1)...] {
            guard isSameChanger(marker), Int(marker.from.level.rounded()) == end else { break }
            end = Int(marker.to.level.rounded())
        }
        return end
    }

    /// Remaining distance and time, e.g. "70 m · <1 min".
    static func remaining(metres: Double) -> String {
        let distance = Int(metres.rounded())
        return "\(String(localized: "\(distance) m", bundle: .module)) · \(walkingTime(metres: metres))"
    }

    /// "<1 min" below one minute, otherwise whole minutes rounded up.
    static func walkingTime(metres: Double) -> String {
        let seconds = max(0, metres) / walkingSpeed
        if seconds < 60 { return String(localized: "<1 min", bundle: .module) }
        let minutes = Int((seconds / 60).rounded(.up))
        return String(localized: "\(minutes) min", bundle: .module)
    }

    /// SF Symbol for the next manoeuvre.
    static func symbol(for guidance: RouteGuidance) -> String {
        if guidance.hasArrived { return "mappin.circle" }
        if guidance.isOffRoute { return "exclamationmark.triangle" }
        switch guidance.manoeuvre?.kind {
        case .turnLeft, .turnSharpLeft: return "arrow.turn.up.left"
        case .turnSlightLeft: return "arrow.up.left"
        case .turnRight, .turnSharpRight: return "arrow.turn.up.right"
        case .turnSlightRight: return "arrow.up.right"
        case .levelChange: return "arrow.up.arrow.down"
        default: return "arrow.up"
        }
    }

    /// Visitor-facing name of a level changer feature type.
    static func levelChanger(_ featureType: String) -> String {
        switch featureType {
        case "elevator": String(localized: "lift", bundle: .module)
        case "escalator": String(localized: "escalator", bundle: .module)
        case "staircase": String(localized: "stairs", bundle: .module)
        case "ramp": String(localized: "ramp", bundle: .module)
        default: featureType
        }
    }

    /// Floor chip label, e.g. "L1".
    static func floorLabel(_ level: Double) -> String {
        "L\(Int(level.rounded()))"
    }
}
