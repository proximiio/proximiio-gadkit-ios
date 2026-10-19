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

enum VisitPlan {
    /// A journey from POI ids in visit order. Ids that match no place are dropped. Each stop's
    /// `group` is the id of the gallery that contains it, for the floor-then-gallery order.
    static func journey(poiIDs: [String], places: [VenuePlace], galleries: [Gallery] = []) -> Journey {
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

    /// `journey` after a change of the venue data. Pure; covered by tests.
    /// - A reached or done stop keeps its stored values.
    /// - Any other planned stop whose POI is no longer a place is removed.
    /// - Any other planned stop takes the title, coordinate, floor and gallery of its POI. Its id
    ///   and state stay.
    /// - Detour stops stay as they are.
    static func reconciled(_ journey: Journey, places: [VenuePlace], galleries: [Gallery] = []) -> Journey {
        let byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Journey(stops: journey.stops.compactMap { stop in
            guard followsItsPlace(stop), let poiID = stop.poiID else { return stop }
            guard let place = byID[poiID] else { return nil }
            var updated = Self.stop(for: place, galleries: galleries)
            updated.id = stop.id
            updated.state = stop.state
            updated.iconName = stop.iconName
            return updated
        })
    }

    /// The pending, active and skipped planned stops whose POI is no longer a place. Pure; covered
    /// by tests.
    static func stopsWithoutPlace(in journey: Journey, places: [VenuePlace]) -> [JourneyStop] {
        let ids = Set(places.map(\.id))
        return journey.stops.filter { stop in
            followsItsPlace(stop) && stop.poiID.map { !ids.contains($0) } == true
        }
    }

    private static func followsItsPlace(_ stop: JourneyStop) -> Bool {
        stop.kind == .planned && stop.state != .reached && stop.state != .done
    }

    /// A row of the journey list: a section header or a stop.
    enum ListRow: Identifiable {
        case header(id: String, title: String)
        case stop(JourneyStop)

        var id: String {
            switch self {
            case .header(let id, _): id
            case .stop(let stop): stop.id
            }
        }
    }

    /// The journey list in visit order, one flat list: a header before each run of consecutive
    /// stops with the same section, for example a gallery. A gallery visited twice gets two
    /// headers, so the list keeps the visit order. A run without a section has no header. A
    /// header's id follows the first stop of its run, so rows keep their identity when the order
    /// changes (PM 2026-10-15: the list showed rows of an older order). Pure; covered by tests.
    static func listRows(_ stops: [JourneyStop], sectionOf: (JourneyStop) -> String?) -> [ListRow] {
        var rows: [ListRow] = []
        var current: String?
        for (index, stop) in stops.enumerated() {
            let section = sectionOf(stop)
            if index == 0 || section != current, let section {
                rows.append(.header(id: "header-\(stop.id)", title: section))
            }
            current = section
            rows.append(.stop(stop))
        }
        return rows
    }

    /// True when `stop` is the last artwork still to visit (Figma 04.01 "approaching end of tour").
    static func isLastOpenStop(_ stop: JourneyStop, in journey: Journey) -> Bool {
        openArtworks(in: journey).map(\.id) == [stop.id]
    }

    /// Artworks still to visit: pending, active or reached. A finished journey has none.
    static func remainingStopCount(in journey: Journey) -> Int {
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
/// | Order | ordered floor by floor and gallery by gallery from the visitor | the curators' order |
///
/// The background is the same (PM 2026-10-14: ignore the curated tour colour).
public enum JourneyKind: String, Codable, Sendable, CaseIterable {
    case personalised
    case curated

    /// Whether the stop card names the gallery of the next stop first. Pure; covered by tests.
    var guidesToGalleryFirst: Bool { self == .personalised }
    /// Whether the list shows gallery names. Pure; covered by tests.
    var listsGalleries: Bool { self == .personalised }
    /// Whether the visitor can skip an artwork. Pure; covered by tests.
    var allowsSkip: Bool { self == .personalised }
    /// Whether the stops keep their order: no ordering from the visitor at the start, after a
    /// detour or after an artwork visited out of order. Pure; covered by tests.
    var keepsOrder: Bool { self == .curated }
}

/// Title, summary and kind of a visit, shown on Journey ready (02.10A) and the Hub card.
struct VisitMeta: Codable, Equatable, Sendable {
    var title: String
    var summary: String?
    /// `personalised` for a stored visit from before the kind existed.
    var kind: JourneyKind

    init(title: String, summary: String? = nil, kind: JourneyKind = .personalised) {
        self.title = title
        self.summary = summary
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        kind = try container.decodeIfPresent(JourneyKind.self, forKey: .kind) ?? .personalised
    }

    static func standard(stopCount: Int, kind: JourneyKind = .personalised) -> VisitMeta {
        VisitMeta(title: String(localized: "Your journey", bundle: .module), summary: String(localized: "\(stopCount) stops", bundle: .module), kind: kind)
    }
}

/// Gallery first on the stop card (DAILY-CALL R2; PM, Monday "Navigation to a gallery"). While the
/// leg ends at the gallery of the active artwork (`GalleryFirstRouting`), the card names the gallery
/// and shows no stop number. The first fix inside that gallery marks the artwork reached: the leg and
/// the card lead to the artwork until the active stop changes, so the card does not flicker at the
/// gallery's edge.
enum GalleryFirst {
    /// Stop numbers appear at the stop and inside the stop's gallery only.
    static func showsStopNumber(state: VisitCardState, galleryAhead: Gallery?) -> Bool {
        if case .atStop = state { return true }
        return galleryAhead == nil
    }
}
