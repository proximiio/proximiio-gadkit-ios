//
//  ProximiMapView.swift
//  ProximiioGADKit
//
//  The journey screen on the host app's SDK (Nagarro, 2026-10-16: "one UI component for the map
//  view … that plugs into our existing SDK session and event setup"): Map / List toggle, search,
//  the map with floor button, compass and stop card, and the list.
//
//  The view is a UI component. The host app starts the SDK, attaches the position provider of its
//  wristband session, owns the journey (`ProximiJourney`) and decides when a stop is visited or
//  skipped. The view draws the journey it gets, routes to the first stop still to visit and
//  reports what the visitor does as `ProximiMapEvent`s. It does not start or stop the SDK, does not
//  change the wristband session and reports no geofence or wristband event. It hands its
//  `JourneyNavigator` to `onNavigator`, so the host app reads the map library's journey events and
//  route cues itself.
//
//  Everything beyond that is in `Options`, off by default: the bottom bar, the background, the
//  view's own prompts, the journey logic (visits, order) and the Live Activity. `ProximiMap` uses
//  all of them.
//
import Proximiio
import ProximiioMap
import SwiftUI

public struct ProximiMapView: View {
    /// What the view does beyond drawing the journey and reporting events.
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The bar at the bottom with Back and the Map / List button. Back shows with `onClose` and
        /// calls it, after "Leave the tour here" with `prompts`.
        public static let bottomBar = Options(rawValue: 1 << 0)
        /// The package's background image around the map card. Without it the view is transparent.
        public static let background = Options(rawValue: 1 << 1)
        /// The view's own prompts: "Skip this artwork?", "You've left your route", "Probably at …",
        /// "Change your route?", "Leave the tour here" and Journey Complete. Without them the view
        /// reports `skipRequested`, `offRoute`, `positionUncertain` and `journeyFinished` and shows
        /// nothing, the route follows the visitor who left it, and "Go here" on an amenity starts the
        /// detour at once.
        public static let prompts = Options(rawValue: 1 << 2)
        /// The view moves the journey on and writes it to the binding: an artwork is visited when the
        /// visitor enters its geofence or stays at it out of order, a personalised journey is ordered
        /// floor by floor and gallery by gallery, and a stop whose POI is deleted is skipped. Without
        /// it only the host app's journey changes the stops, and the view writes nothing.
        public static let progress = Options(rawValue: 1 << 3)
        /// The journey's Live Activity. The widget extension needs `ProximiioGADLiveActivity`.
        public static let liveActivity = Options(rawValue: 1 << 4)

        public static let all: Options = [.bottomBar, .background, .prompts, .progress, .liveActivity]
    }

    @Binding private var journey: ProximiJourney
    private let sdk: Proximiio
    private let options: Options
    private let settings: GADSettings
    private let routeAccessibility: RouteAccessibility
    private let mode: VisitMode
    private let onEvent: (ProximiMapEvent) -> Void
    private let onClose: (() -> Void)?
    private let onNavigator: @MainActor (JourneyNavigator) -> Void

    @State private var model = HostedMapModel()

    /// - Parameters:
    ///   - sdk: The host app's SDK, started, with the position provider of the wristband session
    ///     attached.
    ///   - journey: The journey to show. A journey without stops, or without a stop on the map, shows
    ///     the map alone. The view applies every change of the host app to the open screen. It
    ///     writes to the binding only with `Options.progress`.
    ///   - options: What the view does beyond drawing the journey. None by default. The view reads
    ///     them when it opens.
    ///   - settings: Times and distances of the screen. The view reads them when it opens.
    ///   - routeAccessibility: Accessibility needs for routes, on top of the accessible routes
    ///     button the visitor can turn on.
    ///   - mode: Map or List when the view opens.
    ///   - onEvent: The journey events and the controls the visitor used. Geofence and wristband
    ///     events come from the host app's SDK, not from this view.
    ///   - onClose: Back on the bottom bar, "Leave the tour" and the close button of Journey Complete.
    ///     `nil` (default): the bottom bar has no Back, so "Leave the tour here" never shows, and the
    ///     close button of Journey Complete returns to the map.
    ///   - onNavigator: Called with the `JourneyNavigator` that draws the journey, before the journey
    ///     starts, and again with a new navigator each time the screen starts again (a new journey
    ///     kind, a removed stop, the first journey on an empty map). The previous navigator's
    ///     `events` streams then finish. Read `navigator.events` inside the call, so no event is
    ///     missed, and set `onCue` and `cueRules` there; the view sets neither. Change the journey
    ///     through `journey` only: the view does not see calls such as `skip(stopID:)` or
    ///     `markDone(stopID:)` on the navigator.
    public init(
        sdk: Proximiio,
        journey: Binding<ProximiJourney>,
        options: Options = [],
        settings: GADSettings = .standard,
        routeAccessibility: RouteAccessibility = .none,
        mode: VisitMode = .map,
        onEvent: @escaping (ProximiMapEvent) -> Void = { _ in },
        onClose: (() -> Void)? = nil,
        onNavigator: @escaping @MainActor (JourneyNavigator) -> Void = { _ in }
    ) {
        _journey = journey
        self.sdk = sdk
        self.options = options
        self.settings = settings
        self.routeAccessibility = routeAccessibility
        self.mode = mode
        self.onEvent = onEvent
        self.onClose = onClose
        self.onNavigator = onNavigator
    }

    public var body: some View {
        Group {
            if let loaded = model.loaded {
                VisitView(
                    venue: loaded.venue,
                    journey: loaded.journey,
                    kind: loaded.kind,
                    options: loaded.options,
                    mode: mode,
                    incoming: model.incoming,
                    persist: { [model, binding = $journey, generation = loaded.generation] journey in
                        model.write(journey, generation: generation, to: binding)
                    },
                    onClose: onClose,
                    onNavigator: onNavigator
                )
                .id(loaded.generation)
                .routeAccessibility(routeAccessibility)
                .onVisitEvent { [model] event in model.handle(event) }
            } else {
                HostedMapLoading(options: options, onClose: onClose)
            }
        }
        .task {
            model.onEvent = onEvent
            await model.start(sdk: sdk, settings: settings, options: options, journey: $journey)
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
        /// The journey the screen starts with.
        let journey: Journey
        let kind: JourneyKind
        /// The options when the view opened.
        let options: ProximiMapView.Options
        /// Changes when the screen starts again; `VisitView` is created again.
        let generation: Int
    }

    private(set) var loaded: Loaded?
    /// The host app's journey after a change the open screen applies in place.
    private(set) var incoming: IncomingJourney?
    @ObservationIgnored var onEvent: ((ProximiMapEvent) -> Void)?
    @ObservationIgnored private var venue: VenueService?
    @ObservationIgnored private var options: ProximiMapView.Options = []
    @ObservationIgnored private var places: [VenuePlace] = []
    @ObservationIgnored private var galleries: [Gallery] = []
    /// The host app's journey on screen, matched to the places.
    @ObservationIgnored private var hosted: HostedJourney?
    /// The journey last shown or written. Another value from the host app changes the screen.
    @ObservationIgnored private var current: ProximiJourney?
    /// The host app's latest journey while the venue loads.
    @ObservationIgnored private var latest: ProximiJourney?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var isStarting = false

    /// Loads the venue and shows `journey`. After `stop()`, starts the venue data downloads again.
    func start(sdk: Proximiio, settings: GADSettings, options: ProximiMapView.Options, journey: Binding<ProximiJourney>) async {
        if let venue {
            await venue.data.start(interval: settings.venueDataRefreshInterval)
            return
        }
        guard !isStarting else { return }
        isStarting = true
        self.options = options
        latest = journey.wrappedValue
        let venue = await VenueService.hosted(sdk: sdk, settings: settings)
        self.venue = venue
        await loadPlaces()
        venue.data.onChange = { [weak self] in
            Task { await self?.loadPlaces() }
        }
        FieldLog.log("hosted map: ready · \(places.count) places · options \(options.rawValue)")
        show(latest ?? journey.wrappedValue)
    }

    private func loadPlaces() async {
        guard let venue else { return }
        let features = await venue.sdk.features()
        places = VenuePlace.all(in: features)
        galleries = await Gallery.load(from: venue.sdk, features: features, places: places)
    }

    /// Starts the screen with `journey`.
    private func show(_ journey: ProximiJourney) {
        current = journey
        guard let venue else { return }
        let matched = HostedJourney(journey, places: places, galleries: galleries)
        FieldLog.log("hosted map: start · \(journey.kind.rawValue) · \(matched.journey.stops.count) of \(journey.stops.count) stops on the map")
        hosted = matched
        incoming = nil
        generation += 1
        loaded = Loaded(venue: venue, journey: matched.journey, kind: journey.kind, options: options, generation: generation)
    }

    /// The binding changed. The open screen applies a value the view did not write in place; one it
    /// cannot apply starts the screen again.
    func journeyChanged(_ journey: ProximiJourney) {
        latest = journey
        guard venue != nil, journey != current else { return }
        current = journey
        let matched = HostedJourney(journey, places: places, galleries: galleries)
        guard let hosted, let loaded, matched.canReplace(hosted, kind: journey.kind, shownKind: loaded.kind) else {
            show(journey)
            return
        }
        FieldLog.log("hosted map: journey applied in place · \(matched.journey.stops.count) stops")
        self.hosted = matched
        revision += 1
        incoming = IncomingJourney(journey: matched.journey, revision: revision)
    }

    /// Writes the order and states of the navigator's journey to the host app's journey, with
    /// `Options.progress` only, and only from the screen of the current `generation`: a screen that
    /// started again leaves the controller of the old one running until its tasks end. `nil` (after
    /// Journey Complete) changes nothing: the journey already holds the last states.
    func write(_ journey: Journey?, generation: Int, to binding: Binding<ProximiJourney>) {
        guard options.contains(.progress), generation == self.generation, let journey, let hosted else { return }
        let updated = hosted.hostJourney(from: journey, kind: binding.wrappedValue.kind)
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

/// While the venue loads: a spinner, with the background and Back of `options`.
private struct HostedMapLoading: View {
    let options: ProximiMapView.Options
    let onClose: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if options.contains(.background) { ScreenBackground.map.view }
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                    if options.contains(.bottomBar), let onClose {
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
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom - 14, 4))
                .foregroundStyle(Palette.ink)
            }
            .ignoresSafeArea()
        }
    }
}
