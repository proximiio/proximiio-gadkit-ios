//
//  GADConfigurationError.swift
//  ProximiioGADKit
//
//  Checks of the backend values before the SDK starts (Nagarro, 2026-11-22: an API base URL
//  without `https://` ended the app). `Proximiio(configuration:)` of SDK 6.0.0-beta.75 stops the
//  process on a base URL that is not https; these checks throw before that call.
//
//  `ProximiMap.start()` runs them on its `GADConfiguration`. A host app that creates the SDK or
//  the wristband binding itself calls `GADConfiguration.validate(_:)` before it does so.
//
import Foundation
import Proximiio
#if canImport(ProximiioBlueiot)
import ProximiioBlueiot
#endif

/// A backend value the SDK cannot start with. `errorDescription` names the value and the fault,
/// in English, for the developer; it holds no token.
public enum GADConfigurationError: LocalizedError, Equatable, Sendable {
    /// A value of the configuration: its name is the text in the message.
    public enum Value: String, Equatable, Sendable {
        case apiBaseURL = "API base URL"
        case fallbackAPIBaseURL = "fallback API base URL"
        case relayAPIBaseURL = "relay-api base URL"
        case applicationToken = "application token"
        case relayAPIAppToken = "relay-api app token"
    }

    /// The URL has no host, for example `api.example.com` without `https://`.
    case urlWithoutHost(Value, String)
    /// The URL is not https. http is accepted for localhost only.
    case urlNotHTTPS(Value, String)
    /// The token is empty.
    case emptyToken(Value)
    /// The token holds a space or a line break, for example from a copied line.
    case tokenWithWhitespace(Value)

    public var errorDescription: String? {
        switch self {
        case .urlWithoutHost(let value, let text):
            "The \(value.rawValue) \"\(text)\" has no host. Write it with the scheme, for example https://api.example.com."
        case .urlNotHTTPS(let value, let text):
            "The \(value.rawValue) \"\(text)\" is not an https URL."
        case .emptyToken(let value):
            "The \(value.rawValue) is empty."
        case .tokenWithWhitespace(let value):
            "The \(value.rawValue) holds a space or a line break."
        }
    }
}

extension GADConfiguration {
    /// Throws the first value `ProximiMap` cannot start with: the API base URL, the application
    /// token, the relay-api base URL, the relay-api app token.
    public func validate() throws {
        try Self.check(url: apiBaseURL, as: .apiBaseURL)
        try Self.check(token: applicationToken, as: .applicationToken)
        try Self.check(url: relayAPI.baseURL, as: .relayAPIBaseURL)
        try Self.check(token: relayAPIAppToken, as: .relayAPIAppToken)
    }

    /// Throws the first value of `configuration` the SDK cannot start with: the API base URL, each
    /// fallback API base URL, the token. Call it before `Proximiio(configuration:)`.
    public static func validate(_ configuration: ProximiioConfiguration) throws {
        try check(url: configuration.apiBaseURL, as: .apiBaseURL)
        for url in configuration.fallbackAPIBaseURLs { try check(url: url, as: .fallbackAPIBaseURL) }
        try check(token: configuration.token, as: .applicationToken)
    }

    /// Throws the first value of `configuration` the wristband binding cannot work with: the
    /// relay-api base URL, the relay-api app token. Call it before `BlueiotWristbandBinding(configuration:)`.
    public static func validate(_ configuration: BlueiotBindingConfiguration) throws {
        try check(url: configuration.relayURL.baseURL, as: .relayAPIBaseURL)
        try check(token: configuration.appToken, as: .relayAPIAppToken)
    }

    /// A host, and https; http for localhost only (the SDK's rule for a base URL). Pure; covered by tests.
    static func check(url: URL, as value: GADConfigurationError.Value) throws {
        guard let host = url.host, !host.isEmpty else {
            throw GADConfigurationError.urlWithoutHost(value, url.absoluteString)
        }
        switch url.scheme?.lowercased() {
        case "https": return
        case "http" where ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()): return
        default: throw GADConfigurationError.urlNotHTTPS(value, url.absoluteString)
        }
    }

    /// Not empty and without spaces or line breaks. Pure; covered by tests.
    static func check(token: String, as value: GADConfigurationError.Value) throws {
        guard !token.isEmpty else { throw GADConfigurationError.emptyToken(value) }
        guard token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw GADConfigurationError.tokenWithWhitespace(value)
        }
    }
}
