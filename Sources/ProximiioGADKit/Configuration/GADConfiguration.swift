//
//  GADConfiguration.swift
//  ProximiioGADKit
//
//  The backend of the host app's build: the Proximi.io API and the relay-api. The host app
//  passes it to `WristbandSession` and `VenueService.start`. ProximiioGADKit sets no fallback
//  host, so it contacts only these two hosts.
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

public struct GADConfiguration: Equatable, Sendable {
    /// Proximi.io API base URL. Passed to the SDK as `apiBaseURL`.
    public var apiBaseURL: URL
    /// Proximi.io application token of the Guggenheim organisation.
    public var applicationToken: String
    /// relay-api base URL: wristband binding and wristband positions. Scheme and host only;
    /// the SDK drops any path.
    public var relayAPI: BlueiotCloudRelayEndpoint
    /// relay-api app token of the site. The SDK sends it on `GET /v1/meta` and
    /// `POST /v1/bindings`.
    public var relayAPIAppToken: String

    public init(apiBaseURL: URL, applicationToken: String, relayAPI: BlueiotCloudRelayEndpoint, relayAPIAppToken: String) {
        self.apiBaseURL = apiBaseURL
        self.applicationToken = applicationToken
        self.relayAPI = relayAPI
        self.relayAPIAppToken = relayAPIAppToken
    }
}
