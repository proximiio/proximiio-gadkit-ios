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
//  On iOS 26 and later the glass styles are Apple's glass button style (`.buttonStyle(.glass)`):
//  the system draws the glass and the pressed state (Figma "Glass review: iOS 26, iOS 27 and
//  Android", node 16349:60996, 2026-10-24). Earlier versions draw `glassSurface` and scale a
//  pressed button to 0.95. Selected is a 1 pt ink outline; disabled is 40 % opacity.
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
/// design's button. On iOS 26 and later Apple's glass button style draws the button; its insets
/// around the label (12 pt horizontal, 7 pt vertical at the regular control size) are taken from
/// the label, so the button keeps the design's size.
struct GlassButton<Label: View>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    var shape: GlassButtonShape
    var isSelected = false
    /// The glass below iOS 26. On iOS 26 and later every button is Apple's Regular glass.
    var strength: GlassStrength = .regular
    @ViewBuilder let label: Label
    @Environment(\.isEnabled) private var isEnabled

    /// The insets of `.buttonStyle(.glass)` at the regular control size.
    static var systemInsets: EdgeInsets { EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12) }

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: configuration.role, action: configuration.trigger) {
                label
                    .foregroundStyle(Palette.ink)
                    .padding(-Self.systemInsets)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .buttonBorderShape(borderShape)
            .controlSize(.regular)
            .overlay { outline }
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                label.foregroundStyle(Palette.ink)
            }
            .buttonStyle(LegacyGlassButtonStyle(shape: shape, strength: strength, isEnabled: isEnabled))
            .overlay { outline }
        }
    }

    @available(iOS 26, *)
    private var borderShape: ButtonBorderShape {
        switch shape {
        case .roundedRectangle(let radius): .roundedRectangle(radius: radius)
        case .capsule: .capsule
        case .circle: .circle
        }
    }

    @ViewBuilder private var outline: some View {
        if isSelected {
            switch shape {
            case .roundedRectangle(let radius): RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.ink, lineWidth: 1).allowsHitTesting(false)
            case .capsule: Capsule().strokeBorder(Palette.ink, lineWidth: 1).allowsHitTesting(false)
            case .circle: Circle().strokeBorder(Palette.ink, lineWidth: 1).allowsHitTesting(false)
            }
        }
    }
}

/// The glass buttons below iOS 26: `glassSurface` in the button's shape, scaled to 0.95 while
/// pressed.
private struct LegacyGlassButtonStyle: ButtonStyle {
    let shape: GlassButtonShape
    let strength: GlassStrength
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    @ViewBuilder private func surface(_ label: some View) -> some View {
        switch shape {
        case .roundedRectangle(let radius): label.glassSurface(RoundedRectangle(cornerRadius: radius), strength: strength, shadow: isEnabled)
        case .capsule: label.glassSurface(Capsule(), strength: strength, shadow: isEnabled)
        case .circle: label.glassSurface(Circle(), strength: strength, shadow: isEnabled)
        }
    }
}

private extension EdgeInsets {
    static prefix func - (insets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: -insets.top, leading: -insets.leading, bottom: -insets.bottom, trailing: -insets.trailing)
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
