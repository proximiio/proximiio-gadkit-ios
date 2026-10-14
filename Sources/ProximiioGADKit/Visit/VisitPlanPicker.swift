//
//  VisitPlanPicker.swift
//  ProximiioGADKit
//
//  Picks the stops of a visit by hand. The tap order is the visit order. Stands in for the
//  personalised journey from Nagarro's guide until that integration exists.
//
import SwiftUI

public struct VisitPlanPicker: View {
    let places: [VenuePlace]
    let onStart: ([String]) -> Void
    let onCancel: () -> Void

    public init(places: [VenuePlace], onStart: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        self.places = places
        self.onStart = onStart
        self.onCancel = onCancel
    }

    @State private var query = ""
    @State private var picked: [String] = []

    public var body: some View {
        NavigationStack {
            List(VenuePlace.matching(query, in: places)) { place in
                Button {
                    if let index = picked.firstIndex(of: place.id) {
                        picked.remove(at: index)
                    } else {
                        picked.append(place.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title).textStyle(.bodyMedium)
                            Text(GuidanceText.floorLabel(place.level)).textStyle(.bodyExtraSmall).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let index = picked.firstIndex(of: place.id) {
                            Text("\(index + 1)", bundle: .module)
                                .textStyle(.bodySmallBold)
                                .frame(width: 28, height: 28)
                                .background(Palette.ink, in: Circle())
                                .foregroundStyle(Palette.white)
                        }
                    }
                    .foregroundStyle(Palette.ink)
                }
            }
            .searchable(text: $query)
            .navigationTitle(Text("Plan your visit", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel", bundle: .module), action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Start", bundle: .module)) { onStart(picked) }.disabled(picked.isEmpty)
                }
            }
        }
    }
}
