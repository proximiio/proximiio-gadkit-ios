//
//  JourneyScreens.swift
//  ProximiioGADKit
//
//  Journey lifecycle screens from the Figma file:
//
//  - Journey ready (02.10A, node 6902:55705)
//  - Manage journey (02.11): edit stops, craft a new one, delete
//  - Exit confirmation (03.10, Overlay node 6902:45589)
//  - Journey Complete (PM review 2026-10-12, `design/monday-2026-10-12/journey-complete.png`)
//
import SwiftUI

/// "YOUR PERSONALISED JOURNEY · Light & Perception": title, summary, Start the Journey or
/// Go to the Museum, Back to Hub.
struct JourneyReadyView: View {
    let meta: VisitMeta
    let isAtMuseum: Bool
    let onStart: () -> Void
    let onBack: () -> Void

    init(meta: VisitMeta, isAtMuseum: Bool, onStart: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.meta = meta
        self.isAtMuseum = isAtMuseum
        self.onStart = onStart
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            ScreenBackground.hub.view
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 15) {
                    // Figma 02.10A, and "CURATED" on the curated tour's start frame.
                    Text(meta.kind == .curated ? "CURATED" : "YOUR PERSONALISED JOURNEY", bundle: .module).textStyle(.caption)
                    Text(meta.title).font(GADFonts.custom("GuggenheimSansDisplay-SemiBold", size: 32, relativeTo: .largeTitle))
                    if let summary = meta.summary {
                        Text(summary).textStyle(.bodySmallRegular)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(width: 322)
                Spacer()
                VStack(spacing: 28) {
                    if isAtMuseum {
                        Button(String(localized: "Start the Journey", bundle: .module), action: onStart).buttonStyle(.primary)
                    } else {
                        VStack(spacing: 10) {
                            Button(String(localized: "Go to Museum", bundle: .module), action: onStart).buttonStyle(.primary)
                            Text("It will be ready when you arrive at GAD", bundle: .module).textStyle(.bodyExtraSmall)
                        }
                    }
                    Button(String(localized: "Back to Hub", bundle: .module), action: onBack).buttonStyle(.textAction)
                }
                .frame(width: 322)
                .padding(.bottom, 20)
            }
            .foregroundStyle(Palette.ink)
        }
    }
}

/// Manage journey (02.11): edit the stops, craft a new journey, or delete the current one.
struct ManageJourneySheet: View {
    let meta: VisitMeta
    let onEdit: () -> Void
    let onCraftNew: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    init(
        meta: VisitMeta,
        onEdit: @escaping () -> Void,
        onCraftNew: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.meta = meta
        self.onEdit = onEdit
        self.onCraftNew = onCraftNew
        self.onDelete = onDelete
        self.onClose = onClose
    }

    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 10) {
            Text(meta.title).textStyle(.h1Bold)
            if let summary = meta.summary { Text(summary).textStyle(.bodySmallRegular) }
            VStack(spacing: 12) {
                Button(String(localized: "Edit stops", bundle: .module), action: onEdit).buttonStyle(.primary)
                Button(String(localized: "Craft a new journey", bundle: .module), action: onCraftNew).buttonStyle(.primary)
                if isConfirmingDelete {
                    Button(String(localized: "Delete this journey", bundle: .module), role: .destructive, action: onDelete)
                        .buttonStyle(.primary)
                        .foregroundStyle(Palette.activeRed)
                } else {
                    Button(String(localized: "Delete journey", bundle: .module)) { withAnimation { isConfirmingDelete = true } }
                        .buttonStyle(.textAction)
                }
            }
            .padding(.top, 20)
            Button(String(localized: "Close", bundle: .module), action: onClose).buttonStyle(.textAction)
        }
        .overlaySheetStyle()
    }
}

/// "Leave the tour here" (03.10): progress is saved; the visitor can carry on.
struct ExitConfirmationSheet: View {
    let visited: Int
    let total: Int
    let onLeave: () -> Void
    let onCarryOn: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Leave the tour here", bundle: .module).textStyle(.h1Bold)
            Text("You've visited \(visited) of \(total) stops. Your journey is saved.", bundle: .module)
                .textStyle(.bodySmallRegular)
                .padding(.bottom, 20)
            Button(String(localized: "Leave the tour", bundle: .module), action: onLeave).buttonStyle(.primary)
            Button(String(localized: "Carry on", bundle: .module), action: onCarryOn).buttonStyle(.textAction)
        }
        .overlaySheetStyle()
    }
}

/// Journey Complete: the journey ends here. The close button leaves the visit; the map button
/// opens the museum map. The subtitle is the design's text (PM review 2026-10-12).
struct JourneyCompleteView: View {
    let venue: VenueService
    let onClose: () -> Void

    @State private var isShowingMap = false

    var body: some View {
        ZStack {
            AuroraBackground(variant: .mint)
            VStack(spacing: 0) {
                HStack {
                    Text("Journey Complete", bundle: .module).textStyle(.bodyBold)
                    Spacer()
                    GlassSquareButton(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .regular))
                    }
                    .accessibilityLabel(Text("Close", bundle: .module))
                }
                .padding(.horizontal, 30)
                .padding(.top, 12)
                VStack(spacing: 20) {
                    Text("You've walked your route", bundle: .module).textStyle(.cardTitle)
                    Text("Sculptural works exploring negative space and mass - six pieces, unfolding through the room.", bundle: .module)
                        .textStyle(.bodyMedium)
                }
                .multilineTextAlignment(.center)
                .frame(width: 322)
                .padding(.top, 60)
                Spacer()
                BottomGlassBar {
                    Button { isShowingMap = true } label: {
                        Image(systemName: "map").font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(RoundGlassButtonStyle())
                    .accessibilityLabel(Text("Museum map", bundle: .module))
                } trailing: {
                    EmptyView()
                }
            }
            .foregroundStyle(Palette.ink)
        }
        .fullScreenCover(isPresented: $isShowingMap) {
            ZStack(alignment: .topLeading) {
                MuseumMapView(venue: venue)
                Button { isShowingMap = false } label: {
                    Image(systemName: "chevron.backward")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(Text("Back", bundle: .module))
                .padding(16)
            }
        }
    }
}
