//
//  FieldLogUploadTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif
import Testing
@testable import ProximiioGADKit

struct FieldLogUploadTests {
    private func defaults() -> UserDefaults {
        let name = "FieldLogUploadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aChunkEndsWithAWholeLine() {
        let file = Data("one\ntwo\nthr".utf8)
        #expect(FieldLogUploadState.chunkRange(fileCount: file.count, offset: 0, pending: 0, limit: 100, file: file) == 0..<8)
        #expect(FieldLogUploadState.chunkRange(fileCount: file.count, offset: 0, pending: 0, limit: 5, file: file) == 0..<4)
        // Only an unfinished line is left.
        #expect(FieldLogUploadState.chunkRange(fileCount: file.count, offset: 8, pending: 0, limit: 100, file: file) == nil)
        #expect(FieldLogUploadState.chunkRange(fileCount: file.count, offset: 11, pending: 0, limit: 100, file: file) == nil)
    }

    @Test func aLineLongerThanTheLimitIsSentWhole() {
        let file = Data("a long line\nnext\n".utf8)
        #expect(FieldLogUploadState.chunkRange(fileCount: file.count, offset: 0, pending: 0, limit: 4, file: file) == 0..<12)
    }

    @Test func aChunkThatFailedComesAgainUnchanged() {
        let defaults = defaults()
        var file = Data("one\ntwo\n".utf8)
        let first = FieldLogUploadState.nextChunk(of: file, limit: 100, in: defaults)
        #expect(first?.sequence == 0)
        #expect(first?.data == Data("one\ntwo\n".utf8))
        // More lines are written before the retry.
        file.append(Data("three\n".utf8))
        let retry = FieldLogUploadState.nextChunk(of: file, limit: 100, in: defaults)
        #expect(retry?.sequence == 0)
        #expect(retry?.data == first?.data)
        FieldLogUploadState.accepted(retry!.data.count, in: defaults)
        let second = FieldLogUploadState.nextChunk(of: file, limit: 100, in: defaults)
        #expect(second?.sequence == 1)
        #expect(second?.data == Data("three\n".utf8))
        FieldLogUploadState.accepted(second!.data.count, in: defaults)
        #expect(FieldLogUploadState.nextChunk(of: file, limit: 100, in: defaults) == nil)
    }

    @Test func theUploadGoesOnAfterTheHeadOfTheFileIsCut() {
        let defaults = defaults()
        let file = Data("one\ntwo\nthree\n".utf8)
        let first = FieldLogUploadState.nextChunk(of: file, limit: 4, in: defaults)
        #expect(first?.data == Data("one\n".utf8))
        FieldLogUploadState.accepted(4, in: defaults)
        // `FieldLog` cut "one\ntwo\n": "two" was never sent and is gone.
        FieldLogUploadState.addRemoved(8, in: defaults)
        let cut = Data("three\nfour\n".utf8)
        let next = FieldLogUploadState.nextChunk(of: cut, limit: 100, in: defaults)
        #expect(next?.sequence == 1)
        #expect(next?.data == cut)
    }

    @Test func aDeletedFileStartsAtItsHead() {
        let defaults = defaults()
        let file = Data("one\ntwo\n".utf8)
        _ = FieldLogUploadState.nextChunk(of: file, limit: 100, in: defaults)
        FieldLogUploadState.accepted(8, in: defaults)
        let fresh = Data("new\n".utf8)
        #expect(FieldLogUploadState.nextChunk(of: fresh, limit: 100, in: defaults)?.data == fresh)
    }

    @Test func theRelaysAnswerDecidesTheNextStep() {
        #expect(FieldLogUploader.outcome(of: 204) == .stored)
        #expect(FieldLogUploader.outcome(of: 409) == .stored)
        #expect(FieldLogUploader.outcome(of: 413) == .tooLarge)
        #expect(FieldLogUploader.outcome(of: 401) == .refused)
        #expect(FieldLogUploader.outcome(of: 403) == .refused)
        #expect(FieldLogUploader.outcome(of: 500) == .retry)
        #expect(FieldLogUploader.outcome(of: 0) == .retry)
    }

    /// Production hosts, 2026-11-21: Cloudflare answers some requests with 403 and
    /// `cf-mitigated: challenge`. The uploads stay on.
    @Test func aProxyChallengeIsNotTheRelaysRefusal() {
        #expect(FieldLogUploader.isProxyChallenge(mitigated: "challenge", contentType: "text/html; charset=UTF-8"))
        #expect(FieldLogUploader.isProxyChallenge(mitigated: nil, contentType: "Text/HTML"))
        #expect(!FieldLogUploader.isProxyChallenge(mitigated: nil, contentType: "application/json"))
        #expect(!FieldLogUploader.isProxyChallenge(mitigated: nil, contentType: nil))
        #expect(FieldLogUploader.outcome(of: 403, isProxyChallenge: true) == .retry)
        #expect(FieldLogUploader.outcome(of: 401, isProxyChallenge: true) == .retry)
        #expect(FieldLogUploader.outcome(of: 403, isProxyChallenge: false) == .refused)
    }

    @Test func theUploadCarriesTheInstallAndTheSequence() {
        let headers = FieldLogUploader.headers(sequence: 7, appToken: "t")
        #expect(headers["Authorization"] == "Bearer t")
        #expect(headers["X-Log-Seq"] == "7")
        #expect(headers["X-Log-Platform"] == "ios")
        #expect(headers["X-Log-GADKit"] == FieldLog.packageVersion)
        #expect(headers["X-Log-Install"]?.isEmpty == false)
    }
}

struct BindingFieldLogTests {
    private let session = BlueiotBindingSession(
        bindingID: UUID(uuidString: "0B28C465-9DD1-4375-A148-4E192110E751")!,
        endsAt: Date(timeIntervalSince1970: 2_000_000_000), tokenExpiresAt: Date(timeIntervalSince1970: 1_900_000_000))

    @Test func theStreamOpensOnlineAndClosesWithTheNextState() {
        var log = BindingFieldLog.StreamLog()
        var diagnostics = BlueiotBindingDiagnostics()
        #expect(log.lines(for: .active(session, link: .connecting, signal: .ok), diagnostics: diagnostics).isEmpty)
        #expect(log.lines(for: .active(session, link: .online, signal: .ok), diagnostics: diagnostics)
            == ["relay stream: open · binding 0b28c465-9dd1-4375-a148-4e192110e751 · sse"])
        // A signal change keeps the stream.
        #expect(log.lines(for: .active(session, link: .online, signal: .lost(since: .now)), diagnostics: diagnostics).isEmpty)
        diagnostics.lastError = "timed out"
        #expect(log.lines(for: .active(session, link: .reconnecting, signal: .ok), diagnostics: diagnostics)
            == ["relay stream: closed · binding 0b28c465-9dd1-4375-a148-4e192110e751 · active, reconnecting · timed out"])
        diagnostics.lastError = nil
        _ = log.lines(for: .active(session, link: .online, signal: .ok), diagnostics: diagnostics)
        #expect(log.lines(for: .ended(.superseded), diagnostics: diagnostics)
            == ["relay stream: closed · binding 0b28c465-9dd1-4375-a148-4e192110e751 · ended, SUPERSEDED"])
        #expect(log.lines(for: .unbound, diagnostics: diagnostics).isEmpty)
    }

    @Test func aPositionLineIsWrittenAtMostEveryFiveSeconds() {
        #expect(BindingFieldLog.logsPosition(now: 100, last: nil))
        #expect(!BindingFieldLog.logsPosition(now: 104.9, last: 100))
        #expect(BindingFieldLog.logsPosition(now: 105, last: 100))
        let line = BindingFieldLog.positionLine(
            timestamp: Date(timeIntervalSince1970: 1_794_822_000.5), now: Date(timeIntervalSince1970: 1_794_822_000.82))
        #expect(line == "relay position: ts 1794822000500 · age 320")
    }
}
