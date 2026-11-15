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
//  The route also starts where the origin projects onto the path network. `extended(from:maximumMeters:)`
//  adds the straight segment from the origin to the route's start, once per computed route, so the line
//  starts at the visitor and does not move with later positions (PM, Monday "Routing Tongari-Kun ->
//  Goroka man", 2026-11-15).
//
import Proximiio

extension ComputedRoute {
    /// The route with a first segment from `origin` to its start, when `origin` is at least 1 cm and
    /// at most `maximumMeters` from the start. The distance and the walking time include the segment.
    /// The start instruction moves to `origin`, and the instruction after it takes the segment's
    /// distance and time. Otherwise the route itself. Pure; covered by tests.
    func extended(from origin: ProximiioCoordinate, maximumMeters: Double) -> ComputedRoute {
        guard let start = coordinates.first else { return self }
        let meters = GeoMath.haversineDistance(from: origin, to: start)
        guard meters >= 0.01, meters <= maximumMeters else { return self }
        let seconds = RouteCostModel().walkingSeconds(meters: meters)
        var steps = instructions
        if let first = steps.first, case .start = first.kind {
            steps[0] = RouteInstruction(kind: .start, coordinate: origin, distanceMeters: first.distanceMeters,
                                        level: first.level, durationSeconds: first.durationSeconds)
            if steps.count > 1 {
                let next = steps[1]
                steps[1] = RouteInstruction(kind: next.kind, coordinate: next.coordinate, distanceMeters: next.distanceMeters + meters,
                                            level: next.level, durationSeconds: next.durationSeconds + seconds)
            }
        }
        return ComputedRoute(
            coordinates: [origin] + coordinates,
            distanceMeters: distanceMeters + meters,
            segments: [RouteSegment(start: origin, end: start, distanceMeters: meters)] + segments,
            level: level,
            levelChanges: levelChanges,
            instructions: steps,
            durationSeconds: durationSeconds + seconds
        )
    }

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
