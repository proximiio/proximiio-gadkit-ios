//
//  VenueTitlesTests.swift
//  ProximiioGADKitTests
//
import Proximiio
import Testing
@testable import ProximiioGADKit

struct VenueTitlesTests {
    /// The untagged `title` is English: it names the kind in English and not in Arabic.
    @Test func theUntaggedTitleCountsOnlyForTheDataLanguage() {
        let toilet = ProximiioAmenity(id: "a-toilet", title: "Accessible Toilet")
        let titles = VenueTitles.titles(of: toilet, untaggedLanguage: "en")
        #expect(VenueTitles.title(in: titles, language: "en") == "Accessible Toilet")
        #expect(VenueTitles.title(in: titles, language: "en-GB") == "Accessible Toilet")
        #expect(VenueTitles.title(in: titles, language: "ar") == nil)
        #expect(VenueTitles.titles(of: toilet, untaggedLanguage: "").isEmpty)
    }

    /// `title_i18n` names the kind in each of its languages and goes before the untagged title.
    @Test func theTranslatedTitleGoesBeforeTheUntaggedTitle() {
        let toilet = ProximiioAmenity(
            id: "a-toilet", title: "Accessible Toilet", metadata: nil,
            titleTranslations: ["AR": "دورة مياه", "en": "Accessible toilet", "fr": "  "])
        let titles = VenueTitles.titles(of: toilet, untaggedLanguage: "en")
        #expect(VenueTitles.title(in: titles, language: "ar") == "دورة مياه")
        #expect(VenueTitles.title(in: titles, language: "ar-AE") == "دورة مياه")
        #expect(VenueTitles.title(in: titles, language: "en") == "Accessible toilet")
        #expect(VenueTitles.title(in: titles, language: "fr") == nil)
    }

    /// A kind takes the titles of its one amenity with a place. Two amenities of a kind leave the
    /// package's text; so does an amenity no place uses.
    @Test func aKindTakesTheTitlesOfItsOnlyUsedAmenity() {
        let amenities = [
            ProximiioAmenity(id: "a-restaurant", title: "Restaurant"),
            ProximiioAmenity(id: "a-women", title: "Women's Restroom"), ProximiioAmenity(id: "a-men", title: "Men's Restroom"),
            ProximiioAmenity(id: "a-prayer", title: "Prayer Room"),
            ProximiioAmenity(id: "a-learning", title: "Learning & Engagement"),
        ]
        let titles = VenueTitles.titles(
            amenities: amenities, used: ["a-restaurant", "a-women", "a-men", "a-learning"], untaggedLanguage: "en")
        #expect(titles == [.restaurant: ["en": "Restaurant"]])
    }

    /// The kind's title is the data title in the app language, else the package's text.
    @Test func aKindWithoutADataTitleShowsThePackagesText() {
        let toilet = ProximiioAmenity(id: "a-toilet", title: "Accessible Toilet")
        VenueTitles.update(amenities: [toilet], used: ["a-toilet"], enabled: true, untaggedLanguage: "en")
        #expect(VenueTitles.title(for: .restroom, language: "en") == "Accessible Toilet")
        #expect(VenueTitles.title(for: .restroom, language: "ar") == nil)
        #expect(VenueTitles.title(for: .cafe, language: "en") == nil)
        VenueTitles.update(amenities: [toilet], used: ["a-toilet"], enabled: false, untaggedLanguage: "en")
        #expect(VenueTitles.title(for: .restroom, language: "en") == nil)
    }
}
