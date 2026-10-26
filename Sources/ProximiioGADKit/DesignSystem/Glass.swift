//
//  Glass.swift
//  ProximiioGADKit
//
//  The glass surface of the design, read with the Plugin API from the Figma components
//  (Button Primary Large 6902:47065, Card_Glass_1/2, toggle, Button_medium):
//
//  - effect: GLASS (Figma's Liquid Glass), radius 4 on buttons and cards, 20 on map controls
//  - fill: a diagonal gradient #E6E6E6 → clear → #E6E6E6
//  - stroke: 1.5 pt white
//  - shadow: x 0, y 3, blur 10, black 15 %
//
//  On iOS 26 and later the surface is Apple's Regular glass (`glassEffect(.regular)`) without the
//  gradient, the stroke and the shadow: "One glass for the whole app: Apple's Regular glass" (Figma
//  "Glass review: iOS 26, iOS 27 and Android", node 16349:60996, 2026-10-24). Earlier versions
//  draw the design's glass with a material.
//
import SwiftUI

/// The glass below iOS 26. On iOS 26 and later every strength is Apple's Regular glass.
@_spi(GADApp) public enum GlassStrength {
    /// Buttons, cards and bars over the coloured backgrounds.
    case regular
    /// Button Small and chips: the gradient at 20 %.
    case light
    /// Cards, rows and buttons over the map and the journey list: frosted, nearly white,
    /// as the Figma map frames show.
    case frosted
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var strength: GlassStrength = .regular
    var showsShadow = true

    /// The Figma fill: #E6E6E6 → clear → #E6E6E6, diagonal.
    private var figmaGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Palette.glassEdge, location: 0.0),
                .init(color: .white.opacity(0.01), location: 0.5),
                .init(color: Palette.glassEdge, location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background {
                    ZStack {
                        switch strength {
                        case .frosted:
                            shape.fill(.regularMaterial)
                            shape.fill(Palette.white.opacity(0.55))
                        case .regular:
                            shape.fill(.ultraThinMaterial).opacity(0.3)
                        case .light:
                            shape.fill(.ultraThinMaterial).opacity(0.2)
                        }
                        shape.fill(figmaGradient).opacity(gradientOpacity)
                    }
                }
                .overlay(shape.strokeBorder(Palette.white, lineWidth: 1.5))
                .compositingGroup()
                .shadow(color: .black.opacity(showsShadow ? 0.15 : 0), radius: 5, x: 0, y: 3)
        }
    }

    private var gradientOpacity: Double {
        switch strength {
        case .regular: 0.55
        case .light: 0.2
        case .frosted: 0.5
        }
    }
}

extension View {
    /// The design's glass surface in `shape`.
    @_spi(GADApp) public func glassSurface<S: InsettableShape>(_ shape: S, strength: GlassStrength = .regular, shadow: Bool = true) -> some View {
        modifier(GlassSurface(shape: shape, strength: strength, showsShadow: shadow))
    }

    /// The design's glass surface with the standard 12 pt corner radius.
    @_spi(GADApp) public func glassSurface(cornerRadius: CGFloat = 12, strength: GlassStrength = .regular) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius), strength: strength))
    }

    /// White bottom-sheet content (Figma `Overlay`, node 6902:45589): 40 pt padding, centred.
    /// The sheet is as tall as its content, so long texts wrap instead of being truncated.
    func overlaySheetStyle() -> some View {
        self
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 30)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
            .modifier(FittedSheetHeight())
            .presentationCornerRadius(50)
            .presentationBackground(Palette.white)
    }
}

/// Sets the sheet's detent to the content's ideal height.
private struct FittedSheetHeight: ViewModifier {
    @State private var height: CGFloat = 300

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
    }
}
