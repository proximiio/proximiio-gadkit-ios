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

    /// Fills the space it gets and no more: a filled image that is taller than the screen (an
    /// iPhone SE's screen is wider than the image) made the stacks around it taller than the
    /// screen, and the bottom bar went off it (PM, iPhone SE, 2026-10-30).
    public var view: some View {
        Color.clear
            .overlay { Image(rawValue, bundle: .module).resizable().scaledToFill() }
            .clipped()
            .ignoresSafeArea()
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
    /// The fades of the map: down to the Map / List control and search at the top, up from the
    /// bottom over about the stop card.
    private static var topFade: CGFloat { 110 }
    private static var bottomFade: CGFloat { 170 }

    var body: some View {
        ZStack {
            map
                .softEdges(cornerRadius: 50)
                // The map fades out under the controls at the top and the card at the bottom (RPR,
                // Monday "Map fade at top & bottom", 2026-10-28).
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.topFade)
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.bottomFade)
                    }
                }
            VStack(spacing: 0) {
                handleArea
                Spacer(minLength: 0).allowsHitTesting(false)
            }
            overlay
        }
        .clipShape(shape)
        .overlay(alignment: .top) {
            // Figma `Swipe`: 60 × 6 pt at 20 % black, a 2 pt white stroke outside it, 9 pt below the
            // card's top edge.
            Capsule()
                .fill(.black.opacity(0.2))
                .frame(width: 60, height: 6)
                .background(Capsule().strokeBorder(Palette.white, lineWidth: 2).padding(-2))
                .padding(.top, 9)
                .accessibilityHidden(true)
        }
        // A 1 pt white stroke outside the card, as in the design.
        .overlay(shape.inset(by: -0.5).stroke(Palette.white, lineWidth: 1))
        // The design's shadow (blur 50, y −3, 15 % black), only outside the card: Figma draws no
        // shadow behind a translucent layer.
        .background {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.15), radius: 25, y: -3)
                .mask {
                    Rectangle().padding(-80)
                        .overlay(shape.blendMode(.destinationOut))
                        .compositingGroup()
                }
                .allowsHitTesting(false)
        }
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

/// "Map | List" toggle on glass, in place of the system's segmented control. One gesture takes taps
/// and slides; VoiceOver and UI tests see two buttons.
struct MapListToggle: View {
    @Binding var showsList: Bool
    /// The finger's travel toward List while it slides the selection, in points.
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.25))) private var slide: CGFloat = 0
    @Environment(\.layoutDirection) private var layoutDirection

    /// The width of one part: the control is 150 pt wide with 4 pt of padding.
    private static let partWidth: CGFloat = (150 - 8) / 2
    /// A finger that travels less than this is a tap.
    private static let slideThreshold: CGFloat = 8

    /// 150 × 50 pt glass with 16 pt corners; the selected part has a black outline (Figma frame of the
    /// PM, Monday "Native elements", 2026-10-28). A finger slides the selection to the other part, as
    /// on the system's segmented control (Monday "Native elements", 2026-10-28 evening).
    var body: some View {
        let forward: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.white.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5))
                .frame(width: Self.partWidth)
                .offset(x: forward * Self.selectionOffset(showsList: showsList, slide: slide, width: Self.partWidth))
            HStack(spacing: 0) {
                label("Map")
                label("List")
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($slide) { value, state, _ in
                    if abs(value.translation.width) >= Self.slideThreshold { state = forward * value.translation.width }
                }
                .onEnded { value in
                    // The finger's distance from the Map end: the local x runs left to right.
                    let position = forward > 0 ? value.location.x : 2 * Self.partWidth - value.location.x
                    showsList = Self.showsList(afterSlide: forward * value.translation.width, at: position,
                                               showsList: showsList, width: Self.partWidth)
                }
        )
        .accessibilityRepresentation {
            HStack(spacing: 0) {
                accessibleButton("Map", isSelected: !showsList) { showsList = false }
                accessibleButton("List", isSelected: showsList) { showsList = true }
            }
        }
        .padding(4)
        .frame(width: 150, height: 50)
        .glassSurface(RoundedRectangle(cornerRadius: 16), strength: .frosted)
        .animation(.spring(duration: 0.25), value: showsList)
    }

    /// The selection's offset from the Map part toward the List part: the selected part, moved by
    /// `slide` and kept inside the control. Pure; covered by tests.
    nonisolated static func selectionOffset(showsList: Bool, slide: CGFloat, width: CGFloat) -> CGFloat {
        min(max((showsList ? width : 0) + slide, 0), width)
    }

    /// Whether the control shows List when the finger lifts: a tap picks the part under the finger,
    /// at `position` from the Map end; a slide picks the part the selection ends over. Pure; covered
    /// by tests.
    nonisolated static func showsList(afterSlide slide: CGFloat, at position: CGFloat, showsList: Bool, width: CGFloat) -> Bool {
        if abs(slide) < slideThreshold { return position > width }
        return selectionOffset(showsList: showsList, slide: slide, width: width) > width / 2
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .localized)
            .textStyle(.largeBodyRegular)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accessibleButton(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title, bundle: .localized).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

/// Amenity shortcuts as a right-aligned stack of small chips (Figma search state). A list taller
/// than the space it gets scrolls and fades out at the bottom (PM, Monday "Amenity search when list
/// is long", 2026-10-29).
struct AmenityChipList: View {
    let shortcuts: [AmenityShortcut]
    var selected: AmenityShortcut?
    let onPick: (AmenityShortcut) -> Void
    @State private var contentSize: CGSize = .zero
    @State private var visibleHeight: CGFloat = 0

    /// The height of the fade at the bottom of a list that scrolls.
    static let fadeHeight: CGFloat = 44

    var body: some View {
        let scrolls = Self.scrolls(contentHeight: contentSize.height, visibleHeight: visibleHeight)
        ScrollView(.vertical) {
            VStack(alignment: .trailing, spacing: 5) {
                ForEach(shortcuts) { shortcut in
                    Button { onPick(shortcut) } label: {
                        HStack(spacing: 5) {
                            shortcut.image?.resizable().scaledToFit().frame(width: 16, height: 16)
                            // One line, as in the design; a long title widens the chip.
                            Text(shortcut.title).lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, -6)
                    }
                    // Frosted: on the clear glass the titles were hard to read over the map
                    // (PM 2026-10-15, "Search menu transparency").
                    .buttonStyle(.small(selected: shortcut == selected, strength: .frosted))
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // The chips' glass reaches past the list's edges.
        .scrollClipDisabledIfAvailable()
        // The last chip scrolls out of the fade.
        .scrollContentBottomMargin(scrolls ? Self.fadeHeight : 0)
        .frame(width: contentSize.width > 0 ? contentSize.width : nil)
        .frame(maxHeight: contentSize.height > 0 ? contentSize.height : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .mask {
            VStack(spacing: 0) {
                Color.black
                if scrolls {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.fadeHeight)
                }
            }
            // Past the edges, so the chips' shadows stay; at the bottom only when nothing fades.
            .padding(.horizontal, -24)
            .padding(.top, -24)
            .padding(.bottom, scrolls ? 0 : -24)
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

    /// Whether the chips need more height than the list has. Pure; covered by tests.
    nonisolated static func scrolls(contentHeight: CGFloat, visibleHeight: CGFloat) -> Bool {
        visibleHeight > 0 && contentHeight > visibleHeight + 0.5
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
                    Text(caption, bundle: .localized).textStyle(.caption).textCase(.uppercase)
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
                    // The line is 18.5 pt high in the design (Figma 10889:108085).
                    .frame(minHeight: 18.5)
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
                Button(action: onPrimary) { Text(primary, bundle: .localized) }.buttonStyle(CardGhostButtonStyle())
                if let onClose {
                    Button(String(localized: "Close", bundle: .localized), action: onClose).buttonStyle(CardGhostButtonStyle())
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
        .frame(height: 93.5)
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
