//
//  LevelChange.swift
//  ProximiioGADKit
//
//  Floor changes and lift rides of the visitor. The journey screen and the museum map move the map
//  to the visitor's floor when the position changes floor (`followsVisitorFloor(_:venue:)`). The
//  level change animation over the map was removed (PM 2026-10-15).
//
//  A floor counts as changed after `confirmations` consecutive fixes on the new floor. The default
//  is 1: the map switches floors on the first fix on the new floor.
//
//  A lift ride: positions stay inside a lift outline for `GADSettings.liftRideDwell` seconds. The
//  field log records the ride and the route's floor at that lift.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct LevelChange: Equatable, Identifiable {
    var from: Int
    var to: Int
    var id: String { "\(from)-\(to)" }
    var isUp: Bool { to > from }
}

struct LevelChangeDetector {
    var confirmations = 1
    private(set) var level: Int?
    private var candidate: Int?
    private var candidateFixes = 0

    /// Swift 6.2 (Xcode 26.3) makes the memberwise initializer private because of the private
    /// stored properties.
    init(confirmations: Int = 1) {
        self.confirmations = confirmations
    }

    /// Feeds the floor of one fix. Returns the change when the new floor is confirmed. The first
    /// floor seen is no change.
    mutating func update(level fixLevel: Double?) -> LevelChange? {
        guard let fixLevel else { return nil }
        let next = Int(fixLevel.rounded())
        guard let current = level else {
            level = next
            return nil
        }
        guard next != current else {
            candidate = nil
            candidateFixes = 0
            return nil
        }
        if candidate == next {
            candidateFixes += 1
        } else {
            candidate = next
            candidateFixes = 1
        }
        guard candidateFixes >= confirmations else { return nil }
        level = next
        candidate = nil
        candidateFixes = 0
        return LevelChange(from: current, to: next)
    }
}

/// A lift cabin outline: a venue polygon feature of type `elevator`. The outline is drawn on one
/// floor, and a lift shaft is vertical, so it applies on every floor.
struct LiftArea {
    let outline: Gallery

    static func all(features: [ProximiioFeature]) -> [LiftArea] {
        features.compactMap { feature in
            guard feature.propertyType == "elevator", let geometry = feature.geometry,
                  let ring = Gallery.outerRing(type: geometry.type, coordinates: geometry.coordinates) else { return nil }
            return LiftArea(outline: Gallery(id: feature.id, name: "", level: 0, ring: ring))
        }
    }

    func contains(_ coordinate: ProximiioCoordinate) -> Bool {
        outline.contains(coordinate, level: nil)
    }

    /// The floor a ride in this lift goes to: the target of the route's next level change when it
    /// leaves `from` by this lift. A level change by stairs or by another lift is not this ride
    /// (PM 2026-10-15: a visitor in a lift saw "Level 3", the target of the route's stairs).
    /// Pure; covered by tests.
    func rideTarget(of change: RouteLevelChange?, from: Int) -> Int? {
        guard let change, change.featureType == "elevator", Int(change.fromLevel.rounded()) == from,
              contains(ProximiioCoordinate(latitude: change.coordinate.latitude, longitude: change.coordinate.longitude))
        else { return nil }
        return Int(change.toLevel.rounded())
    }
}

/// Detects a ride: the visitor counts as in the lift after `dwell` seconds of fixes inside a lift
/// area, so walking past a lift is no ride. The ride ends after `exitFixes` consecutive fixes
/// outside.
struct LiftDetector {
    enum Event: Equatable { case boarded, left }

    var dwell: TimeInterval
    var exitFixes: Int
    private(set) var isRiding = false
    private var insideSince: Date?
    private var outsideFixes = 0

    init(dwell: TimeInterval = GADSettings.standard.liftRideDwell, exitFixes: Int = GADSettings.standard.liftExitFixes) {
        self.dwell = dwell
        self.exitFixes = exitFixes
    }

    mutating func update(inLift: Bool, at time: Date) -> Event? {
        if inLift {
            outsideFixes = 0
            let since = insideSince ?? time
            insideSince = since
            guard !isRiding, time.timeIntervalSince(since) >= dwell else { return nil }
            isRiding = true
            return .boarded
        }
        outsideFixes += 1
        guard outsideFixes >= exitFixes else { return nil }
        insideSince = nil
        guard isRiding else { return nil }
        isRiding = false
        return .left
    }
}

extension View {
    /// Moves the map to the visitor's floor when the session's position changes floor, and logs
    /// lift rides. While `isPaused` the map keeps its floor (a floor without positioning).
    func followsVisitorFloor(_ session: ProximiioMapSession, venue: VenueService, isPaused: Bool = false) -> some View {
        modifier(VisitorFloorModifier(session: session, venue: venue, isPaused: isPaused))
    }
}

private struct VisitorFloorModifier: ViewModifier {
    let session: ProximiioMapSession
    let venue: VenueService
    let isPaused: Bool
    @State private var floors = LevelChangeDetector()
    @State private var lift = LiftDetector()
    @State private var lifts: [LiftArea] = []
    /// The lift the last fix was in.
    @State private var currentLift: LiftArea?

    func body(content: Content) -> some View {
        content
            .task {
                lift = LiftDetector(dwell: venue.settings.liftRideDwell, exitFixes: venue.settings.liftExitFixes)
                lifts = LiftArea.all(features: await venue.sdk.features())
            }
            .onReceive(session.$position) { position in
                if let position { update(with: position) }
            }
    }

    private func update(with position: VenuePosition) {
        let coordinate = ProximiioCoordinate(latitude: position.coordinate.latitude, longitude: position.coordinate.longitude)
        let area = lifts.first { $0.contains(coordinate) }
        if let area { currentLift = area }
        let event = lift.update(inLift: area != nil, at: .now)
        if let change = floors.update(level: position.floor?.level) {
            FieldLog.log("level change: L\(change.from) → L\(change.to)\(isPaused ? " (map keeps its floor)" : "")")
            if !isPaused { session.followMyFloor() }
            return
        }
        if event == .boarded, let from = floors.level {
            FieldLog.log("lift boarded on L\(from), target \(routeTarget(from: from).map { "L\($0)" } ?? "unknown")")
        }
    }

    /// The target floor of the route's next manoeuvre when it is a level change from `from` by the
    /// lift the visitor is in.
    private func routeTarget(from: Int) -> Int? {
        guard case .levelChange(let change)? = session.guidance?.manoeuvre?.kind else { return nil }
        return currentLift?.rideTarget(of: change, from: from)
    }
}
