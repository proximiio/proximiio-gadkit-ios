//
//  AppLanguage.swift
//  ProximiioGADKit
//
//  The package's language, "ar" or "en":
//
//  - `GADSettings.language`, when the host app has set it;
//  - else the language of the `\.locale` the host app gives a package view, when it is not the language
//    the process started in: an app that switches its language with SwiftUI's environment;
//  - else the first of the app's `AppleLanguages`: the visitor's choice in iOS Settings (per-app
//    language), or an app that sets `AppleLanguages` itself.
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
            languageChanged(reason: "host locale \(locale.identifier)")
        }
    }

    /// `GADSettings.language` changed: the host app's own choice, or `nil` to follow the app again.
    static func set(fixed language: String?) {
        guard AppLanguageState.shared.set(fixed: language.map { code(of: $0) }) else { return }
        Task { @MainActor in languageChanged(reason: "GADSettings.language \(language ?? "nil")") }
    }

    /// The language from its three sources, first the one the host app has set. Pure; covered by tests.
    static func resolved(fixed: String?, host: String?, preferred: String) -> String {
        fixed ?? host ?? preferred
    }

    /// Posted on the main thread after `current` changed.
    static let didChange = Notification.Name("ProximiioGADKit.AppLanguage.didChange")

    /// Tells the views and the open maps that `current` changed.
    @MainActor static func languageChanged(reason: String) {
        FieldLog.log("app language \(current) (\(reason))")
        if #available(iOS 17, *) { AppLanguageTracking.shared.changed() }
        NotificationCenter.default.post(name: didChange, object: nil)
        MapLanguageFollower.shared.apply()
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

/// The package's language, readable from any thread. A change reaches the views through
/// `AppLanguage.languageChanged(reason:)`.
final class AppLanguageState: @unchecked Sendable {
    static let shared = AppLanguageState()

    private struct Storage: Sendable {
        var fixed: String?
        var host: String?
        var preferred: String
        var language: String { AppLanguage.resolved(fixed: fixed, host: host, preferred: preferred) }
    }

    private let storage: OSAllocatedUnfairLock<Storage>
    private var observer: NSObjectProtocol?

    private init() {
        storage = OSAllocatedUnfairLock(initialState: Storage(host: nil, preferred: AppLanguage.preferred))
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self, self.set(preferred: AppLanguage.preferred) else { return }
            Task { @MainActor in AppLanguage.languageChanged(reason: "AppleLanguages") }
        }
    }

    /// On iOS 17 and later, reading it in a view's body makes the view show again when it changes.
    var language: String {
        if #available(iOS 17, *) { AppLanguageTracking.shared.access() }
        return storage.withLock { $0.language }
    }

    /// `GADSettings.language`.
    var fixed: String? { storage.withLock { $0.fixed } }

    /// Returns whether `language` changed.
    @discardableResult
    func set(fixed: String?) -> Bool {
        change { $0.fixed = fixed }
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
        return before != after
    }
}

/// iOS 17 and later: makes every view that read the language show again when it changes.
@available(iOS 17, *)
@Observable
final class AppLanguageTracking: @unchecked Sendable {
    static let shared = AppLanguageTracking()

    /// Only observed; it holds no value.
    private var language: Void {
        access(keyPath: \.language)
    }

    func access() {
        _ = language
    }

    @MainActor func changed() {
        withMutation(keyPath: \.language) {}
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
    /// The language the content shows. A change shows this view again on iOS 16 too.
    @State private var language = AppLanguage.current

    func body(content: Content) -> some View {
        if isApplied {
            content
        } else {
            rebuiltOnIOS16(content)
                .environment(\.locale, Locale(languageCode: .init(language), languageRegion: locale.region))
                .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                .environment(\.appliesAppLanguage, true)
                .onValueChange(of: locale, initial: true) { _, locale in AppLanguage.hostLocaleChanged(locale) }
                .onReceive(NotificationCenter.default.publisher(for: AppLanguage.didChange)) { _ in
                    language = AppLanguage.current
                }
        }
    }

    /// iOS 16 has no Observation, so the views that read the language do not show again by
    /// themselves: the content is built again in the new language. The open map starts again.
    @ViewBuilder private func rebuiltOnIOS16(_ content: Content) -> some View {
        if #available(iOS 17, *) {
            content
        } else {
            content.id(language)
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

extension GADSettings {
    /// The language of every package view: `"ar"` or `"en"` (an identifier that starts with "ar"
    /// counts as Arabic, any other as English). `nil`, the default, follows the app: the `\.locale`
    /// the host app gives a package view, else the first of `AppleLanguages`.
    ///
    /// One value for the process, not for one view. It applies at once, also to open maps: the
    /// package's texts, the texts of the venue data, the layout direction and the map labels of
    /// `ProximiMapView`, `ProximiExploreView` and the screens of `.proximiMap(_:)`. Set it from
    /// any thread, at the start of the app and at each change of the app's language.
    public static var language: String? {
        get { AppLanguageState.shared.fixed }
        set { AppLanguage.set(fixed: newValue) }
    }
}
