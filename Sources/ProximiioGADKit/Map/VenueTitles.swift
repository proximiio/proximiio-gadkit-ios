//
//  VenueTitles.swift
//  ProximiioGADKit
//
//  The names of the amenity kinds from the venue data (operator, 2026-11-22, Metis T-1924: the PM
//  edits every shortcut name in the portal). An amenity kind (`AmenityKind`) is named with the
//  title of its amenity in the venue data, in the app language. The package's own text is shown
//  when the data has no title in that language, when two amenities of the kind have a place (the
//  women's and the men's restroom), or when `GADSettings.usesVenueAmenityTitles` is `false`.
//
//  The title of a language is the amenity's `title_i18n[language]`, then
//  `metadata.title_i18n[language]`: the amenities are edited by hand through the REST API, and
//  `metadata` is the field that takes any key (operator, 2026-11-22). The untagged `title` counts
//  only for `GADSettings.venueDataLanguage` ("en"): in Arabic an English `title` does not replace
//  the package's Arabic text.
//
import Foundation
import Proximiio

enum VenueTitles {
    private static let lock = NSLock()
    /// Per kind: the titles of its amenity by language code, lowercased.
    nonisolated(unsafe) private static var stored: [AmenityKind: [String: String]] = [:]

    /// The data title of `kind` in `language`, or `nil` for the package's text.
    static func title(for kind: AmenityKind, language: String = AppLanguage.current) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return stored[kind].flatMap { title(in: $0, language: language) }
    }

    /// The title of `language` in `titles` (keys lowercased): the exact code, then the base
    /// language (`ar` for `ar-AE`). Pure; covered by tests.
    static func title(in titles: [String: String], language: String) -> String? {
        let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
        if let title = titles[code] { return title }
        guard let base = code.split(separator: "-").first.map(String.init), base != code else { return nil }
        return titles[base]
    }

    /// The translated titles of `amenity` by language code, lowercased: `title_i18n`, then the
    /// object `metadata.title_i18n` for the languages `title_i18n` does not have. Blank titles and
    /// values that are no text are left out. Pure; covered by tests.
    static func translations(of amenity: ProximiioAmenity) -> [String: String] {
        var titles: [String: String] = [:]
        func take(_ language: String, _ title: String) {
            let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, titles[code] == nil { titles[code] = trimmed }
        }
        for (language, title) in amenity.titleTranslations { take(language, title) }
        if case .object(let metadata)? = amenity.metadata, case .object(let translated)? = metadata["title_i18n"] {
            for (language, value) in translated {
                if case .string(let title) = value { take(language, title) }
            }
        }
        return titles
    }

    /// The titles of `amenity` by language code, lowercased: `translations(of:)`, and the untagged
    /// `title` under `untaggedLanguage` when they have no title for it. Blank titles are left out.
    /// Pure; covered by tests.
    static func titles(of amenity: ProximiioAmenity, untaggedLanguage: String) -> [String: String] {
        var titles = translations(of: amenity)
        let untagged = untaggedLanguage.lowercased()
        if !untagged.isEmpty, Self.title(in: titles, language: untagged) == nil,
           let title = amenity.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            titles[untagged] = title
        }
        return titles
    }

    /// The titles each kind takes: those of the one amenity of the kind that is in `used`. A kind
    /// with two such amenities has none. Pure; covered by tests.
    static func titles(amenities: [ProximiioAmenity], used: Set<String>, untaggedLanguage: String) -> [AmenityKind: [String: String]] {
        let ids = VenueGlyphs.amenityIDs(amenities: amenities, used: used, withIcon: used)
        let byID = Dictionary(amenities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMapValues { id in
            byID[id].map { titles(of: $0, untaggedLanguage: untaggedLanguage) }.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Takes the kind titles from `amenities` for the amenities that places or level changers use
    /// (`used`). `enabled` is `GADSettings.usesVenueAmenityTitles`, `untaggedLanguage` is
    /// `GADSettings.venueDataLanguage`.
    static func update(amenities: [ProximiioAmenity], used: Set<String>, enabled: Bool, untaggedLanguage: String) {
        let titles = enabled ? titles(amenities: amenities, used: used, untaggedLanguage: untaggedLanguage) : [:]
        lock.lock()
        stored = titles
        lock.unlock()
    }
}
