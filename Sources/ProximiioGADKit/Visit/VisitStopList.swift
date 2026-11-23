//
//  VisitStopList.swift
//  ProximiioGADKit
//
//  The journey as a list (Figma: "Personalized Journey list"). Stops are numbered in
//  visit order and grouped under their gallery; visited stops are dimmed; swiping left offers
//  Skip; a skipped stop is hidden and the list renumbers. There is no undo (PM, Monday "Undo skip
//  removed", 2026-10-23). A curated tour has no gallery headers and no skip.
//  A row shows the artist and "AR" and audio badges from the artwork's place
//  (`VenuePlace.artist`, `hasAR`, `hasAudio`), or the level when the place names no artist.
//
//  The gallery of a stop is the artwork's `metadata.gallery_id` named by the gallery geofence,
//  else the gallery outline it lies in. A stop with neither is under its level ("Level 4"), so
//  it does not appear to belong to the gallery above it (PM 2026-10-15).
//
import Proximiio
import UIKit.UIGestureRecognizerSubclass
import ProximiioMap
import SwiftUI
import UIKit

struct VisitStopList: View {
    let controller: VisitController
    var galleries: [Gallery] = []
    /// Gallery names by gallery id (`Gallery.names(places:)`).
    var galleryNames: [String: String] = [:]
    /// False for a curated tour: no section headers.
    var groupsByGallery = true
    var places: [VenuePlace] = []
    var allowsSkip = true
    /// The journey is paused and `GADSettings.skipsWhilePaused` is `false`: a swipe on an artwork
    /// calls `onSkip` at once, without the skip panel, and a text replaces the swipe hint. The
    /// owner of `onSkip` refuses the skip.
    var isSkipPaused = false
    /// `GADSettings.showsStopNumbers`: off, the badges are circles without a number.
    var showsNumbers = false
    /// `GADSettings.showsStopIcons`: a badge without a number holds the pin of the map's markers.
    var showsIcons = false
    /// `GADSettings.skipsAtSwipe`: the swipe itself asks for the skip.
    var skipsAtSwipe = false
    /// `GADSettings.skipsAtSwipeBothWays`: a swipe towards the trailing edge asks for the skip too.
    var skipsBothWays = false
    let onSkip: (JourneyStop) -> Void

    var body: some View {
        StopList(
            navigator: controller.navigator,
            galleries: galleries,
            galleryNames: galleryNames,
            groupsByGallery: groupsByGallery,
            places: Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            allowsSkip: allowsSkip,
            isSkipPaused: isSkipPaused,
            showsNumbers: showsNumbers,
            showsIcons: showsIcons,
            skipsAtSwipe: skipsAtSwipe,
            skipsBothWays: skipsBothWays,
            onSkip: onSkip
        )
    }
}

private struct StopList: View {
    @ObservedObject var navigator: JourneyNavigator
    let galleries: [Gallery]
    let galleryNames: [String: String]
    let groupsByGallery: Bool
    /// Places by id, for the artist and the badges of a stop.
    let places: [String: VenuePlace]
    let allowsSkip: Bool
    let isSkipPaused: Bool
    let showsNumbers: Bool
    let showsIcons: Bool
    let skipsAtSwipe: Bool
    let skipsBothWays: Bool
    let onSkip: (JourneyStop) -> Void

    private var visibleStops: [JourneyStop] {
        VisitPlan.artworks(in: navigator.journey).filter { $0.state != .skipped }
    }

    /// The row whose skip action is revealed. One row at a time.
    @State private var revealedStopID: String?
    /// True while a row is dragged horizontally; vertical scrolling pauses meanwhile.
    @State private var isSwiping = false
    /// Takes the list's pan to the row under the finger (iOS 18 and later).
    @State private var router = SwipeRouter()
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let numbers = VisitPlan.numbers(for: navigator.journey)
        let _ = router.update(
            skippable: allowsSkip ? Set(visibleStops.filter(SkipSwipe.canSkip).map(\.id)) : [],
            onBegan: { FieldLog.log("list swipe: began · revealed \(revealedStopID == $0)") },
            onEnded: endSwipe
        )
        ScrollView {
            LazyVStack(spacing: 10) {
                // One flat ForEach: stops did not move between nested ForEach groups, which showed
                // rows of an older order (two stops numbered 25, PM 2026-10-15).
                ForEach(VisitPlan.listRows(visibleStops, sectionOf: section(of:))) { listRow in
                    switch listRow {
                    case .header(_, let title):
                        Text(title)
                            .textStyle(.largeBodyBold)
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("journeyListHeader")
                    case .stop(let stop):
                        let canSkip = allowsSkip && SkipSwipe.canSkip(stop)
                        SwipeToSkipRow(
                            stopID: stop.id,
                            router: router,
                            isRevealed: Binding(
                                get: { revealedStopID == stop.id },
                                set: { revealedStopID = $0 ? stop.id : nil }
                            ),
                            isEnabled: canSkip,
                            isSwiping: $isSwiping,
                            skipsAtSwipe: skipsAtSwipe || isSkipPaused,
                            skipsBothWays: skipsBothWays,
                            onSkip: { skip(stop.id) }
                        ) {
                            row(stop, number: numbers[stop.id] ?? 0, isRevealed: revealedStopID == stop.id)
                        }
                    }
                }
                // No hint without a stop to skip: every artwork skipped or visited (PM, Monday
                // "When all artworks skipped, remove 'skip artwork' text").
                if allowsSkip, visibleStops.contains(where: SkipSwipe.canSkip) {
                    // The row slides towards the leading edge: right in a right-to-left layout.
                    // The text of a paused journey is the PM's (Monday "Swipe to skip disabled when
                    // navigation is paused", 2026-11-20).
                    Text(
                        isSkipPaused ? "Resume your journey to skip the artwork"
                            : layoutDirection == .rightToLeft
                            ? "Swipe right to skip an artwork" : "Swipe left to skip an artwork",
                        bundle: .localized
                    )
                        .accessibilityIdentifier(isSkipPaused ? "skipPausedHint" : "skipHint")
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
        .modifier(ListSwipe(router: router))
    }

    /// Asks to skip the stop with `stopID` as the navigator holds it now. A row can hold an older
    /// value of its stop, so the stop is read again; a stop that is skipped or visited is refused.
    private func skip(_ stopID: String) {
        revealedStopID = nil
        guard let stop = navigator.journey.stops.first(where: { $0.id == stopID }), SkipSwipe.canSkip(stop) else {
            FieldLog.log("list skip: \(stopID) is not a stop to skip")
            return
        }
        onSkip(stop)
    }

    /// Ends the list's pan on the row of `stopID`. `translation` and `velocity` are screen values.
    private func endSwipe(_ stopID: String, translation: CGFloat, velocity: CGFloat) {
        let projected = (translation + velocity * 0.2) * SkipSwipe.sign(layoutDirection)
        let end = SkipSwipe.end(
            isRevealed: revealedStopID == stopID, projected: projected,
            skipsAtSwipe: skipsAtSwipe || isSkipPaused, bothWays: skipsBothWays
        )
        FieldLog.log(String(format: "list swipe: ended · %.0f pt · skip %@", projected, end.skips ? "asked" : end.revealed ? "shown" : "hidden"))
        withAnimation(.snappy(duration: 0.25)) {
            router.reset()
            revealedStopID = end.revealed ? stopID : nil
        }
        if end.skips { skip(stopID) }
    }

    /// The section header of a stop: its gallery, else its level.
    private func section(of stop: JourneyStop) -> String? {
        guard groupsByGallery else { return nil }
        if let id = places[stop.poiID ?? stop.id]?.galleryID, let name = galleryNames[id] { return name }
        if let gallery = Gallery.containing(stop.coordinate.proximiio, level: stop.floor?.level, in: galleries) {
            return gallery.name
        }
        return stop.floor.map { String(localized: "Level \(Int($0.level.rounded()))", bundle: .localized) }
    }

    /// A stop as a frosted card (Figma journey list): number badge, title, floor.
    private func row(_ stop: JourneyStop, number: Int, isRevealed: Bool) -> some View {
        let place = places[stop.poiID ?? stop.id]
        let isVisited = stop.state == .done
        let isActive = stop.state == .active || stop.state == .reached
        return HStack(spacing: 16) {
            StopNumberBadge(
                number: showsNumbers ? number : nil,
                emphasis: isRevealed || isActive ? .filled : isVisited ? .visited : .normal,
                showsIcon: showsIcons
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(stop.title).textStyle(.bodyMedium)
                if let artist = place?.artist {
                    Text(artist).textStyle(.bodySmallRegular)
                } else if let level = stop.floor?.level {
                    Text(String(localized: "Level \(Int(level.rounded()))", bundle: .localized)).textStyle(.bodySmallRegular)
                }
            }
            Spacer(minLength: 0)
            if let place { ArtworkBadges(place: place) }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(isVisited ? Text("Visited", bundle: .localized) : Text("", bundle: .localized))
    }
}

/// "AR" and a note when the artwork has an AR view and audio, in the journey list and on the stop
/// card (PM, Monday "Augmented Reality and Audio symbols").
struct ArtworkBadges: View {
    let place: VenuePlace

    var body: some View {
        HStack(spacing: 4) {
            if place.hasAR {
                OutlineBadge(text: "AR").accessibilityLabel(Text("AR view", bundle: .localized))
            }
            if place.hasAudio {
                OutlineBadge(systemImage: "music.note").accessibilityLabel(Text("Audio", bundle: .localized))
            }
        }
    }
}

/// The swipe that reveals the skip action of a row. Distances are logical: negative is towards
/// the leading edge, which is left in a left-to-right layout and right in a right-to-left one.
enum SkipSwipe {
    /// Distance the row slides to reveal the skip panel.
    static let revealWidth: CGFloat = 72

    /// Only a stop still ahead can be skipped.
    static func canSkip(_ stop: JourneyStop) -> Bool {
        stop.state == .pending || stop.state == .active
    }

    /// 1 in a left-to-right layout, -1 in a right-to-left one. Multiplies a screen distance, such
    /// as a drag's translation, to get a logical one. SwiftUI's `offset(x:)` takes a logical one.
    static func sign(_ direction: LayoutDirection) -> CGFloat {
        direction == .rightToLeft ? -1 : 1
    }

    /// The logical offset of the row for a logical drag. It rubber-bands past the open position
    /// and past the closed one. With `bothWays` the row follows a drag towards the trailing edge
    /// as far as `revealWidth` and rubber-bands after it.
    static func offset(isRevealed: Bool, drag: CGFloat, bothWays: Bool = false) -> CGFloat {
        let raw = (isRevealed ? -revealWidth : 0) + drag
        if raw > 0, bothWays { return raw > revealWidth ? revealWidth + (raw - revealWidth) * 0.3 : raw }
        if raw > 0 { return raw * 0.2 }
        if raw < -revealWidth { return -revealWidth + (raw + revealWidth) * 0.3 }
        return raw
    }

    /// True when a drag that would end `projected` logical points from its start leaves the skip
    /// panel revealed.
    static func reveals(isRevealed: Bool, projected: CGFloat) -> Bool {
        (isRevealed ? -revealWidth : 0) + projected < -revealWidth / 2
    }

    /// The end of a drag: whether the skip panel stays revealed, and whether the skip is asked for
    /// now. With `skipsAtSwipe` a drag that would reveal the panel asks for the skip and the row
    /// slides back. With `bothWays` as well, a drag of the same length towards the trailing edge
    /// asks for the skip too (PM's video, 2026-11-22: 7 of 10 swipes went that way and did nothing).
    static func end(isRevealed: Bool, projected: CGFloat, skipsAtSwipe: Bool, bothWays: Bool = false) -> (revealed: Bool, skips: Bool) {
        if skipsAtSwipe, bothWays, !isRevealed, projected > revealWidth / 2 { return (false, true) }
        let revealed = reveals(isRevealed: isRevealed, projected: projected)
        return skipsAtSwipe && revealed ? (false, true) : (revealed, false)
    }
}

/// Swipe a row towards the leading edge to reveal the skip action (Figma journey list, node
/// 11820:71364): the row slides left, its number badge turns red, and a glass panel with the skip
/// glyph appears at the trailing edge. In a right-to-left layout the row slides right and the panel
/// is at the left (PM, Monday "Skipping in Arabic goes the wrong way"). The drag locks to one axis: a horizontal drag pauses
/// scrolling; a vertical drag scrolls and leaves the row in place.
private struct SwipeToSkipRow<Content: View>: View {
    let stopID: String
    @ObservedObject var router: SwipeRouter
    @Binding var isRevealed: Bool
    let isEnabled: Bool
    @Binding var isSwiping: Bool
    var skipsAtSwipe = false
    var skipsBothWays = false
    let onSkip: () -> Void
    @ViewBuilder let content: Content

    private enum Axis { case undecided, horizontal, vertical }

    /// The drag of the row's own gesture (before iOS 18).
    @State private var ownDragX: CGFloat = 0
    @State private var axis: Axis = .undecided
    /// True while the drag gesture runs. SwiftUI resets it when the gesture ends or is cancelled;
    /// a cancelled drag does not call `onEnded`, which left scrolling paused (PM review 2026-10-12).
    @GestureState private var isDragging = false
    @Environment(\.layoutDirection) private var layoutDirection
    private let revealWidth = SkipSwipe.revealWidth

    /// 1 or -1: screen distance to logical distance.
    private var sign: CGFloat { SkipSwipe.sign(layoutDirection) }

    /// The screen distance of the drag: the list's pan on this row, else the row's own gesture.
    private var dragX: CGFloat { router.dragID == stopID ? router.dragX : ownDragX }

    /// The logical offset of the row; `dragX` is a screen distance.
    private var offset: CGFloat {
        SkipSwipe.offset(isRevealed: isRevealed, drag: dragX * sign, bothWays: skipsAtSwipe && skipsBothWays)
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
            // `offset(x:)` follows the layout direction: a negative x is towards the leading edge.
            draggable(content.offset(x: offset))
                .onTapGesture {
                    if isRevealed { withAnimation(.snappy) { isRevealed = false } }
                }
        }
        .animation(.snappy(duration: 0.25), value: isRevealed)
        .onValueChange(of: isDragging) { _, dragging in
            guard !dragging, axis != .undecided || isSwiping else { return }
            axis = .undecided
            isSwiping = false
            withAnimation(.snappy(duration: 0.25)) { ownDragX = 0 }
        }
        // The frame of the row for the list's pan. The offset of the content does not move it.
        .background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .global)
                Color.clear
                    .onAppear { router.frames[stopID] = frame }
                    .onValueChange(of: frame) { _, frame in router.frames[stopID] = frame }
            }
        }
        .onDisappear { router.frames[stopID] = nil }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Skip", bundle: .localized)) { if isEnabled { onSkip() } }
        // For UI tests; VoiceOver does not read identifiers.
        .accessibilityIdentifier(isRevealed ? "journeyStopRow.skipShown" : "journeyStopRow")
    }

    /// Before iOS 18 the row has its own drag. From iOS 18 a SwiftUI drag on a row takes every drag
    /// that starts on it, also as a simultaneous gesture, and the list did not scroll (PM 2026-10-12
    /// and 2026-10-14, `ListScrollUITests`). There the list has one pan (`ListSwipe`).
    @ViewBuilder
    private func draggable(_ row: some View) -> some View {
        if !isEnabled {
            row
        } else if #available(iOS 18.0, *) {
            row
        } else {
            row.simultaneousGesture(drag)
        }
    }

    /// Ends a horizontal drag of the row's own gesture that would stop `projected` logical points
    /// from its start.
    private func end(projected: CGFloat) {
        let end = SkipSwipe.end(isRevealed: isRevealed, projected: projected, skipsAtSwipe: skipsAtSwipe, bothWays: skipsBothWays)
        FieldLog.log(String(format: "list swipe: ended · %.0f pt · skip %@", projected, end.skips ? "asked" : end.revealed ? "shown" : "hidden"))
        withAnimation(.snappy(duration: 0.25)) {
            ownDragX = 0
            isRevealed = end.revealed
        }
        if end.skips { onSkip() }
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
                ownDragX = value.translation.width
            }
            .onEnded { value in
                defer {
                    axis = .undecided
                    isSwiping = false
                }
                guard axis == .horizontal else { return }
                let projected = value.predictedEndTranslation.width * sign
                end(projected: projected)
            }
    }
}

/// The pan of the list, with a field-log line for every touch that reaches the list: `list touch:
/// down` at the touch, and `list touch: up` with the distance moved when the touch ends before the
/// pan was asked to begin. A swipe that moves no row and leaves no `list touch` line did not reach
/// the list; a view of the host app took it (PM, Monday "Swipe bug on iOS 27", video of
/// 2026-11-20 17:23 UTC: two refused swipes without any line).
@available(iOS 18.0, *)
private final class TouchLoggingPan: UIPanGestureRecognizer {
    private var start: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil, let touch = touches.first {
            let point = touch.location(in: nil)
            start = point
            FieldLog.log(String(format: "list touch: down · %.0f, %.0f pt", point.x, point.y))
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        logUp(touches, "up")
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        logUp(touches, "cancelled")
        super.touchesCancelled(touches, with: event)
    }

    override func reset() {
        start = nil
        super.reset()
    }

    /// Only for a touch the pan never took: a begun pan logs `list swipe` lines.
    private func logUp(_ touches: Set<UITouch>, _ word: String) {
        guard state == .possible, let start, let touch = touches.first else { return }
        let point = touch.location(in: nil)
        FieldLog.log(String(format: "list touch: %@ · moved %.0f, %.0f pt · no swipe", word, point.x - start.x, point.y - start.y))
    }
}

/// Takes the list's one pan to the row under the finger. The rows report their frames by stop id,
/// and the list names the stops that can be skipped. The pan holds no stop and no row. With a
/// pan on each row, a swipe on the row "The Golden Sphere" ran the action of the removed row
/// "The Black Angel": the prompt named that artwork and the row did not slide (Nagarro's video
/// and field log, 2026-11-23 08:22 UTC; not reproduced in the simulator).
@MainActor
final class SwipeRouter: ObservableObject {
    /// The stop of the dragged row, and the screen distance of the drag.
    @Published private(set) var dragID: String?
    @Published private(set) var dragX: CGFloat = 0
    /// Row frames in the global coordinate space, by stop id.
    var frames: [String: CGRect] = [:]
    private var skippable: Set<String> = []
    private var onBegan: (String) -> Void = { _ in }
    private var onEnded: (_ stopID: String, _ translation: CGFloat, _ velocity: CGFloat) -> Void = { _, _, _ in }

    /// The list calls this at every update.
    func update(
        skippable: Set<String>,
        onBegan: @escaping (String) -> Void,
        onEnded: @escaping (_ stopID: String, _ translation: CGFloat, _ velocity: CGFloat) -> Void
    ) {
        self.skippable = skippable
        self.onBegan = onBegan
        self.onEnded = onEnded
    }

    /// The stop that can be skipped whose row holds `point`.
    func stopID(at point: CGPoint) -> String? {
        skippable.first { frames[$0]?.contains(point) == true }
    }

    func begin(at point: CGPoint) {
        dragID = stopID(at: point)
        dragX = 0
        if let dragID { onBegan(dragID) }
    }

    func move(_ x: CGFloat) {
        if dragID != nil { dragX = x }
    }

    /// The owner of `onEnded` calls `reset()` inside its animation.
    func end(translation: CGFloat, velocity: CGFloat) {
        guard let dragID else { return }
        onEnded(dragID, translation, velocity)
    }

    func cancel() {
        FieldLog.log("list swipe: cancelled")
        withAnimation(.snappy(duration: 0.25)) { reset() }
    }

    func reset() {
        dragID = nil
        dragX = 0
    }
}

/// The list's pan, from iOS 18. The content shape makes the whole list take the touch: a touch on
/// the part of a row without text did not reach a pan on the row (Nagarro, 2026-11-23).
private struct ListSwipe: ViewModifier {
    let router: SwipeRouter

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.contentShape(Rectangle()).gesture(HorizontalPan(router: router))
        } else {
            content
        }
    }
}

/// A pan that begins only when the drag is more horizontal than vertical and starts on a row that
/// can be skipped. Reports the start, the horizontal translation, and the horizontal velocity at
/// the end to the `SwipeRouter`.
@available(iOS 18.0, *)
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let router: SwipeRouter

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(router: router, converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = TouchLoggingPan()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .began:
            router.begin(at: context.coordinator.start)
            router.move(translation)
        case .changed:
            router.move(translation)
        case .ended:
            router.end(translation: translation, velocity: pan.velocity(in: pan.view).x)
        case .cancelled, .failed:
            router.cancel()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let router: SwipeRouter
        private let converter: CoordinateSpaceConverter

        init(router: SwipeRouter, converter: CoordinateSpaceConverter) {
            self.router = router
            self.converter = converter
        }

        /// Where the drag started, in the global coordinate space.
        var start: CGPoint {
            let location = converter.location(in: .global)
            let translation = converter.translation(in: .global) ?? .zero
            return CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            // Every refused drag is logged, a vertical scroll too: a swipe that moves no row and
            // leaves no line did not reach the list (PM, Monday "Swipe bug on iOS 27", 2026-11-20).
            guard abs(velocity.x) > abs(velocity.y) else {
                FieldLog.log(String(format: "list swipe: not begun · velocity %.0f, %.0f pt/s", velocity.x, velocity.y))
                return false
            }
            let start = start
            guard router.stopID(at: start) != nil else {
                FieldLog.log(String(format: "list swipe: not begun · no row to skip at %.0f, %.0f pt", start.x, start.y))
                return false
            }
            return true
        }

        /// The list's pan waits for this one. A vertical drag fails it at once, so scrolling
        /// starts without delay; a horizontal drag keeps the list still.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
