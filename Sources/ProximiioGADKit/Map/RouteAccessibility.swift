//
//  RouteAccessibility.swift
//  ProximiioGADKit
//
//  The visitor's accessibility needs for routes. The host app sets them on its views with
//  `routeAccessibility(_:)`, for example from its settings screen. The museum map and the journey
//  use them for every route they compute; a change re-routes the route on screen.
//
//  The maps also have an accessible routes button (wheelchair, PM 2026-10-14). While it is on,
//  routes avoid all four, whatever the host app set. Its state is kept in `UserDefaults`
//  (`accessibleRoutesKey`) for both maps and later launches.
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

    /// Every need set: the accessible routes button.
    public static let accessible = RouteAccessibility(
        avoidsStairs: true, avoidsEscalators: true, avoidsRevolvingDoors: true, avoidsInaccessiblePaths: true
    )

    /// The `UserDefaults` key of the accessible routes button.
    static let accessibleRoutesKey = "ProximiioGADKit.accessibleRoutes"

    /// `.accessible` while the button is on, else the host app's needs. Pure; covered by tests.
    static func effective(hostNeeds: RouteAccessibility, accessibleRoutes: Bool) -> RouteAccessibility {
        accessibleRoutes ? .accessible : hostNeeds
    }

    /// The SDK route options: the pedestrian profile with these avoidances.
    var routeOptions: RouteOptions {
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
    func routeAccessibility(_ accessibility: RouteAccessibility) -> some View {
        environment(\.routeAccessibility, accessibility)
    }
}

/// The accessible routes button of the maps: a wheelchair on glass while it is off; white on a
/// filled `Palette.position` square while it is on (PM 2026-10-14: an indicator for both states).
struct AccessibleRoutesButton: View {
    @Binding var isOn: Bool
    var onToggle: (Bool) -> Void = { _ in }

    var body: some View {
        Button {
            isOn.toggle()
            onToggle(isOn)
        } label: {
            Image(systemName: "figure.roll")
                .font(.system(size: 20, weight: .medium))
        }
        // On, and while pressed: a black outline, no colour (RPR, Monday "Accessible routing" and
        // "Buttons to have black border when pressed", 2026-10-28).
        .buttonStyle(SquareGlassButtonStyle(isSelected: isOn))
        .accessibilityLabel(Text("Accessible routes", bundle: .localized))
        .accessibilityValue(isOn ? Text("On", bundle: .localized) : Text("Off", bundle: .localized))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
