//
//  GalleryFirstTests.swift
//  ProximiioGADKitTests
//
//  Port of `guggenheim-android` `GalleryFirstTest.kt`.
//
import Proximiio
import Testing
@testable import ProximiioGADKit

struct GalleryFirstTests {
    private static let square = [
        ProximiioCoordinate(latitude: 0, longitude: 0), ProximiioCoordinate(latitude: 0, longitude: 1),
        ProximiioCoordinate(latitude: 1, longitude: 1), ProximiioCoordinate(latitude: 1, longitude: 0),
    ]
    private let g106 = Gallery(id: "106", name: "Gallery 106", level: 1, ring: Self.square)
    private let g107 = Gallery(id: "107", name: "Gallery 107", level: 1,
                               ring: Self.square.map { ProximiioCoordinate(latitude: $0.latitude + 2, longitude: $0.longitude) })

    @Test func outsideTheStopsGalleryNamesTheGallery() {
        #expect(GalleryFirst.galleryAhead(activeStopID: "s1", stopGallery: g106, reachedStopID: nil) == g106)
        #expect(GalleryFirst.reachedStopID(activeStopID: "s1", stopGallery: g106, visitorGallery: g106, reachedStopID: nil) == "s1")
        #expect(GalleryFirst.reachedStopID(activeStopID: "s1", stopGallery: g106, visitorGallery: g107, reachedStopID: nil) == nil)
        #expect(GalleryFirst.reachedStopID(activeStopID: "s1", stopGallery: g106, visitorGallery: nil, reachedStopID: nil) == nil)
    }

    @Test func theLatchHoldsUntilTheStopChanges() {
        let reached = GalleryFirst.reachedStopID(activeStopID: "s1", stopGallery: g106, visitorGallery: g106, reachedStopID: nil)
        #expect(GalleryFirst.galleryAhead(activeStopID: "s1", stopGallery: g106, reachedStopID: reached) == nil)
        // Walking out of the gallery again keeps the artwork.
        let after = GalleryFirst.reachedStopID(activeStopID: "s1", stopGallery: g106, visitorGallery: nil, reachedStopID: reached)
        #expect(after == "s1")
        #expect(GalleryFirst.galleryAhead(activeStopID: "s1", stopGallery: g106, reachedStopID: after) == nil)
        // The next stop names its gallery again.
        #expect(GalleryFirst.galleryAhead(activeStopID: "s2", stopGallery: g107, reachedStopID: reached) == g107)
        #expect(GalleryFirst.reachedStopID(activeStopID: "s2", stopGallery: g107, visitorGallery: g107, reachedStopID: reached) == "s2")
    }

    @Test func aStopOutsideEveryGalleryShowsTheArtwork() {
        #expect(GalleryFirst.galleryAhead(activeStopID: "s1", stopGallery: nil, reachedStopID: nil) == nil)
        #expect(GalleryFirst.reachedStopID(activeStopID: "s1", stopGallery: nil, visitorGallery: g106, reachedStopID: nil) == nil)
        #expect(GalleryFirst.galleryAhead(activeStopID: nil, stopGallery: g106, reachedStopID: nil) == nil)
    }

    @Test func stopNumber() {
        #expect(!GalleryFirst.showsStopNumber(state: .walking(stop: "Tongari-kun"), galleryAhead: g106))
        #expect(!GalleryFirst.showsStopNumber(state: .nextStopOnOtherLevel(stop: "Tongari-kun", level: 3), galleryAhead: g106))
        #expect(GalleryFirst.showsStopNumber(state: .walking(stop: "Tongari-kun"), galleryAhead: nil))
        #expect(GalleryFirst.showsStopNumber(state: .atStop(stop: "Tongari-kun"), galleryAhead: g106))
    }
}
