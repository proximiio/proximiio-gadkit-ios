//
//  AppLanguage.swift
//  ProximiioGADKit
//
//  The package's language, "ar" or "en":
//
//  - the language of the `\.locale` the host app gives a package view, when it is not the language
//    the process started in: an app that switches its language with SwiftUI's environment;
//  - else the first of the app's `AppleLanguages`: the visitor's choice in iOS Settings (per-app
//    language), or an app that switches its language itself.
//
//  A change applies at once to the package's texts, the layout direction of its views and the labels
//  of the open maps (Nagarro, 2026-10-30: the language changed wrongly while the app ran; PM, Monday
//  "Language switching option missing", 2026-10-26). The texts come from the package bundle's `.lproj`
//  of the language (`Bundle.localized`), because a bundle keeps the localization it chose at launch.
//
import Foundation
import os
import ProximiioMap
import SwiftUI

enum AppLanguage {
    /// "ar" or "en". A view that reads it shows again when it changes.
    static var current: String { AppLanguageState.shared.language }

    /// The package's strings in `current`.
    static var bundle: Bundle { strings(in: current) }

    /// The package's strings in `language`: the package bundle's `.lproj` of it.
    static func strings(in language: String) -> Bundle {
        language == "ar" ? arabicStrings : englishStrings
    }

    private static let arabicStrings = lproj("ar")
    private static let englishStrings = lproj("en")

    private static func lproj(_ language: String) -> Bundle {
        Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
    }

    /// "ar" for an Arabic language identifier, else "en". Pure; covered by tests.
    static func code(of identifier: String?) -> String {
        identifier?.hasPrefix("ar") == true ? "ar" : "en"
    }

    /// The first of the app's `AppleLanguages`.
    static var preferred: String {
        code(of: (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
            ?? Bundle.main.preferredLocalizations.first)
    }

    /// The language of `Locale.current` when the package first read it. SwiftUI's default `\.locale`.
    private static let launchLanguage = Locale.current.language.languageCode?.identifier

    /// The host app's language from the `\.locale` around a package view, or `nil` when that is the
    /// language the process started in. Pure; covered by tests.
    static func hostLanguage(of locale: Locale, launchLanguage: String?) -> String? {
        let language = locale.language.languageCode?.identifier
        return language == launchLanguage ? nil : code(of: language)
    }

    /// The `\.locale` around a package view changed.
    @MainActor static func hostLocaleChanged(_ locale: Locale) {
        let host = hostLanguage(of: locale, launchLanguage: launchLanguage)
        if AppLanguageState.shared.set(host: host) {
            FieldLog.log("app language \(current) (host locale \(locale.identifier))")
            MapLanguageFollower.shared.apply()
        }
    }

    /// Keeps the labels of `session` in `current` while the session lives.
    @MainActor static func follow(_ session: ProximiioMapSession) {
        MapLanguageFollower.shared.add(session)
    }
}

extension Bundle {
    /// The package's strings in the app language (`AppLanguage`). `Text(_:bundle:)` and
    /// `String(localized:bundle:)` of the package take it in place of `.module`.
    static var localized: Bundle { AppLanguage.bundle }
}

/// The package's language. Reading `language` in a view's body makes the view show again when it
/// changes.
@Observable
final class AppLanguageState: @unchecked Sendable {
    static let shared = AppLanguageState()

    private struct Storage: Sendable {
        var host: String?
        var preferred: String
        var language: String { host ?? preferred }
    }

    @ObservationIgnored private let storage: OSAllocatedUnfairLock<Storage>
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        storage = OSAllocatedUnfairLock(initialState: Storage(host: nil, preferred: AppLanguage.preferred))
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self, self.set(preferred: AppLanguage.preferred) else { return }
            Task { @MainActor in
                FieldLog.log("app language \(AppLanguage.current) (AppleLanguages)")
                MapLanguageFollower.shared.apply()
            }
        }
    }

    var language: String {
        access(keyPath: \.language)
        return storage.withLock { $0.language }
    }

    /// Returns whether `language` changed.
    @discardableResult
    func set(host: String?) -> Bool {
        change { $0.host = host }
    }

    /// Returns whether `language` changed.
    @discardableResult
    func set(preferred: String) -> Bool {
        change { $0.preferred = preferred }
    }

    private func change(_ edit: @Sendable (inout Storage) -> Void) -> Bool {
        let (before, after) = storage.withLock { storage in
            let before = storage.language
            edit(&storage)
            return (before, storage.language)
        }
        guard before != after else { return false }
        withMutation(keyPath: \.language) {}
        return true
    }
}

extension EnvironmentValues {
    /// A package view above has applied the app language.
    @Entry var appliesAppLanguage = false
}

extension View {
    /// Shows the view in the app language (`AppLanguage`): its `\.locale` and layout direction, and
    /// the `\.locale` the host app gives it passed to `AppLanguage`. Inside another package view
    /// that has applied it, it does nothing.
    func appLanguage() -> some View {
        modifier(AppLanguageModifier())
    }
}

private struct AppLanguageModifier: ViewModifier {
    @Environment(\.locale) private var locale
    @Environment(\.appliesAppLanguage) private var isApplied

    func body(content: Content) -> some View {
        if isApplied {
            content
        } else {
            let language = AppLanguage.current
            content
                .environment(\.locale, Locale(languageCode: .init(language), languageRegion: locale.region))
                .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                .environment(\.appliesAppLanguage, true)
                .onChange(of: locale, initial: true) { _, locale in AppLanguage.hostLocaleChanged(locale) }
        }
    }
}

/// The map sessions whose labels follow `AppLanguage.current`.
@MainActor
private final class MapLanguageFollower {
    static let shared = MapLanguageFollower()

    private struct Entry {
        weak var session: ProximiioMapSession?
    }

    private var entries: [Entry] = []
    private var applied = AppLanguage.current

    func add(_ session: ProximiioMapSession) {
        entries = entries.filter { $0.session != nil } + [Entry(session: session)]
    }

    func apply() {
        let language = AppLanguage.current
        guard language != applied else { return }
        applied = language
        FieldLog.log("map language \(language)")
        for session in entries.compactMap(\.session) {
            session.options.language = language
        }
    }
}
