//
//  VisitStopList.swift
//  ProximiioGADKit
//
//  The journey as a list (Figma: "Personalized Journey list"). Stops are numbered in
//  visit order and grouped under the gallery they lie in; visited stops are dimmed; swiping
//  left offers Skip; a skipped stop is hidden and the list renumbers. "Undo skip" restores
//  the last skipped stop and reports `VisitEvent.skipUndone`. A curated tour passes no
//  galleries and no skip: its stops have no gallery names and cannot be skipped. A row shows the
//  artist and "AR" and audio badges from the artwork's place (`VenuePlace.artist`, `hasAR`,
//  `hasAudio`), or the level when the place names no artist.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct VisitStopList: View {
    @Environment(\.visitEventHandler) private var emit
    let controller: VisitController
    var galleries: [Gallery] = []
    var places: [VenuePlace] = []
    var allowsSkip = true
    let onSkip: (JourneyStop) -> Void

    var body: some View {
        StopList(
            navigator: controller.navigator,
            galleries: galleries,
            places: Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            allowsSkip: allowsSkip,
            lastSkippedStopID: controller.lastSkippedStopID,
            onSkip: onSkip
        ) {
            let stop = controller.navigator.journey.stops.first { $0.id == controller.lastSkippedStopID }
            Task { await controller.undoSkip() }
            if let stop { emit(.skipUndone(stop)) }
        }
    }
}

private struct StopList: View {
    @ObservedObject var navigator: JourneyNavigator
    let galleries: [Gallery]
    /// Places by id, for the artist and the badges of a stop.
    let places: [String: VenuePlace]
    let allowsSkip: Bool
    let lastSkippedStopID: String?
    let onSkip: (JourneyStop) -> Void
    let onUndo: () -> Void

    private var visibleStops: [JourneyStop] {
        VisitPlan.artworks(in: navigator.journey).filter { $0.state != .skipped }
    }

    /// The row whose skip action is revealed. One row at a time.
    @State private var revealedStopID: String?
    /// True while a row is dragged horizontally; vertical scrolling pauses meanwhile.
    @State private var isSwiping = false

    var body: some View {
        let numbers = VisitPlan.numbers(for: navigator.journey)
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(VisitPlan.galleryGroups(visibleStops, galleryOf: gallery(of:)), id: \.id) { group in
                    if let name = group.gallery {
                        Text(name)
                            .textStyle(.largeBodyBold)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.stops) { stop in
                    let canSkip = allowsSkip && (stop.state == .pending || stop.state == .active)
                    SwipeToSkipRow(
                        isRevealed: Binding(
                            get: { revealedStopID == stop.id },
                            set: { revealedStopID = $0 ? stop.id : nil }
                        ),
                        isEnabled: canSkip,
                        isSwiping: $isSwiping,
                        onSkip: {
                            revealedStopID = nil
                            onSkip(stop)
                        }
                    ) {
                        row(stop, number: numbers[stop.id] ?? 0, isRevealed: revealedStopID == stop.id)
                    }
                    }
                }
                if allowsSkip {
                    if lastSkippedStopID != nil {
                        Button(String(localized: "Undo skip", bundle: .module), action: onUndo).buttonStyle(.small).padding(.top, 6)
                    }
                    Text("Swipe left to skip an artwork", bundle: .module)
                        .textStyle(.bodyExtraSmall)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 90)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(isSwiping)
    }

    private func gallery(of stop: JourneyStop) -> String? {
        Gallery.containing(ProximiioCoordinate(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude),
                           level: stop.floor?.level, in: galleries)?.name
    }

    /// A stop as a frosted card (Figma journey list): number badge, title, floor.
    private func row(_ stop: JourneyStop, number: Int, isRevealed: Bool) -> some View {
        let place = places[stop.poiID ?? stop.id]
        let isVisited = stop.state == .done
        let isActive = stop.state == .active || stop.state == .reached
        return HStack(spacing: 16) {
            StopNumberBadge(
                number: number,
                emphasis: isRevealed || isActive ? .filled : isVisited ? .visited : .normal
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(stop.title).textStyle(.bodyMedium)
                if let artist = place?.artist {
                    Text(artist).textStyle(.bodySmallRegular)
                } else if let level = stop.floor?.level {
                    Text(String(localized: "Level \(Int(level.rounded()))", bundle: .module)).textStyle(.bodySmallRegular)
                }
            }
            Spacer(minLength: 0)
            if place?.hasAR == true {
                OutlineBadge(text: "AR").accessibilityLabel(Text("AR view", bundle: .module))
            }
            if place?.hasAudio == true {
                OutlineBadge(systemImage: "music.note").accessibilityLabel(Text("Audio", bundle: .module))
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(isVisited ? Text("Visited", bundle: .module) : Text("", bundle: .module))
    }
}

/// Swipe left on a row to reveal the skip action (Figma journey list, node 11820:71364): the
/// row slides left, its number badge turns red, and a glass panel with the skip glyph
/// appears at the trailing edge. The drag locks to one axis: a horizontal drag pauses
/// scrolling; a vertical drag scrolls and leaves the row in place.
private struct SwipeToSkipRow<Content: View>: View {
    @Binding var isRevealed: Bool
    let isEnabled: Bool
    @Binding var isSwiping: Bool
    let onSkip: () -> Void
    @ViewBuilder let content: Content

    private enum Axis { case undecided, horizontal, vertical }

    @State private var dragX: CGFloat = 0
    @State private var axis: Axis = .undecided
    /// True while the drag gesture runs. SwiftUI resets it when the gesture ends or is cancelled;
    /// a cancelled drag does not call `onEnded`, which left scrolling paused (PM review 2026-10-12).
    @GestureState private var isDragging = false
    /// Distance the row slides to reveal the skip panel.
    private let revealWidth: CGFloat = 72

    private var offset: CGFloat {
        let base: CGFloat = isRevealed ? -revealWidth : 0
        // Rubber-band past the open position and to the right of the closed one.
        let raw = base + dragX
        if raw > 0 { return raw * 0.2 }
        if raw < -revealWidth { return -revealWidth + (raw + revealWidth) * 0.3 }
        return raw
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if isEnabled {
                Button(action: onSkip) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.ink)
                        .frame(width: revealWidth + 24)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 24)
                        .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
                }
                .buttonStyle(.plain)
                .opacity(min(1, -offset / revealWidth))
                .accessibilityHidden(true)
            }
            content
                .offset(x: offset)
                .simultaneousGesture(isEnabled ? drag : nil)
                .onTapGesture {
                    if isRevealed { withAnimation(.snappy) { isRevealed = false } }
                }
        }
        .animation(.snappy(duration: 0.25), value: isRevealed)
        .onChange(of: isDragging) { _, dragging in
            guard !dragging, axis != .undecided || isSwiping else { return }
            axis = .undecided
            isSwiping = false
            withAnimation(.snappy(duration: 0.25)) { dragX = 0 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Skip", bundle: .module)) { if isEnabled { onSkip() } }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                if axis == .undecided {
                    let dx = abs(value.translation.width), dy = abs(value.translation.height)
                    guard dx > 6 || dy > 6 else { return }
                    axis = dx > dy ? .horizontal : .vertical
                    if axis == .horizontal { isSwiping = true }
                }
                guard axis == .horizontal else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                defer {
                    axis = .undecided
                    isSwiping = false
                }
                guard axis == .horizontal else { return }
                let projected = (isRevealed ? -revealWidth : 0) + value.predictedEndTranslation.width
                withAnimation(.snappy(duration: 0.25)) {
                    dragX = 0
                    isRevealed = projected < -revealWidth / 2
                }
            }
    }
}
