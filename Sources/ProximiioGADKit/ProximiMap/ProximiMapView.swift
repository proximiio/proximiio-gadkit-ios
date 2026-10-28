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
        /// calls it, after "Leave the tour here" with `leaveTourPrompt`.
        public static let bottomBar = Options(rawValue: 1 << 0)
        /// The package's background image around the map card. Without it the view is transparent.
        public static let background = Options(rawValue: 1 << 1)
        /// "Skip this artwork?" after a swipe on a stop in the list. Without it the view reports
        /// `skipRequested` only, and the host app decides.
        public static let skipPrompt = Options(rawValue: 1 << 6)
        /// "Looks like you've left your route" with "Dismiss". With `progress`, a personalised journey
        /// keeps the leg where the visitor left it until another artwork is nearer. Without it the
        /// view reports `offRoute` only, and the route follows the visitor who left it.
        public static let offRoutePrompt = Options(rawValue: 1 << 7)
        /// "Probably at …" when the position is uncertain near the active stop. Without it the view
        /// reports `positionUncertain`.
        public static let uncertainPositionPrompt = Options(rawValue: 1 << 8)
        /// "Leave the tour here" after Back on the bottom bar during a journey in progress. Without it
        /// Back calls `onClose` at once.
        public static let leaveTourPrompt = Options(rawValue: 1 << 10)
        /// All four prompts.
        public static let prompts: Options = [.skipPrompt, .offRoutePrompt, .uncertainPositionPrompt, .leaveTourPrompt]
        /// The view moves the journey on and writes it to the binding: an artwork is visited when the
        /// visitor enters its geofence or stays at it out of order, a personalised journey is ordered
        /// floor by floor and gallery by gallery, and a stop whose POI is deleted is skipped. Without
        /// it only the host app's journey changes the stops, and the view writes nothing.
        public static let progress = Options(rawValue: 1 << 3)
        /// The journey's Live Activity. The widget extension needs `ProximiioGADLiveActivity`.
        public static let liveActivity = Options(rawValue: 1 << 4)
        /// Journey Complete when the last stop is done. Without it the view reports
        /// `journeyFinished` and shows nothing (Nagarro, Monday "Journey finished view", 2026-10-26).
        public static let journeyComplete = Options(rawValue: 1 << 5)

        public static let all: Options = [.bottomBar, .background, .prompts, .progress, .liveActivity, .journeyComplete]
    }

    @Binding private var journey: ProximiJourney
    private let destination: Binding<ProximiDestination?>
    private let isPaused: Binding<Bool>
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
    ///   - destination: A place to route the visitor to at once, for example from the audio guide. With
    ///     a journey it is a detour, as after "Go here" on an amenity, with no card and no prompt; a
    ///     stop of the journey still to visit becomes the next stop instead. Without a journey the map
    ///     shows the route from the visitor. The view sets it back to `nil` when the route ends:
    ///     "Resume your Journey", "Close", another place picked on the map, or
    ///     `ProximiMapEvent.destinationUnavailable`. Setting it to `nil` ends the route.
    ///   - isPaused: `true` pauses the journey, for example from the audio guide's pause button. The
    ///     dot moves and the route stays, but no artwork is visited, no off-route warning shows and
    ///     the leg is not routed again. The stop card shows "Journey paused" with "Resume your
    ///     Journey". `false` resumes it: the leg is drawn again from the visitor, and a personalised
    ///     journey with `Options.progress` is ordered again from the visitor first. "Resume your
    ///     Journey" on the card sets it back to `false` and reports `ProximiMapEvent.journeyResumed`.
    ///     A change of the host app reports no event.
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
    ///     kind, a journey without a stop on the map, the first journey on an empty map). The
    ///     previous navigator's `events` streams then finish. Read `navigator.events` inside the
    ///     call, so no event is missed, and set `onCue` and `cueRules` there; the view sets neither.
    ///     Any other change of `journey` goes to `update(to:)` of the same navigator. Change the
    ///     journey through `journey` only: the view does not see calls such as `skip(stopID:)` or
    ///     `markDone(stopID:)` on the navigator.
    public init(
        sdk: Proximiio,
        journey: Binding<ProximiJourney>,
        destination: Binding<ProximiDestination?> = .constant(nil),
        isPaused: Binding<Bool> = .constant(false),
        options: Options = [],
        settings: GADSettings = .standard,
        routeAccessibility: RouteAccessibility = .none,
        mode: VisitMode = .map,
        onEvent: @escaping (ProximiMapEvent) -> Void = { _ in },
        onClose: (() -> Void)? = nil,
        onNavigator: @escaping @MainActor (JourneyNavigator) -> Void = { _ in }
    ) {
        _journey = journey
        self.destination = destination
        self.isPaused = isPaused
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
                    destination: destination,
                    isPaused: isPaused,
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

    /// Loads the venue and shows `journey`. After `stop()`, follows the venue data changes again.
    func start(sdk: Proximiio, settings: GADSettings, options: ProximiMapView.Options, journey: Binding<ProximiJourney>) async {
        if let venue {
            await venue.data.start()
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
        places = VenuePlace.all(in: features, amenities: (try? await venue.sdk.amenities()) ?? [])
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
    /// Journey Complete) changes nothing: the journey already holds the last states. A new order of
    /// the stops sends `stopOrderChanged` after the write.
    func write(_ journey: Journey?, generation: Int, to binding: Binding<ProximiJourney>) {
        guard options.contains(.progress), generation == self.generation, let journey, let hosted else { return }
        let previous = binding.wrappedValue
        let updated = hosted.hostJourney(from: journey, kind: previous.kind)
        guard updated != previous else { return }
        current = updated
        binding.wrappedValue = updated
        if Self.isReordered(previous, to: updated) {
            onEvent?(.stopOrderChanged(updated))
        }
    }

    /// `true` when the stop ids of `updated` are in another order than those of `previous`. A change
    /// of the states alone is no new order. Pure; covered by tests.
    nonisolated static func isReordered(_ previous: ProximiJourney, to updated: ProximiJourney) -> Bool {
        previous.stops.map(\.id) != updated.stops.map(\.id)
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
            // Without `.background` the stack is as wide as the spinner, and the reader puts it at
            // the leading edge (Nagarro, 2026-10-23).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }
}
