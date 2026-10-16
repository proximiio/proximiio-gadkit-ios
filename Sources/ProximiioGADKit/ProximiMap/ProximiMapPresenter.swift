//
//  ProximiMapPresenter.swift
//  ProximiioGADKit
//
//  `.proximiMap(_:)`: presents the screens and sheets of a `ProximiMap` over the host app's view.
//  The museum map, Journey ready and the journey are full-screen covers; the stop picker and
//  Manage journey are sheets. One presentation at a time; `ProximiMap` presents the next one after
//  the dismissal of the previous.
//
import Proximiio
import ProximiioMap
import SwiftUI

extension View {
    /// Presents the screens of `map` over this view. Attach it once, to a view that stays on screen
    /// while the app runs, for example the root view.
    public func proximiMap(_ map: ProximiMap) -> some View {
        modifier(ProximiMapPresenter(map: map))
    }
}

struct ProximiMapPresenter: ViewModifier {
    @Bindable var map: ProximiMap

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $map.cover, onDismiss: map.coverDismissed) { cover in
                coverContent(cover)
                    .routeAccessibility(map.routeAccessibility)
                    .onVisitEvent { map.handle($0) }
            }
            .sheet(item: $map.sheet, onDismiss: map.sheetDismissed) { sheet in
                sheetContent(sheet)
            }
    }

    @ViewBuilder private func coverContent(_ cover: ProximiMap.Cover) -> some View {
        if let venue = map.venue {
            switch cover {
            case .museumMap:
                MuseumMapScreen(venue: venue) { map.cover = nil }
            case .ready:
                if let journey = VisitStore.load() {
                    JourneyReadyFlow(map: map, venue: venue, meta: storedMeta(for: journey))
                }
            case .visit:
                if let journey = VisitStore.load() {
                    VisitView(venue: venue, journey: journey, kind: storedMeta(for: journey).kind) { map.cover = nil }
                }
            #if DEBUG
            case .hosted:
                HostedMapCheck(map: map, sdk: venue.sdk)
            #endif
            }
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: ProximiMap.Sheet) -> some View {
        switch sheet {
        case .planJourney:
            VisitPlanPicker(places: map.places) { ids in
                map.planned(poiIDs: ids)
            } onCancel: {
                map.sheet = nil
            }
        case .manageJourney:
            if let journey = VisitStore.load() {
                ManageJourneySheet(
                    meta: storedMeta(for: journey),
                    onEdit: map.editJourney,
                    onCraftNew: map.craftNewJourney,
                    onDelete: {
                        map.deleteJourney()
                        map.sheet = nil
                    },
                    onClose: { map.sheet = nil }
                )
            }
        }
    }

    private func storedMeta(for journey: Journey) -> VisitMeta {
        VisitStore.loadMeta() ?? .standard(stopCount: VisitPlan.artworks(in: journey).count)
    }
}

/// Journey ready (02.10A), and the journey once the visitor starts it. One cover, so the
/// transition does not dismiss and present again.
private struct JourneyReadyFlow: View {
    let map: ProximiMap
    let venue: VenueService
    let meta: VisitMeta

    @State private var visit: Journey?

    var body: some View {
        if let visit {
            VisitView(venue: venue, journey: visit, kind: meta.kind) { map.cover = nil }
        } else {
            JourneyReadyView(meta: meta, isAtMuseum: map.isAtMuseum, onStart: {
                // Away from the museum, "Go to Museum" closes: the host app shows the journey until
                // the visitor arrives.
                guard map.isAtMuseum else {
                    map.cover = nil
                    return
                }
                // The stored journey: the venue data can change while this screen is open.
                guard let stored = VisitStore.load() else {
                    map.cover = nil
                    return
                }
                visit = stored
                map.visitStarted()
            }, onBack: { map.cover = nil })
        }
    }
}

#if DEBUG
/// `-hostedMap`: `ProximiMapView` on the app's SDK. The line at the top counts the stop states of
/// the journey the view writes, for UI tests.
private struct HostedMapCheck: View {
    @Bindable var map: ProximiMap
    let sdk: Proximiio

    var body: some View {
        ProximiMapView(sdk: sdk, journey: $map.hostedJourney, routeAccessibility: map.routeAccessibility) { event in
            FieldLog.log("hosted map → host app: \(event)")
        } onClose: {
            map.cover = nil
        }
        .overlay(alignment: .top) {
            Text(Self.states(of: map.hostedJourney))
                .font(.caption2)
                .accessibilityIdentifier("hostedJourneyStates")
        }
    }

    /// For example "pending 3 · visited 0 · skipped 1".
    static func states(of journey: ProximiJourney) -> String {
        func count(_ state: ProximiJourney.State) -> Int { journey.stops.filter { $0.state == state }.count }
        return "pending \(count(.pending)) · visited \(count(.visited)) · skipped \(count(.skipped))"
    }
}
#endif
