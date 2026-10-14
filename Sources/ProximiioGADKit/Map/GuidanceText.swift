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

    /// The instruction line, e.g. "Turn left in 50 m".
    static func instruction(for guidance: RouteGuidance) -> String {
        if guidance.hasArrived { return String(localized: "You have arrived", bundle: .module) }
        if guidance.isOffRoute { return String(localized: "You have left the route", bundle: .module) }
        let metres = Int(guidance.distanceToManoeuvreMeters.rounded())
        switch guidance.manoeuvre?.kind {
        case .turnLeft, .turnSharpLeft: return String(localized: "Turn left in \(metres) m", bundle: .module)
        case .turnSlightLeft: return String(localized: "Bear left in \(metres) m", bundle: .module)
        case .turnRight, .turnSharpRight: return String(localized: "Turn right in \(metres) m", bundle: .module)
        case .turnSlightRight: return String(localized: "Bear right in \(metres) m", bundle: .module)
        case .levelChange(let change):
            let level = Int(change.toLevel.rounded())
            return String(localized: "Take the \(levelChanger(change.featureType)) to level \(level)", bundle: .module)
        case .arrive: return String(localized: "Arrive in \(metres) m", bundle: .module)
        default: return String(localized: "Head straight for \(metres) m", bundle: .module)
        }
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
