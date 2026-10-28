//
//  ExploreCatalogTests.swift
//  ProximiioGADKitTests
//
import Foundation
import UIKit
import Proximiio
import Testing
@testable import ProximiioGADKit

struct ExploreCatalogTests {
    private static let museum = "museum"
    private static let office = "office"
    private static let thematic = "org:thematic"
    private static let single = "org:single"

    private static func place(_ id: String, _ title: String, level: Double, amenity: String? = nil,
                              placeID: String = museum, details: String? = nil) -> VenuePlace {
        var place = VenuePlace(id: id, title: title, details: details,
                               coordinate: .init(latitude: 24.54, longitude: 54.40), level: level, amenityID: amenity)
        place.placeID = placeID
        // The test ids name their amenity ("org:cafe").
        place.amenityKind = amenity.flatMap { AmenityKind.kind(forAmenityID: $0, title: nil) }
        return place
    }

    private static func destination(_ galleryID: String, name: String, level: Double, poi: String) -> GalleryDestination {
        let ring = [ProximiioCoordinate(latitude: 24.5, longitude: 54.4), ProximiioCoordinate(latitude: 24.5, longitude: 54.41),
                    ProximiioCoordinate(latitude: 24.51, longitude: 54.41), ProximiioCoordinate(latitude: 24.51, longitude: 54.4)]
        return GalleryDestination(gallery: Gallery(id: galleryID, name: name, level: level, ring: ring),
                                  entry: .init(latitude: 24.505, longitude: 54.405), placeID: poi)
    }

    private static let catalog: ExploreCatalog = {
        var highlight = place("art", "Tongari-kun", level: 1)
        highlight.isArtwork = true
        highlight.artist = "Yayoi Kusama"
        highlight.galleryID = "g202"
        highlight.includedAmenityIDs = [VenuePlace.highlightAmenityID]
        var artwork = place("art2", "Untitled", level: 2)
        artwork.isArtwork = true
        let places = [
            place("p303", "G303 Language", level: 3, amenity: thematic, details: "Words and signs"),
            place("p202", "G202 Yayoi Kusama", level: 2, amenity: single),
            highlight, artwork,
            place("cafe", "Café", level: 0, amenity: "org:cafe"),
            place("lift", "Elevator 1", level: 1, amenity: "org:elevator"),
            place("dctPrayer", "DCT prayer room", level: 1, amenity: "org:prayer", placeID: office),
        ]
        let destinations = [
            "g303": destination("g303", name: "G303 Language", level: 3, poi: "p303"),
            "g202": destination("g202", name: "G202 Yayoi Kusama", level: 2, poi: "p202"),
        ]
        return ExploreCatalog(places: places, destinations: destinations,
                              categories: [thematic: "Thematic Gallery", single: "Single Artist Gallery"])
    }()

    @Test func spacesAreTheGalleriesWithCategoryAndDescription() {
        let spaces = Self.catalog.spaces
        #expect(spaces.map(\.title) == ["G202 Yayoi Kusama", "G303 Language"])
        #expect(spaces.map(\.lines) == [["Single Artist Gallery"], ["Words and signs"]])
        #expect(spaces.first?.id == "p202")
        #expect(spaces.first?.gallery?.id == "g202")
    }

    @Test func highlightsAreTheArtworksWithTheHighlightAmenity() {
        let highlights = Self.catalog.highlights
        #expect(highlights.map(\.title) == ["Tongari-kun"])
        #expect(highlights.first?.lines == ["Yayoi Kusama", "G202 Yayoi Kusama"])
    }

    @Test func amenitiesLeaveOutLiftsArtworksAndOtherBuildings() {
        #expect(Self.catalog.amenities.map(\.id) == ["cafe"])
        #expect(Self.catalog.amenities.first?.kind == .amenity(.cafe))
    }

    @Test func levelsAndGroupsGoFromTheLowest() {
        #expect(Self.catalog.levels == [0, 1, 2, 3])
        let groups = ExploreCatalog.byLevel(Self.catalog.spaces + Self.catalog.amenities)
        #expect(groups.map(\.level) == [0, 2, 3])
        #expect(groups.map { $0.items.map(\.id) } == [["cafe"], ["p202"], ["p303"]])
    }

    @Test func aTapInsideAGalleryFindsItsSpaceOnItsLevel() {
        let inside = ProximiioCoordinate(latitude: 24.505, longitude: 54.405)
        #expect(Self.catalog.space(at: inside, level: 3)?.id == "p303")
        #expect(Self.catalog.space(at: inside, level: 1) == nil)
        #expect(Self.catalog.space(at: .init(latitude: 24.6, longitude: 54.5), level: 3) == nil)
    }

    @Test func aSpaceFramesItsOutline() {
        #expect(Self.catalog.spaces.first?.framedPoints.count == 4)
        #expect(Self.catalog.amenities.first?.framedPoints.count == 1)
    }

    @Test func theSymbolFollowsTheCategory() {
        #expect(ExploreItem.symbol(for: "Single Artist Gallery") == "paintpalette.fill")
        #expect(ExploreItem.symbol(for: "Thematic Gallery") == "square.grid.2x2.fill")
        #expect(ExploreItem.symbol(for: "Learning & Engagement") == "star.circle.fill")
        #expect(ExploreItem.symbol(for: nil) == "building.columns.fill")
    }

    @Test func theLegendSplitsGalleriesFromFacilitiesAndLeavesOutOtherBuildings() {
        var art = Self.place("art", "Untitled", level: 1, amenity: "org:artwork")
        art.isArtwork = true
        let places = [
            Self.place("p303", "G303 Language", level: 3, amenity: Self.thematic),
            Self.place("perf", "Performance hall", level: 1, amenity: "org:performance"),
            Self.place("lift", "Elevator 1", level: 1, amenity: "org:elevator"),
            Self.place("wc", "Women's Restroom", level: 2, amenity: "org:women"),
            Self.place("dctShop", "DCT shop", level: 1, amenity: "org:shop", placeID: Self.office),
            art,
        ]
        let catalog = ExploreCatalog(
            places: places,
            destinations: ["g303": Self.destination("g303", name: "G303 Language", level: 3, poi: "p303")],
            categories: [Self.thematic: "Thematic Gallery", "org:performance": "Performance Gallery", "org:elevator": "Elevator",
                         "org:women": "Women's Restroom", "org:shop": "Shop", "org:artwork": "Artwork"],
            levelChangerTypes: ["elevator", "staircase"]
        )
        #expect(catalog.legendGalleries.map(\.title) == ["Performance Gallery", "Thematic Gallery"])
        // The POI "Elevator" names the lift already; the staircases add "Stairs".
        #expect(catalog.legendFacilities.map(\.title) == ["Elevator", "Stairs", "Women's Restroom"])
        #expect(catalog.spaces.first?.amenityID == Self.thematic)
    }
}

/// PM, Monday "Explore Museum view: gallery POI view", 2026-10-26.
struct ExploreCalloutTests {
    @Test func thePlaceGoesWhereTheDesignHasItAndIsFramedAroundIt() {
        let size = CGSize(width: 402, height: 874)
        let target = ExploreCalloutLayout.target(in: size)
        #expect(abs(target.x - 124.5) < 0.01 && abs(target.y - 657) < 0.01)
        let insets = ExploreCalloutLayout.framingInsets(in: size)
        // The padded box is centred on the target.
        #expect(abs((insets.left + size.width - insets.right) / 2 - target.x) < 0.01)
        #expect(abs((insets.top + size.height - insets.bottom) / 2 - target.y) < 0.01)
        #expect(insets.bottom >= 110 && insets.top >= 140)
    }

    @Test func theFrameIsCentredOnThePlace() {
        let ring = [ProximiioCoordinate(latitude: 24, longitude: 54), ProximiioCoordinate(latitude: 24.002, longitude: 54.004)]
        let item = ExploreItem(id: "p", kind: .space, title: "G101", lines: [], level: 1,
                               coordinate: ProximiioCoordinate(latitude: 24.0005, longitude: 54.001),
                               gallery: Gallery(id: "g", name: "G101", level: 1, ring: ring))
        let points = ExploreCalloutLayout.framedPoints(of: item)
        let latitudes = points.map(\.latitude), longitudes = points.map(\.longitude)
        #expect(abs((latitudes.min()! + latitudes.max()!) / 2 - 24.0005) < 1e-9)
        #expect(abs((longitudes.min()! + longitudes.max()!) / 2 - 54.001) < 1e-9)
    }
}
