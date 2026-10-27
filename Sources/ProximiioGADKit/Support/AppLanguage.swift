//
//  AppLanguage.swift
//  ProximiioGADKit
//
//  The app language for map labels: "ar" when the first preferred language is Arabic, else "en".
//  The visitor picks it in iOS Settings (per-app language). An app that switches its language
//  itself sets `AppleLanguages`; the open maps take the new language at once (PM, Monday "Language
//  switching option missing", 2026-10-26). The package's texts follow at the next launch.
//
import Foundation
import ProximiioMap

enum AppLanguage {
    static var current: String {
        let preferred = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
            ?? Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.hasPrefix("ar") ? "ar" : "en"
    }

    /// Keeps the labels of `session` in `current` while the session lives.
    @MainActor static func follow(_ session: ProximiioMapSession) {
        MapLanguageFollower.shared.add(session)
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
    private var observer: NSObjectProtocol?

    func add(_ session: ProximiioMapSession) {
        entries = entries.filter { $0.session != nil } + [Entry(session: session)]
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MapLanguageFollower.shared.languageMayHaveChanged() }
        }
    }

    private func languageMayHaveChanged() {
        let language = AppLanguage.current
        guard language != applied else { return }
        applied = language
        FieldLog.log("map language \(language)")
        for session in entries.compactMap(\.session) {
            session.options.language = language
        }
    }
}
