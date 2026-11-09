//
//  RouteToStop.swift
//  ProximiioGADKit
//
//  The SDK's route ends where the destination projects onto the path network. A stop beside the
//  path, such as an artwork on a wall, is a few metres further. `extended(to:maximumMeters:)` adds
//  the straight segment from the route's end to the stop (user, 2026-11-09). The journey legs to a
//  stop (`GalleryFirstRouting`) and the "Go here" routes of the maps end at the stop. A leg to a
//  gallery's POI (gallery first) ends on the path.
//
import Proximiio

extension ComputedRoute {
    /// The route with a last segment from its end to `stop`, when `stop` is at least 1 cm and at
    /// most `maximumMeters` from the end. The distance, the walking time and the arrive instruction
    /// include the segment, and the arrive instruction moves to `stop`. Otherwise the route itself.
    /// Pure; covered by tests.
    func extended(to stop: ProximiioCoordinate, maximumMeters: Double) -> ComputedRoute {
        guard let end = coordinates.last else { return self }
        let meters = GeoMath.haversineDistance(from: end, to: stop)
        guard meters >= 0.01, meters <= maximumMeters else { return self }
        let seconds = RouteCostModel().walkingSeconds(meters: meters)
        var steps = instructions
        if let arrive = steps.last, case .arrive = arrive.kind {
            steps[steps.count - 1] = RouteInstruction(
                kind: .arrive,
                coordinate: stop,
                distanceMeters: arrive.distanceMeters + meters,
                level: arrive.level,
                durationSeconds: arrive.durationSeconds + seconds
            )
        }
        return ComputedRoute(
            coordinates: coordinates + [stop],
            distanceMeters: distanceMeters + meters,
            segments: segments + [RouteSegment(start: end, end: stop, distanceMeters: meters)],
            level: level,
            levelChanges: levelChanges,
            instructions: steps,
            durationSeconds: durationSeconds + seconds
        )
    }
}
