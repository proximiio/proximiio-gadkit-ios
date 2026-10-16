//
//  AuroraBackground.swift
//  ProximiioGADKit
//
//  The soft multicolour gradient behind most screens in the design ("Backgrounds" frame).
//  Approximation built from blurred brand colours; replace with the exported asset when
//  the design team supplies one.
//
import SwiftUI

@_spi(GADApp) public struct AuroraBackground: View {
    public enum Variant {
        /// Peach top, pastel band along the bottom.
        case standard
        /// Lime, mint and cyan (Journey Complete, PM review 2026-10-12).
        case mint
    }

    var variant: Variant = .standard

    public init(variant: Variant = .standard) {
        self.variant = variant
    }

    public var body: some View {
        GeometryReader { proxy in
            switch variant {
            case .standard: standard(proxy.size)
            case .mint: mint(proxy.size)
            }
        }
        .ignoresSafeArea()
    }

    private func mint(_ size: CGSize) -> some View {
        ZStack {
            Palette.white
            blob(Palette.mint.opacity(0.8), diameter: size.width * 0.9)
                .position(x: size.width * 0.05, y: size.height * 0.05)
            blob(Palette.lime.opacity(0.6), diameter: size.width * 0.6)
                .position(x: size.width * 0.05, y: size.height * 0.3)
            blob(Palette.cyan.opacity(0.85), diameter: size.width * 1.1)
                .position(x: size.width * 0.6, y: size.height * 0.62)
            blob(Palette.mint.opacity(0.7), diameter: size.width * 0.7)
                .position(x: size.width * 1.0, y: size.height * 0.5)
            blob(Palette.white.opacity(0.8), diameter: size.width * 0.6)
                .position(x: size.width * 0.75, y: size.height * 0.12)
            blob(Palette.white.opacity(0.7), diameter: size.width * 0.8)
                .position(x: size.width * 0.3, y: size.height * 0.98)
        }
    }

    private func standard(_ size: CGSize) -> some View {
            ZStack {
                Palette.white
                // Peach glow in the top leading corner.
                blob(Palette.orange.opacity(0.75), diameter: size.width * 0.8)
                    .position(x: size.width * -0.05, y: size.height * 0.03)
                blob(Color(hex: 0xFFC488).opacity(0.7), diameter: size.width * 0.5)
                    .position(x: size.width * 0.05, y: size.height * 0.12)
                // Pastel band along the bottom edge.
                blob(Palette.cyan.opacity(0.55), diameter: size.width * 0.9)
                    .position(x: size.width * 0.0, y: size.height * 0.9)
                blob(Palette.lavender.opacity(0.6), diameter: size.width * 0.7)
                    .position(x: size.width * 0.55, y: size.height * 0.98)
                blob(Palette.red.opacity(0.45), diameter: size.width * 0.6)
                    .position(x: size.width * 0.75, y: size.height * 1.05)
                blob(Palette.orange.opacity(0.45), diameter: size.width * 0.6)
                    .position(x: size.width * 1.05, y: size.height * 0.93)
            }
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.4)
    }
}

#Preview {
    AuroraBackground()
}

#Preview("Mint") {
    AuroraBackground(variant: .mint)
}
