//
//  ExploreMuseumView.swift
//  ProximiioGADKit
//
//  The Explore Museum map (Figma "Explore Museum", node 12129:102006; PM screens 2026-10-23).
//  "Level N" and the floor changer are at the top. The legend button and the Spaces, Highlights and
//  Amenities tabs are at the bottom. A tab opens its list over the map (`ExploreCatalog`); the legend
//  button opens the map legend (PM, Monday "Explore Museum: Map legend missing", 2026-10-23). A row,
//  or a tap on a gallery or a POI, shows its floor and its card. The galleries of the shown floor
//  are filled with the level colour; while a gallery's card is open, the other galleries are lighter.
//
//  The visitor is not at the museum here: the map has no position dot, no route and a camera that
//  does not follow (`MapStyle.exploreOptions()`). The design's About the Building and Collections
//  tabs have no content in the app (DAILY-CALL N14).
//
import MapLibre
import Proximiio
import ProximiioMap
import SwiftUI

/// What the panel over the lower part of the map shows.
enum ExplorePanel: Equatable {
    case list(ExploreTab)
    case legend
}

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
    /// The open list or the legend, or `nil` for the map alone.
    @State private var panel: ExplorePanel?
    /// The amenities' icons from the venue data, by amenity id.
    @State private var amenityIcons: [String: UIImage] = [:]
    /// The place whose card is open.
    @State private var selected: ExploreItem?
    /// The features the map does not draw: artworks, level changers (drawn by `mapLayers`) and the
    /// amenities of `AmenityKind`.
    @State private var hiddenFeatureIDs: Set<String> = []
    /// The size of the map.
    @State private var mapSize: CGSize = .zero

    init(venue: VenueService) {
        self.venue = venue
        _session = StateObject(wrappedValue: MapStyle.session(sdk: venue.sdk, options: MapStyle.exploreOptions(settings: venue.settings), galleryIcons: true))
    }

    /// The map area under the level title and above the tab bar.
    private let mapInsets = UIEdgeInsets(top: 130, left: 30, bottom: 120, right: 30)

    var body: some View {
        ZStack {
            ProximiioMapView(session: session)
                .softEdges(cornerRadius: 40)
                .ignoresSafeArea(edges: .bottom)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
            MapLoadingSpinner(session: session, timeout: venue.settings.mapLoadingTimeout)
            if panel == nil, let selected {
                ExploreCallout(item: selected, session: session, icons: amenityIcons, target: ExploreCalloutLayout.target(in: mapSize)) {
                    self.selected = nil
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.opacity)
            }
            VStack(spacing: 0) {
                header
                Spacer()
            }
            if let panel {
                panelView(panel)
                    .transition(.move(edge: .bottom))
            }
            VStack(spacing: 12) {
                Spacer()
                tabBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .animation(.easeInOut(duration: 0.25), value: panel)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .task { await start() }
        .task { await MapDiagnostics.follow(session, name: "explore") }
        .onChange(of: venue.data.version) { _, _ in
            Task { await load() }
        }
        .onReceive(session.$selectedFloor) { floor in
            guard !VenueLevel.same(floor.level, level) else { return }
            level = floor.level
            applyMapLayers()
        }
        .onChange(of: selected) { _, _ in
            applyMapLayers()
            applyHiddenFeatures()
        }
    }

    // MARK: Top

    private var header: some View {
        HStack(alignment: .top) {
            // Regular 24 as in the Figma frame 12129:102006 (PM, Monday "Font size and style", 2026-10-26).
            Text(String(localized: "Level \(Int(level.rounded()))", bundle: .module))
                .textStyle(.h1Regular)
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
            GlassSquareButton(isSelected: panel == .legend, action: { toggle(.legend) }) {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .medium))
            }
            .accessibilityLabel(Text("Map legend", bundle: .module))
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
            toggle(.list(item))
        } label: {
            Text(item.title)
                .textStyle(.bodySmallRegular)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if panel == .list(item) {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ink, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(panel == .list(item) ? .isSelected : [])
    }

    /// Opens `target`, or closes it when it is open.
    private func toggle(_ target: ExplorePanel) {
        if panel == target {
            panel = nil
        } else {
            selected = nil
            panel = target
        }
    }

    // MARK: Panel

    /// A list or the legend over the lower part of the map. Dragging its top edge down closes it.
    private func panelView(_ panel: ExplorePanel) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 14) {
                        Capsule()
                            .fill(Palette.ink.opacity(0.25))
                            .frame(width: 44, height: 5)
                        HStack(alignment: .firstTextBaseline) {
                            Text(title(of: panel)).textStyle(panel == .legend ? .bodySmallSemiBold : .cardTitle)
                            Spacer()
                            if case .list(let tab) = panel {
                                Text(summary(tab)).textStyle(.bodySmallRegular)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.horizontal, 24)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                        if value.translation.height > 60 { self.panel = nil }
                    })
                    ScrollView {
                        switch panel {
                        case .list(let tab): list(tab)
                        case .legend: legend
                        }
                    }
                    // The rows fade out above the tab bar: its glass shows the text under it.
                    .mask {
                        VStack(spacing: 0) {
                            Rectangle()
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 30)
                            Color.clear.frame(height: proxy.safeAreaInsets.bottom + 16 + 50 + 6)
                        }
                    }
                }
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * (panel == .legend ? 0.62 : 0.72))
                .glassSurface(UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40), strength: .frosted)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func title(of panel: ExplorePanel) -> String {
        switch panel {
        case .list(let tab): tab.title
        case .legend: String(localized: "Map legend", bundle: .module)
        }
    }

    /// The rows of `tab`, by level.
    private func list(_ tab: ExploreTab) -> some View {
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
                                    Button { show(item) } label: { ExploreRow(item: item, icons: amenityIcons) }
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

    /// The map legend of the PM's screen: the facilities and the galleries the museum's POIs use, with
    /// their map icons.
    private var legend: some View {
        HStack(alignment: .top, spacing: 20) {
            legendColumn(String(localized: "Facilities", bundle: .module), catalog.legendFacilities)
            legendColumn(String(localized: "Galleries", bundle: .module), catalog.legendGalleries)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        // Clear of the tab bar.
        .padding(.bottom, 110)
    }

    private func legendColumn(_ title: String, _ entries: [ExploreLegendEntry]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).textStyle(.bodySmallRegular)
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    ExploreIcon.glyph(amenityID: entry.amenityID, title: entry.title, icons: amenityIcons)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Text(entry.title).textStyle(.bodySmallBold)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
        let scale = UIScreen.main.scale
        amenityIcons = Dictionary(amenities.compactMap { amenity in amenity.icon.flatMap { AmenityIcon.rasterImage($0, scale: scale) }.map { (amenity.id, $0) } },
                                  uniquingKeysWith: { first, _ in first })
        let categories = Dictionary(amenities.compactMap { amenity in amenity.title.map { (amenity.id, $0) } },
                                    uniquingKeysWith: { first, _ in first })
        let levelChangers = LevelChangerPlace.all(in: features)
        catalog = ExploreCatalog(places: places, destinations: Gallery.destinations(geofences: geofences, places: places, features: features),
                                 categories: categories, levelChangerTypes: Set(levelChangers.map(\.featureType)),
                                 facilities: .facilities(amenities))
        mapLayers.updateLevelChangers(levelChangers)
        // The artworks are not drawn: the galleries and the Highlights list show them. Nor are the
        // amenities: the Amenities list and the red marker show them (PM, Monday "Explore museum view:
        // default map view", 2026-10-26).
        let amenityPlaces = places.filter { place in !place.isArtwork && AmenityKind.allCases.contains { $0.matches(place) } }
        hiddenFeatureIDs = Set(levelChangers.map(\.id)).union(places.filter(\.isArtwork).map(\.id)).union(amenityPlaces.map(\.id))
        applyHiddenFeatures()
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

    /// Closes the list, shows `item`'s floor and opens its card. The place is framed around the
    /// callout's target point (`ExploreCalloutLayout`).
    private func show(_ item: ExploreItem) {
        panel = nil
        show(level: item.level)
        selected = item
        guard let bounds = PlaceFraming.bounds(of: ExploreCalloutLayout.framedPoints(of: item), minimumMeters: venue.settings.amenityFramingMinimumMeters) else { return }
        session.camera.fit(bounds: bounds, padding: ExploreCalloutLayout.framingInsets(in: mapSize), animated: true)
    }

    /// A tap on a POI of the lists or inside a gallery opens its card; elsewhere it closes the card.
    private func tapped(_ identifiers: [String], at coordinate: ProximiioCoordinate) {
        let all = catalog.all
        if let item = identifiers.lazy.compactMap({ id in all.first { $0.id == id } }).first
            ?? catalog.space(at: coordinate, level: level) {
            show(item)
        } else {
            panel = nil
            selected = nil
        }
    }

    /// The selected place's own POI is not drawn: the callout's dot marks it.
    private func applyHiddenFeatures() {
        session.hiddenFeatureIDs = hiddenFeatureIDs.union(selected.map { [$0.id] } ?? [])
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
    let icons: [String: UIImage]

    var body: some View {
        HStack(spacing: 16) {
            if item.kind != .highlight {
                ExploreIcon(item: item, icons: icons)
            }
            ExploreText(item: item)
            Spacer(minLength: 8)
            Text(GuidanceText.floorLabel(item.level)).textStyle(.bodyBold)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// The card of a place picked on the map (PM, Monday "Explore Museum view: gallery POI view",
/// 2026-10-26): over the map above the place, a line down to the place, and the place as a black dot
/// in a translucent ring with its title under it. In the design's 402 × 874 pt frame the place is at
/// (124.5, 657) and the card's bottom 55 pt above it, 32 pt from the sides. The map frames the place
/// there (`ExploreCalloutLayout`); the line and the dot follow the place when the visitor moves the map.
private struct ExploreCallout: View {
    let item: ExploreItem
    let session: ProximiioMapSession
    let icons: [String: UIImage]
    /// Where the place goes (`ExploreCalloutLayout.target(in:)`).
    let target: CGPoint
    let onClose: () -> Void

    var body: some View {
        TimelineView(.animation) { _ in
            let point = projectedPoint ?? target
            let cardBottom = target.y - 55
            ZStack(alignment: .topLeading) {
                Group {
                    if point.y > cardBottom {
                        Rectangle()
                            .fill(Palette.ink)
                            .frame(width: 1, height: point.y - cardBottom)
                            .position(x: point.x, y: (cardBottom + point.y) / 2)
                    }
                    marker.position(point)
                    Text(item.title)
                        .textStyle(.bodySmallBold)
                        .multilineTextAlignment(.center)
                        .frame(width: 140)
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: point.x, y: point.y + 30)
                }
                .foregroundStyle(Palette.ink)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                ExploreCard(item: item, icons: icons, onClose: onClose)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(0, cardBottom), alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The black dot in a ring at 30 % with a white border.
    private var marker: some View {
        ZStack {
            Circle().fill(Palette.ink.opacity(0.3)).frame(width: 21, height: 21)
            Circle().strokeBorder(Palette.white.opacity(0.7), lineWidth: 1).frame(width: 23, height: 23)
            Circle().fill(Palette.ink).frame(width: 8.27, height: 8.27)
        }
    }

    /// The place on the map view.
    private var projectedPoint: CGPoint? {
        guard let mapView = session.canvas?.mapView else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        return mapView.convert(coordinate, toPointTo: mapView)
    }
}

/// Where `ExploreCallout` puts the place.
enum ExploreCalloutLayout {
    /// Where the place goes on a map of `size`. Pure; covered by tests.
    static func target(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 124.5 / 402, y: size.height * 657 / 874)
    }

    /// The item's framed points mirrored around its place, so the frame's centre is the place and the
    /// fit puts the place on the target. Pure; covered by tests.
    static func framedPoints(of item: ExploreItem) -> [ProximiioCoordinate] {
        let place = item.coordinate
        return item.framedPoints.flatMap { point in
            [point, ProximiioCoordinate(latitude: 2 * place.latitude - point.latitude, longitude: 2 * place.longitude - point.longitude)]
        }
    }

    /// The padding that frames the place in a box around `target(in:)`, clear of the level title
    /// and the tab bar. Pure; covered by tests.
    static func framingInsets(in size: CGSize) -> UIEdgeInsets {
        guard size.width > 100, size.height > 400 else { return UIEdgeInsets(top: 130, left: 30, bottom: 120, right: 30) }
        let point = target(in: size)
        let halfWidth = point.x - 16
        let halfHeight = max(40, min(point.y - 140, size.height - point.y - 110))
        return UIEdgeInsets(top: point.y - halfHeight, left: point.x - halfWidth,
                            bottom: size.height - point.y - halfHeight, right: size.width - point.x - halfWidth)
    }
}

/// The card of a place on the map: the icon, the title and its lines, the level and a close button.
private struct ExploreCard: View {
    let item: ExploreItem
    let icons: [String: UIImage]
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if item.kind != .highlight {
                ExploreIcon(item: item, icons: icons)
            }
            ExploreText(item: item, isCard: true)
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

/// The title (italic for an artwork) and the lines under it. The card's text is larger than the
/// list's: Bold 18 and Regular 16 (Figma frame 12129:102006).
private struct ExploreText: View {
    let item: ExploreItem
    var isCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .italic(item.kind == .highlight)
                .textStyle(isCard ? .largeBodyBold : .bodyBold)
            ForEach(item.lines, id: \.self) { line in
                Text(line).textStyle(isCard ? .bodyRegular : .bodySmallRegular)
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// The icon in a white circle: the design's glyph of an amenity kind, else the icon of the POI's
/// amenity in the venue data (the icon the map draws), else a symbol for the gallery's category.
private struct ExploreIcon: View {
    let item: ExploreItem
    let icons: [String: UIImage]

    var body: some View {
        Group {
            if case .amenity(let kind) = item.kind {
                kind.icon.image.resizable().scaledToFit().frame(width: 22, height: 22)
            } else if let id = item.amenityID, let image = icons[id] {
                // The data's icon is a 30 px marker, a white circle with the glyph: it fills the
                // circle.
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit().frame(width: 44, height: 44)
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

extension ExploreIcon {
    /// The legend's glyph of an amenity: the design's glyph of its kind, else its icon in the venue
    /// data, else a symbol for a gallery category.
    @ViewBuilder static func glyph(amenityID: String, title: String, icons: [String: UIImage]) -> some View {
        if let kind = AmenityKind.kind(forAmenityID: amenityID, title: title) {
            kind.icon.image.resizable().scaledToFit().foregroundStyle(Palette.ink).padding(4)
        } else if let image = icons[amenityID] {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: ExploreItem.symbol(for: title)).resizable().scaledToFit().foregroundStyle(Palette.ink)
        }
    }
}
