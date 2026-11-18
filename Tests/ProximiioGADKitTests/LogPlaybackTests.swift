//
//  LogPlaybackTests.swift
//  ProximiioGADKitTests
//
#if DEBUG
import Foundation
import Testing
@testable import ProximiioGADKit

/// The positions of a field log, for the playback in the simulator.
struct LogPlaybackTests {
    private let log = """
    [GAD] 2026-11-18T05:39:59.100Z guidance stop Le Salon L1 · visitor L1 acc 1.0 · remaining 12.0
    [GAD] 2026-11-18T05:40:00.463Z position custom 24.540280,54.398799 L1 acc 1.0
    [GAD] 2026-11-18T05:40:01.701Z position custom 24.540284,54.398801 L1 acc 1.0
    [GAD] 2026-11-18T05:40:01.800Z relay position: ts 1794990015336 · age 120
    [GAD] 2026-11-18T05:41:00.463Z position custom 24.540300,54.398900 L2 acc 2.5
    [GAD] 2026-11-19T05:40:30.000Z position custom 24.541000,54.399000 L1 acc 1.0
    """

    @Test func thePositionLinesOfTheDayAreRead() {
        let samples = LogPlayback.samples(in: log, day: "2026-11-18", from: nil, to: nil)
        #expect(samples.count == 3)
        #expect(samples[0] == LogPlaybackSample(offset: 0, latitude: 24.540280, longitude: 54.398799, level: 1, accuracy: 1))
        #expect(abs(samples[1].offset - 1.238) < 0.001)
        #expect(samples[2].level == 2)
        #expect(samples[2].accuracy == 2.5)
        #expect(abs(samples[2].offset - 60) < 0.001)
    }

    @Test func thePartBetweenTwoTimesIsRead() {
        let samples = LogPlayback.samples(in: log, day: "2026-11-18", from: "05:40:01", to: "05:40:59")
        #expect(samples.count == 1)
        #expect(samples[0].offset == 0)
        #expect(samples[0].latitude == 24.540284)
        #expect(LogPlayback.samples(in: log, day: "2026-11-20", from: nil, to: nil).isEmpty)
    }
}
#endif
