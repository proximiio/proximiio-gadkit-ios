//
//  GalleryNearbyDetector.swift
//  ProximiioGADKit
//
//  Detects when the gallery of the journey's active stop is nearby: the visitor is less than
//  `GADSettings.galleryNearbyMeters` from an entrance of the gallery in a straight line, on its
//  level, or inside the gallery's outline. An entrance is a POI with the amenity
//  `GADSettings.galleryEntranceAmenityID` and the gallery's id in `metadata.gallery_id`; a gallery
//  without one uses its own POI (GAD PM, Monday "Entry POIs, connected to gallery", 2026-11-15).
//  A visitor inside the outline of another gallery with an artwork still to visit is reported too,
//  with the first such artwork: the visitor left the route and entered that gallery. That report
//  waits until the visitor has been inside for `GADSettings.otherGalleryNearbySeconds` (by default
//  `galleryEntryOrderSeconds`, the time after which the journey is ordered again with that gallery
//  first), so the report and the new order come on the same position (infra, Metis T-1928,
//  2026-11-22: a visitor at a gallery's edge got the report 52 s before the route changed).
//  `VisitView` reports it as `VisitEvent.galleryNearby`; the host app can start the gallery's
//  introduction on it (Nagarro, PM, Monday "Approaching gallery information", 2026-11-10).
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
    private let entranceAmenityID: String
    /// Seconds inside another gallery of the journey before it is reported.
    private let otherGallerySeconds: TimeInterval
    /// The `gallery_id` of the last gallery reported, while it is still the active stop's gallery.
    private var reportedGalleryID: String?
    /// The `gallery_id` of another gallery of the journey reported while the visitor is inside it.
    private var reportedOtherGalleryID: String?
    /// The other gallery of the journey the visitor is inside, and since when.
    private var otherGalleryInside: (id: String, since: Date)?

    init(nearbyMeters: CLLocationDistance = GADSettings.standard.galleryNearbyMeters,
         entranceAmenityID: String = GADSettings.standard.galleryEntranceAmenityID,
         otherGallerySeconds: TimeInterval = 0) {
        self.nearbyMeters = nearbyMeters
        self.entranceAmenityID = entranceAmenityID
        self.otherGallerySeconds = otherGallerySeconds
    }

    /// The next `update` reports the active stop's gallery again when it is nearby.
    func reset() {
        reportedGalleryID = nil
        reportedOtherGalleryID = nil
    }

    /// The stop whose gallery is reported now, else `nil`: `stop` when its gallery is nearby and was
    /// not reported yet, else the first of `openStops` whose gallery the visitor is inside.
    /// `outlines` are the gallery outlines by `gallery_id` (`GalleryDestination`); `openStops` the
    /// stops still to visit, in the journey's order. `now` is the time of the position.
    func update(position: VenuePosition?, stop: JourneyStop?, places: [VenuePlace], outlines: [GalleryDestination],
                openStops: [JourneyStop] = [], now: Date = .now) -> JourneyStop? {
        if let reported = active(position: position, stop: stop, places: places, outlines: outlines) { return reported }
        guard let position else { return nil }
        let here = position.coordinate.proximiio
        let level = position.floor?.level
        let activeGalleryID = stop.flatMap { Self.gallery(of: $0.poiID ?? $0.id, in: places) }?.remoteID
        for other in openStops where other.id != stop?.id {
            guard let gallery = Self.gallery(of: other.poiID ?? other.id, in: places), let galleryID = gallery.remoteID,
                  galleryID != activeGalleryID,
                  outlines.first(where: { $0.id == galleryID })?.gallery.contains(here, level: level) == true
            else { continue }
            guard galleryID != reportedOtherGalleryID else { return nil }
            if otherGalleryInside?.id != galleryID { otherGalleryInside = (galleryID, now) }
            guard let since = otherGalleryInside?.since, now.timeIntervalSince(since) >= otherGallerySeconds else { return nil }
            reportedOtherGalleryID = galleryID
            FieldLog.log("gallery nearby: \(gallery.title) · stop \(other.title) · inside, not the active stop's gallery")
            return other
        }
        // Outside every other gallery of the journey: the next entry reports again.
        reportedOtherGalleryID = nil
        otherGalleryInside = nil
        return nil
    }

    /// `stop` when its gallery is nearby and was not reported yet, else `nil`.
    private func active(position: VenuePosition?, stop: JourneyStop?, places: [VenuePlace], outlines: [GalleryDestination]) -> JourneyStop? {
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
        if isInside, galleryID == reportedOtherGalleryID {
            // Reported when the visitor entered it; it is the active stop's gallery now.
            reportedGalleryID = galleryID
            reportedOtherGalleryID = nil
            return nil
        }
        let entrances = Self.entrances(of: galleryID, in: places, amenityID: entranceAmenityID)
        let points = entrances.isEmpty ? [gallery] : entrances
        guard isInside || points.contains(where: {
            Self.isNearby(here, level: level, gallery: $0.coordinate, galleryLevel: $0.level, within: nearbyMeters)
        }) else { return nil }
        reportedGalleryID = galleryID
        FieldLog.log("gallery nearby: \(gallery.title) · stop \(stop.title)\(isInside ? " · inside" : "") · \(entrances.count) entrances")
        return stop
    }

    /// The entrance POIs of the gallery `galleryID`: the places with the amenity `amenityID` and
    /// `metadata.gallery_id` equal to it. Pure; covered by tests.
    nonisolated static func entrances(of galleryID: String, in places: [VenuePlace], amenityID: String) -> [VenuePlace] {
        places.filter { $0.amenityID == amenityID && $0.galleryID == galleryID }
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
