//
//  ExploreCatalogTests.swift
//  ProximiioGADKitTests
//
import Foundation
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
        #expect(spaces.map(\.lines) == [["Single Artist Gallery"], ["Thematic Gallery. Words and signs"]])
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
}
