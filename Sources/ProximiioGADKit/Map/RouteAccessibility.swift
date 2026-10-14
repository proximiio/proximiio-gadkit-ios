//
//  RouteAccessibility.swift
//  ProximiioGADKit
//
//  The visitor's accessibility needs for routes. The host app sets them on its views with
//  `routeAccessibility(_:)`, for example from its settings screen. The museum map and the journey
//  use them for every route they compute; a change re-routes the route on screen.
//
//  Each need is an SDK avoidance (`RouteOptions.Avoidance`) and works only where the venue data
//  marks it:
//  - stairs: level changers with `type` `staircase`
//  - escalators: level changers with `type` `escalator`
//  - revolving doors: `door` point features with a `radius`; the route keeps that distance
//  - inaccessible paths: routing paths with `narrowPath: true`
//
import Proximiio
import SwiftUI

public struct RouteAccessibility: Codable, Hashable, Sendable {
    public var avoidsStairs: Bool
    public var avoidsEscalators: Bool
    public var avoidsRevolvingDoors: Bool
    /// Paths the venue data marks as narrow (`narrowPath`).
    public var avoidsInaccessiblePaths: Bool

    public init(
        avoidsStairs: Bool = false,
        avoidsEscalators: Bool = false,
        avoidsRevolvingDoors: Bool = false,
        avoidsInaccessiblePaths: Bool = false
    ) {
        self.avoidsStairs = avoidsStairs
        self.avoidsEscalators = avoidsEscalators
        self.avoidsRevolvingDoors = avoidsRevolvingDoors
        self.avoidsInaccessiblePaths = avoidsInaccessiblePaths
    }

    /// No need set: routes may use every path.
    public static let none = RouteAccessibility()

    /// The SDK route options: the pedestrian profile with these avoidances.
    public var routeOptions: RouteOptions {
        var avoid: Set<RouteOptions.Avoidance> = []
        if avoidsStairs { avoid.insert(.staircases) }
        if avoidsEscalators { avoid.insert(.escalators) }
        if avoidsRevolvingDoors { avoid.insert(.revolvingDoors) }
        if avoidsInaccessiblePaths { avoid.insert(.narrowPaths) }
        return RouteOptions(profile: .pedestrian, avoid: avoid)
    }
}

private struct RouteAccessibilityKey: EnvironmentKey {
    static let defaultValue = RouteAccessibility.none
}

extension EnvironmentValues {
    var routeAccessibility: RouteAccessibility {
        get { self[RouteAccessibilityKey.self] }
        set { self[RouteAccessibilityKey.self] = newValue }
    }
}

extension View {
    /// The accessibility needs that `MuseumMapScreen` and `VisitView` in this view use for routes.
    /// A change re-routes the route on screen. Default `RouteAccessibility.none`.
    public func routeAccessibility(_ accessibility: RouteAccessibility) -> some View {
        environment(\.routeAccessibility, accessibility)
    }
}
