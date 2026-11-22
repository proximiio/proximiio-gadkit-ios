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
            ("Women's Restroom", .restroom), ("Men's Restroom", .restroom), ("Toilet", .restroom), ("Cafe", .cafe),
            ("Restaurant", .restaurant), ("Theatre", .theatre),
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

    /// The dark pixels of `image` drawn at `scale`, in points.
    private static func glyphBounds(of image: UIImage, tint: Bool, scale: CGFloat = 8) -> CGRect {
        let size = image.size
        let width = Int(size.width * scale), height = Int(size.height * scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        (tint ? image.withTintColor(.black, renderingMode: .alwaysOriginal) : image).draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            // The red channel is premultiplied: divide by alpha, or the marker circle's edge counts as dark.
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 128
                && Int(pixels[(y * width + x) * 4]) * 255 / Int(pixels[(y * width + x) * 4 + 3]) < 120 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    /// The PM's icons of 2026-11-22 have the size of the design's first set: a 16 pt glyph box and a
    /// 30 pt marker, the glyph 10 to 14 pt on its longer side, in the centre.
    @Test func everyAmenityIconHasTheDesignsSize() throws {
        for kind in AmenityKind.allCases {
            let glyph = try #require(UIImage(named: kind.icon.rawValue, in: .module, compatibleWith: nil), "\(kind)")
            #expect(glyph.size == CGSize(width: 16, height: 16), "\(kind)")
            let markerName = try #require(kind.icon.markerImageName)
            let marker = try #require(UIImage(named: markerName, in: .module, compatibleWith: nil), "\(kind)")
            #expect(marker.size == CGSize(width: 30, height: 30), "\(kind)")
            for (image, side, tint) in [(glyph, CGFloat(16), true), (marker, CGFloat(30), false)] {
                let bounds = Self.glyphBounds(of: image, tint: tint)
                #expect((10...14.2).contains(max(bounds.width, bounds.height)), "\(kind) \(side): \(bounds)")
                #expect(abs(bounds.midX - side / 2) < 0.6 && abs(bounds.midY - side / 2) < 0.6, "\(kind) \(side): \(bounds)")
            }
        }
    }

    /// A kind takes the icon of its one amenity with a place. Two amenities of a kind (the women's
    /// and the men's restroom) leave the bundled glyph; so does an amenity no place uses (the
    /// "Cafe" of another category) and one without an icon.
    @Test func aKindTakesTheIconOfItsOnlyUsedAmenity() {
        let amenities = [
            ProximiioAmenity(id: "a-cafe", title: "Cafe"), ProximiioAmenity(id: "a-cafe-other", title: "Cafe"),
            ProximiioAmenity(id: "a-women", title: "Women's Restroom"), ProximiioAmenity(id: "a-men", title: "Men's Restroom"),
            ProximiioAmenity(id: "a-prayer", title: "Prayer Room"), ProximiioAmenity(id: "a-stairs", title: "Staircase"),
            ProximiioAmenity(id: "a-gallery", title: "Thematic Gallery"),
        ]
        let ids = VenueGlyphs.amenityIDs(
            amenities: amenities, used: ["a-cafe", "a-women", "a-men", "a-prayer", "a-stairs", "a-gallery"],
            withIcon: ["a-cafe", "a-cafe-other", "a-women", "a-men", "a-stairs", "a-gallery"])
        #expect(ids == [.cafe: "a-cafe", .stairs: "a-stairs"])
    }

    /// The portal's icon of a kind is drawn in the design's marker: the marker keeps the data
    /// icon's size and the glyph is in its centre, 16/30 of the marker.
    @Test func aKindsDataIconIsDrawnInTheDesignsMarker() throws {
        let cafe = ProximiioAmenity(id: "org:cafe", title: "Cafe", icon: Self.icon(side: 120))
        let marker = try #require(MapStyle.amenityImage(for: cafe, scale: 1))
        #expect(marker.size == CGSize(width: 120, height: 120))
        // The data icon is a black square: in the marker it is the 64 px square in the centre.
        let bounds = Self.glyphBounds(of: marker, tint: false, scale: 1)
        #expect(abs(bounds.width - 64) <= 2 && abs(bounds.height - 64) <= 2, "\(bounds)")
        #expect(abs(bounds.midX - 60) <= 1 && abs(bounds.midY - 60) <= 1, "\(bounds)")
        // With the setting off the bundled marker is drawn, at the same size.
        let bundled = try #require(MapStyle.amenityImage(for: cafe, scale: 1, venueIcons: false))
        #expect(bundled.size == CGSize(width: 120, height: 120))
        #expect(Self.glyphBounds(of: bundled, tint: false, scale: 1).width < 60)
    }

    @Test func aGlyphKeepsItsProportions() {
        let rect = CGRect(x: 7, y: 7, width: 16, height: 16)
        #expect(VenueGlyphs.aspectFit(CGSize(width: 120, height: 120), in: rect) == rect)
        #expect(VenueGlyphs.aspectFit(CGSize(width: 120, height: 60), in: rect) == CGRect(x: 7, y: 11, width: 16, height: 8))
    }
}
