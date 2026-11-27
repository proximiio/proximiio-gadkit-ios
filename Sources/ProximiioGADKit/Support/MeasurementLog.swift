//
//  MeasurementLog.swift
//  ProximiioGADKit
//
//  Field log lines for the measurements of the contract KPIs (Metis T-1950, 2026-11-27). They
//  change no behaviour and have no setting.
//
//      search category <title> (<screen>): <n> places · nearest <title> L<level> · <ms> ms
//      search text <n> chars (<screen>): <n> of <n> places · <ms> ms
//      explore list <tab>: <n> items · shown in <ms> ms
//      destination <title>: <outcome> in <ms> ms
//      drawn position <map>: <lat>,<lng> L<level> · at <epoch ms> · fix <lat>,<lng> ts <epoch ms> · relay <lat>,<lng> ts <epoch ms>
//      relay positions: <n> in <s> s
//
//  Times of a search and of a filter count from the call to the result on the device. Coordinates
//  have 7 decimals, about 1 cm.
//
import Foundation
import os
import Proximiio
import ProximiioMap

enum MeasurementLog {
    // MARK: Search and filter

    /// The whole milliseconds from `start` to now.
    static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = (ContinuousClock.now - start).components
        return Int(((Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) * 1000).rounded())
    }

    /// The nearest place of `shortcut`, as `AmenityShortcut.nearest(in:from:level:)`, with a
    /// `search category` line.
    static func nearest(of shortcut: AmenityShortcut, in places: [VenuePlace], from coordinate: ProximiioCoordinate?,
                        level: Double?, screen: String) -> VenuePlace? {
        let start = ContinuousClock.now
        let matching = places.filter(shortcut.matches)
        let nearest = AmenityShortcut.nearest(of: matching, from: coordinate, level: level)
        FieldLog.log(categoryLine(title: shortcut.title, screen: screen, results: matching.count, nearest: nearest,
                                  milliseconds: milliseconds(since: start)))
        return nearest
    }

    /// Pure; covered by tests.
    static func categoryLine(title: String, screen: String, results: Int, nearest: VenuePlace?, milliseconds: Int) -> String {
        let place = nearest.map { "\($0.title) L\(Int($0.level.rounded()))" } ?? "none"
        return "search category \(title) (\(screen)): \(results) places · nearest \(place) · \(milliseconds) ms"
    }

    /// The length of the last text search that got a line, by screen. A SwiftUI body runs the same
    /// search again at every render.
    private static let loggedSearches = OSAllocatedUnfairLock(initialState: [String: String]())

    /// The places with `query` in their title, as `VenuePlace.matching(_:in:)`, with a `search text`
    /// line for each new query that is not empty. The line holds the length of the query, not its
    /// text.
    static func places(matching query: String, in places: [VenuePlace], screen: String) -> [VenuePlace] {
        let start = ContinuousClock.now
        let result = VenuePlace.matching(query, in: places)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = loggedSearches.withLock { logged -> Bool in
            guard logged[screen] != needle else { return false }
            logged[screen] = needle
            return true
        }
        if isNew, !needle.isEmpty {
            FieldLog.log(textLine(characters: needle.count, screen: screen, results: result.count, places: places.count,
                                  milliseconds: milliseconds(since: start)))
        }
        return result
    }

    /// Pure; covered by tests.
    static func textLine(characters: Int, screen: String, results: Int, places: Int, milliseconds: Int) -> String {
        "search text \(characters) chars (\(screen)): \(results) of \(places) places · \(milliseconds) ms"
    }

    /// Pure; covered by tests.
    static func listLine(tab: String, items: Int, milliseconds: Int) -> String {
        "explore list \(tab): \(items) items · shown in \(milliseconds) ms"
    }

    /// Pure; covered by tests.
    static func destinationLine(title: String, outcome: String, milliseconds: Int) -> String {
        "destination \(title): \(outcome) in \(milliseconds) ms"
    }

    // MARK: Drawn position

    /// The last position of the relay-api the binding's provider gave, before the SDK processes it.
    /// `BindingFieldLog` and `VenueService` set it for every sample while the field log is on.
    static let latestRelayPosition = OSAllocatedUnfairLock<CustomPositionSample?>(initialState: nil)

    /// What one `drawn position` line holds.
    struct DrawnSample: Equatable {
        /// The centre of the position dot in the last frame the map drew.
        var drawn: MapCoordinate
        /// The position of the SDK the dot moves toward, with its floor and its time.
        var fix: MapCoordinate?
        var level: Double?
        var fixTime: Date?
        /// The last position of the relay-api, with the time of the positioning engine (`ts`).
        var relay: ProximiioCoordinate?
        var relayTime: Date?
    }

    /// The sample of `session` now. `nil` while the map draws no position dot.
    @MainActor
    static func drawnSample(of session: ProximiioMapSession) -> DrawnSample? {
        guard let frame = session.renderer?.frame, let drawn = frame.drawn else { return nil }
        let relay = latestRelayPosition.withLock { $0 }
        return DrawnSample(drawn: drawn.coordinate, fix: frame.position?.coordinate, level: frame.position?.floor?.level,
                           fixTime: frame.position?.timestamp, relay: relay?.coordinate, relayTime: relay?.timestamp)
    }

    /// Pure; covered by tests.
    static func drawnLine(_ sample: DrawnSample, map: String, now: Date) -> String {
        let level = sample.level.map { String(Int($0.rounded())) } ?? "-"
        let fix = sample.fix.map { "\(text($0.latitude, $0.longitude)) ts \(sample.fixTime.map(epoch) ?? "-")" } ?? "-"
        let relay = sample.relay.map { "\(text($0.latitude, $0.longitude)) ts \(sample.relayTime.map(epoch) ?? "-")" } ?? "-"
        return "drawn position \(map): \(text(sample.drawn.latitude, sample.drawn.longitude)) L\(level) · at \(epoch(now))"
            + " · fix \(fix) · relay \(relay)"
    }

    private static func text(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.7f,%.7f", latitude, longitude)
    }

    /// Milliseconds since 1970, the unit of the relay-api `ts`.
    private static func epoch(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    // MARK: Position rate

    /// Counts the positions of the relay-api and gives a `relay positions` line for every
    /// `interval` seconds. The line is written with the first position after the interval, so a
    /// gap in the positions shows as a longer time.
    struct RateLog {
        static let interval: TimeInterval = 60

        private var start: TimeInterval?
        private var count = 0

        /// Counts a position at `now` (seconds of a monotonic clock). Pure; covered by tests.
        mutating func position(at now: TimeInterval) -> String? {
            guard let start else {
                self.start = now
                count = 0
                return nil
            }
            count += 1
            guard now - start >= Self.interval else { return nil }
            defer {
                self.start = now
                count = 0
            }
            return String(format: "relay positions: %d in %.1f s", count, now - start)
        }
    }
}
