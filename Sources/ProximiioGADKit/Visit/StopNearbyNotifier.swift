//
//  StopNearbyNotifier.swift
//  ProximiioGADKit
//
//  Posts a local notification when the next stop of the journey (the navigator's active stop) is
//  less than `nearbyMeters` away, on the visitor's level. Each stop posts once per visit. The
//  title is the stop title.
//
//  The distance is the route still to walk (`RouteGuidance.remainingMeters`) while the visitor
//  follows the leg. It is a straight line when there is no guidance (the field log of 2026-10-14
//  shows an active stop without one) or when the visitor is off the route: `remainingMeters` is
//  then measured from the nearest point of the route, not from the visitor.
//
//  `GeofenceNotifier` requests the authorization and shows notifications in the foreground.
//
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap
import UserNotifications

@MainActor
final class StopNearbyNotifier {
    nonisolated static let nearbyMeters: CLLocationDistance = 5

    private var notifiedStopIDs: Set<String> = []
    private let post: @MainActor (UNNotificationRequest) -> Void

    /// `post` delivers the notification. The default adds it to `UNUserNotificationCenter`. A test
    /// process without a host app has no notification center, so tests pass their own.
    init(post: @escaping @MainActor (UNNotificationRequest) -> Void = { request in
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }) {
        self.post = post
    }

    /// Posts the notification when `stop` is nearby and has not posted one in this visit.
    /// `guidance` is the navigator's guidance for the leg to `stop`.
    /// - Returns: `stop` when it posted the notification, else `nil`.
    @discardableResult
    func update(position: VenuePosition?, stop: JourneyStop?, guidance: RouteGuidance?) -> JourneyStop? {
        guard let position, let stop, !notifiedStopIDs.contains(stop.id),
              Self.isNearby(position.coordinate.proximiio, level: position.floor?.level,
                            stop: stop.coordinate.proximiio, stopLevel: stop.floor?.level,
                            routeMeters: guidance.flatMap { $0.isOffRoute ? nil : $0.remainingMeters })
        else { return nil }
        notifiedStopIDs.insert(stop.id)
        let request = Self.request(for: stop)
        FieldLog.log("notification: \(request.identifier) \(stop.title)")
        post(request)
        return stop
    }

    /// `true` when `stop` is on the visitor's level and less than `nearbyMeters` away: `routeMeters`
    /// when set, else the straight line from `position`. An unknown level matches any level. Pure;
    /// covered by tests.
    nonisolated static func isNearby(
        _ position: ProximiioCoordinate, level: Double?, stop: ProximiioCoordinate, stopLevel: Double?,
        routeMeters: Double? = nil
    ) -> Bool {
        guard VenueLevel.matches(level, stopLevel) else { return false }
        if let routeMeters { return routeMeters < nearbyMeters }
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)
        return here.distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude)) < nearbyMeters
    }

    /// The notification for `stop`. Pure; covered by tests.
    nonisolated static func request(for stop: JourneyStop) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = stop.title
        content.body = String(localized: "The next stop of your journey is less than \(Int(nearbyMeters)) m away.", bundle: .module)
        content.threadIdentifier = "journey"
        return UNNotificationRequest(identifier: "stop-nearby-\(stop.id)", content: content, trigger: nil)
    }
}
