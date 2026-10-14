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

    @Test func aKnownAmenityIsDrawnWithTheThirtyPointMarker() throws {
        let amenity = ProximiioAmenity(id: "org:cafe", title: "Cafe")
        let image = try #require(MapStyle.amenityImage(for: amenity, scale: 3))
        #expect(image.size == CGSize(width: 30, height: 30))
    }

    @Test func anOtherAmenityKeepsItsIconAtTheScreenScale() throws {
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        }
        let amenity = ProximiioAmenity(id: "org:artwork", title: "Artwork", icon: "data:image/png;base64," + pixels.base64EncodedString())
        let image = try #require(MapStyle.amenityImage(for: amenity, scale: 3))
        #expect(image.size == CGSize(width: 10, height: 10))
    }
}
