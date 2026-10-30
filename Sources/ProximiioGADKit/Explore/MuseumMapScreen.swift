//
//  MuseumMapScreen.swift
//  ProximiioGADKit
//
//  The Explore Museum map as a full screen: the back button and "Explore Museum", then
//  `ExploreMuseumView`. Opened with `ProximiMap.open(.museumMap)`, in this app from the Hub's journey
//  card away from the museum.
//
import SwiftUI

struct MuseumMapScreen: View {
    let venue: VenueService
    let onBack: () -> Void

    init(venue: VenueService, onBack: @escaping () -> Void) {
        self.venue = venue
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ExploreMuseumView(venue: venue)
                .frame(maxHeight: .infinity)
        }
        .background(AuroraBackground())
    }

    /// The back button and the title, "Explore" bold and "Museum" regular.
    private var header: some View {
        ZStack {
            (Text("Explore", bundle: .localized).font(TextStyle.largeBodyBold.font)
                + Text(verbatim: " ")
                + Text("Museum", bundle: .localized).font(TextStyle.largeBodyRegular.font))
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.iconGlass)
                .accessibilityLabel(Text("Back", bundle: .localized))
                Spacer()
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
