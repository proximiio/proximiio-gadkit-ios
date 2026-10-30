//
//  AppLanguageTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Testing
@testable import ProximiioGADKit

struct AppLanguageTests {
    @Test func arabicIdentifiersAreArabicAndTheRestEnglish() {
        #expect(AppLanguage.code(of: "ar") == "ar")
        #expect(AppLanguage.code(of: "ar-AE") == "ar")
        #expect(AppLanguage.code(of: "en-GB") == "en")
        #expect(AppLanguage.code(of: "sk") == "en")
        #expect(AppLanguage.code(of: nil) == "en")
    }

    /// The host app's `\.locale` counts only in another language than the process started in.
    @Test func theHostLocaleCountsInAnotherLanguageThanTheLaunch() {
        #expect(AppLanguage.hostLanguage(of: Locale(identifier: "ar"), launchLanguage: "en") == "ar")
        #expect(AppLanguage.hostLanguage(of: Locale(identifier: "en_AE"), launchLanguage: "ar") == "en")
        #expect(AppLanguage.hostLanguage(of: Locale(identifier: "en_SK"), launchLanguage: "en") == nil)
        #expect(AppLanguage.hostLanguage(of: Locale(identifier: "ar_AE"), launchLanguage: "ar") == nil)
    }

    /// The strings come from the `.lproj` of the language, whatever the process started in.
    @Test func theStringsAreThoseOfTheLanguage() {
        #expect(String(localized: "Search", bundle: AppLanguage.strings(in: "ar")) == "بحث")
        #expect(String(localized: "Search", bundle: AppLanguage.strings(in: "en")) == "Search")
        #expect(String(localized: "Level \(2)", bundle: AppLanguage.strings(in: "en")) == "Level 2")
    }
}
