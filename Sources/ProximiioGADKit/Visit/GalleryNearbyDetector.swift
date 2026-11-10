//
//  GalleryNearbyDetector.swift
//  ProximiioGADKit
//
//  Detects when the gallery of the journey's active stop is nearby: the visitor is less than
//  `GADSettings.galleryNearbyMeters` from the gallery's POI in a straight line, on its level, or
//  inside the gallery's outline. `VisitView` reports it as `VisitEvent.galleryNearby`; the host app
//  can start the gallery's introduction on it (Nagarro, PM, Monday "Approaching gallery
//  information", 2026-11-10).
//
//  A gallery is reported once while it stays the gallery of the active stop: two stops in a row in
//  one gallery report it once, and a journey that comes back to a gallery reports it again.
//  `reset()` reports the current gallery again: the journey resumed after a pause (PM, Monday
//  "Sending entered geofences & approaching gallery at start", 2026-11-10).
//
import CoreLocation
import Foundation
import Proximiio
import ProximiioMap

@MainActor
final class GalleryNearbyDetector {
    private let nearbyMeters: CLLocationDistance
    /// The `gallery_id` of the last gallery reported, while it is still the active stop's gallery.
    private var reportedGalleryID: String?

    init(nearbyMeters: CLLocationDistance = GADSettings.standard.galleryNearbyMeters) {
        self.nearbyMeters = nearbyMeters
    }

    /// The next `update` reports the active stop's gallery again when it is nearby.
    func reset() {
        reportedGalleryID = nil
    }

    /// `stop` when its gallery is nearby and was not reported yet, else `nil`. `outlines` are the
    /// gallery outlines by `gallery_id` (`GalleryDestination`).
    func update(position: VenuePosition?, stop: JourneyStop?, places: [VenuePlace], outlines: [GalleryDestination]) -> JourneyStop? {
        guard let stop, let gallery = Self.gallery(of: stop.poiID ?? stop.id, in: places), let galleryID = gallery.remoteID else {
            // A stop without a gallery ends the last report: the next stop in that gallery reports it again.
            if stop != nil { reportedGalleryID = nil }
            return nil
        }
        guard galleryID != reportedGalleryID else { return nil }
        // Another gallery is ahead now; the earlier one reports again when the journey comes back.
        reportedGalleryID = nil
        guard let position else { return nil }
        let here = position.coordinate.proximiio
        let level = position.floor?.level
        let isInside = outlines.first { $0.id == galleryID }?.gallery.contains(here, level: level) ?? false
        guard isInside || Self.isNearby(here, level: level, gallery: gallery.coordinate, galleryLevel: gallery.level, within: nearbyMeters)
        else { return nil }
        reportedGalleryID = galleryID
        FieldLog.log("gallery nearby: \(gallery.title) · stop \(stop.title)\(isInside ? " · inside" : "")")
        return stop
    }

    /// The gallery POI of the artwork `placeID`: the place that is not an artwork and whose
    /// `remote_id` is the artwork's `metadata.gallery_id`. Pure; covered by tests.
    nonisolated static func gallery(of placeID: String, in places: [VenuePlace]) -> VenuePlace? {
        guard let galleryID = places.first(where: { $0.id == placeID })?.galleryID, !galleryID.isEmpty else { return nil }
        return places.first { !$0.isArtwork && $0.remoteID == galleryID }
    }

    /// `true` when the gallery's POI is on the visitor's level and less than `nearbyMeters` away in a
    /// straight line. An unknown level matches any level. Pure; covered by tests.
    nonisolated static func isNearby(
        _ position: ProximiioCoordinate, level: Double?, gallery: ProximiioCoordinate, galleryLevel: Double?,
        within nearbyMeters: CLLocationDistance = GADSettings.standard.galleryNearbyMeters
    ) -> Bool {
        guard VenueLevel.matches(level, galleryLevel) else { return false }
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)
        return here.distance(from: CLLocation(latitude: gallery.latitude, longitude: gallery.longitude)) < nearbyMeters
    }
}
