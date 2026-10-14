//
//  BeforeYouGoSheet.swift
//  ProximiioGADKit
//
//  End of the journey (Figma "Stage 03", 04.03 "End of journey — shop/café/book tour"):
//  the places to visit on the way out. "Watch your Visit Recap" belongs to Nagarro's guide
//  and is not shown.
//
import SwiftUI

struct BeforeYouGoSheet: View {
    let places: [VenuePlace]
    let onPick: (VenuePlace) -> Void

    /// Café, museum shop and kiosk, when the venue data has them.
    private var suggestions: [VenuePlace] {
        var result: [VenuePlace] = []
        for kind in [AmenityKind.cafe, .museumShop] {
            if let place = places.first(where: kind.matches) { result.append(place) }
        }
        if let kiosk = places.first(where: { $0.title.localizedCaseInsensitiveContains("kiosk") }) { result.append(kiosk) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BEFORE YOU GO", bundle: .module).textStyle(.caption)
            Text("Take your time leaving - here's what's next", bundle: .module).textStyle(.h1Bold)
            if suggestions.isEmpty {
                Text("Thank you for visiting Guggenheim Abu Dhabi.", bundle: .module).textStyle(.bodySmallRegular)
            }
            ForEach(suggestions) { place in
                Button { onPick(place) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title).textStyle(.bodyBold)
                            Text(place.details ?? GuidanceText.floorLabel(place.level))
                                .textStyle(.bodyExtraSmall)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                    }
                    .padding(20)
                    .glassSurface(cornerRadius: 12)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.ink)
        .padding(30)
        .presentationCornerRadius(50)
        .presentationBackground { AuroraBackground() }
    }
}
