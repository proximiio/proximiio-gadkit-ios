//
//  VenueDataRefresh.swift
//  ProximiioGADKit
//
//  Follows changes of the venue data while the app runs. The screens read the data when they open
//  and again when `version` changes.
//
//  The SDK's audit sync applies the changes of features, geofences, floors and places every
//  `ProximiioConfiguration.syncInterval` (300 s by default), and `Proximiio.venueDataChanges()` names the kinds whose stored data changed (SDK
//  6.0.0-beta.61). After a sync pass that changed features the SDK has already rebuilt the route
//  network. Nothing is downloaded here.
//
//  The open map redraws the changed features, floors, places and geofences itself (map
//  6.0.0-beta.47). A running `JourneyNavigator` routes its legs again only on
//  `routeNetworkChanged()`, which `VisitView` calls on a change of `.features`.
//
import Foundation
import Observation
import Proximiio

@MainActor
@Observable
final class VenueDataRefresh {
    /// Changes when the features, geofences, floors or places changed.
    private(set) var version = 0
    /// The kinds of the last change, set before `version` changes.
    @ObservationIgnored private(set) var changedKinds: Set<VenueDataKind> = []
    /// Runs after `version` changed. Set by `ProximiMap`.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let sdk: Proximiio
    /// The stored features, sorted by id.
    @ObservationIgnored private var features: [ProximiioFeature] = []
    @ObservationIgnored private var follow: Task<Void, Never>?

    /// The kinds the screens read.
    nonisolated static let watchedKinds: Set<VenueDataKind> = [.features, .geofences, .floors, .places]

    init(sdk: Proximiio) {
        self.sdk = sdk
    }

    /// Call after the first `loadRouteNetwork()` or `loadCachedRouteNetwork()`. A second call while
    /// the changes are followed does nothing.
    func start() async {
        guard follow == nil else { return }
        features = Self.sorted(await sdk.features())
        let changes = await sdk.venueDataChanges()
        follow = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                await self.apply(change.kinds)
            }
        }
    }

    /// Ends the follow-up. `ProximiMapView` calls it when it closes.
    func stop() {
        follow?.cancel()
        follow = nil
    }

    private func apply(_ kinds: Set<VenueDataKind>) async {
        let watched = kinds.intersection(Self.watchedKinds)
        guard !watched.isEmpty else { return }
        var description = watched.map(\.rawValue).sorted().joined(separator: ", ")
        if watched.contains(.features) {
            let features = Self.sorted(await sdk.features())
            description += " (\(Self.changes(from: self.features, to: features)))"
            self.features = features
        }
        changedKinds = watched
        version += 1
        FieldLog.log("venue data changed · \(description) · version \(version)")
        onChange?()
    }

    nonisolated static func sorted(_ features: [ProximiioFeature]) -> [ProximiioFeature] {
        features.sorted { $0.id < $1.id }
    }

    /// The difference between two feature lists, by id. Pure; covered by tests.
    nonisolated static func changes(from old: [ProximiioFeature], to new: [ProximiioFeature]) -> Changes {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Changes(
            added: after.keys.filter { before[$0] == nil }.count,
            removed: before.keys.filter { after[$0] == nil }.count,
            changed: after.filter { id, feature in before[id].map { $0 != feature } ?? false }.count
        )
    }

    struct Changes: Equatable, CustomStringConvertible {
        var added = 0
        var removed = 0
        var changed = 0

        var isEmpty: Bool { added == 0 && removed == 0 && changed == 0 }
        var description: String { "\(added) added, \(removed) removed, \(changed) changed" }
    }
}
