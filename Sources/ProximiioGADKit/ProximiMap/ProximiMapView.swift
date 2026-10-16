//
//  ProximiMapView.swift
//  ProximiioGADKit
//
//  The journey screen on the host app's SDK (Nagarro, 2026-10-16: "one UI component for the map
//  view … that plugs into our existing SDK session and event setup"): Map / List toggle, search,
//  the map with floor button, compass and stop card, and the list.
//
//  The host app starts the SDK, attaches the position provider of its wristband session and owns
//  the journey (`ProximiJourney`). The view routes from stop to stop and writes the stop order and
//  the stop states to the journey binding. It does not start or stop the SDK, does not change the
//  wristband session, stores nothing and reports no geofence or wristband event.
//
import Proximiio
import ProximiioMap
import SwiftUI

public struct ProximiMapView: View {
    @Binding private var journey: ProximiJourney
    private let sdk: Proximiio
    private let settings: GADSettings
    private let routeAccessibility: RouteAccessibility
    private let mode: VisitMode
    private let onEvent: (ProximiMapEvent) -> Void
    private let onClose: () -> Void

    @State private var model = HostedMapModel()

    /// - Parameters:
    ///   - sdk: The host app's SDK, started, with the position provider of the wristband session
    ///     attached.
    ///   - journey: The journey to show. The view writes the stop order and the stop states to it. A
    ///     value the view did not write starts the journey again from that value.
    ///   - settings: Times and distances of the screen. The view reads them when it opens.
    ///   - routeAccessibility: Accessibility needs for routes, on top of the accessible routes
    ///     button the visitor can turn on.
    ///   - mode: Map or List when the view opens.
    ///   - onEvent: The journey events and the controls the visitor used. Geofence and wristband
    ///     events come from the host app's SDK, not from this view.
    ///   - onClose: Back, "Leave the tour" or the close button of Journey Complete. The host app
    ///     closes the view.
    public init(
        sdk: Proximiio,
        journey: Binding<ProximiJourney>,
        settings: GADSettings = .standard,
        routeAccessibility: RouteAccessibility = .none,
        mode: VisitMode = .map,
        onEvent: @escaping (ProximiMapEvent) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        _journey = journey
        self.sdk = sdk
        self.settings = settings
        self.routeAccessibility = routeAccessibility
        self.mode = mode
        self.onEvent = onEvent
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if let loaded = model.loaded {
                VisitView(
                    venue: loaded.venue,
                    journey: loaded.hosted.journey,
                    kind: journey.kind,
                    mode: mode,
                    persist: { [model, binding = $journey] journey in model.write(journey, to: binding) },
                    onClose: onClose
                )
                .id(loaded.generation)
                .routeAccessibility(routeAccessibility)
                .onVisitEvent { [model] event in model.handle(event) }
            } else {
                HostedMapStatus(message: model.hasNoKnownStop ? ProximiMapError.noKnownArtworks.localizedDescription : nil, onClose: onClose)
            }
        }
        .task {
            model.onEvent = onEvent
            await model.start(sdk: sdk, settings: settings, journey: $journey)
        }
        .onChange(of: journey) { _, journey in model.journeyChanged(journey) }
        .onDisappear { model.stop() }
    }
}

/// The state of a `ProximiMapView`: the venue on the host app's SDK and the journey on screen.
@MainActor
@Observable
final class HostedMapModel {
    struct Loaded {
        let venue: VenueService
        let hosted: HostedJourney
        /// Changes when the journey starts again; `VisitView` is created again.
        let generation: Int
    }

    private(set) var loaded: Loaded?
    /// No stop of the journey is a POI of the venue.
    private(set) var hasNoKnownStop = false
    @ObservationIgnored var onEvent: ((ProximiMapEvent) -> Void)?
    @ObservationIgnored private var venue: VenueService?
    @ObservationIgnored private var settings = GADSettings.standard
    @ObservationIgnored private var places: [VenuePlace] = []
    @ObservationIgnored private var galleries: [Gallery] = []
    /// The journey last shown or written. Another value from the host app starts the journey again.
    @ObservationIgnored private var current: ProximiJourney?
    /// The host app's latest journey while the venue loads.
    @ObservationIgnored private var latest: ProximiJourney?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isStarting = false

    /// Loads the venue and shows `journey`. After `stop()`, starts the venue data downloads again.
    func start(sdk: Proximiio, settings: GADSettings, journey: Binding<ProximiJourney>) async {
        if let venue {
            await venue.data.start(interval: settings.venueDataRefreshInterval)
            return
        }
        guard !isStarting else { return }
        isStarting = true
        self.settings = settings
        latest = journey.wrappedValue
        let venue = await VenueService.hosted(sdk: sdk, settings: settings)
        self.venue = venue
        await loadPlaces()
        venue.data.onChange = { [weak self] in
            Task { await self?.loadPlaces() }
        }
        FieldLog.log("hosted map: ready · \(places.count) places")
        show(latest ?? journey.wrappedValue)
    }

    private func loadPlaces() async {
        guard let venue else { return }
        let features = await venue.sdk.features()
        places = VenuePlace.all(in: features)
        galleries = await Gallery.load(from: venue.sdk, features: features, places: places)
    }

    private func show(_ journey: ProximiJourney) {
        current = journey
        guard let venue else { return }
        let hosted = HostedJourney(journey, places: places, galleries: galleries)
        FieldLog.log("hosted map: journey \(journey.kind.rawValue) · \(hosted.journey.stops.count) of \(journey.stops.count) stops on the map")
        guard !hosted.journey.stops.isEmpty else {
            loaded = nil
            hasNoKnownStop = true
            return
        }
        hasNoKnownStop = false
        generation += 1
        loaded = Loaded(venue: venue, hosted: hosted, generation: generation)
    }

    /// The binding changed. A value the view did not write starts the journey again.
    func journeyChanged(_ journey: ProximiJourney) {
        latest = journey
        guard venue != nil, journey != current else { return }
        show(journey)
    }

    /// Writes the order and states of the navigator's journey to the host app's journey. `nil`
    /// (after Journey Complete) changes nothing: the journey already holds the last states.
    func write(_ journey: Journey?, to binding: Binding<ProximiJourney>) {
        guard let journey, let loaded else { return }
        let updated = loaded.hosted.hostJourney(from: journey, kind: binding.wrappedValue.kind)
        guard updated != binding.wrappedValue else { return }
        current = updated
        binding.wrappedValue = updated
    }

    func handle(_ event: VisitEvent) {
        FieldLog.log("hosted map event: \(event)")
        guard let mapped = ProximiMap.event(for: event, places: places) else { return }
        onEvent?(mapped)
    }

    func stop() {
        venue?.stop()
    }
}

/// Loading, or the message when the journey has no stop on the map, with Back.
private struct HostedMapStatus: View {
    let message: String?
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScreenBackground.map.view
                VStack {
                    Spacer()
                    if let message {
                        Text(message)
                            .textStyle(.largeBodyRegular)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
                        ProgressView()
                    }
                    Spacer()
                    BottomGlassBar {
                        Button(action: onClose) {
                            Image(systemName: "chevron.backward").font(.system(size: 18, weight: .medium))
                        }
                        .buttonStyle(RoundGlassButtonStyle())
                        .accessibilityLabel(Text("Back", bundle: .module))
                    } trailing: {
                        EmptyView()
                    }
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom - 14, 4))
                .foregroundStyle(Palette.ink)
            }
            .ignoresSafeArea()
        }
    }
}
