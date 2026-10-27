//
//  ProximiExploreView.swift
//  ProximiioGADKit
//
//  The Explore Museum map as a UI component on the host app's SDK (Nagarro, 2026-10-27): "Level N"
//  and the floor changer at the top, the map, the legend button and the Spaces, Highlights and
//  Amenities tabs with their lists and cards (`ExploreMuseumView`). No title, no Back and no
//  background: the host app draws them. `ProximiMap.open(.museumMap)` shows the same map with the
//  package's title and Back.
//
//  The visitor need not be at the museum: the map draws no position and no route. The view does not
//  start, stop or configure the SDK.
//
import Proximiio
import SwiftUI

public struct ProximiExploreView: View {
    private let sdk: Proximiio
    private let settings: GADSettings

    @State private var venue: VenueService?

    /// - Parameters:
    ///   - sdk: The host app's SDK, started. The view reads the venue data the SDK holds and follows
    ///     its `venueDataChanges()`.
    ///   - settings: The zoom range and the map's loading timeout. The view reads them when it opens.
    public init(sdk: Proximiio, settings: GADSettings = .standard) {
        self.sdk = sdk
        self.settings = settings
    }

    public var body: some View {
        Group {
            if let venue {
                ExploreMuseumView(venue: venue)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if let venue {
                // Back on screen after `onDisappear`.
                await venue.data.start()
            } else {
                venue = await VenueService.hosted(sdk: sdk, settings: settings)
            }
        }
        .onDisappear { venue?.stop() }
    }
}
