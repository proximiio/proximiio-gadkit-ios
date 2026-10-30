//
//  ArrivalDetector.swift
//  ProximiioGADKit
//
//  Detects that the visitor is at the museum (Figma "Stage 02 – Museum Arrival", 02A.01:
//  "When the location has gathered that the user is at the museum, on opening the app it
//  should acknowledge it").
//
//  Two sources: a wristband or playback position (the visitor is inside), or one location fix of
//  the phone within `radius` of a place of the venue. The phone fix needs When In Use
//  authorization, which `VenueService.start` requests. No region monitoring: that needs Always
//  authorization, which the package does not request.
//
import Combine
import CoreLocation
import Foundation
import Proximiio

@MainActor
final class ArrivalDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// Distance from a place of the venue that counts as "at the museum", in metres.
    nonisolated static let radius: CLLocationDistance = 400

    @Published private(set) var isAtMuseum = false
    /// Location authorization, for "Location is required".
    @Published private(set) var authorization: CLAuthorizationStatus
    /// Called once, when `isAtMuseum` becomes `true`.
    var onArrival: (() -> Void)?

    private let manager = CLLocationManager()
    private var places: [ProximiioCoordinate] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Requests one phone fix and compares it with the places.
    func check(places: [VenuePlace]) {
        self.places = places.map(\.coordinate)
        guard !places.isEmpty else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    /// A position from the wristband or playback means the visitor is inside.
    func positionReceived() {
        arrive()
    }

    private func arrive() {
        guard !isAtMuseum else { return }
        isAtMuseum = true
        onArrival?()
    }

    /// `true` when `location` is within `radius` of one of `places`. The GAD organisation has two
    /// venues 11 km apart, so the mean of all places is near neither. Pure; covered by tests.
    nonisolated static func isNear(_ location: CLLocation, places: [ProximiioCoordinate], radius: CLLocationDistance = radius) -> Bool {
        places.contains { location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= radius }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if Self.isNear(location, places: places) { arrive() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            if !places.isEmpty, status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }
}
