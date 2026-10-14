//
//  VenueLevel.swift
//  ProximiioGADKit
//
//  Level comparison. A level is a `Double`, and a mezzanine can be 1.5. Rounding to an integer
//  would merge level 1.5 with level 2, so levels are compared with a tolerance.
//
import Foundation

enum VenueLevel {
    /// Two levels closer than this are the same level.
    static let tolerance = 0.01

    /// `true` when `a` and `b` are the same level. Pure; covered by tests.
    static func same(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < tolerance
    }

    /// `true` when either level is unknown or both are the same level. Pure; covered by tests.
    static func matches(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return true }
        return same(a, b)
    }
}
