//
//  Buttons.swift
//  ProximiioGADKit
//
//  Button styles from the Figma "Buttons" section (node 6902:47010):
//
//  | Style | Figma component | Shape |
//  |---|---|---|
//  | `.primary` | Button Primary Large | glass, 60 pt high, full width, Body Medium |
//  | `.ghost` | Button Ghost Medium | glass, 40 pt high, Body Medium |
//  | `.small` | Button Small | glass, 32 pt high, Body Small |
//  | `.iconGlass` | Button_medium | glass, 40 × 40 pt, 16 pt icon |
//  | `.textAction` | "Skip for now", "Carry on" | Body Small, underlined |
//
//  The glass styles draw `glassSurface` in the button's shape: Apple's Regular glass on iOS 26 and
//  later. Pressed and selected are a 1 pt ink outline; the button does not grow or shrink (PM, Monday
//  "Buttons to have black border when pressed", 2026-10-28: Apple's glass button style grew on a
//  press). Disabled is 40 % opacity.
//
import SwiftUI

@_spi(GADApp) public struct PrimaryButtonStyle: PrimitiveButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .roundedRectangle(12)) {
            configuration.label
                .textStyle(.bodyMedium)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }
}

@_spi(GADApp) public struct GhostButtonStyle: PrimitiveButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .roundedRectangle(12)) {
            configuration.label
                .textStyle(.bodyMedium)
                .padding(.horizontal, 30)
                .frame(minHeight: 40)
        }
    }
}

@_spi(GADApp) public struct SmallButtonStyle: PrimitiveButtonStyle {
    var isSelected = false
    var strength: GlassStrength = .light

    public func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .roundedRectangle(12), isSelected: isSelected, strength: strength) {
            configuration.label
                .textStyle(.bodySmallRegular)
                .padding(.horizontal, 16)
                .frame(minHeight: 32)
        }
    }
}

@_spi(GADApp) public struct IconGlassButtonStyle: PrimitiveButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .roundedRectangle(12)) {
            configuration.label
                .frame(width: 40, height: 40)
        }
    }
}

@_spi(GADApp) public struct TextActionButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodySmallRegular)
            .underline()
            .foregroundStyle(Palette.ink)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The shape of a `GlassButton`.
enum GlassButtonShape: Equatable {
    /// A rounded rectangle with this corner radius.
    case roundedRectangle(CGFloat)
    case capsule
    case circle
}

/// The button of `configuration` with `label` on glass in `shape`. `label` has the size of the
/// design's button.
struct GlassButton<Label: View>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    var shape: GlassButtonShape
    var isSelected = false
    /// The glass below iOS 26. On iOS 26 and later every button is Apple's Regular glass.
    var strength: GlassStrength = .regular
    @ViewBuilder let label: Label
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(role: configuration.role, action: configuration.trigger) {
            label.foregroundStyle(Palette.ink)
        }
        .buttonStyle(GlassSurfaceButtonStyle(shape: shape, strength: strength, isSelected: isSelected, isEnabled: isEnabled))
    }
}

/// `glassSurface` in the button's shape, with the 1 pt ink outline while pressed or selected.
private struct GlassSurfaceButtonStyle: ButtonStyle {
    let shape: GlassButtonShape
    let strength: GlassStrength
    let isSelected: Bool
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label)
            .contentShape(Rectangle())
            .overlay {
                if isSelected || configuration.isPressed { outline }
            }
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
    }

    @ViewBuilder private func surface(_ label: some View) -> some View {
        switch shape {
        case .roundedRectangle(let radius): label.glassSurface(RoundedRectangle(cornerRadius: radius), strength: strength, shadow: isEnabled)
        case .capsule: label.glassSurface(Capsule(), strength: strength, shadow: isEnabled)
        case .circle: label.glassSurface(Circle(), strength: strength, shadow: isEnabled)
        }
    }

    @ViewBuilder private var outline: some View {
        switch shape {
        case .roundedRectangle(let radius): RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.ink, lineWidth: 1).allowsHitTesting(false)
        case .capsule: Capsule().strokeBorder(Palette.ink, lineWidth: 1).allowsHitTesting(false)
        case .circle: Circle().strokeBorder(Palette.ink, lineWidth: 1).allowsHitTesting(false)
        }
    }
}

@_spi(GADApp) extension PrimitiveButtonStyle where Self == PrimaryButtonStyle {
    @_spi(GADApp) public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

@_spi(GADApp) extension PrimitiveButtonStyle where Self == GhostButtonStyle {
    @_spi(GADApp) public static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

@_spi(GADApp) extension PrimitiveButtonStyle where Self == SmallButtonStyle {
    @_spi(GADApp) public static var small: SmallButtonStyle { SmallButtonStyle() }
    @_spi(GADApp) public static func small(selected: Bool, strength: GlassStrength = .light) -> SmallButtonStyle {
        SmallButtonStyle(isSelected: selected, strength: strength)
    }
}

@_spi(GADApp) extension PrimitiveButtonStyle where Self == IconGlassButtonStyle {
    @_spi(GADApp) public static var iconGlass: IconGlassButtonStyle { IconGlassButtonStyle() }
}

@_spi(GADApp) extension ButtonStyle where Self == TextActionButtonStyle {
    @_spi(GADApp) public static var textAction: TextActionButtonStyle { TextActionButtonStyle() }
}
