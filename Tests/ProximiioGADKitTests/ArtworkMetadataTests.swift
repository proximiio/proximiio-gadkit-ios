//
//  ArtworkMetadataTests.swift
//  ProximiioGADKitTests
//
import Foundation
import Proximiio
import Testing
@testable import ProximiioGADKit

struct ArtworkMetadataTests {
    private func place(metadata: String) throws -> VenuePlace {
        let json = """
        {"type": "Feature", "id": "a", "geometry": {"type": "Point", "coordinates": [54.4, 24.5]},
         "properties": {"type": "poi", "title": "Untitled (Mirrored Room)", "level": 1, "metadata": \(metadata)}}
        """
        let feature = try JSONDecoder().decode(ProximiioFeature.self, from: Data(json.utf8))
        return try #require(VenuePlace(feature: feature))
    }

    @Test func readsArtistAndBadges() throws {
        let place = try place(metadata: #"{"artist_name": "Lucas Samaras", "has_ar": true, "has_audio": "true"}"#)
        #expect(place.artist == "Lucas Samaras")
        #expect(place.hasAR)
        #expect(place.hasAudio)
    }

    @Test func withoutTheKeysThereIsNoArtistAndNoBadge() throws {
        let place = try place(metadata: #"{"artwork_id": "x", "artist_id": "y"}"#)
        #expect(place.artist == nil)
        #expect(!place.hasAR)
        #expect(!place.hasAudio)
    }

    @Test func flagValues() {
        #expect(VenuePlace.flag(.bool(true)))
        #expect(VenuePlace.flag(.string("TRUE")))
        #expect(VenuePlace.flag(.number(1)))
        #expect(!VenuePlace.flag(.bool(false)))
        #expect(!VenuePlace.flag(.string("yes")))
        #expect(!VenuePlace.flag(.number(0)))
        #expect(!VenuePlace.flag(nil))
    }
}
