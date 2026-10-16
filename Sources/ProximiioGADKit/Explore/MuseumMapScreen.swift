//
//  MuseumMapScreen.swift
//  ProximiioGADKit
//
//  The museum map as a full screen: header with back button and title, then `MuseumMapView`
//  with the gallery legend. Opened from the Hub's journey card away from the museum.
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
            MuseumMapView(venue: venue, showsLegend: true)
                .frame(maxHeight: .infinity)
        }
        .background(AuroraBackground())
    }

    private var header: some View {
        ZStack {
            Text("Museum Map", bundle: .module).textStyle(.largeBodyBold)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.iconGlass)
                .accessibilityLabel(Text("Back", bundle: .module))
                Spacer()
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
