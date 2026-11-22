//
//  VenueGlyphs.swift
//  ProximiioGADKit
//
//  The glyphs of the amenity kinds from the venue data (PM, 2026-11-22: every amenity icon is
//  edited in the portal). An amenity kind (`AmenityKind`) is drawn with the icon of its amenity in
//  the venue data. The glyph bundled in the package is drawn when the data has no icon for the
//  kind, when two amenities of the kind have a place (the women's and the men's restroom), or when
//  `GADSettings.usesVenueAmenityIcons` is `false`.
//
//  A data icon is a dark glyph on a transparent square (120 × 120 px in the GAD data). It takes the
//  place of the bundled 16 pt glyph: tinted in lists and chips, in the centre of the 30 pt marker
//  on the maps.
//
import Foundation
import Proximiio
import UIKit

enum VenueGlyphs {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: [GADIcon: UIImage] = [:]

    /// The data glyph of `icon`, or `nil` for the bundled one.
    static func glyph(for icon: GADIcon) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return stored[icon]
    }

    /// Sets the data glyphs. Returns `true` when a glyph was added, removed or replaced.
    @discardableResult static func set(_ glyphs: [GADIcon: UIImage]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let changed = Set(glyphs.keys) != Set(stored.keys) || glyphs.contains { stored[$0.key]?.pngData() != $0.value.pngData() }
        stored = glyphs
        return changed
    }

    /// The amenity whose icon each kind takes: the one amenity of the kind that is in `used` and
    /// has an icon. A kind with two such amenities has none. Pure; covered by tests.
    static func amenityIDs(amenities: [ProximiioAmenity], used: Set<String>, withIcon: Set<String>) -> [AmenityKind: String] {
        var candidates: [AmenityKind: Set<String>] = [:]
        for amenity in amenities where used.contains(amenity.id) && withIcon.contains(amenity.id) {
            guard let kind = AmenityKind.kind(forAmenityID: amenity.id, title: amenity.title) else { continue }
            candidates[kind, default: []].insert(amenity.id)
        }
        return candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Takes the glyphs from `icons` (by amenity id) for the amenities that places or level
    /// changers use (`used`). `enabled` is `GADSettings.usesVenueAmenityIcons`.
    @discardableResult static func update(amenities: [ProximiioAmenity], used: Set<String>, icons: [String: UIImage], enabled: Bool) -> Bool {
        guard enabled else { return set([:]) }
        let ids = amenityIDs(amenities: amenities, used: used, withIcon: Set(icons.keys))
        var glyphs: [GADIcon: UIImage] = [:]
        for (kind, id) in ids { glyphs[kind.icon] = icons[id] }
        return set(glyphs)
    }

    /// The 30 pt map marker of the design with `glyph` in its centre: a white circle with a
    /// `#EEEDED` border and the glyph in a 16 pt square, dark. `size` scales the marker.
    static func marker(glyph: UIImage, size: CGSize = CGSize(width: 30, height: 30), scale: CGFloat = 0) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        if scale > 0 { format.scale = scale }
        let unit = min(size.width, size.height) / 30
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: unit / 2, dy: unit / 2))
            UIColor.white.setFill()
            circle.fill()
            UIColor(hex: 0xEEEDED).setStroke()
            circle.lineWidth = unit
            circle.stroke()
            glyph.withTintColor(UIColor(hex: 0x2B2B2B), renderingMode: .alwaysOriginal)
                .draw(in: aspectFit(glyph.size, in: CGRect(x: 7 * unit, y: 7 * unit, width: 16 * unit, height: 16 * unit)))
        }
    }

    /// `size` scaled to fit `rect`, in its centre. Pure; covered by tests.
    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let factor = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * factor, height: size.height * factor)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}
