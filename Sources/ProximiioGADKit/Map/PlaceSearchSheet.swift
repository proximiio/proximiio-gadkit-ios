//
//  PlaceSearchSheet.swift
//  ProximiioGADKit
//
//  Place search on the map (Figma "MAP Functionality Approach 02", "Search"): a search field,
//  the amenity shortcuts and the matching places with their floor.
//
import SwiftUI

struct PlaceSearchSheet: View {
    let places: [VenuePlace]
    /// The amenity shortcuts, in order (`AmenityListing.searchShortcuts(places:amenities:icons:language:)`).
    let shortcuts: [AmenityShortcut]
    let onPick: (VenuePlace) -> Void
    let onPickAmenity: (AmenityShortcut) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(shortcuts) { shortcut in
                                    Button { onPickAmenity(shortcut) } label: {
                                        Label {
                                            Text(shortcut.title)
                                        } icon: {
                                            if let kind = shortcut.kind {
                                                Image(systemName: kind.symbol)
                                            } else {
                                                shortcut.image?.resizable().scaledToFit().frame(width: 16, height: 16)
                                            }
                                        }
                                            .textStyle(.bodySmallRegular)
                                            .padding(.horizontal, 12)
                                            .frame(minHeight: 36)
                                            .overlay(Capsule().stroke(Palette.inputStroke))
                                    }
                                    .foregroundStyle(Palette.ink)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                Section {
                    ForEach(VenuePlace.matching(query, in: places)) { place in
                        Button { onPick(place) } label: {
                            HStack {
                                Text(place.title).textStyle(.bodyMedium)
                                Spacer()
                                Text(GuidanceText.floorLabel(place.level))
                                    .textStyle(.bodyExtraSmall)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search the museum", bundle: .module))
            .navigationTitle(Text("Search", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
