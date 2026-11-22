//
//  GADConfigurationErrorTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import Testing
@testable import ProximiioGADKit

struct GADConfigurationErrorTests {
    private func configuration(api: String = "https://api.example.com", token: String = "token",
                               relay: String = "https://relay.example.com", relayToken: String = "relay") -> GADConfiguration? {
        GADConfiguration(apiBaseURL: URL(string: api)!, applicationToken: token,
                         relayAPIBaseURL: URL(string: relay)!, relayAPIAppToken: relayToken)
    }

    @Test func aCompleteConfigurationPasses() throws {
        try #require(configuration()).validate()
        try GADConfiguration.check(url: URL(string: "http://localhost:8080")!, as: .apiBaseURL)
    }

    /// Nagarro, 2026-11-22: the API base URL without `https://`.
    @Test func anAPIBaseURLWithoutTheSchemeHasNoHost() throws {
        let broken = try #require(configuration(api: "api.example.com"))
        #expect(throws: GADConfigurationError.urlWithoutHost(.apiBaseURL, "api.example.com")) { try broken.validate() }
    }

    @Test func anAPIBaseURLOverHTTPIsRefused() throws {
        let broken = try #require(configuration(api: "http://api.example.com"))
        #expect(throws: GADConfigurationError.urlNotHTTPS(.apiBaseURL, "http://api.example.com")) { try broken.validate() }
    }

    @Test func aRelayOverHTTPIsRefused() throws {
        let broken = try #require(configuration(relay: "http://relay.example.com"))
        #expect(throws: GADConfigurationError.urlNotHTTPS(.relayAPIBaseURL, "http://relay.example.com")) { try broken.validate() }
    }

    @Test func emptyTokensAndTokensWithWhitespaceAreRefused() throws {
        #expect(throws: GADConfigurationError.emptyToken(.applicationToken)) {
            try #require(configuration(token: "")).validate()
        }
        #expect(throws: GADConfigurationError.tokenWithWhitespace(.applicationToken)) {
            try #require(configuration(token: "token\n")).validate()
        }
        #expect(throws: GADConfigurationError.emptyToken(.relayAPIAppToken)) {
            try #require(configuration(relayToken: "")).validate()
        }
    }

    /// The host app's own SDK configuration: the base URL, each fallback URL, the token.
    @Test func theSDKConfigurationIsChecked() throws {
        var sdk = ProximiioConfiguration.relayOnly(token: "token", runsInBackground: true)
        sdk.apiBaseURL = URL(string: "https://api.example.com")!
        sdk.fallbackAPIBaseURLs = []
        try GADConfiguration.validate(sdk)
        sdk.apiBaseURL = URL(string: "api.example.com")!
        #expect(throws: GADConfigurationError.urlWithoutHost(.apiBaseURL, "api.example.com")) { try GADConfiguration.validate(sdk) }
        sdk.apiBaseURL = URL(string: "https://api.example.com")!
        sdk.fallbackAPIBaseURLs = [URL(string: "http://other.example.com")!]
        #expect(throws: GADConfigurationError.urlNotHTTPS(.fallbackAPIBaseURL, "http://other.example.com")) {
            try GADConfiguration.validate(sdk)
        }
    }

    @Test func theBindingConfigurationIsChecked() throws {
        let relay = try #require(BlueiotCloudRelayEndpoint(text: "https://relay.example.com"))
        try GADConfiguration.validate(BlueiotBindingConfiguration(relayURL: relay, appToken: "relay"))
        #expect(throws: GADConfigurationError.emptyToken(.relayAPIAppToken)) {
            try GADConfiguration.validate(BlueiotBindingConfiguration(relayURL: relay, appToken: ""))
        }
    }

    /// The message names the value and holds no token.
    @Test func theMessageNamesTheValue() {
        let message = GADConfigurationError.urlWithoutHost(.apiBaseURL, "api.example.com").localizedDescription
        #expect(message.contains("API base URL"))
        #expect(message.contains("api.example.com"))
    }
}
