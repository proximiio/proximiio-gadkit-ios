//
//  BindingFieldLog.swift
//  ProximiioGADKit
//
//  Field log lines of a wristband binding in the fixed form the relay-api parses for its
//  wristband timeline (relay-api, Metis T-1797, 2026-11-16):
//
//      relay stream: open · binding <uuid> · <sse|ws|poll>
//      relay stream: closed · binding <uuid> · <cause>
//      relay position: ts <engine time, epoch ms> · age <ms>
//
//  A stream is open while the binding's link is online. The cause of a close is the state that
//  followed, plus the binding's last error when it has one. A position line is written for the
//  first position and then at most every `positionInterval` seconds.
//
//  For a host app on `ProximiMapView`, which owns its binding, `follow(_:logsStates:)` with `true`
//  also writes the `wristband:`, `wristband session:` and `binding diagnostics:` lines that
//  `WristbandSession` writes for `ProximiMap`.
//
import Foundation
import os
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

enum BindingFieldLog {
    /// Seconds between two `relay position:` lines.
    static let positionInterval: TimeInterval = 5

    private static let tasks = OSAllocatedUnfairLock(initialState: [Task<Void, Never>]())

    /// Follows `binding` until the next call. `logsStates` adds the state, session and diagnostics
    /// lines. Does nothing while the field log is off.
    static func follow(_ binding: BlueiotWristbandBinding, logsStates: Bool) {
        let old = tasks.withLock { tasks -> [Task<Void, Never>] in
            defer { tasks = [] }
            return tasks
        }
        old.forEach { $0.cancel() }
        MeasurementLog.latestRelayPosition.withLock { $0 = nil }
        guard FieldLog.isEnabled else { return }
        var new: [Task<Void, Never>] = []
        new.append(Task {
            var stream = StreamLog()
            for await state in binding.stateChanges() {
                let diagnostics = await binding.diagnostics
                if logsStates {
                    FieldLog.log("wristband: \(WristbandCopy.logLine(for: state))")
                    if let session = BindingLog.session(of: state) { FieldLog.log("wristband session: \(session)") }
                    FieldLog.log("binding diagnostics: \(BindingLog.diagnostics(diagnostics))")
                }
                for line in stream.lines(for: state, diagnostics: diagnostics) { FieldLog.log(line) }
            }
        })
        new.append(Task {
            var last: TimeInterval?
            var rate = MeasurementLog.RateLog()
            for await sample in binding.positionProvider.samples() {
                let now = ProcessInfo.processInfo.systemUptime
                MeasurementLog.latestRelayPosition.withLock { $0 = sample }
                if let line = rate.position(at: now) { FieldLog.log(line) }
                guard Self.logsPosition(now: now, last: last) else { continue }
                last = now
                FieldLog.log(Self.positionLine(timestamp: sample.timestamp, now: Date()))
            }
        })
        if logsStates {
            new.append(Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard case .active = await binding.state else { continue }
                    let diagnostics = await binding.diagnostics
                    FieldLog.log("binding diagnostics: \(BindingLog.diagnostics(diagnostics))")
                }
            })
        }
        let started = new
        tasks.withLock { $0 = started }
    }

    /// Whether a position at `now` gets a line, `last` being the time of the last line. Pure;
    /// covered by tests.
    static func logsPosition(now: TimeInterval, last: TimeInterval?) -> Bool {
        guard let last else { return true }
        return now - last >= positionInterval
    }

    /// "relay position: ts <engine ms> · age <ms>". Pure; covered by tests.
    static func positionLine(timestamp: Date, now: Date) -> String {
        let engine = Int64((timestamp.timeIntervalSince1970 * 1000).rounded())
        let age = Int64((now.timeIntervalSince(timestamp) * 1000).rounded())
        return "relay position: ts \(engine) · age \(age)"
    }

    /// Turns the binding states into the `relay stream:` lines. Pure; covered by tests.
    struct StreamLog {
        /// The binding of the open stream.
        private(set) var open: UUID?

        mutating func lines(for state: BlueiotBindingState, diagnostics: BlueiotBindingDiagnostics) -> [String] {
            var lines: [String] = []
            let online: UUID? = if case let .active(session, link, _) = state, link == .online { session.bindingID } else { nil }
            if let open, open != online {
                var cause = WristbandCopy.logLine(for: state)
                if let error = diagnostics.lastError { cause += " · \(error)" }
                lines.append("relay stream: closed · binding \(open.uuidString.lowercased()) · \(cause)")
                self.open = nil
            }
            if let online, open == nil {
                lines.append("relay stream: open · binding \(online.uuidString.lowercased()) · \(Self.transport(diagnostics))")
                open = online
            }
            return lines
        }

        static func transport(_ diagnostics: BlueiotBindingDiagnostics) -> String {
            if diagnostics.usesPolling { return "poll" }
            return diagnostics.transport == .serverSentEvents ? "sse" : "ws"
        }
    }
}
