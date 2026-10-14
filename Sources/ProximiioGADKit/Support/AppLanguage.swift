//
//  AppLanguage.swift
//  ProximiioGADKit
//
//  The app language for map labels: "ar" when the first preferred language is Arabic, else "en".
//  The visitor picks it in iOS Settings (per-app language).
//
import Foundation

enum AppLanguage {
    static var current: String {
        let preferred = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
            ?? Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.hasPrefix("ar") ? "ar" : "en"
    }
}
