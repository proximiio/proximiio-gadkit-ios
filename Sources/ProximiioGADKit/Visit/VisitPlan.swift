//
//  VisitPlan.swift
//  ProximiioGADKit
//
//  The ordered stops of a visit, and the pure rules the visit screens use.
//
//  The stops of a personalised journey come from Nagarro's guide as an ordered list of
//  Proximi.io POI ids (see `AudioGuideHost`). Debug builds can also pick stops by hand.
//
import Foundation
import ProximiioMap

public enum VisitPlan {
    /// A journey from POI ids in visit order. Ids that match no place are dropped. Each stop's
    /// `group` is the id of the gallery that contains it, for the floor-then-gallery order.
    public static func journey(poiIDs: [String], places: [VenuePlace], galleries: [Gallery] = []) -> Journey {
        let byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Journey(stops: poiIDs.compactMap { byID[$0] }.map { stop(for: $0, galleries: galleries) })
    }

    static func stop(for place: VenuePlace, galleries: [Gallery] = []) -> JourneyStop {
        JourneyStop(
            id: place.id,
            title: place.title,
            coordinate: MapCoordinate(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
            floor: FloorKey(level: place.level),
            poiID: place.id,
            group: Gallery.containing(place.coordinate, level: place.level, in: galleries)?.id
        )
    }

    struct GalleryGroup {
        var id: String
        var gallery: String?
        var stops: [JourneyStop]
    }

    /// Consecutive stops in the same gallery form one group. A gallery visited twice yields two
    /// groups, so the list keeps the visit order.
    static func galleryGroups(_ stops: [JourneyStop], galleryOf: (JourneyStop) -> String?) -> [GalleryGroup] {
        var groups: [GalleryGroup] = []
        for stop in stops {
            let gallery = galleryOf(stop)
            if let last = groups.last, last.gallery == gallery {
                groups[groups.count - 1].stops.append(stop)
            } else {
                groups.append(GalleryGroup(id: "\(groups.count)-\(gallery ?? "")", gallery: gallery, stops: [stop]))
            }
        }
        return groups
    }

    /// True when `stop` is the last artwork still to visit (Figma 04.01 "approaching end of tour").
    static func isLastOpenStop(_ stop: JourneyStop, in journey: Journey) -> Bool {
        openArtworks(in: journey).map(\.id) == [stop.id]
    }

    /// Artworks still to visit: pending, active or reached. A finished journey has none.
    public static func remainingStopCount(in journey: Journey) -> Int {
        openArtworks(in: journey).count
    }

    private static func openArtworks(in journey: Journey) -> [JourneyStop] {
        journey.stops.filter { $0.kind != .detour && ($0.state == .pending || $0.state == .active || $0.state == .reached) }
    }

    /// The journey's artworks: stops that are not detours. An amenity added as a detour has no
    /// number and is not in the list (PM review 2026-10-12).
    static func artworks(in journey: Journey) -> [JourneyStop] {
        journey.stops.filter { $0.kind != .detour }
    }

    /// Display number of each artwork that is not skipped, 1-based, in visit order.
    /// Skipped stops and detours get no number, so the list renumbers after a skip, as the design shows.
    static func numbers(for journey: Journey) -> [String: Int] {
        var result: [String: Int] = [:]
        var next = 1
        for stop in artworks(in: journey) where stop.state != .skipped {
            result[stop.id] = next
            next += 1
        }
        return result
    }
}

/// What the visit card shows (Figma "MAP Functionality Approach 02" annotations).
enum VisitCardState: Equatable {
    /// The navigator has not activated a stop yet.
    case starting
    /// "Next stop: Gallery 2", with the next instruction.
    case walking(stop: String)
    /// "Next stop is on Level 2 / Take the lift", while the visitor is on another floor.
    case nextStopOnOtherLevel(stop: String, level: Int)
    /// "Current artwork: Untitled (Mirrored Room)", until the journey moves on. Hidden while
    /// `showsArrival` is false.
    case atStop(stop: String)
    /// Every stop is done or skipped.
    case finished

    /// False: on arrival the card keeps the stop until the journey moves on 2 s later, with no
    /// "Current artwork" state (PM review 2026-10-12: the card is not needed).
    static let showsArrival = false

    static func make(
        activeStop: JourneyStop?,
        hasArrived: Bool,
        isFinished: Bool,
        visitorLevel: Double?,
        showsArrival: Bool = VisitCardState.showsArrival
    ) -> VisitCardState {
        guard let stop = activeStop else { return isFinished ? .finished : .starting }
        if hasArrived && showsArrival { return .atStop(stop: stop.title) }
        if let stopLevel = stop.floor?.level, let visitorLevel,
           Int(stopLevel.rounded()) != Int(visitorLevel.rounded()) {
            return .nextStopOnOtherLevel(stop: stop.title, level: Int(stopLevel.rounded()))
        }
        return .walking(stop: stop.title)
    }
}

/// A journey the visitor built with the guide, or a tour by the museum's curators (PM 2026-10-14,
/// Figma "Personalised" and "Guided"). `VisitView` differs by kind:
///
/// | | Personalised | Curated |
/// |---|---|---|
/// | Stop card | names the gallery until the visitor is in it, then the artwork | names the artwork |
/// | List | stops under gallery names | stops without gallery names |
/// | Skip | the visitor can skip an artwork | no skip |
///
/// The background is the same (PM 2026-10-14: ignore the curated tour colour).
public enum JourneyKind: String, Codable, Sendable, CaseIterable {
    case personalised
    case curated

    /// Whether the stop card names the gallery of the next stop first. Pure; covered by tests.
    public var guidesToGalleryFirst: Bool { self == .personalised }
    /// Whether the list shows gallery names. Pure; covered by tests.
    public var listsGalleries: Bool { self == .personalised }
    /// Whether the visitor can skip an artwork. Pure; covered by tests.
    public var allowsSkip: Bool { self == .personalised }
}

/// Title, summary and kind of a visit, shown on Journey ready (02.10A) and the Hub card.
public struct VisitMeta: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String?
    /// `personalised` for a stored visit from before the kind existed.
    public var kind: JourneyKind

    public init(title: String, summary: String? = nil, kind: JourneyKind = .personalised) {
        self.title = title
        self.summary = summary
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        kind = try container.decodeIfPresent(JourneyKind.self, forKey: .kind) ?? .personalised
    }

    public static func standard(stopCount: Int, kind: JourneyKind = .personalised) -> VisitMeta {
        VisitMeta(title: String(localized: "Your journey", bundle: .module), summary: String(localized: "\(stopCount) stops", bundle: .module), kind: kind)
    }
}

/// Gallery first on the stop card (DAILY-CALL R2). While the visitor is outside the gallery of the
/// active stop, the card names the gallery and shows no stop number. The first fix inside that
/// gallery latches the stop: the card names the artwork until the active stop changes, so it does
/// not flicker at the gallery's edge. The route always leads to the artwork. Same rule as
/// `guggenheim-android` `GalleryFirst`.
enum GalleryFirst {
    /// The gallery the card names instead of the artwork, or `nil` once the stop is latched.
    static func galleryAhead(activeStopID: String?, stopGallery: Gallery?, reachedStopID: String?) -> Gallery? {
        guard let activeStopID, reachedStopID != activeStopID else { return nil }
        return stopGallery
    }

    /// The latched stop after a fix or a change of the active stop: the active stop once the
    /// visitor is in its gallery, otherwise `reachedStopID` unchanged.
    static func reachedStopID(activeStopID: String?, stopGallery: Gallery?, visitorGallery: Gallery?, reachedStopID: String?) -> String? {
        guard let activeStopID, reachedStopID != activeStopID,
              let stopGallery, visitorGallery?.id == stopGallery.id else { return reachedStopID }
        return activeStopID
    }

    /// Stop numbers appear at the stop and inside the stop's gallery only.
    static func showsStopNumber(state: VisitCardState, galleryAhead: Gallery?) -> Bool {
        if case .atStop = state { return true }
        return galleryAhead == nil
    }
}
