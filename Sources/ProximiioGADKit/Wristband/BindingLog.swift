//
//  BindingLog.swift
//  ProximiioGADKit
//
//  Field log text for the wristband binding: the bind, the session of an
//  active state and the binding client's diagnostics. The bind and session lines hold the relay's
//  binding id, which the relay-api logs also hold. The bind line holds the band's label as
//  scanned, so the relay team can look up the band without asking the tester (relay-api,
//  2026-10-28). No line holds a visitor id or a token.
//
//  Times are ISO 8601 in UTC, like the `FieldLog` time stamps.
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

enum BindingLog {
    /// "binding <id> · ends <time> · token expires <time>", plus "signal lost since <time>" while
    /// the venue does not hear the band, or "privacy zone since <time>" while it is silent in a
    /// privacy zone. `nil` without an active session.
    static func session(of state: BlueiotBindingState) -> String? {
        guard case let .active(session, _, signal) = state else { return nil }
        var parts = [
            "binding \(session.bindingID.uuidString.lowercased())",
            "ends \(session.endsAt.formatted(.iso8601))",
            "token expires \(session.tokenExpiresAt.formatted(.iso8601))",
        ]
        switch signal {
        case let .lost(since): parts.append("signal lost since \(since.formatted(.iso8601))")
        case let .privacyZone(since): parts.append("privacy zone since \(since.formatted(.iso8601))")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// "tag <label> · started" before the bind request.
    static func bindStarted(label: String) -> String {
        "tag \(label) · started"
    }

    /// "tag <label> · binding <id>" after a bind.
    static func bind(label: String, bindingID: UUID) -> String {
        "tag \(label) · binding \(bindingID.uuidString.lowercased())"
    }

    /// "tag <label> · failed: <error>" after a refused or failed bind.
    static func bind(label: String, error: any Error) -> String {
        "tag \(label) · failed: \(error)"
    }

    /// Every counter of `diagnostics` on one line. `lastError` and `lastRequestID` are added
    /// when set; the request id matches the relay-api request log.
    static func diagnostics(_ diagnostics: BlueiotBindingDiagnostics) -> String {
        var parts = [
            diagnostics.transport.rawValue + (diagnostics.usesPolling ? " polling" : ""),
            "connections \(diagnostics.connections)",
            "reconnects \(diagnostics.reconnects)",
            "keep-alive age \(seconds(diagnostics.secondsSinceLastKeepAlive))",
            "token left \(seconds(diagnostics.tokenSecondsRemaining))",
            "refreshes \(diagnostics.refreshes)",
            "rebinds \(diagnostics.automaticRebinds)",
            "stale closes \(diagnostics.staleClosesIgnored)",
            "positions \(diagnostics.positionsDelivered)",
            "repeats dropped \(diagnostics.repeatedPositionsDropped)",
        ]
        if let error = diagnostics.lastError { parts.append("last error \(error)") }
        if let requestID = diagnostics.lastRequestID { parts.append("request \(requestID)") }
        return parts.joined(separator: " · ")
    }

    private static func seconds(_ value: TimeInterval?) -> String {
        value.map { String(format: "%.1f s", $0) } ?? "-"
    }
}

public extension FieldLog {
    /// Binds this phone to the band with `tagID` through `binding`, as `binding.bind(tagID:)` does,
    /// and writes the attempt to the field log:
    ///
    ///     wristband bind: tag <label> · started
    ///     wristband bind: tag <label> · binding <id>
    ///     wristband bind: tag <label> · failed: <error>
    ///
    /// The first line is written before the request, so an attempt that does not return, or that
    /// the app cancels, is in the log too (Nagarro, 2026-11-22 and 23: "Tag not connecting" and
    /// a `CancellationError` left no line). A host app that binds itself calls this in place of
    /// `binding.bind(tagID:)`.
    ///
    /// - Returns: The session of the bind.
    /// - Throws: What `binding.bind(tagID:)` throws.
    @discardableResult
    static func bind(tagID: String, with binding: BlueiotWristbandBinding) async throws -> BlueiotBindingSession {
        try await logged(tagID: tagID) { try await binding.bind(tagID: tagID) }
    }

    /// The lines of `bind(tagID:with:)` around `bind`. Covered by tests.
    internal static func logged(
        tagID: String, bind: () async throws -> BlueiotBindingSession
    ) async throws -> BlueiotBindingSession {
        log("wristband bind: \(BindingLog.bindStarted(label: tagID))")
        do {
            let session = try await bind()
            log("wristband bind: \(BindingLog.bind(label: tagID, bindingID: session.bindingID))")
            return session
        } catch {
            log("wristband bind: \(BindingLog.bind(label: tagID, error: error))")
            throw error
        }
    }
}
