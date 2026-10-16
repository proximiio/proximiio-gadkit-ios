//
//  GADConfiguration.swift
//  ProximiioGADKit
//
//  The backend of the host app's build: the Proximi.io API and the relay-api. The host app
//  passes it to `ProximiMap`. ProximiioGADKit sets no fallback host, so it contacts only these
//  two hosts.
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
    /// Times and distances of the screens.
    public var settings: GADSettings

    /// `nil` when `relayAPIBaseURL` is not an http or https URL with a host.
    public init?(
        apiBaseURL: URL,
        applicationToken: String,
        relayAPIBaseURL: URL,
        relayAPIAppToken: String,
        settings: GADSettings = .standard
    ) {
        guard let relayAPI = BlueiotCloudRelayEndpoint(text: relayAPIBaseURL.absoluteString) else { return nil }
        self.init(
            apiBaseURL: apiBaseURL,
            applicationToken: applicationToken,
            relayAPI: relayAPI,
            relayAPIAppToken: relayAPIAppToken,
            settings: settings
        )
    }

    public init(
        apiBaseURL: URL,
        applicationToken: String,
        relayAPI: BlueiotCloudRelayEndpoint,
        relayAPIAppToken: String,
        settings: GADSettings = .standard
    ) {
        self.apiBaseURL = apiBaseURL
        self.applicationToken = applicationToken
        self.relayAPI = relayAPI
        self.relayAPIAppToken = relayAPIAppToken
        self.settings = settings
    }
}
