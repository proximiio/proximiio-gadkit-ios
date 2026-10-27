//
//  AmenityListing.swift
//  ProximiioGADKit
//
//  Which amenities a list shows, and in what order, from the amenity's `metadata` (PM, Monday
//  "Amenity search & Map legend views", 2026-10-27):
//
//  - `in_search` and `search_order`: the amenity shortcuts of the maps' search.
//  - `in_facilities` and `facilities_order`: the Explore Museum map's Amenities list and the
//    facilities of its legend.
//
//  `metadata` and both keys are optional. A flag that is `false` or "false" leaves the amenity out; a
//  flag `true` or "true" puts in an amenity the list does not show by itself. The order is a number or
//  a numeric string, lowest first. An amenity without an order comes after the ordered ones, in the
//  list's own order.
//
import Foundation
import Proximiio

struct AmenityListing: Equatable, Sendable {
    /// The order of each amenity that has one, by amenity id.
    private(set) var order: [String: Double] = [:]
    /// The amenities whose flag is false, by id.
    private(set) var excluded: Set<String> = []
    /// The amenities whose flag is true, by id.
    private(set) var included: Set<String> = []
    /// The same by lower-case amenity title, for the legend's lifts and stairs.
    private(set) var orderByTitle: [String: Double] = [:]
    private(set) var excludedTitles: Set<String> = []

    /// No amenity has the keys: each list keeps its own choice and order.
    static let all = AmenityListing()

    private init() {}

    /// The listing of `amenities` under `flag` and `orderKey`. Pure; covered by tests.
    init(amenities: [ProximiioAmenity], flag: String, orderKey: String) {
        for amenity in amenities {
            guard case .object(let metadata)? = amenity.metadata else { continue }
            let title = amenity.title?.lowercased()
            switch Self.flag(metadata[flag]) {
            case false?:
                excluded.insert(amenity.id)
                if let title { excludedTitles.insert(title) }
                continue
            case true?:
                included.insert(amenity.id)
            case nil:
                break
            }
            if let rank = Self.number(metadata[orderKey]) {
                order[amenity.id] = rank
                if let title { orderByTitle[title] = rank }
            }
        }
    }

    static func search(_ amenities: [ProximiioAmenity]) -> AmenityListing {
        AmenityListing(amenities: amenities, flag: "in_search", orderKey: "search_order")
    }

    static func facilities(_ amenities: [ProximiioAmenity]) -> AmenityListing {
        AmenityListing(amenities: amenities, flag: "in_facilities", orderKey: "facilities_order")
    }

    /// The sort key of `amenityID`: its order, after every order without one, `nil` when its flag is
    /// false.
    func rank(of amenityID: String?) -> Double? {
        guard let amenityID else { return .greatestFiniteMagnitude }
        if excluded.contains(amenityID) { return nil }
        return order[amenityID] ?? .greatestFiniteMagnitude
    }

    /// The rank of the amenity titled `title`, as `rank(of:)`.
    func rank(ofTitle title: String) -> Double? {
        let title = title.lowercased()
        if excludedTitles.contains(title) { return nil }
        return orderByTitle[title] ?? .greatestFiniteMagnitude
    }

    /// The shortcut kinds of `places`: the kinds of `AmenityKind.shortcuts` and those of the amenities
    /// with the flag true, without those whose flag is false, by the data's order, then in the order
    /// of `AmenityKind.allCases`. Pure; covered by tests.
    func shortcuts(places: [VenuePlace]) -> [AmenityKind] {
        let ranked = AmenityKind.allCases.compactMap { kind -> (AmenityKind, Double)? in
            let matching = places.filter(kind.matches)
            guard !matching.isEmpty else { return nil }
            let isFlagged = matching.contains { $0.amenityID.map(included.contains) ?? false }
            guard AmenityKind.shortcuts.contains(kind) || isFlagged else { return nil }
            return matching.compactMap { rank(of: $0.amenityID) }.min().map { (kind, $0) }
        }
        return ranked.enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }
            .map(\.element.0)
    }

    private static func flag(_ value: JSONValue?) -> Bool? {
        switch value {
        case .bool(let flag): flag
        case .string(let text):
            switch text.lowercased() {
            case "true": true
            case "false": false
            default: nil
            }
        case .number(let number): number != 0
        default: nil
        }
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number): number
        case .string(let text): Double(text)
        default: nil
        }
    }
}
