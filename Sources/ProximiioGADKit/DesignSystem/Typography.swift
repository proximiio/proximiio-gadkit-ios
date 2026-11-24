//
//  Typography.swift
//  ProximiioGADKit
//
//  Text styles from the Figma "Typography" section (node 6902:46986), read with
//  `get_variable_defs`. Every style uses Guggenheim Sans Display at 100 % line height.
//  Caption has 6 % letter spacing.
//
//  Every style scales with Dynamic Type, relative to the closest system text style.
//
//  The font files are package resources (`Resources/Fonts`). `GADFonts` registers them for the
//  process the first time a font is created, so a host app lists no `UIAppFonts`.
//
//  Guggenheim Sans Display has no Arabic glyphs. While the package's language is Arabic, every style
//  uses Guggenheim Arabic in the same weight (`GADFonts.name(_:language:)`). Guggenheim Arabic holds
//  the Latin glyphs of Guggenheim Sans Display with the same advance widths, and a line gap of 27 %
//  of the point size between the lines of a text.
//
import CoreText
import SwiftUI
import UIKit

@_spi(GADApp) public enum TextStyle: CaseIterable, Sendable {
    case cardTitle
    case h1Regular, h1Bold
    case largeBodyRegular, largeBodyBold
    case bodyRegular, bodyMedium, bodyBold
    case bodySmallRegular, bodySmallBold
    /// The title of the Explore Museum map legend: SemiBold 14 (PM, Monday "Explore Museum: Map legend
    /// missing", 2026-10-26).
    case bodySmallSemiBold
    case bodyExtraSmall, caption

    public enum Weight: String, Sendable {
        case regular = "Regular", medium = "Medium", semiBold = "SemiBold", bold = "Bold"
    }

    public var weight: Weight {
        switch self {
        case .cardTitle, .bodySmallSemiBold: .semiBold
        case .h1Bold, .largeBodyBold, .bodyBold, .bodySmallBold: .bold
        case .bodyMedium: .medium
        default: .regular
        }
    }

    /// Point size at the default Dynamic Type setting.
    public var size: CGFloat {
        switch self {
        case .cardTitle: 32
        case .h1Regular, .h1Bold: 24
        case .largeBodyRegular, .largeBodyBold: 18
        case .bodyRegular, .bodyMedium, .bodyBold: 16
        case .bodySmallRegular, .bodySmallBold, .bodySmallSemiBold: 14
        case .bodyExtraSmall, .caption: 12
        }
    }

    /// Letter spacing in points (Figma gives Caption 6 %).
    public var tracking: CGFloat {
        self == .caption ? size * 0.06 : 0
    }

    /// The system style this one scales with.
    public var relativeTo: Font.TextStyle {
        switch self {
        case .cardTitle: .largeTitle
        case .h1Regular, .h1Bold: .title
        case .largeBodyRegular, .largeBodyBold: .title3
        case .bodyRegular, .bodyMedium, .bodyBold: .body
        case .bodySmallRegular, .bodySmallBold, .bodySmallSemiBold: .subheadline
        case .bodyExtraSmall: .footnote
        case .caption: .caption
        }
    }

    /// PostScript name of the bundled font file.
    public var postScriptName: String { "GuggenheimSansDisplay-\(weight.rawValue)" }

    public var font: Font { GADFonts.custom(postScriptName, size: size, relativeTo: relativeTo) }
}

/// The Guggenheim Sans Display and Guggenheim Arabic fonts of the package bundle.
@_spi(GADApp) public enum GADFonts {
    /// Registers the fonts for this process. Later calls do nothing. `TextStyle.font` calls it;
    /// a host app calls it only before it creates a font by name, for example with
    /// `UIFont(name:size:)`.
    public static func register() {
        _ = registration
    }

    private static let registration: Void = {
        for type in ["ttf", "otf"] {
            for url in Bundle.module.urls(forResourcesWithExtension: type, subdirectory: nil) ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static let latinPrefix = "GuggenheimSansDisplay-"
    static let arabicPrefix = "GuggenheimArabicBETAv2-"

    /// The PostScript name to draw `name` with in `language`: the Guggenheim Arabic font of the same
    /// weight for a Guggenheim Sans Display name in Arabic, else `name`. Pure; covered by tests.
    static func name(_ name: String, language: String) -> String {
        guard language == "ar", name.hasPrefix(latinPrefix) else { return name }
        return arabicPrefix + name.dropFirst(latinPrefix.count)
    }

    /// A package font by the PostScript name of its Guggenheim Sans Display file, scaled with
    /// Dynamic Type. In Arabic it is the Guggenheim Arabic font of the same weight.
    static func custom(_ name: String, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        register()
        return .custom(Self.name(name, language: AppLanguage.current), size: size, relativeTo: style)
    }

    /// The same font for UIKit drawing, at a fixed size.
    static func uiFont(_ name: String, size: CGFloat) -> UIFont? {
        register()
        return UIFont(name: Self.name(name, language: AppLanguage.current), size: size)
    }
}

extension View {
    /// Applies a design-system text style.
    @_spi(GADApp) public func textStyle(_ style: TextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
