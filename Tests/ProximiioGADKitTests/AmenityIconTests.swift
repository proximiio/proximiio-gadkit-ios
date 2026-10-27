//
//  AmenityIconTests.swift
//  ProximiioGADKitTests
//
import Proximiio
import ProximiioMap
import Testing
import UIKit
@testable import ProximiioGADKit

struct AmenityIconTests {
    @Test func gadAmenitiesMapToTheirKinds() {
        let cases: [(String, AmenityKind?)] = [
            ("Women's Restroom", .womensRestroom), ("Men's Restroom", .mensRestroom), ("Cafe", .cafe),
            ("Helpdesk", .helpDesk), ("Prayer Room", .prayerRoom), ("Staircase", .stairs),
            ("Elevator", .elevator), ("Museum Shop", .museumShop),
            ("Womens restroom visited", nil), ("Womens restroom distination", nil),
            ("Artwork", nil), ("Gallery", nil), ("Escalator", nil),
        ]
        for (title, kind) in cases {
            #expect(AmenityKind.kind(forAmenityID: "org:id", title: title) == kind, "\(title)")
        }
    }

    /// A data icon of `side` × `side` pixels.
    private static func icon(side: CGFloat) -> String {
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return "data:image/png;base64," + pixels.base64EncodedString()
    }

    /// The design's marker takes the size of the data icon it replaces, so the style's `icon-size`
    /// scales it as MapTap scales the data icon.
    @Test func aKnownAmenityIsDrawnWithTheDesignsMarkerAtTheDataIconsSize() throws {
        let cafe = ProximiioAmenity(id: "org:cafe", title: "Cafe", icon: Self.icon(side: 120))
        #expect(try #require(MapStyle.amenityImage(for: cafe, scale: 3)).size == CGSize(width: 120, height: 120))
        let withoutIcon = ProximiioAmenity(id: "org:cafe", title: "Cafe")
        #expect(try #require(MapStyle.amenityImage(for: withoutIcon, scale: 3)).size == CGSize(width: 120, height: 120))
    }

    /// One point per pixel, as MapLibre GL JS in the portal and MapTap (PM, 2026-10-27: icon-size 0.2
    /// for 120 px icons drew 8 pt gallery icons on iOS).
    @Test func anOtherAmenityKeepsItsIconAtOnePointPerPixel() throws {
        let amenity = ProximiioAmenity(id: "org:artwork", title: "Artwork", icon: Self.icon(side: 120))
        let image = try #require(MapStyle.amenityImage(for: amenity, scale: 3))
        #expect(image.size == CGSize(width: 120, height: 120))
    }

    /// The Explore Museum circle has the data icon's size too.
    @Test func theExploreGalleryCircleHasTheDataIconsSize() throws {
        let gallery = ProximiioAmenity(id: "org:thematic", title: "Thematic Gallery", icon: Self.icon(side: 120))
        let image = try #require(MapStyle.exploreAmenityImage(for: gallery, scale: 3))
        #expect(image.size == CGSize(width: 120, height: 120))
    }
}
