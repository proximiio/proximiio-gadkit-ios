//
//  FieldLog.swift
//  ProximiioGADKit
//
//  A text log of positions, tracking health and journey events for field tests. Off until the
//  host app sets `FieldLog.isEnabled`; the Proximi GAD app turns it on in Debug and Staging
//  (TestFlight) builds. The file is `Documents/gad-debug.log`; `FieldLogShareButton` hands it
//  to the share sheet.
//
//  The file is cut to its last `keepBytes` when it grows past `maxBytes`.
//
import Foundation
import os
import OSLog
import SwiftUI

public enum FieldLog {
    static let maxBytes = 8_000_000
    static let keepBytes = 4_000_000

    /// `Documents/gad-debug.log`.
    public static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("gad-debug.log")

    private static let queue = DispatchQueue(label: "io.proximi.gad.fieldlog")
    private static let enabled = OSAllocatedUnfairLock(initialState: false)

    /// Whether `log` writes. `false` by default. Set it once at launch, before the first
    /// `VenueService.start`: the service starts its log tasks only when it is `true`.
    public static var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set { enabled.withLock { $0 = newValue } }
    }

    /// Appends one line with a time stamp. Also writes to standard error, which is unbuffered.
    /// Does nothing, and does not evaluate `message`, while `isEnabled` is `false`.
    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "[GAD] \(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message())\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async { append(Data(line.utf8)) }
    }

    /// Writes the header of a new session: app version, build and date.
    public static func logLaunch() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        log("launch \(version) (\(build)) \(Date().formatted(.iso8601))")
    }

    /// Copies this process's unified-log entries of `subsystem` and `category` to the field log
    /// every `interval`, until the calling task is cancelled. For SDK code that logs to os.Logger
    /// only, such as the visitor reporting client.
    public static func copyOSLogEntries(subsystem: String, category: String, every interval: Duration = .seconds(15)) async {
        var since = Date()
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@", subsystem, category)
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
                  let entries = try? store.getEntries(at: store.position(date: since), matching: predicate)
            else { continue }
            for case let entry as OSLogEntryLog in entries where entry.date > since {
                log("os \(category): \(entry.composedMessage)")
                since = entry.date
            }
        }
    }

    private static func append(_ data: Data) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        handle.write(data)
        if size + UInt64(data.count) > UInt64(maxBytes) { truncate() }
    }

    private static func truncate() {
        guard let data = try? Data(contentsOf: url), data.count > keepBytes else { return }
        var tail = data.suffix(keepBytes)
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) { tail = tail[(newline + 1)...] }
        try? Data(tail).write(to: url)
    }
}

/// Shares `Documents/gad-debug.log`, for example by Mail or AirDrop.
public struct FieldLogShareButton: View {
    public init() {}

    public var body: some View {
        ShareLink(item: FieldLog.url) {
            Label { Text(verbatim: "Share debug log") } icon: { Image(systemName: "ladybug") }
        }
    }
}
