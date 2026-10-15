//
//  GADSettings.swift
//  ProximiioGADKit
//
//  The times and distances of the map and journey screens. The host app sets them in
//  `GADConfiguration.settings`, or later in `VenueService.settings`; a screen reads them when it
//  opens. The defaults are the PM's values as of 2026-10-14.
//
import Foundation

public struct GADSettings: Equatable, Sendable {
    // MARK: Wristband tracking alerts

    /// Seconds without positioning before "We've lost your place". The SDK reports positioning
    /// unavailable about 10 s after the last fix, so 110 is about 2 min after it.
    public var trackingLostAfter: TimeInterval = 110
    /// Seconds without positioning before "Your wristband has stopped responding". Must be more
    /// than `trackingLostAfter`. 170 is about 3 min after the last fix.
    public var trackingStoppedAfter: TimeInterval = 170

    // MARK: Arrival

    /// Seconds between the arrival at an artwork (its geofence) and the route to the next stop.
    public var artworkAdvanceDelay: TimeInterval = 2
    /// Seconds inside the geofence of an artwork that is not the next stop before it counts as
    /// visited out of order. A longer time keeps a visitor who crosses it on the way from marking it.
    public var outOfOrderDwell: TimeInterval = 0
    /// An amenity has no geofence. It is reached within 2.5 × the position accuracy, at least this
    /// many metres…
    public var amenityArrivalMinimumMeters: Double = 5
    /// …and at most this many metres…
    public var amenityArrivalMaximumMeters: Double = 10
    /// …for this many seconds.
    public var amenityArrivalDwell: TimeInterval = 5

    // MARK: Notifications

    /// "The next stop of your journey is less than … m away": the distance along the route, or
    /// in a straight line without a route.
    public var stopNearbyMeters: Double = 5

    // MARK: Route

    /// Metres from the route before "You've left your route".
    public var offRouteMeters: Double = 30
    /// Seconds off the route before "You've left your route", at any distance.
    public var offRouteSeconds: TimeInterval = 300
    /// The position dot is drawn on the route while it is within this many metres of it. Display
    /// only; guidance and arrival use the real position.
    public var routeSnapMeters: Double = 0.5

    // MARK: Map

    /// Zoom of "Centre on me" and of the first position.
    public var followZoom: Double = 21

    // MARK: Lift

    /// Seconds of fixes inside a lift outline before the visitor counts as riding it ("In the
    /// lift", "Level up"). A shorter stay is walking past the lift.
    public var liftRideDwell: TimeInterval = 3
    /// Consecutive fixes outside the lift outline that end the ride.
    public var liftExitFixes: Int = 2

    // MARK: "Probably at …"

    /// Positions less accurate than this (metres) near the next stop ask "Are you at …?".
    public var uncertainAccuracyMeters: Double = 8
    /// Seconds a question the visitor answered stays quiet.
    public var locationQuestionQuietPeriod: TimeInterval = 120

    // MARK: Journey order

    /// Seconds a new personalised journey waits for a fix before it is ordered without one.
    public var firstFixWait: TimeInterval = 5
    /// Seconds after the start in which the first fix orders a journey that was ordered without one.
    public var lateOrderWindow: TimeInterval = 60

    // MARK: Live Activity

    /// The shortest gap in seconds between two Live Activity updates of the instruction. A new
    /// step is sent at once.
    public var liveActivityMinimumInterval: TimeInterval = 5

    public init() {}

    /// The defaults.
    public static let standard = GADSettings()
}
