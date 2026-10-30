//
//  TrackingMonitor.swift
//  ProximiioGADKit
//
//  Reports when the wristband stops delivering positions during a visit (Figma "Wristband",
//  edge cases "Lost tracking mid-narration" and "Device removed or battery dead"). `VisitView`
//  reports the state as `VisitEvent.trackingChanged` and shows no alert (PM 2026-10-15).
//
//  The signal is `Proximiio.positioningAvailabilityChanges()`: it turns `false` about 10 s
//  after the last fix from the relay provider, whether the socket failed or the tag went
//  silent. Unavailable for `GADSettings.trackingLostAfter` seconds is "lost your place";
//  unavailable for `trackingStoppedAfter` seconds is "stopped responding". The position stream is
//  not used for this: its timestamps are publish times, not fix times.
//
//  In a privacy zone (`Proximiio.privacyZoneStateChanges()`, SDK 6.0.0-beta.64) the state is
//  `.privacyZone`, however long the band is silent there: the visitor is not lost (Monday "Privacy
//  zones", 2026-10-19).
//
import Combine
import Foundation
import Proximiio

/// Whether the wristband delivers positions during a visit.
public enum TrackingHealth: Equatable, Sendable {
    /// Positioning has not been available yet in this visit.
    case waiting
    case tracking
    /// No positions for `GADSettings.trackingLostAfter` seconds.
    case lostPlace
    /// No positions for `GADSettings.trackingStoppedAfter` seconds, for example an empty battery.
    case stoppedResponding
    /// The visitor is in a privacy zone (`PrivacyZoneState.isPrivate`). The map holds a grey dot at
    /// the last position before the zone.
    case privacyZone

    /// `settings`: `trackingLostAfter` and `trackingStoppedAfter`. Pure; covered by tests.
    static func evaluate(wasEverAvailable: Bool, unavailableSince: Date?, isPrivate: Bool = false, now: Date, settings: GADSettings = .standard) -> TrackingHealth {
        if isPrivate { return .privacyZone }
        guard wasEverAvailable else { return .waiting }
        guard let unavailableSince else { return .tracking }
        let unavailable = now.timeIntervalSince(unavailableSince)
        if unavailable >= settings.trackingStoppedAfter { return .stoppedResponding }
        return unavailable >= settings.trackingLostAfter ? .lostPlace : .tracking
    }
}

@MainActor
final class TrackingMonitor: ObservableObject {
    @Published private(set) var health: TrackingHealth = .waiting
    @Published private(set) var lastCoordinate: ProximiioCoordinate?
    @Published private(set) var lastLevel: Double?
    @Published private(set) var lastAccuracy: Double?

    private var wasEverAvailable = false
    private var unavailableSince: Date?
    private var isPrivate = false
    private let sdk: Proximiio
    private let settings: GADSettings
    private var tasks: [Task<Void, Never>] = []

    init(sdk: Proximiio, settings: GADSettings = .standard) {
        self.sdk = sdk
        self.settings = settings
    }

    func start() {
        guard tasks.isEmpty else { return }
        // Last position, for "Probably at …".
        tasks.append(Task { [weak self] in
            guard let positions = await self?.sdk.positions() else { return }
            var logged = Date.distantPast
            for await update in positions {
                guard let self else { return }
                self.lastCoordinate = update.coordinate
                self.lastLevel = update.floor?.level
                self.lastAccuracy = update.horizontalAccuracy
                if Date().timeIntervalSince(logged) >= 1 {
                    logged = Date()
                    FieldLog.log(String(format: "position %@ %.6f,%.6f L%@ acc %.1f", update.source.rawValue,
                                           update.coordinate.latitude, update.coordinate.longitude,
                                           update.floor.map { String(Int($0.level)) } ?? "-", update.horizontalAccuracy))
                }
            }
        })
        // Availability: the signal for both alerts.
        tasks.append(Task { [weak self] in
            guard let changes = await self?.sdk.positioningAvailabilityChanges() else { return }
            for await isAvailable in changes {
                guard let self else { return }
                FieldLog.log("positioning available: \(isAvailable)")
                if isAvailable {
                    self.wasEverAvailable = true
                    self.unavailableSince = nil
                } else if self.unavailableSince == nil {
                    self.unavailableSince = Date()
                }
                self.reevaluate()
            }
        })
        // Privacy zone: the phone's own zone or the relay's `private`.
        tasks.append(Task { [weak self] in
            guard let changes = await self?.sdk.privacyZoneStateChanges() else { return }
            for await state in changes {
                guard let self else { return }
                FieldLog.log("privacy zone: private \(state.isPrivate) · zone \(state.isInPrivacyZone) · relay \(state.positioningSourcePrivateSince.map { $0.formatted(.iso8601) } ?? "-")")
                self.isPrivate = state.isPrivate
                self.reevaluate()
            }
        })
        // Moves "lost your place" to "stopped responding" while nothing else changes.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.reevaluate()
                if FieldLog.isEnabled {
                    let connections = await self.sdk.positionProviderConnections()
                    FieldLog.log("connections \(connections.mapValues(\.rawValue)) health \(self.health)")
                }
            }
        })
    }

    private func reevaluate() {
        let health = TrackingHealth.evaluate(wasEverAvailable: wasEverAvailable, unavailableSince: unavailableSince, isPrivate: isPrivate, now: Date(), settings: settings)
        guard health != self.health else { return }
        FieldLog.log("tracking health: \(health)")
        self.health = health
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// The nearest place on `level`, by straight-line distance. Pure; covered by tests.
    nonisolated static func nearest(to coordinate: ProximiioCoordinate?, level: Double?, in places: [VenuePlace]) -> VenuePlace? {
        guard let coordinate else { return nil }
        let candidates = places.filter { VenueLevel.matches($0.level, level) }
        return candidates.min {
            squaredDistance($0.coordinate, coordinate) < squaredDistance($1.coordinate, coordinate)
        }
    }

    private nonisolated static func squaredDistance(_ a: ProximiioCoordinate, _ b: ProximiioCoordinate) -> Double {
        let dLat = a.latitude - b.latitude
        let dLon = (a.longitude - b.longitude) * cos(a.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }
}
