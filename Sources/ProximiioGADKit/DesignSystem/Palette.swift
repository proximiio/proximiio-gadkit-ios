//
//  Palette.swift
//  ProximiioGADKit
//
//  Colours from the Figma "Color palette" section (node 6902:47826). The hex values are
//  final; the semantic names below them are our reading of the design and are to be
//  confirmed with the design team (see design/README.md).
//
import SwiftUI

public enum Palette {
    // MARK: Brand spectrum, in the order the palette shows it.
    public static let lime = Color(hex: 0x65FF2E)
    public static let mint = Color(hex: 0x00FFB2)
    public static let cyan = Color(hex: 0x34EEFF)
    public static let blue = Color(hex: 0x6FA6FF)
    public static let lavender = Color(hex: 0xC0B3FF)
    public static let violet = Color(hex: 0xBB87F3)
    public static let purple = Color(hex: 0xA566FF)
    public static let orchid = Color(hex: 0xCF63C0)
    public static let red = Color(hex: 0xFF5353)
    public static let orange = Color(hex: 0xFA8352)
    public static let yellow = Color(hex: 0xFFE523)

    // MARK: Neutrals
    public static let white = Color(hex: 0xFFFFFF)
    public static let ink = Color(hex: 0x2B2B2B)

    // MARK: Glass and badges (Figma components)
    public static let glassEdge = Color(hex: 0xE6E6E6)
    public static let badgeStroke = Color(hex: 0xEEEDED)
    /// Red of the active stop and the destination marker (Figma map frames).
    public static let activeRed = Color(hex: 0xED3731)
    /// Blue of the "you are here" marker (`You_are_here.svg`).
    public static let position = Color(hex: 0x3F69FF)

    // MARK: Inputs (Figma "Inputs" section)
    public static let inputFill = Color(hex: 0xEEFAF0)
    public static let inputStroke = Color(hex: 0xDDDDDD)
    public static let errorLabel = Color(hex: 0xFF0000)
    public static let errorStroke = Color(hex: 0xFF8686)

    /// Opacity of a disabled control (buttons and inputs).
    public static let disabledOpacity = 0.4

    /// The colour of a museum level on the map ("MAP Functionality Approach 02",
    /// Level 0–4). Read from the level previews; to be confirmed with the design team.
    public static func level(_ level: Int) -> Color {
        switch level {
        case 0: mint
        case 1: blue
        case 2: purple
        case 3: yellow
        case 4: orange
        default: ink
        }
    }
}

extension Color {
    /// A colour from a 24-bit RGB value, e.g. `0x2B2B2B`.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
