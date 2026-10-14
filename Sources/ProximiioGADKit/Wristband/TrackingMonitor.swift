//
//  TrackingMonitor.swift
//  ProximiioGADKit
//
//  Reports when the wristband stops delivering positions during a visit (Figma "Wristband",
//  edge cases "Lost tracking mid-narration" and "Device removed or battery dead").
//
//  The signal is `Proximiio.positioningAvailabilityChanges()`: it turns `false` about 10 s
//  after the last fix from the relay provider, whether the socket failed or the tag went
//  silent. Unavailable for `GADSettings.trackingLostAfter` seconds is "lost your place";
//  unavailable for `trackingStoppedAfter` seconds is "stopped responding". The position stream is not used for this: its timestamps are
//  publish times, not fix times.
//
import Foundation
import Observation
import Proximiio

enum TrackingHealth: Equatable, Sendable {
    /// Positioning has not been available yet in this visit. Nothing is shown.
    case waiting
    case tracking
    /// "We've lost your place in the room".
    case lostPlace
    /// "Your wristband has stopped responding".
    case stoppedResponding

    /// `settings`: `trackingLostAfter` and `trackingStoppedAfter`. Pure; covered by tests.
    static func evaluate(wasEverAvailable: Bool, unavailableSince: Date?, now: Date, settings: GADSettings = .standard) -> TrackingHealth {
        guard wasEverAvailable else { return .waiting }
        guard let unavailableSince else { return .tracking }
        let unavailable = now.timeIntervalSince(unavailableSince)
        if unavailable >= settings.trackingStoppedAfter { return .stoppedResponding }
        return unavailable >= settings.trackingLostAfter ? .lostPlace : .tracking
    }
}

@MainActor
@Observable
final class TrackingMonitor {
    private(set) var health: TrackingHealth = .waiting
    private(set) var lastFix: Date?
    private(set) var lastCoordinate: ProximiioCoordinate?
    private(set) var lastLevel: Double?
    private(set) var lastAccuracy: Double?

    private var wasEverAvailable = false
    private var unavailableSince: Date?
    private let sdk: Proximiio
    private let settings: GADSettings
    private var tasks: [Task<Void, Never>] = []

    init(sdk: Proximiio, settings: GADSettings = .standard) {
        self.sdk = sdk
        self.settings = settings
    }

    func start() {
        guard tasks.isEmpty else { return }
        // Last position, for "Last Seen".
        tasks.append(Task { [weak self] in
            guard let positions = await self?.sdk.positions() else { return }
            var logged = Date.distantPast
            for await update in positions {
                guard let self else { return }
                self.lastFix = update.timestamp
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
        let health = TrackingHealth.evaluate(wasEverAvailable: wasEverAvailable, unavailableSince: unavailableSince, now: Date(), settings: settings)
        guard health != self.health else { return }
        FieldLog.log("tracking health: \(health)")
        self.health = health
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// "Gallery 2, 9:38": the nearest place on the last floor and the time of the last position.
    func lastSeen(in places: [VenuePlace]) -> String? {
        guard let lastFix else { return nil }
        let time = lastFix.formatted(date: .omitted, time: .shortened)
        guard let place = Self.nearest(to: lastCoordinate, level: lastLevel, in: places) else { return time }
        return "\(place.title), \(time)"
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
