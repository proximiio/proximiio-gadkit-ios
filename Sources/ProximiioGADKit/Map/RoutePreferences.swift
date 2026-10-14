//
//  RoutePreferences.swift
//  ProximiioGADKit
//
//  The visitor's route preference, set in "My Profile". A step-free route uses the SDK's
//  wheelchair profile: no stairs, no escalators, no narrow paths. The museum map and the
//  journey read it when they compute a route.
//
import Foundation
import Proximiio

enum RoutePreferences {
    private static let key = "GuggenheimAbuDhabi.stepFreeRoutes"

    static func isStepFree(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func setStepFree(_ isStepFree: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(isStepFree, forKey: key)
    }

    /// The SDK route options for the preference.
    static func options(in defaults: UserDefaults = .standard) -> RouteOptions {
        RouteOptions(profile: isStepFree(in: defaults) ? .wheelchair : .pedestrian)
    }
}
