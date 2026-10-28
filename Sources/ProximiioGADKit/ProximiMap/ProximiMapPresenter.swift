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
                #if DEBUG
                if DebugLaunch.current.hostedMap {
                    ProximiExploreView(sdk: venue.sdk, settings: venue.settings)
                        .overlay(alignment: .topTrailing) {
                            Button("Close map") { map.cover = nil }.font(.caption2).padding(.top, 60)
                        }
                } else {
                    MuseumMapScreen(venue: venue) { map.cover = nil }
                }
                #else
                MuseumMapScreen(venue: venue) { map.cover = nil }
                #endif
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
/// `-hostedMap`: `ProximiMapView` on the app's SDK with the default options, as Nagarro's app uses
/// it. This view is the host app: it skips a stop the visitor swiped, "Visited" marks the first
/// pending stop visited, "Remove" removes the last stop, and "Host pause" / "Host resume" set
/// `isPaused`. The lines at the top count the stop states of its journey, list the navigators it got
/// from `onNavigator` and the events of the last one, and show `isPaused` and the view's last events,
/// for UI tests.
private struct HostedMapCheck: View {
    @Bindable var map: ProximiMap
    let sdk: Proximiio
    /// The names of the navigator's events, oldest first.
    @State private var navigatorEvents: [String] = []
    @State private var navigatorTask: Task<Void, Never>?
    /// The navigators `onNavigator` got. The screen starts again with a new one.
    @State private var navigators = 0
    /// `-hostedDestination`.
    @State private var destination: ProximiDestination?
    @State private var isPaused = false
    /// The names of the view's events, oldest first.
    @State private var viewEvents: [String] = []

    var body: some View {
        ProximiMapView(
            sdk: sdk,
            journey: $map.hostedJourney,
            destination: $destination,
            isPaused: $isPaused,
            routeAccessibility: map.routeAccessibility,
            onEvent: { event in
                FieldLog.log("hosted map → host app: \(event)")
                viewEvents.append(String(String(describing: event).prefix { $0 != "(" }))
                if case .skipRequested(let stop) = event { set(stop.id, to: .skipped) }
            },
            onNavigator: { navigator in
                let events = navigator.events
                navigators += 1
                navigatorTask?.cancel()
                navigatorTask = Task {
                    for await event in events {
                        navigatorEvents.append(String(String(describing: event).prefix { $0 != "(" }))
                    }
                }
            }
        )
        .overlay(alignment: .top) {
            VStack {
                HStack {
                    Text(Self.states(of: map.hostedJourney))
                        .font(.caption2)
                        .accessibilityIdentifier("hostedJourneyStates")
                    if let first = map.hostedJourney.stops.first(where: { $0.state == .pending }) {
                        Button("Visited") { set(first.id, to: .visited) }.font(.caption2)
                    }
                    if map.hostedJourney.stops.count > 1 {
                        Button("Remove") { map.hostedJourney.stops.removeLast() }.font(.caption2)
                    }
                    Button(isPaused ? "Host resume" : "Host pause") { isPaused.toggle() }.font(.caption2)
                    Button("Close map") { map.cover = nil }.font(.caption2)
                }
                Text("navigator \(navigators): \(navigatorEvents.suffix(6).joined(separator: " "))")
                    .font(.caption2)
                    .accessibilityIdentifier("hostedNavigatorEvents")
                Text("destination \(destination?.poiID ?? "none")")
                    .font(.caption2)
                    .accessibilityIdentifier("hostedDestination")
                Text("paused \(isPaused) · events \(viewEvents.suffix(4).joined(separator: " "))")
                    .font(.caption2)
                    .accessibilityIdentifier("hostedPaused")
            }
        }
        .task {
            guard let title = DebugLaunch.current.hostedDestination else { return }
            try? await Task.sleep(for: .seconds(5))
            guard let place = map.places.first(where: { $0.title == title })
                    ?? map.places.first(where: { $0.title.localizedCaseInsensitiveContains(title) }) else {
                FieldLog.log("hosted map: no place matches \(title)")
                return
            }
            // proximiio-mcp returns `properties.id`: the feature id after the organisation id.
            let id = place.id.split(separator: ":").last.map(String.init) ?? place.id
            FieldLog.log("hosted map: destination \(place.title) · \(id)")
            destination = ProximiDestination(poiID: id)
        }
    }

    private func set(_ poiID: String, to state: ProximiJourney.State) {
        guard let index = map.hostedJourney.stops.firstIndex(where: { $0.id == poiID }) else { return }
        map.hostedJourney.stops[index].state = state
    }

    /// For example "pending 3 · visited 0 · skipped 1".
    static func states(of journey: ProximiJourney) -> String {
        func count(_ state: ProximiJourney.State) -> Int { journey.stops.filter { $0.state == state }.count }
        return "pending \(count(.pending)) · visited \(count(.visited)) · skipped \(count(.skipped))"
    }
}
#endif
