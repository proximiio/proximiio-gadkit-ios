//
//  GeofenceNotifier.swift
//  ProximiioGADKit
//
//  Posts a local notification when the visitor enters or leaves a geofence. The title is the
//  geofence name. Every geofence type posts one: galleries, artworks and any other type. A
//  geofence without a name posts nothing. Privacy zones post nothing.
//
//  Authorization is requested once a wristband session is active, because geofence events need
//  positions from the band. Figma has no notification pre-prompt yet (01.04), so iOS shows its
//  own dialog. Notifications also show while the app is in the foreground.
//
//  A notification replaces the earlier one of the same geofence and direction. Walking along a
//  geofence edge leaves one enter and one exit notification per geofence, not a stack.
//
import Foundation
import Proximiio
import UserNotifications

@MainActor
public final class GeofenceNotifier {
    /// The notification center keeps a weak reference to its delegate.
    private static let presenter = ForegroundPresenter()

    public init() {}

    /// Asks for authorization to show alerts. iOS shows its dialog only while the decision is
    /// undetermined.
    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }

    /// Posts a notification for every geofence enter and exit event of `sdk`. Returns when the
    /// stream finishes or the calling task is cancelled.
    public func run(sdk: Proximiio) async {
        let center = UNUserNotificationCenter.current()
        center.delegate = Self.presenter
        for await event in await sdk.geofenceEvents() {
            guard let request = Self.request(for: event) else { continue }
            FieldLog.log("notification: \(request.identifier) \(request.content.title)")
            try? await center.add(request)
        }
    }

    /// The notification for a geofence enter or exit, or `nil` for a geofence without a name and
    /// for privacy zones. Pure; covered by tests.
    nonisolated static func request(for event: GeofenceEvent) -> UNNotificationRequest? {
        let geofence: ProximiioGeofence
        let direction: String
        let body: String
        switch event {
        case .entered(let entered):
            (geofence, direction, body) = (entered, "entered", String(localized: "You entered this area.", bundle: .module))
        case .exited(let exited, _):
            (geofence, direction, body) = (exited, "exited", String(localized: "You left this area.", bundle: .module))
        default:
            return nil
        }
        guard let name = geofence.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = body
        content.threadIdentifier = "geofence"
        return UNNotificationRequest(identifier: "geofence-\(direction)-\(geofence.id)", content: content, trigger: nil)
    }
}

/// Shows notifications while the app is in the foreground. iOS does not show them by default.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
