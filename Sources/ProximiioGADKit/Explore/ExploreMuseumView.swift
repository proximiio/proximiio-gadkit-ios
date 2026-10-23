//
//  ExploreMuseumView.swift
//  ProximiioGADKit
//
//  The Explore Museum map (Figma "Explore Museum", node 12129:102006; PM screens 2026-10-23).
//  "Level N" and the floor changer are at the top. The list button and the Spaces, Highlights and
//  Amenities tabs are at the bottom. A tab opens its list over the map (`ExploreCatalog`). A row,
//  or a tap on a gallery or a POI, shows its floor and its card. The galleries of the shown floor
//  are filled with the level colour; while a gallery's card is open, the other galleries are lighter.
//
//  The visitor is not at the museum here: the map has no position dot, no route and a camera that
//  does not follow (`MapStyle.exploreOptions()`). The design's About the Building and Collections
//  tabs have no content in the app (DAILY-CALL N14).
//
import Proximiio
import ProximiioMap
import SwiftUI

/// The lists of the Explore Museum map.
enum ExploreTab: CaseIterable, Identifiable {
    case spaces, highlights, amenities

    var id: Self { self }

    var title: String {
        switch self {
        case .spaces: String(localized: "Spaces", bundle: .module)
        case .highlights: String(localized: "Highlights", bundle: .module)
        case .amenities: String(localized: "Amenities", bundle: .module)
        }
    }
}

struct ExploreMuseumView: View {
    let venue: VenueService

    @StateObject private var session: ProximiioMapSession
    @State private var mapLayers = JourneyMapLayers()
    @State private var catalog = ExploreCatalog()
    @State private var level: Double = 0
    /// The open list, or `nil` for the map alone.
    @State private var tab: ExploreTab?
    /// The list the list button opens.
    @State private var lastTab: ExploreTab = .spaces
    /// The place whose card is open.
    @State private var selected: ExploreItem?

    init(venue: VenueService) {
        self.venue = venue
        _session = StateObject(wrappedValue: MapStyle.session(sdk: venue.sdk, options: MapStyle.exploreOptions()))
    }

    /// The map area under the level title, the card and the tab bar.
    private let mapInsets = UIEdgeInsets(top: 130, left: 30, bottom: 220, right: 30)

    var body: some View {
        ZStack {
            ProximiioMapView(session: session)
                .softEdges(cornerRadius: 40)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 0) {
                header
                Spacer()
            }
            if let tab {
                listPanel(tab)
                    .transition(.move(edge: .bottom))
            }
            VStack(spacing: 12) {
                Spacer()
                if tab == nil, let selected {
                    ExploreCard(item: selected) { self.selected = nil }
                        .transition(.opacity)
                }
                tabBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.25), value: tab)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .task { await start() }
        .onChange(of: venue.data.version) { _, _ in
            Task { await load() }
        }
        .onReceive(session.$selectedFloor) { floor in
            guard !VenueLevel.same(floor.level, level) else { return }
            level = floor.level
            applyMapLayers()
        }
        .onChange(of: selected) { _, _ in applyMapLayers() }
    }

    // MARK: Top

    private var header: some View {
        HStack(alignment: .top) {
            Text(String(localized: "Level \(Int(level.rounded()))", bundle: .module))
                .textStyle(.cardTitle)
                .padding(.top, 8)
                .accessibilityIdentifier("exploreLevel")
            Spacer()
            // Shown once the museum's levels are known, so its menu is never empty.
            if !catalog.levels.isEmpty {
                floorChanger
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// The floor changer of the PM screens: the level in a tile of the level colour, a chevron under
    /// it, in a frosted frame. Lists the museum's levels, highest first.
    private var floorChanger: some View {
        Menu {
            ForEach(catalog.levels.reversed(), id: \.self) { candidate in
                Button(String(localized: "Level \(Int(candidate))", bundle: .module)) { show(level: candidate) }
            }
        } label: {
            VStack(spacing: 4) {
                Text(GuidanceText.floorLabel(level))
                    .textStyle(.bodyBold)
                    .frame(width: 46, height: 46)
                    .background(levelTile, in: RoundedRectangle(cornerRadius: 10))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .glassSurface(RoundedRectangle(cornerRadius: 14), strength: .frosted)
        }
        .accessibilityLabel(Text("Floor \(GuidanceText.floorLabel(level))", bundle: .module))
    }

    private var levelTile: LinearGradient {
        let color = Palette.level(Int(level.rounded()))
        return LinearGradient(colors: [color, color.opacity(0.45)], startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    // MARK: Bottom

    private var tabBar: some View {
        HStack(spacing: 10) {
            GlassSquareButton(isSelected: tab != nil, action: toggleList) {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel(Text("List", bundle: .module))
            HStack(spacing: 0) {
                ForEach(ExploreTab.allCases) { item in
                    tabButton(item)
                }
            }
            .padding(5)
            .frame(height: 50)
            .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
        }
    }

    private func tabButton(_ item: ExploreTab) -> some View {
        Button {
            if tab == item {
                tab = nil
            } else {
                selected = nil
                tab = item
                lastTab = item
            }
        } label: {
            Text(item.title)
                .textStyle(.bodySmallRegular)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if tab == item {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == item ? .isSelected : [])
    }

    private func toggleList() {
        if tab == nil {
            selected = nil
            tab = lastTab
        } else {
            tab = nil
        }
    }

    // MARK: List

    /// The list of `tab` over the lower part of the map. Dragging its top edge down closes it.
    private func listPanel(_ tab: ExploreTab) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 14) {
                        Capsule()
                            .fill(Palette.ink.opacity(0.25))
                            .frame(width: 44, height: 5)
                        HStack(alignment: .firstTextBaseline) {
                            Text(tab.title).textStyle(.cardTitle)
                            Spacer()
                            Text(summary(tab)).textStyle(.bodySmallRegular)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                        if value.translation.height > 60 { self.tab = nil }
                    })
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let groups = ExploreCatalog.byLevel(items(for: tab))
                            if groups.isEmpty {
                                Text(String(localized: "Nothing here yet.", bundle: .module))
                                    .textStyle(.bodySmallRegular)
                                    .padding(.top, 20)
                            }
                            ForEach(groups) { group in
                                Text(String(localized: "Level \(Int(group.level))", bundle: .module))
                                    .textStyle(.caption)
                                    .textCase(.uppercase)
                                    .tracking(1.5)
                                    .padding(.top, 20)
                                    .padding(.bottom, 4)
                                ForEach(group.items) { item in
                                    Button { show(item) } label: { ExploreRow(item: item) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("exploreRow")
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        // Clear of the tab bar.
                        .padding(.bottom, 110)
                    }
                }
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.72)
                .glassSurface(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40), strength: .frosted)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func items(for tab: ExploreTab) -> [ExploreItem] {
        switch tab {
        case .spaces: catalog.spaces
        case .highlights: catalog.highlights
        case .amenities: catalog.amenities
        }
    }

    /// "8 spaces · 4 levels", "6 works", "12 amenities · 5 levels".
    private func summary(_ tab: ExploreTab) -> String {
        let items = items(for: tab)
        let levels = String(localized: "\(Set(items.map { $0.level.rounded() }).count) levels", bundle: .module)
        switch tab {
        case .spaces: return String(localized: "\(items.count) spaces", bundle: .module) + " · " + levels
        case .highlights: return String(localized: "\(items.count) works", bundle: .module)
        case .amenities: return String(localized: "\(items.count) amenities", bundle: .module) + " · " + levels
        }
    }

    // MARK: Map

    private func start() async {
        await MapStyle.waitForCanvas(of: session)
        session.onFeatureTap = { identifiers, coordinate in
            tapped(identifiers, at: ProximiioCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        mapLayers.attach(to: session)
        await load()
        // The lowest floor with a gallery, framed on the whole museum.
        show(level: catalog.spaces.map(\.level).min() ?? catalog.levels.first ?? 0)
        if let bounds = PlaceFraming.bounds(of: catalog.spaces.flatMap(\.framedPoints), minimumMeters: 60) {
            session.camera.fit(bounds: bounds, padding: mapInsets, animated: false)
        }
    }

    /// The lists, at the start and after a change of the venue data.
    private func load() async {
        let features = await venue.sdk.features()
        let places = VenuePlace.all(in: features)
        let geofences = await venue.sdk.geofences()
        let amenities = (try? await venue.sdk.amenities()) ?? []
        let categories = Dictionary(amenities.compactMap { amenity in amenity.title.map { (amenity.id, $0) } },
                                    uniquingKeysWith: { first, _ in first })
        catalog = ExploreCatalog(places: places, destinations: Gallery.destinations(geofences: geofences, places: places),
                                 categories: categories)
        let levelChangers = LevelChangerPlace.all(in: features)
        mapLayers.updateLevelChangers(levelChangers)
        // The artworks are not drawn: the galleries and the Highlights list show them.
        session.hiddenFeatureIDs = Set(levelChangers.map(\.id)).union(places.filter(\.isArtwork).map(\.id))
        if let current = selected {
            selected = catalog.all.first { $0.id == current.id }
        }
        applyMapLayers()
    }

    private func show(level: Double) {
        session.select(floor: FloorKey(level: level))
        self.level = level
        if let selected, !VenueLevel.same(selected.level, level) { self.selected = nil }
        applyMapLayers()
    }

    /// Closes the list, shows `item`'s floor, frames it and opens its card.
    private func show(_ item: ExploreItem) {
        tab = nil
        show(level: item.level)
        selected = item
        guard let bounds = PlaceFraming.bounds(of: item.framedPoints, minimumMeters: venue.settings.amenityFramingMinimumMeters) else { return }
        session.camera.fit(bounds: bounds, padding: mapInsets, animated: true)
    }

    /// A tap on a POI of the lists or inside a gallery opens its card; elsewhere it closes the card.
    private func tapped(_ identifiers: [String], at coordinate: ProximiioCoordinate) {
        let all = catalog.all
        let item = identifiers.lazy.compactMap { id in all.first { $0.id == id } }.first
            ?? catalog.space(at: coordinate, level: level)
        tab = nil
        selected = item
    }

    /// The galleries of the shown floor and the marker of a selected amenity.
    private func applyMapLayers() {
        let focus = selected?.kind == .space ? selected?.id : nil
        let fills = catalog.spaces.compactMap { item -> JourneyMapLayers.GalleryFill? in
            item.gallery.map { JourneyMapLayers.GalleryFill(gallery: $0, isDestination: focus == nil || focus == item.id) }
        }
        mapLayers.update(fills: fills, level: level)
        if let selected, case .amenity(let kind) = selected.kind {
            mapLayers.updateHighlight(JourneyMapLayers.Highlight(coordinate: selected.coordinate, level: selected.level, icon: kind.icon))
        } else {
            mapLayers.updateHighlight(nil)
        }
    }
}

/// A row of the lists: the icon, the title and its lines, and the level.
private struct ExploreRow: View {
    let item: ExploreItem

    var body: some View {
        HStack(spacing: 16) {
            if item.kind != .highlight {
                ExploreIcon(item: item)
            }
            ExploreText(item: item)
            Spacer(minLength: 8)
            Text(GuidanceText.floorLabel(item.level)).textStyle(.bodyBold)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// The card of a place on the map: the icon, the title and its lines, the level and a close button.
private struct ExploreCard: View {
    let item: ExploreItem
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if item.kind != .highlight {
                ExploreIcon(item: item)
            }
            ExploreText(item: item)
            Spacer(minLength: 8)
            Text(GuidanceText.floorLabel(item.level)).textStyle(.bodyBold)
        }
        .padding(.leading, 16)
        .padding(.trailing, 36)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("Close", bundle: .module))
        }
        .foregroundStyle(Palette.ink)
        .glassSurface(RoundedRectangle(cornerRadius: 16), strength: .frosted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exploreCard")
    }
}

/// The title (italic for an artwork) and the lines under it.
private struct ExploreText: View {
    let item: ExploreItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .italic(item.kind == .highlight)
                .textStyle(.bodyBold)
            ForEach(item.lines, id: \.self) { line in
                Text(line).textStyle(.bodySmallRegular)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// The icon in a white circle: the amenity's icon, or a symbol for the gallery's category.
private struct ExploreIcon: View {
    let item: ExploreItem

    var body: some View {
        Group {
            if case .amenity(let kind) = item.kind {
                kind.icon.image.resizable().scaledToFit().frame(width: 22, height: 22)
            } else {
                Image(systemName: ExploreItem.symbol(for: item.category)).font(.system(size: 18, weight: .medium))
            }
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 44, height: 44)
        .background(Palette.white, in: Circle())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}
