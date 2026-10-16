//
//  RouteAccessibilityTests.swift
//  ProximiioGADKitTests
//
import Proximiio
import Testing
@_spi(GADApp) @testable import ProximiioGADKit

struct RouteAccessibilityTests {
    @Test func noNeedAvoidsNothing() {
        let options = RouteAccessibility.none.routeOptions
        #expect(options.profile == .pedestrian)
        #expect(options.effectiveAvoidances.isEmpty)
    }

    @Test func eachNeedIsOneAvoidance() {
        #expect(RouteAccessibility(avoidsStairs: true).routeOptions.effectiveAvoidances == [.staircases])
        #expect(RouteAccessibility(avoidsEscalators: true).routeOptions.effectiveAvoidances == [.escalators])
        #expect(RouteAccessibility(avoidsRevolvingDoors: true).routeOptions.effectiveAvoidances == [.revolvingDoors])
        #expect(RouteAccessibility(avoidsInaccessiblePaths: true).routeOptions.effectiveAvoidances == [.narrowPaths])
    }

    @Test func allNeedsTogether() {
        let all = RouteAccessibility(avoidsStairs: true, avoidsEscalators: true, avoidsRevolvingDoors: true, avoidsInaccessiblePaths: true)
        #expect(all.routeOptions.effectiveAvoidances == [.staircases, .escalators, .revolvingDoors, .narrowPaths])
    }

    @Test func theAccessibleRoutesButtonAvoidsAllFour() {
        let host = RouteAccessibility(avoidsStairs: true)
        #expect(RouteAccessibility.effective(hostNeeds: host, accessibleRoutes: false) == host)
        let on = RouteAccessibility.effective(hostNeeds: host, accessibleRoutes: true)
        #expect(on.routeOptions.effectiveAvoidances == [.staircases, .escalators, .revolvingDoors, .narrowPaths])
    }

    #if DEBUG
    @Test func launchArgumentSetsTheNeeds() {
        let launch = DebugLaunch(arguments: ["app", "-routeAvoid", "stairs, revolvingDoors"])
        #expect(launch.routeAccessibility == RouteAccessibility(avoidsStairs: true, avoidsRevolvingDoors: true))
        #expect(DebugLaunch(arguments: ["app"]).routeAccessibility == .none)
    }
    #endif
}
