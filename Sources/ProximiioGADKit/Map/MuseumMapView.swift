//
//  MuseumMapView.swift
//  ProximiioGADKit
//
//  The museum map of Journey Complete: venue style, floors, amenities, the visitor's position and
//  one route. A tap on a place shows `PlaceInfoCard`; "Go here" computes a route from the current
//  position and shows `StopInfoCard`. Layout and controls follow the Figma map frames
//  ("MAP Functionality Approach 02"). The Explore Museum map is `ExploreMuseumView`.
//
//  `MapOptions.fallbackStyleURL` is `nil`. With the default, a failed style load makes
//  the map fetch demotiles.maplibre.org, which a production build must not contact.
//
import Proximiio
import ProximiioMap
import SwiftUI

struct MuseumMapView: View {
    let venue: VenueService
    /// Routed to after the first position, e.g. a place picked in "Before You Go".
    let initialDestination: VenuePlace?

    @StateObject private var session: ProximiioMapSession
    @Environment(\.routeAccessibility) private var hostAccessibility
    @AppStorage(RouteAccessibility.accessibleRoutesKey) private var accessibleRoutes = false

    private var accessibility: RouteAccessibility {
        RouteAccessibility.effective(hostNeeds: hostAccessibility, accessibleRoutes: accessibleRoutes)
    }
    @State private var places: [VenuePlace] = []
    /// The search shortcuts' choice and order (`in_search`, `search_order`).
    @State private var searchListing = AmenityListing.all
    @State private var selectedPlace: VenuePlace?
    @State private var destination: VenuePlace?
    @State private var routeError: String?
    @State private var isSearching = false
    /// The lifts, staircases and escalators on every floor they serve.
    @State private var mapLayers = JourneyMapLayers()
    /// The lift or stairs view and the map of a floor without positioning.
    @State private var floorGuide: FloorWithoutPositioningGuide

    init(venue: VenueService, initialDestination: VenuePlace? = nil) {
        self.venue = venue
        self.initialDestination = initialDestination
        _session = StateObject(wrappedValue: MapStyle.session(sdk: venue.sdk, options: MapStyle.options(settings: venue.settings)))
        _floorGuide = State(initialValue: FloorWithoutPositioningGuide(settings: venue.settings))
    }

    @State private var isShowingAmenities = false
    @State private var selectedAmenity: AmenityKind?
    @State private var detailPlace: VenuePlace?

    var body: some View {
        ZStack {
            ProximiioMapView(session: session)
                .ignoresSafeArea(edges: .bottom)
            MapLoadingSpinner(session: session, timeout: venue.settings.mapLoadingTimeout)
            controls
            if case .changing(let change) = floorGuide.phase {
                FloorChangeView(change: change)
                    .onTapGesture { floorGuide.showFloor() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: floorGuide.phase)
        .task { await MapDiagnostics.follow(session, name: "museum") }
        .task {
            // No dot in a privacy zone (`MapStyle.hidingPosition(_:)`).
            let position = MapStyle.options(settings: venue.settings).position
            for await state in await venue.sdk.privacyZoneStateChanges() {
                session.options.position = state.isPrivate ? MapStyle.hidingPosition(position) : position
            }
        }
        .task {
            floorGuide.onEnter = { [session] change in
                // Under the search button, beside the map buttons, above the route card.
                FloorWithoutPositioningGuide.show(change, on: session, padding: UIEdgeInsets(top: 90, left: 40, bottom: 230, right: 90))
            }
            floorGuide.onLeave = { [session] _ in
                session.followMyFloor()
                session.recentre()
            }
            await MapStyle.waitForCanvas(of: session)
            session.guidanceRules = .venueWalk
            session.onFeatureTap = { identifiers, _ in
                if let place = VenuePlace.place(under: identifiers, in: places) {
                    isShowingAmenities = false
                    // A place with a photo or a description opens the detail sheet of the
                    // Explore Museum design; other places show the compact card.
                    if place.imageURL != nil || place.details != nil {
                        detailPlace = place
                    } else {
                        selectedPlace = place
                    }
                }
            }
            await loadPlaces()
            mapLayers.attach(to: session)
            mapLayers.update(fills: [], level: session.selectedFloor.level)
            if let initialDestination {
                while session.position == nil { try? await Task.sleep(for: .milliseconds(500)) }
                await route(to: initialDestination)
            }
            #if DEBUG
            if let query = DebugLaunch.current.routeTo,
               let place = VenuePlace.matching(query, in: places).first {
                // Waits for the first position, then routes as the "Go" button does.
                while session.position == nil { try? await Task.sleep(for: .milliseconds(500)) }
                DebugLaunch.log("route to \(place.title) (level \(Int(place.level)))")
                await route(to: place)
            }
            #endif
        }
        // The follow camera keeps the initial venue framing. The first position zooms
        // in to `MapOptions.recentreZoom` on the visitor.
        .followsVisitorFloor(session, venue: venue, isPaused: floorGuide.isActive)
        .onChange(of: venue.data.version) { _, _ in
            Task { await loadPlaces() }
        }
        .onReceive(session.$guidance) { _ in
            Task { @MainActor in
                floorGuide.update(
                    coordinate: session.position?.coordinate, level: session.position?.floor?.level,
                    markers: session.routeRenderer?.geometry?.markers ?? [], destinationID: destination?.id
                )
            }
        }
        .onReceive(session.$selectedFloor) { floor in
            mapLayers.update(fills: [], level: floor.level)
        }
        .onChange(of: destination) { _, place in
            mapLayers.updateHighlight(JourneyMapLayers.highlight(of: place))
        }
        .onChange(of: accessibility) {
            if let destination { Task { await route(to: destination) } }
        }
        .onChange(of: session.position == nil) { _, hasNoPosition in
            if !hasNoPosition { session.recentre() }
        }
        .sheet(item: $detailPlace) { place in
            PlaceDetailSheet(place: place) {
                detailPlace = nil
                Task { await route(to: place) }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(50)
        }
        .sheet(isPresented: $isSearching) {
            PlaceSearchSheet(places: places, shortcuts: availableAmenities) { place in
                isSearching = false
                selectedPlace = place
            } onPickAmenity: { kind in
                isSearching = false
                routeToNearest(kind)
            }
            .presentationDetents([.large])
        }
    }

    /// Controls over the map, from the Figma map frames.
    private var controls: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    GlassSquareButton(isSelected: isShowingAmenities, action: { withAnimation { isShowingAmenities.toggle() } }) {
                        GADIcon.search.image.resizable().scaledToFit().frame(width: 24, height: 24)
                    }
                    .accessibilityLabel(Text("Search", bundle: .module))
                    if isShowingAmenities {
                        AmenityChipList(kinds: availableAmenities, selected: selectedAmenity) { kind in
                            selectedAmenity = kind
                            isShowingAmenities = false
                            routeToNearest(kind)
                        }
                        Button(String(localized: "Search the museum", bundle: .module)) { isSearching = true }
                            .buttonStyle(.small)
                            .transition(.opacity)
                    }
                }
            }
            // A long amenity list takes the free height before the spacer; it scrolls past that.
            .layoutPriority(1)
            Spacer()
            HStack(alignment: .bottom) {
                Spacer()
                VStack(spacing: 5) {
                    GlassSquareButton(action: { floorGuide.leave(); session.followMyFloor(); session.recentre() }) {
                        GADIcon.compass.image.resizable().scaledToFit().frame(width: 24, height: 24)
                    }
                    .disabled(session.position == nil)
                    .accessibilityLabel(Text("Centre on me", bundle: .module))
                    AccessibleRoutesButton(isOn: $accessibleRoutes)
                    floorButton
                }
            }
            if let destination {
                StopInfoCard(
                    caption: "NEXT STOP",
                    title: destination.title,
                    instruction: routeError ?? instruction,
                    remaining: remainingText
                ) {
                    destinationIcon(for: destination)
                } trailing: {
                    Button(action: endRoute) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("End route", bundle: .module))
                } badges: {
                    EmptyView()
                }
                if session.guidance?.isOffRoute == true && session.guidance?.hasArrived == false && !floorGuide.isActive {
                    Button(String(localized: "New route from here", bundle: .module)) { Task { await route(to: destination) } }
                        .buttonStyle(.small)
                }
            } else if let place = selectedPlace {
                PlaceInfoCard(
                    title: place.title,
                    subtitle: placeSubtitle(place),
                    primary: "Go here",
                    onPrimary: {
                        selectedPlace = nil
                        Task { await route(to: place) }
                    },
                    onClose: { selectedPlace = nil }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        // Keeps the map's attribution button (bottom trailing) uncovered.
        .padding(.bottom, destination == nil && selectedPlace == nil ? 40 : 16)
        .animation(.easeInOut(duration: 0.2), value: isShowingAmenities)
    }

    /// Floor button ("L1", Bold 18). Lists the venue's floors; picking one pins the map to it.
    private var floorButton: some View {
        Menu {
            Button(String(localized: "Follow my floor", bundle: .module)) {
                floorGuide.leave()
                session.followMyFloor()
            }
                .disabled(session.position == nil)
            ForEach(session.floors.reversed(), id: \.key) { floor in
                Button(floor.name ?? GuidanceText.floorLabel(floor.key.level)) { session.select(floor: floor.key) }
            }
        } label: {
            Text(GuidanceText.floorLabel(session.selectedFloor.level))
                .textStyle(.largeBodyBold)
                .foregroundStyle(Palette.ink)
                .frame(width: 50, height: 50)
                .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
        }
        .accessibilityLabel(Text("Floor \(GuidanceText.floorLabel(session.selectedFloor.level))", bundle: .module))
    }

    private var availableAmenities: [AmenityKind] {
        searchListing.shortcuts(places: places)
    }

    /// The route's next step. On a floor without positioning the guidance follows fixes from
    /// another floor, so the card says that the position is not shown.
    private var instruction: String? {
        if floorGuide.isActive { return String(localized: "Your position is not shown on this level.", bundle: .module) }
        return session.guidance.map { GuidanceText.instruction(for: $0, markers: session.routeRenderer?.geometry?.markers ?? []) }
    }

    private var remainingText: String? {
        guard routeError == nil, !floorGuide.isActive, let guidance = session.guidance, !guidance.isOffRoute, !guidance.hasArrived else { return nil }
        return GuidanceText.remaining(metres: guidance.remainingMeters)
    }

    /// "Amenity · Level 1" or "Level 1".
    /// Places and level changers, at the start and after a change of the venue data.
    private func loadPlaces() async {
        let features = await venue.data.features()
        let amenities = await venue.data.amenities()
        places = VenuePlace.all(in: features, amenities: amenities)
        searchListing = .search(amenities)
        let levelChangers = LevelChangerPlace.all(in: features)
        mapLayers.updateLevelChangers(levelChangers)
        mapLayers.updateCones(VenueCone.all(in: features))
        session.hiddenFeatureIDs = Set(levelChangers.map(\.id))
    }

    private func placeSubtitle(_ place: VenuePlace) -> String { place.cardSubtitle }

    @ViewBuilder private func destinationIcon(for place: VenuePlace) -> some View {
        if let kind = AmenityKind.allCases.first(where: { $0.matches(place) }) {
            kind.icon.image.resizable().scaledToFit()
        } else {
            Image(systemName: session.guidance.map(GuidanceText.symbol(for:)) ?? "arrow.up")
                .font(.system(size: 16, weight: .medium))
        }
    }

    /// Routes to the nearest place of `kind`, preferring the visitor's floor.
    private func routeToNearest(_ kind: AmenityKind) {
        let here = session.position
        let from = here.map { ProximiioCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        guard let place = kind.nearest(in: places, from: from, level: here?.floor?.level) else { return }
        selectedPlace = nil
        Task {
            await route(to: place)
            // Under the search button, beside the map buttons, above the route card.
            PlaceFraming.show(place, on: session, padding: UIEdgeInsets(top: 90, left: 40, bottom: 230, right: 90),
                              minimumMeters: venue.settings.amenityFramingMinimumMeters)
        }
    }

    // MARK: Routing

    /// Computes a route from the current position to `place` with the SDK's on-device router.
    private func route(to place: VenuePlace) async {
        destination = place
        guard let here = session.position else {
            routeError = String(localized: "Waiting for your position.", bundle: .module)
            session.clearRoute()
            return
        }
        do {
            let route = try await venue.sdk.computeRoute(
                from: ProximiioCoordinate(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude),
                fromLevel: here.floor?.level ?? 0,
                to: place.coordinate,
                toLevel: place.level,
                options: accessibility.routeOptions
            )
            session.setRoute(route)
            routeError = nil
            #if DEBUG
            let changers = route.levelChanges.map { "\($0.featureType) L\(Int($0.fromLevel))→L\(Int($0.toLevel))" }
            DebugLaunch.log("route to \(place.title): \(Int(route.distanceMeters)) m via \(changers) avoiding \(accessibility.routeOptions.effectiveAvoidances.map(\.rawValue).sorted())")
            #endif
        } catch {
            #if DEBUG
            DebugLaunch.log("route to \(place.title) failed from level \(here.floor?.level ?? 0): \(error)")
            #endif
            session.clearRoute()
            if case WayfindingRoutingError.noRoute(.noAccessibleRoute) = error {
                routeError = String(localized: "No route from here with your accessibility settings.", bundle: .module)
            } else {
                routeError = String(localized: "No route from here.", bundle: .module)
            }
        }
    }

    private func endRoute() {
        destination = nil
        routeError = nil
        session.clearRoute()
    }
}

/// Place detail (Figma "Explore Museum" pin detail, node 6902:59556): image 16:9, title,
/// opening note, description and "Guide Me".
private struct PlaceDetailSheet: View {
    let place: VenuePlace
    let onGuide: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let url = place.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Palette.inputStroke
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                    .padding(.bottom, 20)
                }
                Text(place.title).textStyle(.h1Bold)
                Text(String(localized: "Level \(Int(place.level.rounded()))", bundle: .module)).textStyle(.caption).textCase(.uppercase)
                if let details = place.details {
                    Text(details).textStyle(.bodySmallRegular).padding(.top, 10)
                }
                Button(String(localized: "Guide Me", bundle: .module), action: onGuide).buttonStyle(.primary).padding(.top, 30)
            }
            .foregroundStyle(Palette.ink)
            .padding(30)
        }
        .presentationBackground(Palette.white)
    }
}
