//
//  BindingLog.swift
//  ProximiioGADKit
//
//  Field log text for the wristband binding: the session of an
//  active state and the binding client's diagnostics. The session line holds the relay's binding
//  id, which the relay-api logs also hold. No line holds a tag id, a visitor id or a token.
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
