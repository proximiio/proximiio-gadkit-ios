//
//  DemoPairing.swift
//  ProximiioGADKit
//
#if DEBUG
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

/// Debug builds only. The pairing flow with a connector that answers after 2 seconds
/// (`-demoWristbandPairing`). A failing bind throws `tagAlreadyBound`.
@_spi(GADApp) public enum DemoPairing {
    @MainActor
    public static func make(succeeds: Bool) -> WristbandPairing {
        WristbandPairing(connector: Connector(succeeds: succeeds))
    }

    @MainActor
    private final class Connector: WristbandConnecting {
        let succeeds: Bool
        init(succeeds: Bool) { self.succeeds = succeeds }

        func locationAsk() async -> WristbandLocationAsk? { nil }

        func ask(_ ask: WristbandLocationAsk) async {}

        func bind(_ label: String) async throws {
            try? await Task.sleep(for: .seconds(2))
            if !succeeds { throw BlueiotBindingError.tagAlreadyBound(requestID: nil) }
        }
    }
}
#endif
