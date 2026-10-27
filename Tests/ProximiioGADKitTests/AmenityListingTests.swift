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

    private static let places = [
        place("p-women", "Women's restroom", amenity: "a-women"), place("p-men", "Men's restroom", amenity: "a-men"),
        place("p-cafe", "Cafe", amenity: "a-cafe"), place("p-help", "Help Desk", amenity: "a-help"),
        place("p-prayer", "Prayer Room", amenity: "a-prayer"), place("p-shop", "Museum Shop", amenity: "a-shop"),
        place("p-stairs", "Staircase", amenity: "a-stairs"),
    ]

    /// Without metadata the shortcuts are the built-in ones, in the built-in order.
    @Test func withoutMetadataTheShortcutsStay() {
        let listing = AmenityListing.search([Self.amenity("a-women", "Women's Restroom"), Self.amenity("a-cafe", "Cafe", [:])])
        #expect(listing.shortcuts(places: Self.places) == AmenityKind.shortcuts)
        #expect(AmenityListing.all.shortcuts(places: Self.places) == AmenityKind.shortcuts)
    }

    /// The GAD data on 2026-10-27: five amenities ordered, Help Desk without metadata after them.
    @Test func theOrderComesFromTheMetadataAndTheRestFollows() {
        let listing = AmenityListing.search([
            Self.amenity("a-prayer", "Prayer Room", ["in_search": .string("true"), "search_order": .number(4)]),
            Self.amenity("a-women", "Women's Restroom", ["in_search": .string("true"), "search_order": .number(1)]),
            Self.amenity("a-shop", "Museum Shop", ["in_search": .string("true"), "search_order": .number(5)]),
            Self.amenity("a-cafe", "Cafe", ["in_search": .string("true"), "search_order": .number(3)]),
            Self.amenity("a-men", "Men's Restroom", ["in_search": .string("true"), "search_order": .string("2")]),
            Self.amenity("a-help", "Helpdesk"),
        ])
        #expect(listing.shortcuts(places: Self.places) == [.womensRestroom, .mensRestroom, .cafe, .prayerRoom, .museumShop, .helpDesk])
    }

    /// A flag that is false leaves the amenity out; a flag that is true puts in one the list does not
    /// show by itself.
    @Test func theFlagLeavesOutOrPutsIn() {
        let listing = AmenityListing.search([
            Self.amenity("a-help", "Helpdesk", ["in_search": .bool(false)]),
            Self.amenity("a-stairs", "Staircase", ["in_search": .bool(true), "search_order": .number(0)]),
        ])
        let shortcuts = listing.shortcuts(places: Self.places)
        #expect(!shortcuts.contains(.helpDesk))
        #expect(shortcuts.first == .stairs)
        #expect(listing.rank(of: "a-help") == nil)
        #expect(listing.rank(of: "a-unknown") == .greatestFiniteMagnitude)
        #expect(listing.rank(of: nil) == .greatestFiniteMagnitude)
    }

    /// The facilities keys order the Explore Museum's Amenities list within a level and the legend.
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
        #expect(catalog.amenities.first?.title == "Museum Shop")
        #expect(!catalog.amenities.contains { $0.title == "Women's restroom" })
        #expect(catalog.legendFacilities.map(\.title).prefix(2) == ["Museum Shop", "Elevator"])
        #expect(!catalog.legendFacilities.contains { $0.title == "Women's Restroom" })
    }
}
