//
//  LogPlayback.swift
//  ProximiioGADKit
//
//  Debug builds only. Plays the positions of a field log as a position provider, so a walk
//  recorded on site runs again in the simulator. See `DebugLaunch` (`-logPlayback`).
//
#if DEBUG
import Foundation
import Proximiio

/// One position of a field log.
struct LogPlaybackSample: Equatable, Sendable {
    /// Seconds since the first sample of the played part.
    var offset: TimeInterval
    var latitude: Double
    var longitude: Double
    var level: Int
    var accuracy: Double
}

enum LogPlayback {
    /// The positions in `text` between `from` and `to` (`HH:mm:ss`, UTC, inclusive) on `day`
    /// (`yyyy-MM-dd`). Reads the `position custom` lines: `[GAD] <day>T<time>Z position custom
    /// <lat>,<lng> L<level> acc <metres>`. `day` nil takes every day; then `from` and `to` compare
    /// the time of day alone. Pure; covered by tests.
    static func samples(in text: String, day: String?, from: String?, to: String?) -> [LogPlaybackSample] {
        var samples: [LogPlaybackSample] = []
        var first: TimeInterval?
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("[GAD] "), line.count > 40 else { continue }
            let stamp = line.dropFirst(6).prefix(24)
            let parts = stamp.split(separator: "T")
            guard parts.count == 2, let seconds = seconds(of: parts[1]) else { continue }
            if let day, parts[0] != day { continue }
            let time = parts[1].prefix(8)
            if let from, time < from { continue }
            if let to, time > to { continue }
            let message = line.dropFirst(6).drop { $0 != " " }.dropFirst()
            guard message.hasPrefix("position custom ") else { continue }
            let fields = message.dropFirst("position custom ".count).split(separator: " ")
            let coordinate = fields.first?.split(separator: ",") ?? []
            guard fields.count >= 4, coordinate.count == 2,
                  let latitude = Double(coordinate[0]), let longitude = Double(coordinate[1]),
                  fields[1].hasPrefix("L"), let level = Int(fields[1].dropFirst()),
                  let accuracy = Double(fields[3])
            else { continue }
            let absolute = seconds
            let start = first ?? absolute
            first = start
            // A log over midnight: the time of day starts again.
            let offset = absolute >= start ? absolute - start : absolute - start + 86400
            samples.append(LogPlaybackSample(offset: offset, latitude: latitude, longitude: longitude, level: level, accuracy: accuracy))
        }
        return samples
    }

    /// Seconds of the day of `HH:mm:ss.SSSZ`.
    private static func seconds(of time: Substring) -> TimeInterval? {
        let fields = time.dropLast(time.hasSuffix("Z") ? 1 : 0).split(separator: ":")
        guard fields.count == 3, let hours = Double(fields[0]), let minutes = Double(fields[1]), let seconds = Double(fields[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

/// Plays `samples` at `speed`. The positions carry the time they are played at.
final class LogPlaybackProvider: CustomPositionProviding, @unchecked Sendable {
    let name = "log-playback"
    let runsInBackground = true
    private let positions: [LogPlaybackSample]
    private let speed: Double
    private let floorIDs: [Int: String]
    private let lock = NSLock()
    private var continuations: [AsyncStream<CustomPositionSample>.Continuation] = []
    private var task: Task<Void, Never>?

    init(samples: [LogPlaybackSample], speed: Double, floorIDs: [Int: String]) {
        self.positions = samples
        self.speed = max(speed, 0.1)
        self.floorIDs = floorIDs
    }

    func samples() -> AsyncStream<CustomPositionSample> {
        AsyncStream { continuation in
            lock.withLock { continuations.append(continuation) }
        }
    }

    func start() async {
        guard lock.withLock({ task == nil }) else { return }
        let samples = positions, speed = speed, floorIDs = floorIDs
        let played = Task { [weak self] in
            let start = ContinuousClock.now
            for sample in samples {
                try? await Task.sleep(until: start + .seconds(sample.offset / speed))
                guard !Task.isCancelled, let self else { return }
                let position = CustomPositionSample(
                    coordinate: ProximiioCoordinate(latitude: sample.latitude, longitude: sample.longitude),
                    horizontalAccuracy: sample.accuracy, floorID: floorIDs[sample.level], timestamp: .now, sourceName: self.name)
                for continuation in self.lock.withLock({ self.continuations }) { continuation.yield(position) }
            }
            FieldLog.log("log playback: the last position is played")
        }
        lock.withLock { task = played }
    }

    func stop() async {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }

    var connection: CustomPositionProviderConnection { get async { .online } }
    func connectionChanges() -> AsyncStream<CustomPositionProviderConnection>? { nil }
}
#endif
