//
//  FieldLogUpload.swift
//  ProximiioGADKit
//
//  Sends the field log to the relay-api of the build (operator, 2026-11-16: the logs of every
//  tester on site are collected). The app sends the lines written since the last accepted upload
//  to `POST <relay>/v1/app-logs` with the relay app token, every `interval` seconds, at the start
//  and when the app goes to the background. A chunk that fails is sent again unchanged, with the
//  same sequence number, so the relay stores it once. The log goes only to the relay base URL the
//  host app set: a production build sends it to the client's relay.
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif
import UIKit

public extension FieldLog {
    /// The version of the package, sent with each upload.
    static let packageVersion = "1.65.1"

    /// Starts sending the field log to the relay-api of `binding`, with its app token. Call it once,
    /// after the host app created its `BlueiotWristbandBinding`. A second call replaces the first.
    /// Does nothing while `isEnabled` is `false`.
    ///
    /// - Parameter interval: Seconds between uploads. 0 or less sends nothing.
    ///
    /// It also writes the lines of `binding` to the log: its states, sessions, diagnostics, the
    /// relay stream and one relay position every 5 s. The relay-api links the log to the wristband
    /// through them.
    static func startUploading(binding: BlueiotWristbandBinding, interval: TimeInterval = 900) {
        BindingFieldLog.follow(binding, logsStates: true)
        startUploading(
            relayURL: binding.configuration.relayURL.baseURL, appToken: binding.configuration.appToken, interval: interval)
    }

    /// Starts sending the field log to `relayURL` (scheme and host of the relay-api) with `appToken`.
    static func startUploading(relayURL: URL, appToken: String, interval: TimeInterval = 900) {
        Task { await FieldLogUploader.shared.start(relayURL: relayURL, appToken: appToken, interval: interval) }
    }

    /// Stops the uploads. The log file stays.
    static func stopUploading() {
        Task { await FieldLogUploader.shared.stop() }
    }
}

/// Where the upload is in the log. Positions count bytes from the start of the log, so they hold
/// when `FieldLog` cuts the head of the file. Read and written on `FieldLog.queue`.
enum FieldLogUploadState {
    private static let removedKey = "GuggenheimAbuDhabi.fieldLog.removedBytes"
    private static let uploadedKey = "GuggenheimAbuDhabi.fieldLog.uploadedBytes"
    private static let sequenceKey = "GuggenheimAbuDhabi.fieldLog.sequence"
    private static let pendingKey = "GuggenheimAbuDhabi.fieldLog.pendingLength"
    private static let installKey = "GuggenheimAbuDhabi.fieldLog.install"

    /// Bytes `FieldLog` cut from the head of the file since the install.
    static func addRemoved(_ count: Int, in defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: removedKey) + count, forKey: removedKey)
    }

    /// A random id of this install.
    static func install(in defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: installKey) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: installKey)
        return id
    }

    /// The next chunk: its sequence number and bytes, or `nil` when every line is sent. A chunk
    /// that was sent and not accepted comes again with the same bytes. Call on `FieldLog.queue`.
    static func nextChunk(of file: Data, limit: Int, in defaults: UserDefaults = .standard) -> (sequence: Int, data: Data)? {
        let removed = defaults.integer(forKey: removedKey)
        var uploaded = defaults.integer(forKey: uploadedKey)
        var pending = defaults.integer(forKey: pendingKey)
        // The file is shorter than the place of the upload: it was deleted. Start at its head.
        if uploaded > removed + file.count { uploaded = removed; pending = 0 }
        // The head of the chunk was cut from the file: those lines are gone.
        if uploaded < removed { uploaded = removed; pending = 0 }
        defaults.set(uploaded, forKey: uploadedKey)
        let range = Self.chunkRange(fileCount: file.count, offset: uploaded - removed, pending: pending, limit: limit, file: file)
        guard let range else {
            defaults.set(0, forKey: pendingKey)
            return nil
        }
        defaults.set(range.count, forKey: pendingKey)
        return (defaults.integer(forKey: sequenceKey), file.subdata(in: range))
    }

    /// The byte range of the next chunk in `file`: `pending` bytes when a chunk waits, else up to
    /// `limit` bytes that end with a line. A line longer than `limit` is sent whole. Pure; covered
    /// by tests.
    static func chunkRange(fileCount: Int, offset: Int, pending: Int, limit: Int, file: Data) -> Range<Int>? {
        guard offset >= 0, offset < fileCount else { return nil }
        if pending > 0, offset + pending <= fileCount { return offset..<(offset + pending) }
        let end = min(fileCount, offset + max(1, limit))
        if end == fileCount {
            // Only whole lines: the last line may still be written.
            guard let newline = file[offset..<end].lastIndex(of: UInt8(ascii: "\n")) else { return nil }
            return offset..<(newline + 1)
        }
        if let newline = file[offset..<end].lastIndex(of: UInt8(ascii: "\n")) { return offset..<(newline + 1) }
        // One line longer than the limit.
        let next = file[end..<fileCount].firstIndex(of: UInt8(ascii: "\n")).map { $0 + 1 } ?? fileCount
        return offset..<next
    }

    /// The relay stored the chunk of `count` bytes. Call on `FieldLog.queue`.
    static func accepted(_ count: Int, in defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: uploadedKey) + count, forKey: uploadedKey)
        defaults.set(defaults.integer(forKey: sequenceKey) + 1, forKey: sequenceKey)
        defaults.set(0, forKey: pendingKey)
    }

    /// The relay refused the chunk for its size: the next one is cut again.
    static func forgetPending(in defaults: UserDefaults = .standard) {
        defaults.set(0, forKey: pendingKey)
    }
}

actor FieldLogUploader {
    static let shared = FieldLogUploader()

    private var loop: Task<Void, Never>?
    private var background: Task<Void, Never>?
    private var relayURL: URL?
    private var appToken = ""
    /// Bytes per request. Halved when the relay answers 413.
    private var chunkBytes = 512_000
    private var isSending = false
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func start(relayURL: URL, appToken: String, interval: TimeInterval) {
        stop()
        guard FieldLog.isEnabled, interval > 0, !appToken.isEmpty else { return }
        self.relayURL = relayURL
        self.appToken = appToken
        FieldLog.log("install \(FieldLogUploadState.install())")
        FieldLog.log("log upload: on · every \(Int(interval)) s · \(relayURL.host ?? "-")")
        loop = Task { [weak self] in
            // The first upload sends what a run that was killed left behind.
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.send()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        background = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                let task = await UIApplication.shared.beginBackgroundTask(withName: "gad-log-upload")
                await self?.send()
                await UIApplication.shared.endBackgroundTask(task)
            }
        }
    }

    func stop() {
        loop?.cancel()
        background?.cancel()
        loop = nil
        background = nil
        relayURL = nil
        appToken = ""
    }

    /// Sends the chunks that wait, at most 8 per call.
    func send() async {
        guard !isSending, let relayURL else { return }
        isSending = true
        // One line per run, written after the last chunk: a line per chunk would be the next chunk.
        var stored = 0
        var storedBytes = 0
        defer {
            isSending = false
            if stored > 0 { FieldLog.log("log upload: \(stored) chunks stored · \(storedBytes) bytes") }
        }
        for _ in 0..<8 {
            let limit = chunkBytes
            let chunk: (sequence: Int, data: Data)? = await withCheckedContinuation { continuation in
                FieldLog.queue.async {
                    let file = (try? Data(contentsOf: FieldLog.url)) ?? Data()
                    continuation.resume(returning: FieldLogUploadState.nextChunk(of: file, limit: limit))
                }
            }
            guard let chunk else { return }
            var request = URLRequest(url: relayURL.appendingPathComponent("v1/app-logs"))
            request.httpMethod = "POST"
            for (field, value) in Self.headers(sequence: chunk.sequence, appToken: appToken) {
                request.setValue(value, forHTTPHeaderField: field)
            }
            let status: Int
            do {
                let (_, response) = try await session.upload(for: request, from: chunk.data)
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch {
                FieldLog.log("log upload: \(chunk.sequence) failed: \(error.localizedDescription)")
                return
            }
            switch Self.outcome(of: status) {
            case .stored:
                await onQueue { FieldLogUploadState.accepted(chunk.data.count) }
                stored += 1
                storedBytes += chunk.data.count
            case .tooLarge:
                chunkBytes = max(16_000, chunkBytes / 2)
                await onQueue { FieldLogUploadState.forgetPending() }
                FieldLog.log("log upload: \(chunk.sequence) too large · next chunks up to \(chunkBytes) bytes")
            case .refused:
                FieldLog.log("log upload: \(chunk.sequence) refused with \(status) · off until the next start")
                stop()
                return
            case .retry:
                FieldLog.log("log upload: \(chunk.sequence) answered \(status)")
                return
            }
        }
    }

    private func onQueue(_ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            FieldLog.queue.async {
                body()
                continuation.resume()
            }
        }
    }

    enum Outcome: Equatable { case stored, tooLarge, refused, retry }

    /// What the app does with the relay's answer. 409: the relay already holds this sequence
    /// number. Pure; covered by tests.
    static func outcome(of status: Int) -> Outcome {
        switch status {
        case 200..<300, 409: .stored
        case 413: .tooLarge
        case 401, 403: .refused
        default: .retry
        }
    }

    /// The headers of an upload. The app token goes to the relay only, as on `GET /v1/meta`.
    static func headers(sequence: Int, appToken: String, bundle: Bundle = .main) -> [String: String] {
        [
            "Authorization": "Bearer \(appToken)",
            "Content-Type": "text/plain; charset=utf-8",
            "X-Log-Install": FieldLogUploadState.install(),
            "X-Log-Seq": String(sequence),
            "X-Log-Platform": "ios",
            "X-Log-App": bundle.bundleIdentifier ?? "-",
            "X-Log-App-Build": bundle.infoDictionary?["CFBundleVersion"] as? String ?? "-",
            "X-Log-GADKit": FieldLog.packageVersion,
        ]
    }
}
