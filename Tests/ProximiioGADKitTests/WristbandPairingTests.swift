//
//  WristbandPairingTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif
import Testing
@_spi(GADApp) @testable import ProximiioGADKit

@MainActor
private final class FakeConnector: WristbandConnecting {
    /// One answer per bind: `nil` succeeds, an error is thrown.
    var results: [BlueiotBindingError?]
    var locationAnswer: WristbandLocationAsk?
    private(set) var bound: [String] = []
    private(set) var asked: [WristbandLocationAsk] = []

    init(results: [BlueiotBindingError?], locationAnswer: WristbandLocationAsk? = nil) {
        self.results = results
        self.locationAnswer = locationAnswer
    }

    func locationAsk() async -> WristbandLocationAsk? { locationAnswer }

    func ask(_ ask: WristbandLocationAsk) async { asked.append(ask) }

    func bind(_ label: String) async throws {
        bound.append(label)
        let result = results.isEmpty ? .network(ProximiioUnderlyingError(URLError(.notConnectedToInternet))) : results.removeFirst()
        if let result { throw result }
    }
}

@MainActor
struct WristbandPairingTests {
    /// The binding call for host apps with their own scanner (`connect(code:)`).
    @Test func connectAsksForLocationThenBindsTheTrimmedCode() async throws {
        let connector = FakeConnector(results: [nil], locationAnswer: .permission)
        try await connector.connect(code: " GAD-0x3B9B9EFA \n")
        #expect(connector.asked == [.permission])
        #expect(connector.bound == ["GAD-0x3B9B9EFA"])
    }

    @Test func connectWithAnEmptyCodeThrowsInvalidTagIDAndBindsNothing() async {
        let connector = FakeConnector(results: [])
        await #expect(throws: BlueiotBindingError.self) { try await connector.connect(code: "  ") }
        #expect(connector.bound.isEmpty)
    }

    @Test func scannedPayloadIsBoundAsTrimmedText() async {
        let connector = FakeConnector(results: [nil])
        let pairing = WristbandPairing(connector: connector)
        pairing.startScanning()
        await pairing.submit(code: " GAD-0x3B9B9EFA \n")
        #expect(pairing.step == .connected("GAD-0x3B9B9EFA"))
        #expect(connector.bound == ["GAD-0x3B9B9EFA"])
    }

    @Test func emptyCodeStaysOnTheScreenWithAMessage() async {
        let connector = FakeConnector(results: [])
        let pairing = WristbandPairing(connector: connector)
        pairing.enterCodeManually()
        await pairing.submit(code: "   ")
        #expect(pairing.step == .manualEntry)
        #expect(pairing.invalidCodeMessage != nil)
        #expect(connector.bound.isEmpty)
    }

    @Test func typedCodeTheRelayRejectsReturnsToTheField() async {
        let connector = FakeConnector(results: [.invalidTagID(requestID: nil)])
        let pairing = WristbandPairing(connector: connector)
        pairing.enterCodeManually()
        await pairing.submit(code: "abc")
        #expect(pairing.step == .manualEntry)
        #expect(pairing.enteredCode == "abc")
        #expect(pairing.invalidCodeMessage == WristbandCopy.message(for: BlueiotBindingError.invalidTagID(requestID: nil)))
    }

    @Test func failuresCountUpWithTheErrorMessageAndRetryUsesTheSameLabel() async {
        let refused = BlueiotBindingError.tagAlreadyBound(requestID: nil)
        let connector = FakeConnector(results: [refused, refused, nil])
        let pairing = WristbandPairing(connector: connector)
        let message = WristbandCopy.message(for: refused)

        pairing.startScanning()
        await pairing.submit(code: "1000045662")
        #expect(pairing.step == .failed("1000045662", message: message, attempts: 1))
        await pairing.retry()
        #expect(pairing.step == .failed("1000045662", message: message, attempts: 2))
        await pairing.retry()
        #expect(pairing.step == .connected("1000045662"))
        #expect(connector.bound == ["1000045662", "1000045662", "1000045662"])
    }

    @Test func locationIsAskedBeforeTheBindWhenTheBindingNeedsIt() async {
        let connector = FakeConnector(results: [nil], locationAnswer: .preciseLocation)
        let pairing = WristbandPairing(connector: connector)
        await pairing.submit(code: "1000045662")
        #expect(connector.asked == [.preciseLocation])
        #expect(pairing.step == .connected("1000045662"))
    }

    @Test func scanningCanBeCancelledAndCameraDenialIsShown() {
        let pairing = WristbandPairing(connector: FakeConnector(results: []))
        pairing.startScanning()
        #expect(pairing.step == .scanning)
        pairing.cancelScanning()
        #expect(pairing.step == .intro)
        pairing.cameraAccessDenied()
        #expect(pairing.step == .cameraDenied)
    }
}

struct WristbandCopyTests {
    @Test func takeOverRefusalNamesWhatThePhoneSent() {
        let error = BlueiotBindingError.notInAuthorizedZone(cause: .approximateLocation, serverMessage: nil, requestID: nil)
        #expect(WristbandCopy.message(for: error) == WristbandCopy.message(for: .approximateLocation))
        #expect(WristbandCopy.message(for: error).contains("Precise Location"))
    }

    @Test func rateLimitNamesTheWaitInWholeSeconds() {
        let error = BlueiotBindingError.rateLimited(retryAfter: 4.2, requestID: nil)
        #expect(WristbandCopy.message(for: error) == "Too many attempts. Try again in 5 seconds.")
        let withoutWait = BlueiotBindingError.rateLimited(retryAfter: nil, requestID: nil)
        #expect(WristbandCopy.message(for: withoutWait) == "Too many attempts. Try again in a moment.")
    }

    @Test func refusedSwapAndSigningOutageHaveTheirOwnText() {
        #expect(WristbandCopy.message(for: BlueiotBindingError.swapBandsApart(requestID: nil)) == "Hold your current wristband next to the new one and scan again.")
        #expect(WristbandCopy.message(for: BlueiotBindingError.swapAtReception(requestID: nil)) == "Your wristband isn't reachable. Please swap it at the reception desk.")
        #expect(WristbandCopy.message(for: BlueiotBindingError.signingUnavailable(retryAfter: 3, requestID: nil)) == "The museum’s server is busy. Try again in a moment.")
    }

    @Test func supersededSessionTellsTheVisitorAnotherPhoneScannedTheBand() {
        #expect(WristbandCopy.notice(for: .superseded).contains("another phone"))
        #expect(WristbandCopy.notice(for: .unknown("NEW_REASON")) == WristbandCopy.notice(for: .userEnded))
    }

    @Test func logLineHoldsNoSessionDetails() {
        #expect(WristbandCopy.logLine(for: .ended(.timeout)) == "ended, TIMEOUT")
        #expect(WristbandCopy.logLine(for: .unbound) == "unbound")
    }
}

struct TrackingHealthTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func statesFollowAvailability() {
        #expect(TrackingHealth.evaluate(wasEverAvailable: false, unavailableSince: now, now: now) == .waiting)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: nil, now: now) == .tracking)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: now.addingTimeInterval(-1), now: now) == .tracking)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: now.addingTimeInterval(-109), now: now) == .tracking)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: now.addingTimeInterval(-110), now: now) == .lostPlace)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: now.addingTimeInterval(-169), now: now) == .lostPlace)
        #expect(TrackingHealth.evaluate(wasEverAvailable: true, unavailableSince: now.addingTimeInterval(-170), now: now) == .stoppedResponding)
    }

    @Test func nearestPlaceIsOnTheSameLevel() {
        let places = [
            VenuePlace(id: "a", title: "Gallery 1", coordinate: .init(latitude: 24.5000, longitude: 54.4000), level: 1),
            VenuePlace(id: "b", title: "Gallery 2", coordinate: .init(latitude: 24.5010, longitude: 54.4010), level: 1),
            VenuePlace(id: "c", title: "Gallery 301", coordinate: .init(latitude: 24.5001, longitude: 54.4001), level: 3),
        ]
        let here = ProximiioCoordinate(latitude: 24.5002, longitude: 54.4002)
        #expect(TrackingMonitor.nearest(to: here, level: 1, in: places)?.id == "a")
        #expect(TrackingMonitor.nearest(to: here, level: 3, in: places)?.id == "c")
        #expect(TrackingMonitor.nearest(to: nil, level: 1, in: places) == nil)
    }
}
