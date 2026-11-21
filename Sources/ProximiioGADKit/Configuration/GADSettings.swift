//
//  GADSettings.swift
//  ProximiioGADKit
//
//  The times and distances of the map and journey screens. The host app sets them in
//  `GADConfiguration.settings`. The defaults are the PM's values as of 2026-10-14.
//
import Foundation
import Proximiio

public struct GADSettings: Equatable, Sendable {
    // MARK: Wristband tracking

    /// Seconds without positioning before `ProximiMapEvent.trackingChanged(.lostPlace)`. The SDK
    /// reports positioning unavailable about 10 s after the last fix, so 110 is about 2 min after it.
    public var trackingLostAfter: TimeInterval = 110
    /// Seconds without positioning before `ProximiMapEvent.trackingChanged(.stoppedResponding)`. Must
    /// be more than `trackingLostAfter`. 170 is about 3 min after the last fix.
    public var trackingStoppedAfter: TimeInterval = 170

    // MARK: Arrival

    /// `true`: the journey moves to the next stop when the visitor leaves the active artwork: they
    /// are more than `artworkVisitedMeters` from its geofence for `artworkVisitedSeconds`, or they
    /// enter the geofence of another artwork of the journey (GAD PM, 2026-11-15). Inside the geofence the artwork is
    /// reached: the card and the destination marker keep the artwork, and the route shows the leg to
    /// the next stop (`JourneyNavigator.drawsNextLegWhileReached`; GAD PM and Nagarro, 2026-10-30).
    /// `false`: `artworkAdvanceDelay` after the visitor entered it.
    public var advancesOnArtworkExit = true
    /// With `advancesOnArtworkExit` `false`: seconds between the arrival at an artwork (its geofence)
    /// and the route to the next stop.
    public var artworkAdvanceDelay: TimeInterval = 2
    /// With `advancesOnArtworkExit`: the artwork the visitor arrived at is visited when they are more
    /// than this many metres from the border of its geofence…
    public var artworkVisitedMeters: Double = 5
    /// …for this many seconds. One position beyond the distance does not end the visit.
    public var artworkVisitedSeconds: TimeInterval = 2
    /// Seconds inside the geofence of an artwork that is not the next stop before it counts as
    /// visited out of order. A longer time keeps a visitor who crosses it on the way from marking it.
    public var outOfOrderDwell: TimeInterval = 0
    /// `false`: an artwork the visitor enters out of order becomes the current stop. It is visited by
    /// the rules of any artwork the visitor arrived at (`artworkVisitedMeters`, the geofence of
    /// another artwork, the host app). `true`: it is visited at the entry, as before 1.48.0. Without
    /// `advancesOnArtworkExit` it is always visited at the entry (GAD PM, 2026-11-16).
    public var visitsOutOfOrderAtEntry = false
    /// An amenity has no geofence. It is reached within 2.5 × the position accuracy, at least this
    /// many metres…
    public var amenityArrivalMinimumMeters: Double = 5
    /// …and at most this many metres…
    public var amenityArrivalMaximumMeters: Double = 10
    /// …for this many seconds.
    public var amenityArrivalDwell: TimeInterval = 5

    // MARK: Geofences

    /// Seconds the position stays outside an entered geofence or privacy zone before the SDK
    /// reports the exit (`ProximiioConfiguration.geofenceExitDelay`, SDK 6.0.0-beta.63, whose
    /// default is 3). A position back inside within this time reports nothing. Enters are reported
    /// at once. `ProximiMap` sets it when it starts the SDK; `ProximiMapView` runs on the host app's
    /// SDK, which has its own value. 0 reports the exit at the first position outside.
    public var geofenceExitDelay: TimeInterval = 5
    /// Seconds the position stays outside an entered privacy zone before the SDK reports its exit
    /// (`ProximiioConfiguration.privacyZoneExitDelay`, SDK 6.0.0-beta.72). The first position after
    /// a privacy zone comes after this time. `nil` uses `geofenceExitDelay`. `ProximiMap` sets it
    /// when it starts the SDK; `ProximiMapView` runs on the host app's SDK, which has its own value.
    public var privacyZoneExitDelay: TimeInterval? = 1

    // MARK: Next stop nearby

    /// `ProximiMapEvent.stopNearby`: the active stop is less than this many metres away, along the
    /// route, or in a straight line without a route. The package posts no notification for it.
    public var stopNearbyMeters: Double = 5
    /// `ProximiMapEvent.galleryNearby`: an entrance of the active stop's gallery is less than this
    /// many metres away in a straight line, on the visitor's level. A gallery without an entrance
    /// POI uses its own POI. A visitor inside the gallery's outline is nearby at any distance.
    public var galleryNearbyMeters: Double = 5
    /// The amenity of the gallery entrance POIs. An entrance names its gallery in
    /// `metadata.gallery_id`; a gallery can have several (GAD PM, 2026-11-15).
    public var galleryEntranceAmenityID = "7405e6e6-d9f6-4146-adda-de6adbf4a8a1:3c274297-2461-4c4b-b380-262d76a5eca5"

    // MARK: Route

    /// Metres from the leg to the current destination before "Looks like you've left your route",
    /// also where a later leg passes; and from every leg still to walk, for 3 fixes, before the
    /// navigator's `leftRoute` (PM, Monday "Personalized tour: off-route and re-route behaviour",
    /// 2026-10-28).
    public var offRouteMeters: Double = 12
    /// Seconds off the route before "Looks like you've left your route", at any distance.
    public var offRouteSeconds: TimeInterval = 300
    /// Seconds "Looks like you've left your route" stays open, unless the visitor closes it.
    public var offRouteWarningSeconds: TimeInterval = 10
    /// Seconds on a floor the route does not take before the visitor counts as off the route.
    public var wrongFloorSeconds: TimeInterval = 10
    /// `true` keeps the route of a personalised journey at the visitor inside the gallery of the
    /// current artwork: more than `galleryRouteRefreshMeters` off the leg, the stops ahead are
    /// ordered again from the visitor, so the nearest open artwork becomes the current stop, and the
    /// leg is drawn again from the visitor. No warning shows. `false` keeps the leg until
    /// `offRouteMeters`, as before 1.51.0 (PM's field test, 2026-11-17).
    public var refreshesRouteInGallery = true
    /// Metres off the leg, inside the gallery of the current artwork, before
    /// `refreshesRouteInGallery` orders the stops and draws the leg again.
    public var galleryRouteRefreshMeters: Double = 3
    /// The shortest time between two refreshes of `refreshesRouteInGallery`, in seconds.
    public var galleryRouteRefreshSeconds: TimeInterval = 3
    /// Personalised journeys: when the visitor enters a gallery that holds an artwork still to
    /// visit, and the current artwork is in another gallery, the stops ahead are ordered again from
    /// the visitor, so the leg leads to the nearest open artwork. Once per entry; no warning shows.
    /// `false`: the order changes there only off the route or after an artwork is visited, as
    /// before 1.51.0 (PM's field test, 2026-11-17).
    public var ordersAtGalleryEntry = true
    /// Seconds the visitor's position lies in a gallery before `ordersAtGalleryEntry` and
    /// `ordersVisitorGalleryFirst` count the visitor in it. A position that crosses a border for a
    /// shorter time changes no order. 0 counts the first fix.
    public var galleryEntryOrderSeconds: TimeInterval = 3
    /// Personalised journeys: every order from the visitor puts the artworks of the gallery the
    /// visitor is in first, also when an artwork of another gallery is nearer by the route. So the
    /// entry of a gallery (`ordersAtGalleryEntry`), a resume and an order off the route lead to an
    /// artwork of that gallery. `false`: the nearest artwork by the route goes first, as in 1.51.0
    /// (PM's field test and Nagarro's bug list, 2026-11-18).
    public var ordersVisitorGalleryFirst = true
    /// `ProximiMapView` with `.progress`, personalised journeys: the view takes the states of the
    /// journey the host app passes and puts the visited and skipped stops before the pending ones,
    /// each group in the host app's order. It writes that order back. A host app that stores the
    /// states but passes its first order after a restart showed a visited artwork behind open ones
    /// in the list (PM, on site, 2026-11-19). `false` keeps the host app's order.
    public var ordersDoneStopsFirst = true
    /// A `ProximiMapView` or `ProximiExploreView` that started while the phone was locked starts its
    /// map again when the phone is unlocked, with the journey as it is then. On a locked phone the
    /// map cannot read its stored style and tiles when the host app's files have complete data
    /// protection, and such a map stayed blank after the unlock (host app field log, 2026-11-21).
    /// `ProximiMapView` calls `onNavigator` again with a new navigator. `false` keeps the map.
    public var restartsMapAfterUnlock = true
    /// An artwork the visitor has arrived at is marked visited when the visitor enters the geofence
    /// of another artwork of the journey and is outside its own. `false`: only
    /// `artworkVisitedMeters` and `artworkVisitedSeconds` mark it visited.
    public var visitsArtworkAtAnotherArtwork = true
    /// Personalised journeys, the checks that run while the visitor walks (`refreshesRouteInGallery`
    /// and the order off the route): another artwork becomes the current stop only when it is this
    /// many metres nearer to the visitor than the current stop, in a straight line. An artwork of
    /// the visitor's gallery takes the place of one outside it at any distance. 0 takes every other
    /// order, as before 1.53.0, also between two artworks at the same distance.
    public var orderSwitchMinimumMeters: Double = 3
    /// The visitor has arrived at the current artwork after `artworkArrivalMarginSeconds` within
    /// this many metres of its geofence, outside it and inside no geofence of another open artwork
    /// of the journey. 0 (default since 1.55.1, GAD PM 2026-11-18: larger geofences in the venue
    /// data instead): only a fix inside the geofence is the arrival. The visit ends beyond
    /// `artworkVisitedMeters`, which must be larger.
    public var artworkArrivalMarginMeters: Double = 0
    /// How long the visitor stays within `artworkArrivalMarginMeters` before the arrival, in seconds.
    public var artworkArrivalMarginSeconds: TimeInterval = 3
    /// Personalised journeys: in the gallery of the current artwork, the nearest open artwork of
    /// that gallery becomes the current stop when it is `orderSwitchMinimumMeters` nearer to the
    /// visitor than the current stop, in a straight line, also for a visitor on the leg. Checked at
    /// most every `galleryRouteRefreshSeconds`. `false`: the stop changes only off the leg
    /// (`refreshesRouteInGallery`), as before 1.54.0.
    public var ordersNearestArtworkInGalleryFirst = true
    /// Personalised journeys: while the visitor is in no gallery of the journey (the open area
    /// between the galleries), the stops ahead are ordered again from the visitor when that order
    /// starts with another artwork and saves `openAreaOrderMinimumMeters` of walking by the route.
    /// The journey then leads to the nearer gallery (PM, 2026-11-20). `false`: outside the galleries
    /// the order changes only after a visit and after a detour, as before 1.61.1.
    public var ordersInOpenArea = true
    /// The journey map follows the visitor again each time they enter or leave a gallery, when a
    /// gesture left the camera free (PM, 2026-11-20). The next gesture frees the camera again.
    /// Not while the journey is paused. `false`: only "Centre on me" takes the follow again, as
    /// before 1.63.0.
    public var followsAgainAtGalleryChange = true
    /// The journey map draws a line from the visitor to the nearest point of the route ahead, at
    /// every position, on the visitor's floor (PM, Monday "Route drawing feels off", 2026-11-20:
    /// the route did not start at the blue dot). The route itself is not computed again. No line
    /// within 2 m of the route's end, none after the arrival, and none further than
    /// `routeConnectorMaximumMeters` from the route. Off since 1.65.1 (PM, 2026-11-20: the item
    /// is parked). `false`: no line, as from
    /// 2026-10-12 to 1.64.0.
    public var connectsRouteToPosition = false
    /// The longest line `connectsRouteToPosition` draws, in metres. Further from the route there
    /// is no line: a long one crosses walls.
    public var routeConnectorMaximumMeters: Double = 6
    /// How many metres of walking the order from the visitor saves before `ordersInOpenArea` takes
    /// it. A small value changes the destination at every step between two galleries.
    public var openAreaOrderMinimumMeters: Double = 15
    /// The shortest time between two checks of `ordersInOpenArea`, in seconds. Each check asks the
    /// map for an order by walking time.
    public var openAreaOrderSeconds: TimeInterval = 20
    /// Gallery first: an artwork that led to the artwork because the visitor was in its gallery
    /// leads to the gallery again when the visitor is more than this many metres outside the
    /// gallery's outline, or on another floor.
    public var galleryLeftMeters: Double = 5
    /// The journey list: a swipe on an artwork asks for the skip at once (`skipRequested`, and
    /// "Skip it?" with `ProximiMapView.Options.skipPrompt`). `false`: the swipe reveals the skip
    /// button, and a tap on it asks for the skip. `true` since 1.64.0 (PM and Nagarro, Monday
    /// 2026-11-20: no second step).
    public var skipsAtSwipe = true
    /// The journey list while the journey is paused (`ProximiMapView`'s `isPaused`, "Add a stop"):
    /// `false`, the default since 1.59.0: a swipe on an artwork skips nothing, reports no event and
    /// shows "Resume your journey to skip the artwork" with "Dismiss"; the text also replaces the
    /// swipe hint (PM, Monday "Swipe to skip disabled when navigation is paused", 2026-11-20).
    /// `true` keeps the swipe, as before.
    public var skipsWhilePaused = false
    /// The position dot is drawn on the route while it is within this many metres of it. Display
    /// only; guidance and arrival use the real position.
    public var routeSnapMeters: Double = 0.5
    /// The walked part of the route moves only while the position is within this many metres of the
    /// leg; further away it stays where it was (`RouteFollowRules.progressCorridorMeters`). The
    /// remaining distance and the instructions follow every position. `nil`: the walked part follows
    /// the position at any distance (PM, Monday "Route marked as walked too far", 2026-10-30).
    public var progressCorridorMeters: Double? = 3
    /// A route ends where its stop projects onto the path network. The line goes on in a straight
    /// line to the stop when the stop is at most this many metres from that point. The remaining
    /// distance and the walking time include that segment. A leg to a gallery's POI (gallery first)
    /// ends on the path. 0: every route ends on the path. The SDK routes to a stop at most 15 m from
    /// a path (`WayfindingRouter.defaultSnapThresholdMeters`), so 15 extends every route (user,
    /// 2026-11-09).
    public var routeToStopMaximumMeters: Double = 15
    /// A route starts where its origin projects onto the path network. The line starts at the origin,
    /// in a straight line to that point, when the origin is at most this many metres from it. The
    /// origin is the visitor's position when the route is computed; the segment does not move with
    /// later positions. The remaining distance and the walking time include it. 0: every route starts
    /// on the path (GAD PM, 2026-11-15).
    public var routeFromOriginMaximumMeters: Double = 15

    // MARK: Map

    /// Zoom of "Centre on me", of the first position and of the follow, in personalised and curated
    /// journeys, while the visitor is in no gallery. The follow eases to it from `startZoom`. 19
    /// since 1.56.0, was 19.5 (operator, K-39, 2026-11-19).
    public var followZoom: Double = 19
    /// Zoom of the follow while the visitor is in a gallery, in personalised and curated journeys,
    /// or `nil` for `followZoom`. 21.5 since 1.59.0 (PM, Monday "Zoom level", 2026-11-20: 22 is too
    /// close); 22 since 1.56.0 (operator, K-39, 2026-11-19: the map zooms in when the visitor
    /// enters a gallery); `nil` before, and personalised journeys only. Above `maximumZoom` the map
    /// stops at `maximumZoom`.
    public var galleryFollowZoom: Double? = 20
    /// The journey map shows the visitor at this zoom for `startZoomSeconds` before it follows them:
    /// when the journey starts, on the first fix and when the position comes back. `nil` follows at
    /// once (PM, Monday "Zoom level at start + navigation", 2026-10-29 and 2026-10-30).
    public var startZoom: Double? = 17
    /// How long the journey map stays at `startZoom`.
    public var startZoomSeconds: TimeInterval = 2
    /// The height in points over which the journey map fades out at the top of its card, under the
    /// Map / List control. The faded part shows what the host app draws behind `ProximiMapView`.
    /// 0: no fade.
    public var mapTopFadeHeight: Double = 110
    /// The height in points over which the journey map fades out at the bottom of its card, under
    /// the stop card. 0: no fade.
    public var mapBottomFadeHeight: Double = 170
    /// `true` shows journey stop markers that would overlap as one marker with a badge holding the
    /// number of the others (PM, Monday "Clustering", 2026-10-29).
    public var groupsStopMarkers = true
    /// The opacity of the position dot without new positions and in a privacy zone, 0 to 1. The dot
    /// turns grey after the map library's stale time and stays at this opacity; its accuracy ring does
    /// not grow. 0 hides the dot, as before 1.45.0 (user, 2026-11-15).
    public var positionWithoutFixesOpacity: Double = 0.45
    /// `true` shows a journey artwork without a numbered marker as a dot without a number: an artwork
    /// in a gallery the visitor is not in, a skipped artwork, and every artwork while the route leads
    /// to a gallery. `false`, the default since 1.44.0, shows nothing there (GAD PM, 2026-11-15: on hold).
    public var showsStopDots = false
    /// `true` shows the number of a journey artwork in its marker on the map, on the stop card and
    /// in the list. `false`, the default since 1.50.0, shows the same circles without the number
    /// (operator, 2026-11-17). The badge of grouped markers keeps its count (`groupsStopMarkers`).
    public var showsStopNumbers = false
    /// `true` draws a pin icon in the marker of a journey artwork on the map and, since 1.60.0, in
    /// the badge of its row in the journey list, while `showsStopNumbers` is `false`: white in the marker of the current artwork, dark in the others
    /// (RPR design; PM, Monday "Icons for personalized routes", 2026-11-20). `false` shows the
    /// circles alone, as before 1.59.0. The detour's marker and the stop dots have no pin.
    public var showsStopIcons = true
    /// `true` draws a gallery's name label on the journey map in the shape of the gallery's type, as
    /// the museum's floor plan does: a pill for a single-artist gallery, a rectangle with square
    /// corners for a thematic one (operator, 2026-11-20). The type is the title of the amenity of
    /// the gallery's POI. A gallery of no known type has the pill. `false` draws every label as a
    /// pill, as before 1.61.0.
    public var shapesGalleryLabelsByType = false
    /// `true` orders the stops ahead of a personalised journey again from the visitor when an artwork
    /// is marked visited while the visitor stands in another gallery than the next stop's, and that
    /// gallery has an artwork still to visit. `false` keeps the order, as before 1.46.0.
    public var ordersFromVisitorGallery = true
    /// Seconds between two uploads of the field log to the relay-api. `ProximiMap` starts the uploads
    /// in `start()` with the relay base URL and app token of its `GADConfiguration`. 0 sends nothing.
    /// A host app on `ProximiMapView` calls `FieldLog.startUploading(binding:interval:)` itself.
    public var fieldLogUploadInterval: TimeInterval = 900
    /// The farthest the visitor can zoom out, or `nil` for the map library's limit. MapLibre zoom
    /// levels. The camera keeps to the range in every frame the map sets too (`MapOptions`).
    /// 15 since 1.34.0 (user, 2026-11-03).
    public var minimumZoom: Double? = 15
    /// The farthest the visitor can zoom in, or `nil` for the map library's limit. 22 since 1.56.0,
    /// for `galleryFollowZoom`; 21 since 1.34.0 (user, 2026-11-03).
    public var maximumZoom: Double? = 22
    /// The box the screen stays inside, or `nil` for no limit. It holds for gestures and for every
    /// camera move the map makes, on the journey map and the Explore Museum map
    /// (`MapOptions.cameraBounds`, map 6.0.0-beta.62). The map stops zooming out where the box
    /// covers the view, so a `minimumZoom` below that zoom is not reached. The default is the PM's
    /// box around the museum (Monday "Zoom out limit", 2026-11-10).
    public var cameraBounds: GADCameraBounds? = .guggenheimAbuDhabi
    /// `true` picks the first gallery on a floor and the gallery after a finished one by routed
    /// walking time (`JourneyOrderStrategy.floorThenGalleryRouted`, map 6.0.0-beta.62). `false`
    /// picks them by straight-line distance, as before 1.37.0. A stop without a route uses the
    /// straight line in both (PM, Monday "First stop over birds flight vs along the route").
    public var ordersGalleriesByWalkingTime = true
    /// `false` draws the position dot on each fix. `true` slides it toward each fix (the map
    /// library's adaptive smoothing), which shows a fix a moment later (PM, Monday "Visual delay",
    /// 2026-10-23).
    public var smoothsPosition = false
    /// Seconds the heading-up map takes to turn to a new heading (`MapOptions.bearingSettlingTime`,
    /// map default 0.9). Nagarro found the rotation too fast (2026-10-29).
    public var bearingSettlingTime: TimeInterval = 1.5
    /// Heading changes smaller than this, in degrees, do not turn the map (`MapOptions.bearingDeadband`,
    /// map default 0).
    public var bearingDeadband: Double = 5
    /// The longest time in seconds the maps show their spinner while the map library draws the
    /// venue. The spinner goes when the venue's features are on the map, when the map reports an
    /// error, or after this time.
    public var mapLoadingTimeout: TimeInterval = 20
    /// The smallest width and height in metres of the area the map shows for an amenity picked in
    /// the menu, so a near amenity does not zoom the map in further than this.
    public var amenityFramingMinimumMeters: Double = 40
    /// The Explore Museum map opens on the spaces whose centre is at most this far from the median
    /// centre of all spaces, so a space far from the building does not shrink the museum on the
    /// screen (PM, on site, 2026-11-19). `nil` frames every space, as before 1.58.0.
    public var exploreFramingMaximumMeters: Double? = 150

    // MARK: Lift

    /// Seconds of fixes inside a lift outline before the visitor counts as riding it. A shorter
    /// stay is walking past the lift.
    public var liftRideDwell: TimeInterval = 3
    /// Consecutive fixes outside the lift outline that end the ride.
    public var liftExitFixes: Int = 2

    // MARK: Floors without positioning

    /// Floors without positioning. A route there leads to the lift or stairs, shows the lift or
    /// stairs view, then shows that floor with the rest of the route. In stage 1 the GAD level 0
    /// has no positioning (PM 2026-10-14).
    public var levelsWithoutPositioning: Set<Int> = [0]
    /// Metres from the lift or stairs to a floor without positioning at which the visitor counts as
    /// there.
    public var levelChangerReachedMeters: Double = 5
    /// Seconds of the lift or stairs view before the map shows the floor without positioning.
    public var levelChangeViewSeconds: TimeInterval = 5
    /// After the lift or stairs view the map shows the floor the ride ends on until a fix on another
    /// floor than the ride's start, or a fix on that floor this many metres from the lift or stairs
    /// (PM, Monday "Elevator/Staircase animation", 2026-10-28).
    public var rideFloorHoldMeters: Double = 20
    /// Seconds after which the map follows the visitor again when the destination on a floor
    /// without positioning did not change.
    public var floorWithoutPositioningMaximumSeconds: TimeInterval = 1800

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
    /// Gallery first: a leg leads to an artwork's gallery only when the artwork lies in the gallery's
    /// geofence on the same floor, or at most this many metres outside it. Otherwise the leg ends at
    /// the artwork. In the GAD data of 2026-10-19, 34 artworks lie 5–29 m outside their gallery's
    /// geofence.
    public var galleryFirstMarginMeters: Double = 50

    // MARK: Live Activity

    /// The shortest gap in seconds between two Live Activity updates of the instruction. A new
    /// step is sent at once.
    public var liveActivityMinimumInterval: TimeInterval = 5

    // MARK: Position barriers

    /// How walls drawn as barrier features stop a position that jumps through them
    /// (`ProximiioConfiguration.positioning.barriers`, SDK 6.0.0-beta.71). The default is the SDK's:
    /// on, 10 positions on a floor before any is stopped, 2 m/s walking speed, 0.4 m from the wall,
    /// and the newest position accepted again after 10 stopped positions over 5 s. No effect in a
    /// venue without barrier features. `ProximiMap` sets it when it starts the SDK; `ProximiMapView`
    /// uses the host app's SDK configuration.
    public var positionBarriers = BarrierConfiguration()

    // MARK: Notifications

    /// Posts a notification for every geofence enter and exit event, and asks for notification
    /// authorization once a wristband is connected. `ProximiMap` then sets the delegate of
    /// `UNUserNotificationCenter`; a host app with its own delegate turns this off.
    public var postsGeofenceNotifications = true
    /// With `postsGeofenceNotifications`: `false` posts no geofence notification, while the
    /// authorization and the foreground banners of the host app's own notifications stay.
    public var notifiesGeofenceEvents = true

    // MARK: Venue data

    /// No effect since 1.8.0. The screens follow `Proximiio.venueDataChanges()`, and the SDK's audit
    /// sync brings the changed features (`ProximiioConfiguration.syncInterval`).
    @available(*, deprecated, message: "No effect: the venue data follows Proximiio.venueDataChanges(). Set ProximiioConfiguration.syncInterval instead.")
    public var venueDataRefreshInterval: TimeInterval = 300

    public init() {}

    /// The defaults.
    public static let standard = GADSettings()
}

/// A box in degrees that limits the map camera (`GADSettings.cameraBounds`).
public struct GADCameraBounds: Equatable, Sendable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// The PM's box around the Guggenheim Abu Dhabi (Monday "Zoom out limit", 2026-11-10).
    public static let guggenheimAbuDhabi = GADCameraBounds(
        south: 24.53557985, west: 54.39348543, north: 24.54644005, east: 54.40758853
    )
}
