//
//  MapDiagnostics.swift
//  ProximiioGADKit
//
//  Field log only. The state of a map session, written when it changes: the venue features on the
//  map, the features the last push left out, the last error, where the style came from, the shown
//  floor and the zoom. For the floor plan that is missing on the journey map at a high zoom (PM,
//  Monday "Floorplan disappears zometimes", 2026-10-27): a MapLibre shape source takes the
//  venue's collection whole or not at all.
//
import Foundation
import ProximiioMap

@MainActor
enum MapDiagnostics {
    /// One state of a map session. Pure; covered by tests.
    struct Snapshot: Equatable {
        var features: Int
        var dropped: Int
        var error: String?
        var style: String
        var level: Double
        /// The zoom to 0.5.
        var zoom: Double?
        var isCameraReady: Bool

        var line: String {
            let zoomText = zoom.map { String(format: "%.1f", $0) } ?? "-"
            return "map state \(name): features \(features) · dropped \(dropped) · style \(style) · L\(Int(level.rounded())) · zoom \(zoomText) · camera ready \(isCameraReady)"
                + (error.map { " · error \($0)" } ?? "")
        }

        /// Set by `follow(_:name:)`.
        var name = ""

        static func rounded(zoom: Double?) -> Double? {
            zoom.map { ($0 * 2).rounded() / 2 }
        }
    }

    /// Writes the state of `session` to the field log when it changes, checked every second, until
    /// the task is cancelled. Does nothing when the field log is off.
    static func follow(_ session: ProximiioMapSession, name: String) async {
        guard FieldLog.isEnabled else { return }
        var last: Snapshot?
        while !Task.isCancelled {
            var snapshot = Snapshot(
                features: session.featureCount,
                dropped: session.droppedFeatureCount,
                error: session.lastError,
                style: String(describing: session.styleSource),
                level: session.selectedFloor.level,
                zoom: Snapshot.rounded(zoom: session.camera.zoomLevel),
                isCameraReady: session.isCameraReady
            )
            snapshot.name = name
            if snapshot != last {
                FieldLog.log(snapshot.line)
                last = snapshot
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
