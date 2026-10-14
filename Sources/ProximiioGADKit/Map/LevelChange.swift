//
//  LevelChange.swift
//  ProximiioGADKit
//
//  The level change animation (`design/level-changing`, the colleague's GIFs): a floor plate splits
//  into two, then an up or down arrow with "Level up" or "Level down". The journey screen and the
//  museum map show it over the map (`levelChangeAnimation(for:venue:)`):
//
//  - while the visitor rides a lift: positions stay inside a lift outline for `LiftDetector.dwell`
//    seconds. With a route level change at the lift, the overlay plays the animation towards the
//    route's floor. Without one, it shows "In the lift" until the floor changes.
//  - when the position changes floor: the animation towards the new floor, then the map on that
//    floor. A tap closes the overlay.
//
//  The resources `Resources/LevelChange/level-{up,down}-{en,ar}.apng` are the EN and AR GIFs
//  cropped to their content (x 245–1744, y 25–1064 of 1920×1080), scaled to 480 px and reduced to
//  their alpha channel. The app tints them with the position colour.
//
//  A floor counts as changed after `confirmations` consecutive fixes on the new floor. The default
//  is 1: the map switches floors on the first fix on the new floor, and the overlay starts on the
//  same fix, so the switch happens under the animation.
//
import ImageIO
import Proximiio
import ProximiioMap
import SwiftUI
import UIKit

struct LevelChange: Equatable, Identifiable {
    var from: Int
    var to: Int
    var id: String { "\(from)-\(to)" }
    var isUp: Bool { to > from }
}

struct LevelChangeDetector {
    var confirmations = 1
    private(set) var level: Int?
    private var candidate: Int?
    private var candidateFixes = 0

    /// Swift 6.2 (Xcode 26.3) makes the memberwise initializer private because of the private
    /// stored properties.
    init(confirmations: Int = 1) {
        self.confirmations = confirmations
    }

    /// Feeds the floor of one fix. Returns the change when the new floor is confirmed. The first
    /// floor seen is no change.
    mutating func update(level fixLevel: Double?) -> LevelChange? {
        guard let fixLevel else { return nil }
        let next = Int(fixLevel.rounded())
        guard let current = level else {
            level = next
            return nil
        }
        guard next != current else {
            candidate = nil
            candidateFixes = 0
            return nil
        }
        if candidate == next {
            candidateFixes += 1
        } else {
            candidate = next
            candidateFixes = 1
        }
        guard candidateFixes >= confirmations else { return nil }
        level = next
        candidate = nil
        candidateFixes = 0
        return LevelChange(from: current, to: next)
    }
}

/// A lift cabin outline: a venue polygon feature of type `elevator`. The outline is drawn on one
/// floor, and a lift shaft is vertical, so it applies on every floor.
struct LiftArea {
    let outline: Gallery

    static func all(features: [ProximiioFeature]) -> [LiftArea] {
        features.compactMap { feature in
            guard feature.propertyType == "elevator", let geometry = feature.geometry,
                  let ring = Gallery.outerRing(type: geometry.type, coordinates: geometry.coordinates) else { return nil }
            return LiftArea(outline: Gallery(id: feature.id, name: "", level: 0, ring: ring))
        }
    }

    func contains(_ coordinate: ProximiioCoordinate) -> Bool {
        outline.contains(coordinate, level: nil)
    }
}

/// Detects a ride: the visitor counts as in the lift after `dwell` seconds of fixes inside a lift
/// area, so walking past a lift is no ride. The ride ends after `exitFixes` consecutive fixes
/// outside.
struct LiftDetector {
    enum Event: Equatable { case boarded, left }

    var dwell: TimeInterval = 3
    var exitFixes = 2
    private(set) var isRiding = false
    private var insideSince: Date?
    private var outsideFixes = 0

    mutating func update(inLift: Bool, at time: Date) -> Event? {
        if inLift {
            outsideFixes = 0
            let since = insideSince ?? time
            insideSince = since
            guard !isRiding, time.timeIntervalSince(since) >= dwell else { return nil }
            isRiding = true
            return .boarded
        }
        outsideFixes += 1
        guard outsideFixes >= exitFixes else { return nil }
        insideSince = nil
        guard isRiding else { return nil }
        isRiding = false
        return .left
    }
}

/// What the overlay shows: the ride, then the arrival on the new floor.
struct LevelChangeCard: Equatable {
    enum Phase: Equatable { case riding, arrived }

    var phase: Phase
    var from: Int
    /// The floor the visitor goes to. During a ride it comes from the route's level change at this
    /// lift, and is `nil` without one.
    var to: Int?
}

extension View {
    /// Shows `LevelChangeOverlay` while the visitor rides a lift and when the session's position
    /// changes floor, and moves the map to the visitor's floor.
    func levelChangeAnimation(for session: ProximiioMapSession, venue: VenueService) -> some View {
        modifier(LevelChangeModifier(session: session, venue: venue))
    }
}

private struct LevelChangeModifier: ViewModifier {
    let session: ProximiioMapSession
    let venue: VenueService
    @State private var floors = LevelChangeDetector()
    @State private var lift = LiftDetector()
    @State private var lifts: [LiftArea] = []
    @State private var card: LevelChangeCard?

    func body(content: Content) -> some View {
        content
            .task { lifts = LiftArea.all(features: await venue.sdk.features()) }
            .onReceive(session.$position) { position in
                if let position { update(with: position) }
            }
            .overlay {
                if let card {
                    LevelChangeOverlay(card: card)
                        .onTapGesture { self.card = nil }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: card)
    }

    private func update(with position: VenuePosition) {
        let coordinate = ProximiioCoordinate(latitude: position.coordinate.latitude, longitude: position.coordinate.longitude)
        let event = lift.update(inLift: lifts.contains { $0.contains(coordinate) }, at: .now)
        if let change = floors.update(level: position.floor?.level) {
            arrive(change)
            return
        }
        switch event {
        case .boarded:
            guard let from = floors.level else { return }
            board(LevelChangeCard(phase: .riding, from: from, to: routeTarget(from: from)))
        case .left:
            if card?.phase == .riding { card = nil }
        case nil:
            break
        }
    }

    /// The target floor of the route's next manoeuvre when it is a level change from `from`.
    private func routeTarget(from: Int) -> Int? {
        guard case .levelChange(let change)? = session.guidance?.manoeuvre?.kind,
              Int(change.fromLevel.rounded()) == from else { return nil }
        return Int(change.toLevel.rounded())
    }

    private func board(_ riding: LevelChangeCard) {
        FieldLog.log("lift boarded on L\(riding.from), target \(riding.to.map { "L\($0)" } ?? "unknown")")
        card = riding
    }

    private func arrive(_ change: LevelChange) {
        FieldLog.log("level change: L\(change.from) → L\(change.to)")
        let arrived = LevelChangeCard(phase: .arrived, from: change.from, to: change.to)
        card = arrived
        session.followMyFloor()
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if card == arrived { card = nil }
        }
    }
}

/// Full-screen overlay: the animation and "Level X". It plays once and keeps the last frame.
/// A ride with an unknown target shows the first frame and "In the lift"; the animation plays when
/// the floor changes.
struct LevelChangeOverlay: View {
    let card: LevelChangeCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.white.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                Group {
                    if let to = card.to {
                        LevelChangeAnimation(isUp: to > card.from, plays: !reduceMotion)
                    } else {
                        LevelChangeAnimation(isUp: true, plays: false, showsFirstFrame: true)
                    }
                }
                .id(card.to)
                .frame(width: 280, height: 194)
                if let to = card.to {
                    Text("Level \(to)", bundle: .module).textStyle(.h1Bold)
                } else {
                    Text("In the lift", bundle: .module).textStyle(.h1Bold)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Closes the level change", bundle: .module))
    }

    private var accessibilityText: Text {
        switch (card.phase, card.to) {
        case (.arrived, let to?): Text("You are now on level \(to)", bundle: .module)
        case (.riding, let to?): Text("Going to level \(to)", bundle: .module)
        default: Text("In the lift", bundle: .module)
        }
    }
}

private struct LevelChangeAnimation: UIViewRepresentable {
    let isUp: Bool
    let plays: Bool
    var showsFirstFrame = false

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        guard let animation = LevelChangeFrames.load(isUp: isUp) else { return view }
        view.image = showsFirstFrame ? animation.frames.first : animation.frames.last
        if plays {
            view.animationImages = animation.frames
            view.animationDuration = animation.duration
            view.animationRepeatCount = 1
            view.startAnimating()
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}
}

enum LevelChangeFrames {
    struct Animation {
        var frames: [UIImage]
        var duration: TimeInterval
    }

    /// The frames of the APNG for the app's language, tinted with the position colour.
    static func load(isUp: Bool) -> Animation? {
        let language = Bundle.main.preferredLocalizations.first == "ar" ? "ar" : "en"
        guard let url = Bundle.module.url(forResource: "level-\(isUp ? "up" : "down")-\(language)", withExtension: "apng"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let tint = UIColor(Palette.position)
        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            duration += (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
                ?? (png?[kCGImagePropertyAPNGDelayTime] as? Double) ?? 0.04
            frames.append(tinted(image, with: tint))
        }
        return frames.isEmpty ? nil : Animation(frames: frames, duration: duration)
    }

    /// Fills the frame's opaque pixels with `color`.
    private static func tinted(_ image: CGImage, with color: UIColor) -> UIImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIImage(cgImage: image).draw(in: rect)
            color.setFill()
            context.fill(rect, blendMode: .sourceIn)
        }
    }
}
