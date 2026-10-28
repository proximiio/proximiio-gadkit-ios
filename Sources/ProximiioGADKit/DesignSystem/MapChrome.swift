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
import ProximiioMap
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
    /// A drag down from the handle at the top. `nil`: the handle area takes the touches and does
    /// nothing, so a sheet that holds the view can be pulled down there.
    var onPullDown: (() -> Void)?
    @ViewBuilder let map: Map
    @ViewBuilder let overlay: Overlay

    private let shape = RoundedRectangle(cornerRadius: 50, style: .continuous)

    /// The handle area at the top: the map does not pan there (PM, Monday "More space for the pull
    /// down functionality", 2026-10-26).
    private static var handleAreaHeight: CGFloat { 44 }

    var body: some View {
        ZStack {
            map.softEdges(cornerRadius: 50)
            VStack(spacing: 0) {
                handleArea
                Spacer(minLength: 0).allowsHitTesting(false)
            }
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

    @ViewBuilder private var handleArea: some View {
        let area = Color.clear
            .frame(height: Self.handleAreaHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        if let onPullDown {
            area
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height > 60 { onPullDown() }
                })
                .accessibilityHidden(true)
        } else {
            area.accessibilityHidden(true)
        }
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

/// The spinner in the middle of a map while the map library draws the venue (PM, Monday "Spinner on
/// map loading center", 2026-10-26). `isBusy` keeps it while the screen has more to do, such as
/// routing the first leg of a journey.
struct MapLoadingSpinner: View {
    @ObservedObject var session: ProximiioMapSession
    /// `GADSettings.mapLoadingTimeout`.
    let timeout: TimeInterval
    var isBusy = false
    @State private var hasTimedOut = false

    var body: some View {
        let isShown = Self.isShown(featureCount: session.featureCount, lastError: session.lastError, hasTimedOut: hasTimedOut, isBusy: isBusy)
        ZStack {
            if isShown {
                ProgressView()
                    .controlSize(.large)
                    .tint(Palette.ink)
                    .padding(24)
                    .glassSurface(RoundedRectangle(cornerRadius: 16), strength: .frosted)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: isShown)
        .task {
            try? await Task.sleep(for: .seconds(timeout))
            hasTimedOut = true
        }
    }

    /// Shown until the venue's features are on the map, the map reports an error or the timeout
    /// passes, and while `isBusy`. Pure; covered by tests.
    static func isShown(featureCount: Int, lastError: String?, hasTimedOut: Bool, isBusy: Bool) -> Bool {
        isBusy || (featureCount == 0 && lastError == nil && !hasTimedOut)
    }
}

/// "Map | List" toggle: the system's segmented control, 150 pt wide. iOS draws the control and its
/// glass (Figma "Glass review", "System controls", 2026-10-24).
struct MapListToggle: View {
    @Binding var showsList: Bool

    var body: some View {
        Picker(selection: $showsList) {
            Text("Map", bundle: .module).tag(false)
            Text("List", bundle: .module).tag(true)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(width: 150)
    }
}

/// Square glass button, 50 × 50, with an icon or a short label ("L1").
struct GlassSquareButton<Label: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(SquareGlassButtonStyle(isSelected: isSelected))
    }
}

/// The glass of `GlassSquareButton` and `AccessibleRoutesButton`: 50 × 50 pt, frosted.
struct SquareGlassButtonStyle: PrimitiveButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .roundedRectangle(12), isSelected: isSelected, strength: .frosted) {
            configuration.label.frame(width: 50, height: 50)
        }
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
        // A white haze behind the list, so the map behind it shows less (RPR, Monday "White blur
        // behind amenity list", 2026-10-28).
        .background {
            Palette.white.opacity(0.8)
                .padding(-12)
                .blur(radius: 18)
                .allowsHitTesting(false)
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
    /// The instruction line keeps its height without an instruction, for example while the route is
    /// routed again: the card and the buttons above it do not move (RPR, Monday "Accessible routing",
    /// 2026-10-28).
    var keepsInstructionLine = false
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
                if instruction != nil || remaining != nil || keepsInstructionLine {
                    HStack(alignment: .firstTextBaseline) {
                        if let instruction { Text(instruction).textStyle(.bodyExtraSmall).fontWeight(.bold) }
                        Spacer(minLength: 4)
                        if let remaining { Text(remaining).textStyle(.bodyExtraSmall) }
                        if instruction == nil && remaining == nil { Text(verbatim: " ").textStyle(.bodyExtraSmall).hidden() }
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
                if !subtitle.isEmpty { Text(subtitle).textStyle(.bodySmallRegular) }
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

/// Glass button stretched to half the card, 50 pt high ("Go here", "Close").
struct CardGhostButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .roundedRectangle(12)) {
            configuration.label
                .textStyle(.bodyMedium)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
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
struct RoundGlassButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, shape: .circle) {
            configuration.label.frame(width: 60, height: 60)
        }
    }
}
