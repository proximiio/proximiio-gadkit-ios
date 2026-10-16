//
//  VenueDataRefresh.swift
//  ProximiioGADKit
//
//  Follows changes of the venue data while the app runs. The screens read the data when they open
//  and again when `version` changes.
//
//  - Features (POIs, paths, level changers): `loadRouteNetwork()` every
//    `GADSettings.venueDataRefreshInterval` seconds in the foreground and when the app returns to
//    the foreground. It downloads the features, stores them and rebuilds the route network. The
//    SDK sync does not bring feature changes: the audit feed of api.proximi.fi
//    (`/v5/audit/changes`) had no `Feature` record in the 30 days before 2026-10-16, while 500
//    features were created.
//  - Geofences, floors and places: the SDK sync applies them every 300 s. A `Feature` record of
//    the sync rebuilds the route network from the store.
//
//  The open map keeps the POIs it has drawn: the map library reads the features once per session
//  (map 6.0.0-beta.44).
//
import Foundation
import Observation
import Proximiio
import UIKit

@MainActor
@Observable
final class VenueDataRefresh {
    /// Changes when the features, geofences, floors or places changed.
    private(set) var version = 0
    /// Runs after `version` changed. Set by `ProximiMap`.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let sdk: Proximiio
    /// The stored features, sorted by id.
    @ObservationIgnored private var features: [ProximiioFeature] = []
    @ObservationIgnored private var isDownloading = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var foregroundObserver: (any NSObjectProtocol)?

    /// Entities of the SDK sync that the screens read.
    nonisolated static let watchedEntities: Set<String> = ["Feature", "Geofence", "Floor", "Place"]

    init(sdk: Proximiio) {
        self.sdk = sdk
    }

    /// Call after the first `loadRouteNetwork()`. With `interval` 0 only the SDK sync is followed.
    func start(interval: TimeInterval) async {
        features = Self.sorted(await sdk.features())
        tasks.append(Task { [weak self] in await self?.followSync() })
        guard interval > 0 else { return }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                if UIApplication.shared.applicationState != .background {
                    await self.download(reason: "interval")
                }
            }
        })
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.download(reason: "foreground") }
            }
        }
    }

    private func download(reason: String) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            _ = try await sdk.loadRouteNetwork()
        } catch {
            FieldLog.log("venue data: download failed (\(reason)): \(error.localizedDescription)")
            return
        }
        let features = Self.sorted(await sdk.features())
        let changes = Self.changes(from: self.features, to: features)
        guard !changes.isEmpty else { return }
        self.features = features
        changed("features (\(reason)): \(changes)")
    }

    private func followSync() async {
        var entities: Set<String> = []
        for await event in await sdk.syncEvents() {
            switch event {
            case .updated(let entity, _), .deleted(let entity, _):
                if Self.watchedEntities.contains(entity) { entities.insert(entity) }
            case .syncCompleted:
                guard !entities.isEmpty else { continue }
                if entities.contains("Feature") {
                    _ = await sdk.loadCachedRouteNetwork()
                    features = Self.sorted(await sdk.features())
                }
                changed("sync: \(entities.sorted().joined(separator: ", "))")
                entities = []
            default:
                break
            }
        }
    }

    private func changed(_ description: String) {
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
