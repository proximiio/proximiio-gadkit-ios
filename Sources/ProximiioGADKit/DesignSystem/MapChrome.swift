//
//  MapChrome.swift
//  ProximiioGADKit
//
//  The map screen layout of the design ("MAP Functionality Approach 02", nodes
//  10889:108085 and 10889:110275):
//
//  - the map in a glass card with 50 pt corners, 10 pt from the screen edges, over the
//    `BackgroundMap` image, with a drag handle at the top
//  - Map / List toggle (top leading), search (top trailing), compass and floor (trailing)
//  - amenity chips, stop card or amenity card at the bottom of the card
//  - a glass bar under the card with round buttons
//
import SwiftUI

/// Full-screen background image of a design screen.
@_spi(GADApp) public enum ScreenBackground: String {
    case hub = "BackgroundHub"
    case map = "BackgroundMap"

    public var view: some View {
        Image(rawValue, bundle: .module).resizable().scaledToFill().ignoresSafeArea()
    }
}

/// The map in its glass card, with overlays placed inside the card.
struct MapGlassFrame<Map: View, Overlay: View>: View {
    @ViewBuilder let map: Map
    @ViewBuilder let overlay: Overlay

    private let shape = RoundedRectangle(cornerRadius: 50, style: .continuous)

    var body: some View {
        ZStack {
            map.softEdges(cornerRadius: 50)
            overlay
        }
        .clipShape(shape)
        .overlay(alignment: .top) {
            Capsule()
                .fill(.black.opacity(0.2))
                .overlay(Capsule().strokeBorder(Palette.white, lineWidth: 2))
                .frame(width: 60, height: 6)
                .padding(.top, 8)
                .accessibilityHidden(true)
        }
        .overlay(shape.strokeBorder(Palette.white, lineWidth: 1))
        .padding(.horizontal, 10)
    }
}

extension View {
    /// Fades the view to transparent over `width` points at every edge, so the screen background
    /// shows through (the map card of the Figma map frames; PM 2026-10-23). A mask changes the look
    /// only: taps on the faded edge still reach the view.
    func softEdges(_ width: CGFloat = 28, cornerRadius: CGFloat) -> some View {
        mask {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .padding(width / 2)
                .blur(radius: width / 2)
                .drawingGroup()
        }
    }
}

/// "Map | List" toggle: glass 150 × 50 with the selected item outlined.
struct MapListToggle: View {
    @Binding var showsList: Bool

    var body: some View {
        HStack(spacing: 0) {
            item("Map", selected: !showsList) { showsList = false }
            item("List", selected: showsList) { showsList = true }
        }
        .padding(5)
        .frame(width: 150, height: 50)
        .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
    }

    private func item(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title, bundle: .module)
                .textStyle(.bodySmallRegular)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Square glass button, 50 × 50, with an icon or a short label ("L1").
struct GlassSquareButton<Label: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Palette.ink)
                .frame(width: 50, height: 50)
                .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// Amenity shortcuts as a right-aligned stack of small chips (Figma search state).
struct AmenityChipList: View {
    let kinds: [AmenityKind]
    var selected: AmenityKind?
    let onPick: (AmenityKind) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            ForEach(kinds) { kind in
                Button { onPick(kind) } label: {
                    HStack(spacing: 5) {
                        kind.icon.image.resizable().scaledToFit().frame(width: 16, height: 16)
                        Text(kind.title)
                    }
                    .padding(.horizontal, -6)
                }
                // Frosted: on the clear glass the titles were hard to read over the map
                // (PM 2026-10-15, "Search menu transparency").
                .buttonStyle(.small(selected: kind == selected, strength: .frosted))
            }
        }
    }
}

/// Bottom card for the next stop (Figma "Stop Info"): icon in a white circle, NEXT STOP,
/// title, and the instruction with distance and time on one line. The card spans the width
/// of the map card.
struct StopInfoCard<Icon: View, Trailing: View, Badges: View>: View {
    let caption: LocalizedStringKey
    let title: String
    var instruction: String?
    var remaining: String?
    @ViewBuilder let icon: Icon
    @ViewBuilder let trailing: Trailing
    /// At the end of the caption line: the artwork's AR and audio badges (PM, Monday "Augmented
    /// Reality and Audio symbols").
    @ViewBuilder let badges: Badges

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
                .frame(width: 22, height: 22)
                .frame(width: 40, height: 40)
                .background(Palette.white, in: Circle())
                .overlay(Circle().strokeBorder(Palette.badgeStroke, lineWidth: 1.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(caption, bundle: .module).textStyle(.caption).textCase(.uppercase)
                    Spacer(minLength: 4)
                    badges
                }
                Text(title).textStyle(.largeBodyBold).lineLimit(2)
                if instruction != nil || remaining != nil {
                    HStack(alignment: .firstTextBaseline) {
                        if let instruction { Text(instruction).textStyle(.bodyExtraSmall).fontWeight(.bold) }
                        Spacer(minLength: 4)
                        if let remaining { Text(remaining).textStyle(.bodyExtraSmall) }
                    }
                }
            }
            // The card has a fixed width in the design (339 of 402 pt); it never hugs the text.
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            trailing
        }
        .foregroundStyle(Palette.ink)
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.vertical, 20)
        .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
    }
}

/// Bottom card for a picked place (Figma amenity state): title, kind and floor, and two
/// ghost buttons. Without `onClose` the primary button fills the card.
struct PlaceInfoCard: View {
    let title: String
    let subtitle: String
    let primary: LocalizedStringKey
    let onPrimary: () -> Void
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).textStyle(.largeBodyBold)
                Text(subtitle).textStyle(.bodySmallRegular)
            }
            HStack(spacing: 10) {
                Button(action: onPrimary) { Text(primary, bundle: .module) }.buttonStyle(CardGhostButtonStyle())
                if let onClose {
                    Button(String(localized: "Close", bundle: .module), action: onClose).buttonStyle(CardGhostButtonStyle())
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
    }
}

/// Ghost button stretched to half the card, 50 pt high ("Go here", "Close").
struct CardGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodyMedium)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The glass bar under the map card (Figma `Bar_bottom`, node 6902:46776): a capsule with
/// round glass buttons at both ends.
struct BottomGlassBar<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .frame(height: 93)
        .glassSurface(Capsule(), shadow: false)
        .padding(.horizontal, 10)
    }
}

/// Round glass button of the bottom bar, 60 pt.
struct RoundGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Palette.ink)
            .frame(width: 60, height: 60)
            .glassSurface(Circle())
            .opacity(isEnabled ? 1 : Palette.disabledOpacity)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
