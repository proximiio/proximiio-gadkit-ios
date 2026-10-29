//
//  AmenityListingTests.swift
//  ProximiioGADKitTests
//
//  The amenity metadata that chooses and orders the search shortcuts and the Explore Museum
//  facilities (PM, Monday "Amenity search & Map legend views", 2026-10-27). Metadata and its keys are
//  optional.
//
import Proximiio
import Testing
@testable import ProximiioGADKit

struct AmenityListingTests {
    private static func amenity(_ id: String, _ title: String, _ metadata: [String: JSONValue]? = nil) -> ProximiioAmenity {
        ProximiioAmenity(id: id, title: title, metadata: metadata.map { .object($0) })
    }

    private static func place(_ id: String, _ title: String, amenity: String) -> VenuePlace {
        VenuePlace(id: id, title: title, details: nil, coordinate: .init(latitude: 24.54, longitude: 54.40), level: 1, amenityID: amenity)
    }

    private static let places = VenuePlace.withAmenityKinds([
        place("p-women", "Women's restroom", amenity: "a-women"), place("p-men", "Men's restroom", amenity: "a-men"),
        place("p-cafe", "Cafe", amenity: "a-cafe"), place("p-help", "Help Desk", amenity: "a-help"),
        place("p-prayer", "Prayer Room", amenity: "a-prayer"), place("p-shop", "Museum Shop", amenity: "a-shop"),
        place("p-stairs", "Staircase", amenity: "a-stairs"),
    ], amenities: [
        amenity("a-women", "Women's Restroom"), amenity("a-men", "Men's Restroom"), amenity("a-cafe", "Cafe"),
        amenity("a-help", "Helpdesk"), amenity("a-prayer", "Prayer Room"), amenity("a-shop", "Museum Shop"),
        amenity("a-stairs", "Staircase"),
    ])

    /// Without metadata the shortcuts are the built-in ones, in the built-in order.
    @Test func withoutMetadataTheShortcutsStay() {
        let listing = AmenityListing.search([Self.amenity("a-women", "Women's Restroom"), Self.amenity("a-cafe", "Cafe", [:])])
        #expect(listing.shortcuts(places: Self.places) == AmenityKind.shortcuts)
        #expect(AmenityListing.all.shortcuts(places: Self.places) == AmenityKind.shortcuts)
    }

    /// Five amenities with the flag true, in the data's order; Help Desk without metadata is left out
    /// (PM, Monday "Amenity search & Map legend views", 2026-10-28).
    @Test func theFlaggedAmenitiesInTheDataOrderAreTheOnlyShortcuts() {
        let listing = AmenityListing.search([
            Self.amenity("a-prayer", "Prayer Room", ["in_search": .string("true"), "search_order": .number(4)]),
            Self.amenity("a-women", "Women's Restroom", ["in_search": .string("true"), "search_order": .number(1)]),
            Self.amenity("a-shop", "Museum Shop", ["in_search": .string("true"), "search_order": .number(5)]),
            Self.amenity("a-cafe", "Cafe", ["in_search": .string("true"), "search_order": .number(3)]),
            Self.amenity("a-men", "Men's Restroom", ["in_search": .string("true"), "search_order": .string("2")]),
            Self.amenity("a-help", "Helpdesk"),
        ])
        #expect(listing.shortcuts(places: Self.places) == [.womensRestroom, .mensRestroom, .cafe, .prayerRoom, .museumShop])
    }

    /// An amenity with the flag true that is none of the kinds is a shortcut too, with its own title, in
    /// the data's order among the kinds; one without a place is left out (PM, 2026-10-29: the galleries
    /// and Learning & Engagement did not show).
    @Test func flaggedAmenitiesOutsideTheKindsAreShortcuts() {
        let amenities = [
            Self.amenity("a-women", "Women's Restroom", ["in_search": .string("true"), "search_order": .number(1)]),
            Self.amenity("a-learning", "Learning & Engagement", ["in_search": .string("true"), "search_order": .number(6)]),
            Self.amenity("a-shop", "Museum Shop", ["in_search": .string("true"), "search_order": .number(5)]),
            Self.amenity("a-gallery", "Single Artist Gallery", ["in_search": .string("true"), "search_order": .number(7)]),
            Self.amenity("a-empty", "Performance Gallery", ["in_search": .string("true"), "search_order": .number(8)]),
        ]
        let places = Self.places + [
            Self.place("p-learning", "Studio", amenity: "a-learning"),
            Self.place("p-gallery", "G205 Pauliina", amenity: "a-gallery"),
        ]
        let shortcuts = AmenityListing.search(amenities).searchShortcuts(places: places, amenities: amenities, language: "en")
        #expect(shortcuts.map(\.title) == ["Women’s restroom", "Museum Shop", "Learning & Engagement", "Single Artist Gallery"])
        #expect(shortcuts.map(\.kind) == [.womensRestroom, .museumShop, nil, nil])
        #expect(shortcuts[2].matches(places.first { $0.id == "p-learning" }!))
        #expect(!shortcuts[2].matches(places.first { $0.id == "p-gallery" }!))
        // Without a flag true the shortcuts are the kinds alone.
        let unflagged = AmenityListing.all.searchShortcuts(places: places, amenities: amenities)
        #expect(unflagged.map(\.kind) == AmenityKind.shortcuts)
    }

    /// The GAD data on 2026-10-28: only Museum Shop has `in_search` true, so it is the only shortcut.
    @Test func oneFlaggedAmenityIsTheOnlyShortcut() {
        let listing = AmenityListing.search([
            Self.amenity("a-shop", "Museum Shop", ["in_search": .string("true"), "search_order": .number(5)]),
            Self.amenity("a-prayer", "Prayer Room"),
        ])
        #expect(listing.shortcuts(places: Self.places) == [.museumShop])
        #expect(listing.rank(of: "a-prayer") == nil)
        #expect(listing.rank(of: nil) == nil)
    }

    /// Without a flag true, a flag false leaves the amenity out of the built-in shortcuts. A flag true
    /// puts in one the built-in list does not have.
    @Test func theFlagLeavesOutOrPutsIn() {
        let without = AmenityListing.search([Self.amenity("a-help", "Helpdesk", ["in_search": .bool(false)])])
        #expect(without.shortcuts(places: Self.places) == AmenityKind.shortcuts.filter { $0 != .helpDesk })
        #expect(without.rank(of: "a-help") == nil)
        #expect(without.rank(of: "a-unknown") == .greatestFiniteMagnitude)
        #expect(without.rank(of: nil) == .greatestFiniteMagnitude)

        let stairs = AmenityListing.search([Self.amenity("a-stairs", "Staircase", ["in_search": .bool(true), "search_order": .number(0)])])
        #expect(stairs.shortcuts(places: Self.places) == [.stairs])
    }

    /// The facilities keys choose and order the Explore Museum's Amenities list within a level and the
    /// legend. With a flag true only the flagged amenities show.
    @Test func theFacilitiesOrderTheExploreLists() {
        let facilities = AmenityListing.facilities([
            Self.amenity("a-shop", "Museum Shop", ["in_facilities": .string("true"), "facilities_order": .number(1)]),
            Self.amenity("a-women", "Women's Restroom", ["in_facilities": .string("false")]),
            Self.amenity("a-elevator", "Elevator", ["facilities_order": .number(2)]),
        ])
        let catalog = ExploreCatalog(
            places: Self.places, destinations: [:],
            categories: ["a-shop": "Museum Shop", "a-women": "Women's Restroom", "a-cafe": "Cafe", "a-men": "Men's Restroom"],
            levelChangerTypes: ["elevator"], facilities: facilities
        )
        #expect(catalog.amenities.map(\.title) == ["Museum Shop"])
        #expect(catalog.legendFacilities.map(\.title) == ["Museum Shop"])

        let ordered = AmenityListing.facilities([
            Self.amenity("a-women", "Women's Restroom", ["in_facilities": .string("false")]),
            Self.amenity("a-elevator", "Elevator", ["facilities_order": .number(0)]),
        ])
        let unflagged = ExploreCatalog(
            places: Self.places, destinations: [:],
            categories: ["a-shop": "Museum Shop", "a-women": "Women's Restroom", "a-cafe": "Cafe", "a-men": "Men's Restroom"],
            levelChangerTypes: ["elevator"], facilities: ordered
        )
        #expect(!unflagged.amenities.contains { $0.title == "Women's restroom" })
        #expect(unflagged.legendFacilities.first?.title == "Elevator")
        #expect(!unflagged.legendFacilities.contains { $0.title == "Women's Restroom" })
    }
}
