//
//  Buttons.swift
//  ProximiioGADKit
//
//  Button styles from the Figma "Buttons" section (node 6902:47010):
//
//  | Style | Figma component | Shape |
//  |---|---|---|
//  | `.primary` | Button Primary Large | glass, 60 pt high, full width, Body Medium |
//  | `.ghost` | Button Ghost Medium | 1.5 pt ink stroke, 40 pt high, Body Medium |
//  | `.small` | Button Small | light glass, 32 pt high, Body Small |
//  | `.iconGlass` | Button_medium | glass, 40 × 40 pt, 16 pt icon |
//  | `.textAction` | "Skip for now", "Carry on" | Body Small, underlined |
//
//  States: pressed scales to 0.95; disabled is 40 % opacity without shadow.
//
import SwiftUI

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodyMedium)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 60)
            .glassSurface(RoundedRectangle(cornerRadius: 12), shadow: isEnabled)
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodyMedium)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 30)
            .frame(minHeight: 40)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : Palette.disabledOpacity)
    }
}

public struct SmallButtonStyle: ButtonStyle {
    var isSelected = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodySmallRegular)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 32)
            .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .light)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

public struct IconGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.ink)
            .frame(width: 40, height: 40)
            .glassSurface(RoundedRectangle(cornerRadius: 12), shadow: isEnabled)
            .contentShape(Rectangle().inset(by: -2))
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

public struct TextActionButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodySmallRegular)
            .underline()
            .foregroundStyle(Palette.ink)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    public static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

extension ButtonStyle where Self == SmallButtonStyle {
    public static var small: SmallButtonStyle { SmallButtonStyle() }
    public static func small(selected: Bool) -> SmallButtonStyle { SmallButtonStyle(isSelected: selected) }
}

extension ButtonStyle where Self == IconGlassButtonStyle {
    public static var iconGlass: IconGlassButtonStyle { IconGlassButtonStyle() }
}

extension ButtonStyle where Self == TextActionButtonStyle {
    public static var textAction: TextActionButtonStyle { TextActionButtonStyle() }
}
