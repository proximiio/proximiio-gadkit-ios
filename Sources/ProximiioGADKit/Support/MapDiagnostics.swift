//
//  MapDiagnostics.swift
//  ProximiioGADKit
//
//  Field log only. The state of a map session, written when it changes: the venue features on the
//  map, the features the last push left out, the last error, where the style came from, the shown
//  floor, the zoom and the style's fonts the glyph server does not have. For the floor plan that is
//  missing on the journey map at a high zoom (PM, Monday "Floorplan disappears zometimes",
//  2026-10-27): a MapLibre shape source takes the venue's collection whole or not at all.
//  Also the time from a map view's appearance to the map showing the venue and to its first fully
//  drawn frame (`ProximiioMapSession.venueDrawing`, map 6.0.0-beta.56; 2026-10-28).
//
import Combine
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
        /// The style's font stacks the glyph server answered "not found" for, sorted.
        var missingFonts: [String] = []

        var line: String {
            let zoomText = zoom.map { String(format: "%.1f", $0) } ?? "-"
            return "map state \(name): features \(features) · dropped \(dropped) · style \(style) · L\(Int(level.rounded())) · zoom \(zoomText) · camera ready \(isCameraReady)"
                + (missingFonts.isEmpty ? "" : " · missing fonts \(missingFonts.joined(separator: ", "))")
                + (error.map { " · error \($0)" } ?? "")
        }

        /// Set by `follow(_:name:)`.
        var name = ""

        static func rounded(zoom: Double?) -> Double? {
            zoom.map { ($0 * 2).rounded() / 2 }
        }
    }

    /// The time from a map view's appearance to each step of the map showing the venue. Pure;
    /// covered by tests.
    struct Timing: Equatable {
        struct Style: Equatable {
            var source: String
            var isVenue: Bool
            var seconds: Double
        }

        var name = ""
        /// Seconds from `ProximiMap.open(_:)` to the view's appearance, when a screen was opened.
        var openSeconds: Double?
        /// Each style the map took, in order.
        var styles: [Style] = []
        var features: Int?
        var featuresSeconds: Double?
        var cameraSeconds: Double?
        /// The first frame drawn with the venue's features, tiles, icons and labels
        /// (`VenueDrawing.drawn`).
        var drawnSeconds: Double?

        /// The venue's first style, its features and the camera, whichever came last.
        var shownSeconds: Double? {
            guard let style = styles.first(where: \.isVenue), let featuresSeconds, let cameraSeconds else { return nil }
            return max(style.seconds, featuresSeconds, cameraSeconds)
        }

        /// - Parameter closedSeconds: when the view went before the map drew the venue.
        func line(closedSeconds: Double? = nil) -> String {
            var parts = styles.map { "style \($0.source) \(Self.text($0.seconds))" }
            if let features, let featuresSeconds { parts.append("features \(features) \(Self.text(featuresSeconds))") }
            if let cameraSeconds { parts.append("camera ready \(Self.text(cameraSeconds))") }
            if let shownSeconds { parts.append("shown \(Self.text(shownSeconds))") }
            if let drawnSeconds {
                parts.append("drawn \(Self.text(drawnSeconds))" + (openSeconds.map { ", \(Self.text(drawnSeconds + $0)) after open()" } ?? ""))
            } else if let closedSeconds {
                parts.append("closed \(Self.text(closedSeconds)) before drawn")
            }
            return "map timing \(name): " + parts.joined(separator: " · ")
        }

        static func text(_ seconds: Double) -> String {
            String(format: "%.2f s", seconds)
        }
    }

    /// When `ProximiMap.open(_:)` was last called. The next map timing counts from it too.
    static var openedAt: ContinuousClock.Instant?

    /// The seconds from `start` to now.
    static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = (ContinuousClock.now - start).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    /// Records `Timing` from the session's published state, which the map sets on the main
    /// thread, and writes it once: when the map has drawn the venue, or at `close()`. A style the
    /// map takes, or a drawing of the venue, after that gets a line of its own: two drawings in one
    /// opening mean the style was loaded twice.
    @MainActor
    final class TimingRecorder {
        private let start = ContinuousClock.now
        private var timing = Timing()
        private var styleSubscription: AnyCancellable?
        private var drawingSubscription: AnyCancellable?
        private var subscriptions: [AnyCancellable] = []
        private var isWritten = false

        init(session: ProximiioMapSession, name: String) {
            timing.name = name
            timing.openSeconds = MapDiagnostics.openedAt.map { MapDiagnostics.seconds(since: $0) }
            MapDiagnostics.openedAt = nil
            styleSubscription = session.$styleSource.removeDuplicates().sink { [weak self] source in
                MainActor.assumeIsolated { self?.styleChanged(source) }
            }
            drawingSubscription = session.$venueDrawing.removeDuplicates().sink { [weak self] drawing in
                MainActor.assumeIsolated { self?.drawingChanged(drawing) }
            }
            subscriptions = [
                session.$featureCount.first { $0 > 0 }.sink { [weak self] count in
                    MainActor.assumeIsolated { self?.featuresShown(count) }
                },
                session.$isCameraReady.first { $0 }.sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.cameraReady() }
                },
            ]
        }

        /// Writes what was recorded, unless the map drew the venue before, and stops.
        func close() {
            write(closedSeconds: MapDiagnostics.seconds(since: start))
            styleSubscription = nil
            drawingSubscription = nil
        }

        private func drawingChanged(_ drawing: ProximiioMapSession.VenueDrawing) {
            guard drawing == .drawn else { return }
            let seconds = MapDiagnostics.seconds(since: start)
            if isWritten {
                FieldLog.log("map timing \(timing.name): drawn again \(Timing.text(seconds))")
            } else {
                timing.drawnSeconds = seconds
                write(closedSeconds: nil)
            }
        }

        private func styleChanged(_ source: ProximiioMapSession.StyleSource) {
            guard source != .pending else { return }
            let style = Timing.Style(source: String(describing: source), isVenue: source.isVenue,
                                     seconds: MapDiagnostics.seconds(since: start))
            if isWritten {
                FieldLog.log("map timing \(timing.name): style \(style.source) \(Timing.text(style.seconds)) after drawn")
            } else {
                timing.styles.append(style)
            }
        }

        private func featuresShown(_ count: Int) {
            timing.features = count
            timing.featuresSeconds = MapDiagnostics.seconds(since: start)
        }

        private func cameraReady() {
            timing.cameraSeconds = MapDiagnostics.seconds(since: start)
        }

        private func write(closedSeconds: Double?) {
            guard !isWritten else { return }
            isWritten = true
            subscriptions.removeAll()
            FieldLog.log(timing.line(closedSeconds: closedSeconds))
        }
    }

    /// Writes the state of `session` to the field log when it changes, checked every second, until
    /// the task is cancelled, and the time the map takes to show the venue (`Timing`), counted from
    /// the call. Does nothing when the field log is off.
    static func follow(_ session: ProximiioMapSession, name: String) async {
        guard FieldLog.isEnabled else { return }
        let timing = TimingRecorder(session: session, name: name)
        defer { timing.close() }
        var last: Snapshot?
        while !Task.isCancelled {
            var snapshot = Snapshot(
                features: session.featureCount,
                dropped: session.droppedFeatureCount,
                error: session.lastError,
                style: String(describing: session.styleSource),
                level: session.selectedFloor.level,
                zoom: Snapshot.rounded(zoom: session.camera.zoomLevel),
                isCameraReady: session.isCameraReady,
                missingFonts: session.unavailableFontStacks.sorted()
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
