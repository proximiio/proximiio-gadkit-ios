//
//  VenueDataRefresh.swift
//  ProximiioGADKit
//
//  Holds the venue's features, geofences and amenities in memory and follows their changes while
//  the app runs. The screens read the data when they open and again when `version` changes.
//
//  The SDK decodes every stored row on each `features()` call and serves one call at a time. With
//  the GAD venue's 995 features a call took about 0.5 s on the simulator (2026-10-29), and the map's
//  own read of the features waited behind the screens' reads. Each kind is read once here, and again
//  only after `venueDataChanges()` named it.
//
//  The SDK's audit sync applies the changes of features, geofences, floors and places every
//  `ProximiioConfiguration.syncInterval` (300 s by default), and `Proximiio.venueDataChanges()` names the kinds whose stored data changed (SDK
//  6.0.0-beta.61). After a sync pass that changed features the SDK has already rebuilt the route
//  network. Nothing is downloaded here, except the amenity catalogue when the SDK has none stored
//  (`Proximiio.amenities()`).
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
    /// Changes when the features, geofences, floors, places or amenities changed.
    private(set) var version = 0
    /// The kinds of the last change, set before `version` changes.
    @ObservationIgnored private(set) var changedKinds: Set<VenueDataKind> = []
    /// Runs after `version` changed. Set by `ProximiMap`.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored let sdk: Proximiio
    /// The reads every caller of `features()`, `geofences()` and `amenities()` waits for. `nil`
    /// until the first call, and after a change of the kind.
    @ObservationIgnored private var featuresRead: Task<[ProximiioFeature], Never>?
    @ObservationIgnored private var geofencesRead: Task<[ProximiioGeofence], Never>?
    @ObservationIgnored private var amenitiesRead: Task<[ProximiioAmenity], any Error>?
    @ObservationIgnored private var follow: Task<Void, Never>?

    /// Whether the changes are followed: after `start()`, until `stop()` or until the SDK stopped.
    var isFollowing: Bool { follow != nil }

    /// The kinds the screens read.
    nonisolated static let watchedKinds: Set<VenueDataKind> = [.features, .geofences, .floors, .places, .amenities]

    init(sdk: Proximiio) {
        self.sdk = sdk
    }

    /// Call after the first `loadRouteNetwork()` or `loadCachedRouteNetwork()`. Starts the reads of
    /// the features, geofences and amenities and returns without waiting for them. A second call
    /// while the changes are followed does nothing.
    func start() async {
        guard follow == nil else { return }
        // Subscribed before the reads, so a change during a read reads the kind again.
        let changes = await sdk.venueDataChanges()
        _ = featuresTask()
        _ = geofencesTask()
        _ = amenitiesTask()
        follow = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                await self.apply(change.kinds)
            }
            // The stream ends when the SDK stops. The SDK may have deleted the venue data.
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// Ends the follow-up and drops the data read, since the changes made from now on are not
    /// followed.
    func stop() {
        follow?.cancel()
        follow = nil
        featuresRead = nil
        geofencesRead = nil
        amenitiesRead = nil
    }

    /// The stored features, in the SDK's order.
    func features() async -> [ProximiioFeature] {
        await featuresTask().value
    }

    /// The stored geofences.
    func geofences() async -> [ProximiioGeofence] {
        await geofencesTask().value
    }

    /// The amenity catalogue, or none when the SDK has none stored and cannot download it. A
    /// failed read is not kept, so the next call asks the SDK again.
    func amenities() async -> [ProximiioAmenity] {
        let read = amenitiesTask()
        do {
            return try await read.value
        } catch {
            if amenitiesRead == read { amenitiesRead = nil }
            return []
        }
    }

    private func featuresTask() -> Task<[ProximiioFeature], Never> {
        if let featuresRead { return featuresRead }
        let read = Task { [sdk] in
            let started = ContinuousClock.now
            let features = await sdk.features()
            Self.logRead("\(features.count) features", since: started)
            return features
        }
        featuresRead = read
        return read
    }

    private func geofencesTask() -> Task<[ProximiioGeofence], Never> {
        if let geofencesRead { return geofencesRead }
        let read = Task { [sdk] in
            let started = ContinuousClock.now
            let geofences = await sdk.geofences()
            Self.logRead("\(geofences.count) geofences", since: started)
            return geofences
        }
        geofencesRead = read
        return read
    }

    private func amenitiesTask() -> Task<[ProximiioAmenity], any Error> {
        if let amenitiesRead { return amenitiesRead }
        let read = Task { [sdk] in
            let started = ContinuousClock.now
            let amenities = try await sdk.amenities()
            Self.logRead("\(amenities.count) amenities", since: started)
            return amenities
        }
        amenitiesRead = read
        return read
    }

    /// The time includes the wait for the SDK's earlier calls: the SDK serves one call at a time.
    private static func logRead(_ data: String, since started: ContinuousClock.Instant) {
        FieldLog.log("venue data: \(data) read in \(MapDiagnostics.Timing.text(MapDiagnostics.seconds(since: started)))")
    }

    private func apply(_ kinds: Set<VenueDataKind>) async {
        let watched = kinds.intersection(Self.watchedKinds)
        guard !watched.isEmpty else { return }
        var description = watched.map(\.rawValue).sorted().joined(separator: ", ")
        if watched.contains(.geofences) { geofencesRead = nil }
        if watched.contains(.amenities) { amenitiesRead = nil }
        if watched.contains(.features) {
            let old = await features()
            featuresRead = nil
            description += " (\(Self.changes(from: old, to: await features())))"
        }
        changedKinds = watched
        version += 1
        FieldLog.log("venue data changed · \(description) · version \(version)")
        onChange?()
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
