//
//  FloorWithoutPositioning.swift
//  ProximiioGADKit
//
//  Guidance to a floor without positioning (PM 2026-10-15, Monday "POIs on floors with no
//  positioning"). In stage 1 the GAD level 0 has no positioning; the café and the prayer room are
//  there.
//
//  1. The route leads to the lift or stairs as usual.
//  2. Within `GADSettings.levelChangerReachedMeters` of the lift or stairs of a ride that ends on a
//     floor in `GADSettings.levelsWithoutPositioning`, the screen shows the lift or stairs view for
//     `GADSettings.levelChangeViewSeconds` (`FloorChangeView`; a tap ends it).
//  3. The map shows that floor with the rest of the route. It does not follow the visitor there.
//
//  The phase on that floor ends when the destination changes ("Resume your Journey", another
//  stop), on "Centre on me" or the floor button, or after
//  `GADSettings.floorWithoutPositioningMaximumSeconds`. The same destination then gets no second view.
//
//  `FloorChangeView` shows the lift or stairs icon until RPR's animation exists (Monday
//  "Elevator/Staircase view").
//
import Observation
import Proximiio
import ProximiioMap
import SwiftUI
import UIKit

@MainActor
@Observable
final class FloorWithoutPositioningGuide {
    /// The lift or stairs ride to a floor without positioning.
    struct Change: Equatable {
        /// The floor the ride ends on.
        var level: Int
        /// `elevator`, `staircase` or `escalator`.
        var featureType: String
        /// The lift or stairs.
        var coordinate: MapCoordinate
    }

    enum Phase: Equatable {
        case idle
        /// The lift or stairs view.
        case changing(Change)
        /// The map shows the floor without positioning.
        case onFloor(Change)
    }

    private(set) var phase: Phase = .idle
    /// Called when the map should show the floor of `Change`.
    @ObservationIgnored var onEnter: ((Change) -> Void)?
    /// Called when the map should follow the visitor again.
    @ObservationIgnored var onLeave: ((Change) -> Void)?

    @ObservationIgnored private let settings: GADSettings
    @ObservationIgnored private var destinationID: String?
    /// The destination whose phase ended; it gets no second view.
    @ObservationIgnored private var finishedDestinationID: String?
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(settings: GADSettings) {
        self.settings = settings
    }

    /// `true` from the lift or stairs view until the map follows the visitor again.
    var isActive: Bool { phase != .idle }

    /// Feeds a fix. `markers`: the route's level changes; `destinationID`: the leg's destination.
    func update(coordinate: MapCoordinate?, level: Double?, markers: [RouteGeometry.Marker], destinationID: String?) {
        if destinationID != self.destinationID {
            leave()
            self.destinationID = destinationID
            finishedDestinationID = nil
        }
        guard phase == .idle, let destinationID, destinationID != finishedDestinationID, let coordinate,
              let change = Self.reachedChange(coordinate: coordinate, level: level, markers: markers, settings: settings)
        else { return }
        FieldLog.log("floor without positioning: at the \(change.featureType) to L\(change.level)")
        phase = .changing(change)
        let seconds = settings.levelChangeViewSeconds
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.showFloor()
        }
    }

    /// Ends the lift or stairs view: the map shows the floor without positioning.
    func showFloor() {
        guard case .changing(let change) = phase else { return }
        timer?.cancel()
        phase = .onFloor(change)
        FieldLog.log("floor without positioning: showing L\(change.level)")
        onEnter?(change)
        let seconds = settings.floorWithoutPositioningMaximumSeconds
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.leave()
        }
    }

    /// The map follows the visitor again. The destination gets no second view.
    func leave() {
        timer?.cancel()
        timer = nil
        let previous = phase
        guard previous != .idle else { return }
        phase = .idle
        finishedDestinationID = destinationID
        if case .onFloor(let change) = previous {
            FieldLog.log("floor without positioning: following the visitor again")
            onLeave?(change)
        }
    }

    /// The route's next level change from the visitor's floor when its ride ends on a floor without
    /// positioning and the visitor is within `levelChangerReachedMeters` of it. Pure; covered by
    /// tests.
    nonisolated static func reachedChange(coordinate: MapCoordinate, level: Double?, markers: [RouteGeometry.Marker], settings: GADSettings) -> Change? {
        let pending = markers.filter { !$0.isCompleted }
        guard let level, let marker = pending.first(where: { VenueLevel.same($0.from.level, level) }) else { return nil }
        let end = GuidanceText.rideEnd(
            featureType: marker.featureType, coordinate: marker.coordinate,
            from: marker.from.level, to: marker.to.level, markers: pending
        )
        guard settings.levelsWithoutPositioning.contains(end),
              GeoMath.haversineDistance(from: coordinate.proximiio, to: marker.coordinate.proximiio) <= settings.levelChangerReachedMeters
        else { return nil }
        return Change(level: end, featureType: marker.featureType, coordinate: marker.coordinate)
    }

    /// Shows the floor of `change` and frames the route on it inside `padding`, the map area under
    /// the screen's controls and card.
    static func show(_ change: Change, on session: ProximiioMapSession, padding: UIEdgeInsets) {
        session.select(floor: FloorKey(level: Double(change.level)))
        let points = (session.routeRenderer?.geometry?.legs ?? [])
            .filter { VenueLevel.same($0.floor.level, Double(change.level)) }
            .flatMap(\.points)
        guard let bounds = MapGeometry.boundingBox(of: points + [change.coordinate]) else { return }
        session.camera.fit(bounds: bounds, padding: padding, animated: true)
    }
}

/// The lift or stairs view on the way to a floor without positioning: the icon, "Take the lift to
/// level 0" and that the position is not shown there. A tap ends it.
struct FloorChangeView: View {
    let change: FloorWithoutPositioningGuide.Change

    private var icon: GADIcon { change.featureType == "elevator" ? .elevator : .stairs }

    var body: some View {
        ZStack {
            Palette.white.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                icon.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Palette.position)
                    .frame(width: 140, height: 140)
                    .background(Palette.white, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.badgeStroke, lineWidth: 1.5))
                Text(GuidanceText.rideText(featureType: change.featureType, level: change.level))
                    .textStyle(.h1Bold)
                    .multilineTextAlignment(.center)
                Text("Your position is not shown on this level.", bundle: .module)
                    .textStyle(.bodySmallRegular)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("floorChangeView")
    }
}
