//
//  StopNearbyDetector.swift
//  ProximiioGADKit
//
//  Detects when the next stop of the journey (the navigator's active stop) is less than
//  `GADSettings.stopNearbyMeters` away, on the visitor's level. Each stop counts once per visit.
//  `VisitView` reports it as `VisitEvent.stopNearby`; the host app can post a notification for it.
//
//  The distance is the route still to walk (`RouteGuidance.remainingMeters`) while the visitor
//  follows the leg. It is a straight line when there is no guidance (the field log of 2026-10-14
//  shows an active stop without one) or when the visitor is off the route: `remainingMeters` is
//  then measured from the nearest point of the route, not from the visitor.
//
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap

@MainActor
final class StopNearbyDetector {
    private let nearbyMeters: CLLocationDistance
    private var reportedStopIDs: Set<String> = []

    init(nearbyMeters: CLLocationDistance = GADSettings.standard.stopNearbyMeters) {
        self.nearbyMeters = nearbyMeters
    }

    /// `stop` when it is nearby for the first time in this visit, else `nil`. `guidance` is the
    /// navigator's guidance for the leg to `stop`.
    func update(position: VenuePosition?, stop: JourneyStop?, guidance: RouteGuidance?) -> JourneyStop? {
        guard let position, let stop, !reportedStopIDs.contains(stop.id),
              Self.isNearby(position.coordinate.proximiio, level: position.floor?.level,
                            stop: stop.coordinate.proximiio, stopLevel: stop.floor?.level,
                            routeMeters: guidance.flatMap { $0.isOffRoute ? nil : $0.remainingMeters },
                            within: nearbyMeters)
        else { return nil }
        reportedStopIDs.insert(stop.id)
        FieldLog.log("stop nearby: \(stop.title)")
        return stop
    }

    /// `true` when `stop` is on the visitor's level and less than `nearbyMeters` away: `routeMeters`
    /// when set, else the straight line from `position`. An unknown level matches any level. Pure;
    /// covered by tests.
    nonisolated static func isNearby(
        _ position: ProximiioCoordinate, level: Double?, stop: ProximiioCoordinate, stopLevel: Double?,
        routeMeters: Double? = nil, within nearbyMeters: CLLocationDistance = GADSettings.standard.stopNearbyMeters
    ) -> Bool {
        guard VenueLevel.matches(level, stopLevel) else { return false }
        if let routeMeters { return routeMeters < nearbyMeters }
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)
        return here.distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude)) < nearbyMeters
    }
}
