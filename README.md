# ProximiioGADKit

ProximiioGADKit is a Swift package with the museum map, the journey (map and list), the stop picker
and Manage journey of the Proximi GAD app (Guggenheim Abu Dhabi), and the wristband binding. It is
built on the Proximi.io iOS SDK and Map.

The host app uses one entry point, `ProximiMap`:

- it creates one `ProximiMap` and starts it;
- it attaches `.proximiMap(_:)` to a view that stays on screen;
- it opens screens with `open(_:)`;
- it receives every change as a `ProximiMapEvent`.

`ProximiMap` owns the SDK, the wristband session, the stored journey, the notifications and every
screen and sheet of the package. The host app scans the wristband's QR code itself and passes the
code to `connectWristband(code:)`. The Proximi GAD app uses the package the same way.

| Product | Add to | Content |
|---|---|---|
| `ProximiioGADKit` | The app target | `ProximiMap` and its types, `GADConfiguration`, `GADSettings`, `FieldLog`. |
| `ProximiioGADLiveActivity` | The widget extension | `VisitActivityAttributes` and `VisitActivityWidget`. |

## Requirements

- iOS 17 or later. Swift 6 language mode (`swift-tools-version: 6.0`).
- SwiftUI host app.
- Built and tested with Xcode 26.3 and Xcode 27.
- Read access to this repository. The SDK and Map binary packages are public.

## Adding the package

In Xcode: File → Add Package Dependencies → `https://github.com/proximiio/proximiio-gadkit-ios`,
dependency rule "Up to Next Major Version" from `1.0.0`. The versions are the git tags of this
repository. From 1.0.0 a minor or patch version does not break the public API. New `ProximiMapEvent`
cases come in minor versions; a `switch` with `default` keeps compiling. The [Changelog](#changelog)
lists every change; changes that need a change in the host app are marked **Breaking**.

`Package.swift` pins `proximiio-sdk-ios-binary` 6.0.0-beta.59 and `proximiio-map-ios-binary`
6.0.0-beta.44 exactly. The host app needs no dependency on them. A host app that also depends on
these packages must use the same versions.

## Host app setup

### Info.plist

| Key | Why |
|---|---|
| `NSLocationWhenInUseUsageDescription` | `start()` requests location authorization. The relay-api needs a fix for a wristband take-over. |
| `NSLocationTemporaryUsageDescriptionDictionary` → `WristbandTakeover` | Asked when the visitor allowed approximate location only and a take-over needs a precise fix. |
| `NSCameraUsageDescription` | The host app's QR code scanner. |
| `UIBackgroundModes` → `location` | Positions keep arriving while the phone is locked. |
| `NSSupportsLiveActivities` = `YES` | The journey Live Activity. |
| `NSBluetoothAlwaysUsageDescription`, `NSMotionUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSNearbyInteractionUsageDescription` | Never requested. App Store processing requires them because the SDK binary references these APIs (ITMS-90683). |

### Languages

The package ships English and Arabic strings. The host app also declares English and Arabic
(`CFBundleLocalizations`, or Known Regions in the project), so the language setting of the app applies
to the package screens too.

### Fonts

The package registers Guggenheim Sans Display for its screens. The host app lists no fonts.

The widget extension does not register fonts. Add `GuggenheimSansDisplay-Regular.ttf`, `-Medium.ttf`
and `-Bold.ttf` from `Sources/ProximiioGADKit/Resources/Fonts` to the extension and list them in its
`UIAppFonts`.

## Quick start

```swift
import ProximiioGADKit
import SwiftUI

@main
struct MuseumApp: App {
    // One ProximiMap for the life of the app, for example from the DI container.
    @State private var map = ProximiMap(configuration: GADConfiguration(
        apiBaseURL: URL(string: "https://api.example.com")!,
        applicationToken: applicationToken,
        relayAPIBaseURL: URL(string: "https://relay-api.example.com")!,
        relayAPIAppToken: relayAPIAppToken
    )!)

    var body: some Scene {
        WindowGroup {
            HomeView(map: map)
                .proximiMap(map)                    // the package's screens open over this view
                .task { try? await map.start() }
                .task {
                    for await event in map.events {
                        switch event {
                        case .artworkReached(let stop): print("At \(stop.artworkID ?? stop.title)")
                        case .craftNewJourneyRequested: print("Show the audio guide")
                        default: break
                        }
                    }
                }
        }
    }
}

struct HomeView: View {
    let map: ProximiMap

    var body: some View {
        Button("Museum map") { map.open(.museumMap) }
        Button("Start the guide's journey") {
            try? map.setJourney(JourneyPlan(title: "Light & Perception", artworks: ["GAD.2010.00033", "GAD.2018.00034"]))
            map.open(.journeyReady)
        }
    }
}
```

## ProximiMap

`ProximiMap` is `@MainActor` and `@Observable`: SwiftUI views that read its properties update with
them.

| Member | |
|---|---|
| `init(configuration:)` | Creates the wristband session. Starts nothing. |
| `start() async throws` | Starts the SDK, the wristband session and the notifications, and loads the venue. Asks for "While Using the App" location. A second call while starting waits for the first; after a failure it starts again. Throws `ProximiMapError.startFailed`. |
| `status` | `.idle`, `.starting`, `.ready` or `.failed(ProximiMapError)`. For a splash or a retry screen. |
| `connectWristband(code:) async throws` | See "Wristband". |
| `endVisit() async throws` | Ends the wristband session on the relay-api, for example when the visitor returns the wristband. |
| `wristband` | `WristbandStatus`: `.notConnected(notice:)`, `.connecting`, `.connected`. |
| `setJourney(_:) throws -> JourneySummary` | Stores a journey. See "Journeys". |
| `deleteJourney()` | Deletes the stored journey. |
| `journey` | `JourneySummary?` of the stored journey: title, summary, kind, `stopCount`, `remainingStopCount`, `isStarted`. It survives app launches. |
| `open(_:)` | Shows a screen. See "Screens". |
| `close()` | Closes the screen or sheet on screen. |
| `screen` | The screen or sheet on screen, or `nil`. |
| `events` | `AsyncStream<ProximiMapEvent>`. Each access returns a new stream; it ends when its task is cancelled. |
| `isAtMuseum` | `true` after a wristband or playback position, or a phone fix within 400 m of a place of the venue. |
| `isLocationDenied` | `true` when the visitor denied location for the app. The host app can show its own screen for it. |
| `routeAccessibility` | The visitor's accessibility needs for routes. See "Accessibility". |

`start()` creates the SDK (`ProximiioConfiguration.relayOnly`, no fallback host), authenticates,
starts positioning, loads the route network and attaches the wristband's position provider. Visitor
reporting is on. Call it at launch: the map style and the venue data are then loaded before the first
map screen. The package contacts only `apiBaseURL` and the relay-api host.

## Screens

`open(_:)` shows a screen over the view with `.proximiMap(_:)`. A screen already on screen closes
first. Nothing opens before `start()` has finished.

| `ProximiMap.Screen` | Shows | Inside the flow |
|---|---|---|
| `.museumMap` | The museum map: floors, amenities, the visitor's position, search, a route to a tapped place, the gallery legend. | Back closes it. |
| `.journeyReady` | Journey ready (02.10A): the journey's title and summary. Needs a stored journey. | "Start the Journey" (at the museum) opens the journey. "Go to Museum" (away from it) and "Back to Hub" close it. |
| `.journey` | The journey: map and list, the stop card, guidance from stop to stop, detours to amenities, the Live Activity, Journey Complete. Needs a stored journey. | Back on a journey in progress (a stop visited or skipped, not finished) asks "Leave the tour here" first; otherwise it closes. |
| `.planJourney` | The stop picker ("Plan your visit"). | "Start" stores a personalised journey and opens Journey ready. |
| `.manageJourney` | Manage journey (02.11). Needs a stored journey. | "Edit stops" opens the stop picker, or sends `curatedTourChangeRequested` for a curated tour. "Craft a new journey" sends `craftNewJourneyRequested`. "Delete journey", then "Delete this journey", deletes it. |

- The museum map, Journey ready and the journey are full-screen covers. The stop picker and Manage
  journey are sheets.
- `ProximiMapEvent.closed(_:)` follows when a screen closes.
- Call `open(_:)` from a sheet of the host app after that sheet has been dismissed (its `onDismiss`).
  Presenting while another presentation is dismissing can fail.
- The journey screen saves its progress on every change. Journey ready and the journey read the
  stored journey when they open.

## Journeys

```swift
let summary = try map.setJourney(JourneyPlan(
    title: "Light & Perception",
    summary: "6 artworks · 45 min",       // nil shows "6 stops"
    kind: .personalised,
    artworks: ["GAD.2010.00033", "GAD.2018.00034"]
))
map.open(.journeyReady)
```

- `artworks` are in visit order. Each one is an artwork's collection id (`remote_id`) or a Proximi.io
  POI id. Ids that match no POI are left out; `summary.stopCount` is the number kept.
- `setJourney(_:)` throws `ProximiMapError.notStarted` before `start()` has finished, and
  `.noKnownArtworks` when no id matches.
- A new journey replaces the stored one. `ProximiMapEvent.journeyChanged(_:)` follows every change.

A journey the visitor built with the guide is `.personalised`; a tour by the museum's curators is
`.curated` (Figma "Personalised" and "Guided"):

| | `.personalised` | `.curated` |
|---|---|---|
| Stop card | Names the gallery of the next stop until the visitor is in it, then the artwork. | Names the artwork. |
| List | Stops under gallery names. | Stops without gallery names. |
| Skip | The visitor can skip an artwork. | No skip. |
| Order | Ordered floor by floor and gallery by gallery from the visitor, at the start and after a detour or an artwork visited out of order. | The curators' order. An artwork visited out of order is marked visited; the rest keep their order. |

The map and the background are the same for both.

## Wristband

The host app scans the wristband's QR code, or the visitor types the code printed on it:

```swift
do {
    try await map.connectWristband(code: scannedCode)
} catch {
    errorText = error.localizedDescription   // the text for the visitor, English or Arabic
}
```

- `connectWristband(code:)` trims the code and sends it to the relay-api, which resolves every label
  format. When the relay-api needs the phone's location for a take-over, the iOS location dialog comes
  first. It returns when the session is active. It throws `ProximiMapError.wristband` with the text
  for the visitor, for example "This wristband is already in use. Please ask the staff."
- A wristband that another phone follows is taken over when the relay-api allows it. The other phone's
  session ends; its `wristband` becomes `.notConnected(notice:)` with "Your wristband was scanned by
  another phone. Connect it again to follow it on this phone."
- Positions arrive only while `wristband` is `.connected`. A session stored by the SDK is confirmed
  with the relay-api after `start()`.
- The package shows no wristband alerts. `ProximiMapEvent.wristbandChanged(_:)` and
  `trackingChanged(_:)` let the host app show its own.

## Events

`ProximiMap` performs every action itself; the events report them. They arrive on the main actor.

| Event | When |
|---|---|
| `opened(Screen)`, `closed(Screen)` | A screen opened or closed, by `open(_:)` or inside a flow. |
| `craftNewJourneyRequested` | "Craft a new journey" on Manage journey, after it closed. The host app shows its journey crafting. |
| `curatedTourChangeRequested` | "Edit stops" on Manage journey for a curated tour, after it closed. The host app shows its tour choice. |
| `arrivedAtMuseum` | `isAtMuseum` became `true`. Once per launch. |
| `wristbandChanged(WristbandStatus)` | The wristband session changed. |
| `trackingChanged(TrackingHealth)` | During a journey: the wristband's positions stopped (`lostPlace` after `trackingLostAfter`, `stoppedResponding` after `trackingStoppedAfter`) or came back (`tracking`). |
| `geofenceEntered(ProximiGeofence)`, `geofenceExited(ProximiGeofence)` | Every geofence enter and exit, with or without a journey. An artwork geofence has `type` `artwork` and the collection id in `artworkID`. |
| `journeyChanged(JourneySummary?)` | A new, planned, edited or deleted (`nil`) journey, and the progress after the journey screen closed. |
| `nextStop(ProximiStop)` | The route leads to this stop now. |
| `stopNearby(ProximiStop)` | The active stop is less than `stopNearbyMeters` away on the visitor's level. Once per stop. |
| `artworkReached(ProximiStop)` | `artworkAdvanceDelay` after the visitor entered the artwork geofence of the active stop, or stood in its area: the stop is done and the route leads to the next stop. `geofenceEntered` arrives at the enter. |
| `artworkVisitedOutOfOrder(ProximiStop)` | The visitor stayed at an artwork further down the journey. It counts as visited. In a personalised journey the stops ahead are ordered again; a curated tour keeps its order. |
| `skipRequested`, `stopSkipped`, `skipCancelled`, `skipUndone` (`ProximiStop`) | A swipe on a stop in the list, "Skip artwork", "Keep it", "Undo skip". |
| `amenitySelected(ProximiStop)` | An amenity picked on the map. A card shows it with "Go here". |
| `detourStarted(ProximiStop)`, `detourEnded(ProximiStop, completed:)` | "Change your route?" confirmed; the detour reached (`completed`) or left. |
| `journeyResumed` | "Resume your Journey" or "Show the route from here". |
| `offRoute(duration:)`, `backOnRoute` | The visitor has been off the route for `offRouteSeconds`; the visitor is on the route again. |
| `journeyFinished` | Every stop is visited or skipped. Journey Complete shows. |
| `floorWithoutPositioningEntered(level:)`, `floorWithoutPositioningLeft(level:)` | See "Floors without positioning". |
| `modeChanged(VisitMode)`, `recentred`, `accessibleRoutesChanged(Bool)` | The Map / List toggle, "Centre on me", the accessible routes button. |
| `exitRequested`, `exitConfirmed`, `exitCancelled` | Back during a journey in progress (a stop visited or skipped, not finished), "Leave the tour", "Carry on". |

The museum map sends only `opened` and `closed`; the other screen events come from the journey screen.

`ProximiStop` has the POI `id`, the `title`, the artwork's collection id `artworkID` (`nil` for an
amenity) and the `level`.

## Settings

Every time and distance of the screens is in `GADSettings`. Set them in the configuration:

```swift
var settings = GADSettings()
settings.offRouteMeters = 50
settings.postsGeofenceNotifications = false
let configuration = GADConfiguration(
    apiBaseURL: apiBaseURL, applicationToken: applicationToken,
    relayAPIBaseURL: relayAPIBaseURL, relayAPIAppToken: relayAPIAppToken,
    settings: settings
)
```

| Setting | Default | Effect |
|---|---|---|
| `trackingLostAfter` | 110 s | Seconds without positioning before `ProximiMapEvent.trackingChanged(.lostPlace)`. The SDK reports positioning unavailable about 10 s after the last fix: about 2 min. |
| `trackingStoppedAfter` | 170 s | Seconds without positioning before `ProximiMapEvent.trackingChanged(.stoppedResponding)` (about 3 min). |
| `artworkAdvanceDelay` | 2 s | From the arrival at an artwork (its geofence) to the route to the next stop. |
| `outOfOrderDwell` | 0 s | Time inside another artwork's geofence before it counts as visited out of order. |
| `amenityArrivalMinimumMeters`, `amenityArrivalMaximumMeters`, `amenityArrivalDwell` | 5 m, 10 m, 5 s | An amenity is reached within 2.5 × the position accuracy, within these bounds, for this time. |
| `stopNearbyMeters` | 5 m | The "next stop is less than … m away" notification. |
| `offRouteMeters`, `offRouteSeconds` | 30 m, 300 s | "You've left your route": this far from the route, or off it this long. |
| `routeSnapMeters` | 0.5 m | The dot is drawn on the route within this distance. Display only. |
| `followZoom` | 21 | Zoom of "Centre on me" and of the first position. |
| `liftRideDwell`, `liftExitFixes` | 3 s, 2 | Seconds of fixes inside a lift outline before the visitor counts as riding it, and the fixes outside that end the ride. The field log records the rides. |
| `levelsWithoutPositioning` | [0] | Floors without positioning. See "Floors without positioning". |
| `levelChangerReachedMeters` | 5 m | Distance from the lift or stairs to a floor without positioning at which the lift or stairs view shows. |
| `levelChangeViewSeconds` | 5 s | How long the lift or stairs view shows before the map shows the floor without positioning. |
| `floorWithoutPositioningMaximumSeconds` | 1800 s | After this time on a floor without positioning with the same destination, the map follows the visitor again. |
| `uncertainAccuracyMeters`, `locationQuestionQuietPeriod` | 8 m, 120 s | "Probably at …": an uncertain position near the next stop, and how long an answered prompt stays quiet. |
| `firstFixWait`, `lateOrderWindow` | 5 s, 60 s | A new personalised journey waits this long for a fix before it is ordered without one, and the first fix within the window orders it again. |
| `liveActivityMinimumInterval` | 5 s | The shortest gap between two Live Activity updates of the instruction. |
| `postsGeofenceNotifications` | `true` | A notification for every enter and exit of a geofence with a name, and the notification authorization request once a wristband is connected. The "next stop" notification of the journey (`stopNearbyMeters`) does not depend on it. It sets the `UNUserNotificationCenter` delegate, which shows them in the foreground. A host app with its own delegate turns it off. |

## Artwork details in the list

A journey list row shows the artist and "AR" and audio badges from the artwork's POI
`properties.metadata`. Without `artist_name` the row shows the level.

| Key | Value | Shows |
|---|---|---|
| `artist_name` | String, or an i18n object like `title_i18n` | The artist under the title. |
| `has_ar` | `true` | "AR". |
| `has_audio` | `true` | A note. |

The GAD venue data on 2026-10-14 has none of the three keys.

### Gallery headers

In a personalised journey the list shows a header before the stops of each gallery. The gallery of
an artwork is its `metadata.gallery_id`, named by the title of the POI whose
`remote_id` is that id ("G403 Weaving"). An artwork without one is under the gallery outline it lies
in, else under its level ("Level 4"). The GAD venue data on 2026-10-15 has `gallery_id` on artworks in
18 galleries; 14 of the 18 have a gallery POI.

## Floors without positioning

A floor in `GADSettings.levelsWithoutPositioning` has no positioning. In stage 1 that is the GAD
level 0, with the café and the prayer room. A route there, on the journey map and the museum map:

1. leads to the lift or stairs as usual;
2. within `levelChangerReachedMeters` of the lift or stairs, shows the lift or stairs view ("Take the
   stairs to level 0", "Your position is not shown on this level.") for `levelChangeViewSeconds`; a tap
   ends it;
3. shows that floor with the rest of the route. The map does not follow the visitor there, no
   off-route warning shows, the position is not checked against artwork geofences (their enter events
   still count), and the card says that the position is not shown.

The map follows the visitor again when the destination changes ("Resume your Journey", another stop
or route), on "Centre on me" or the floor button, or after `floorWithoutPositioningMaximumSeconds`.
The journey screen sends `floorWithoutPositioningEntered(level:)` and `floorWithoutPositioningLeft(level:)`.
The view shows the lift or stairs icon until the animation from the design team exists.

## Accessibility

The host app sets the visitor's accessibility needs. Every route then avoids what they name, and a
change re-routes the route on screen:

```swift
map.routeAccessibility = RouteAccessibility(avoidsStairs: true, avoidsRevolvingDoors: true)
```

| Need | Avoids, where the venue data marks it |
|---|---|
| `avoidsStairs` | Level changers with `type` `staircase`. |
| `avoidsEscalators` | Level changers with `type` `escalator`. |
| `avoidsRevolvingDoors` | Path pieces within `radius` of a `door` point feature. |
| `avoidsInaccessiblePaths` | Routing paths with `narrowPath: true`. |

- The GAD venue data on 2026-10-14 has staircases and elevators. It has no escalators, no `door`
  features and no `narrowPath` paths, so only `avoidsStairs` changes routes until the data has them.
- The museum map and the journey map have an accessible routes button (a wheelchair, blue while on).
  While it is on, routes avoid all four (`RouteAccessibility.accessible`), whatever the host app set.
  Its state is kept on the device for both maps and later launches.
- When no route meets the needs, the museum map shows "No route from here with your accessibility
  settings." In a journey, the stop card shows "No route to this stop with your accessibility
  settings." and the stop keeps its place; in a personalised journey the visitor can skip it in the
  list.

## Live Activity

The journey screen starts, updates and ends the Live Activity. The widget extension shows it:

```swift
import ProximiioGADLiveActivity
import SwiftUI
import WidgetKit

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
        VisitActivityWidget()
    }
}
```

## Field log

`FieldLog` writes positions, tracking health, geofence, journey, binding and `ProximiMap` events to
`Documents/gad-debug.log`. It is off by default. Turn it on at launch, before `start()`, in test
builds only:

```swift
FieldLog.isEnabled = true
FieldLog.logLaunch()
```

`FieldLogShareButton()` opens the share sheet with the file.

## Debug builds

In the Debug configuration `start()` reads these launch arguments:

| Argument | Effect |
|---|---|
| `-journeyPlayback <journey id>` | Plays a journey stored on Proximi.io instead of the wristband. |
| `-journeySpeed <x>` | Playback speed. Default 1. |
| `-journeyLoop` | Restarts playback after the last waypoint. |
| `-listJourneys` | Prints the organisation's places and journeys with their ids. |
| `-pairWristband <code>` | Binds the wristband after the start. Ignored with `-journeyPlayback`. |
| `-visit "<title>,<title>,…"` | Stores a journey through the first place matching each title and opens it. |
| `-visitKind personalised\|curated` | With `-visit`: the kind of journey. Default personalised. |
| `-visitList` | The journey opens in List mode. |
| `-visitAutoAdvance` | The journey advances 5 m after the visitor leaves a stop. |
| `-openMap` | Opens the museum map. |
| `-routeTo <title>` | With `-openMap`: routes to the first place whose title matches, after the first position. |
| `-routeAvoid stairs,escalators,revolvingDoors,inaccessiblePaths` | Sets `routeAccessibility`. |

Sandbox data (GAD Sandbox organisation):

| Kind | Value |
|---|---|
| Hosts | `https://api.proximi.fi`, `https://relay-api-sandbox.proximi.fi` |
| Test wristbands | `1000054522`, `1000045550`, `1000045662` |

Journeys of the GAD Sandbox organisation on 2026-10-14, for `-journeyPlayback <journey id>`. Each one
passes the SDK's `ProximiioJourney.validate()`. `-listJourneys` prints the current list.

| Journey | Id | Waypoints | Path length |
|---|---|---|---|
| Guggenheim walk 1 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:c77dfca6-07fd-4c19-bf76-fb92bfdf361c` | 21 | 131 m |
| Guggenheim walk 2 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:8c42ce38-c787-4adf-b424-ae7a33a75cce` | 8 | 153 m |
| Guggenheim walk 3 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:5bea514e-ad20-416a-bccc-dda10ea7e880` | 18 | 235 m |
| Guggenheim walk 4 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:57fbece2-7e6f-4c60-a00d-68f9e8e8c0e3` | 12 | 242 m |
| Guggenheim walk 5 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:09ecc5b7-ec2b-4362-849b-d9cc8f670919` | 17 | 200 m, two floors |
| Guggenheim walk 6 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:0bc12bdf-c0e5-491e-b7af-ec743831b85a` | 3 | 98 m |
| Guggenheim walk 7 | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:5bebd389-4f28-4e53-814f-b1ef829fcc3c` | 26 | 131 m |
| Guggenheim walk Test | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:06ffcc22-d033-4186-af80-c65499902cd4` | 4 | 107 m |
| Guggenheim Highlighted Tour | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:6718c69c-37e6-4a28-bd44-00aa35c46b2f` | 25 | 495 m |
| DCT Office walk | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:99a3beee-65cc-43c4-9b35-9e6dbee06e09` | 8 | 34 m, at the DCT office, not the museum |
| Test DCT Walk_Pranav | `7405e6e6-d9f6-4146-adda-de6adbf4a8a1:b9aab2da-09fc-4371-bb46-7071fc010c2f` | 3 | 14 m, at the DCT office, not the museum |

## Privacy

- The SDK reports the visitor to `apiBaseURL`: a visitor id, positions at most every 10 s (or after
  5 m), and geofence enter and exit events. Positions are uploaded every 60 s, when the app goes to the
  background and when it terminates. Geofence enter and exit events are sent as they happen. Without
  network they wait on the device and go out once the network is back. The client requires no consent
  prompt for it.
- Every request to `apiBaseURL` carries the headers `X-Visitor-Id` (the visitor id) and
  `X-Proximiio-SDK` (the SDK version). The API limits the request rate per device by `X-Visitor-Id`. A
  proxy in front of an on-premises API must pass both headers through.
- The SDK's privacy manifest declares Precise Location (App Functionality, Analytics) and Device ID
  (App Functionality, Analytics), neither linked to the user nor used for tracking. Device ID is the
  anonymous visitor id (analytics and the rate limit) and the wristband binding id, which only the
  relay-api receives. The host app's App Store privacy details declare the same.
- `ProximiMap.start()` asks for "While Using the App" location only.

## Tests

```
xcodebuild test -scheme ProximiioGADKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Changelog

Every version is a git tag. **Breaking** marks a change that needs a change in the host app's code or
dependencies; the entry says what to change. Entries before 1.0.0 name the types of the API before
`ProximiMap`.

### 1.0.1 (2026-10-16)

Fixed (documentation only):

- `artworkReached` arrives `artworkAdvanceDelay` after the arrival, when the stop is done.
- `artworkVisitedOutOfOrder` orders the stops ahead again in a personalised journey only.
- Back asks first only on a journey in progress; the button is "Leave the tour".
- "Delete journey" asks "Delete this journey" first.
- `postsGeofenceNotifications`: geofences with a name only; the "next stop" notification does not
  depend on it.
- On a floor without positioning only the position check against artwork geofences stops.
- The museum map sends only `opened` and `closed`.

### 1.0.0 (2026-10-16)

One entry point, `ProximiMap`, replaces the screens and services of 0.15.0 (Nagarro, 2026-10-16: "a
single exposed wrapper component that encapsulates all internal UI components and logic"). From
1.0.0 a minor or patch version does not break the public API.

Breaking:

- The dependency rule is "Up to Next Major Version" from `1.0.0`.
- These are no longer public; `ProximiMap` does what they did:

  | 0.15.0 | 1.0.0 |
  |---|---|
  | `VenueService.start(configuration:binding:)`, `WristbandSession(configuration:)` + `run()` | `ProximiMap(configuration:)` + `start()` |
  | `venue.sdk` | `ProximiMapEvent` (for example `geofenceEntered`, `artworkReached`). The host app does not use the SDK. |
  | `WristbandSession.connect(code:)`, `end()`, `state`, `endNotice`, `WristbandCopy.message(for:)` | `connectWristband(code:)`, `endVisit()`, `wristband`, `error.localizedDescription` |
  | `MuseumMapScreen`, `VisitView`, `JourneyReadyView`, `VisitPlanPicker`, `ManageJourneySheet` | `.proximiMap(_:)` and `open(.museumMap)`, `.journey`, `.journeyReady`, `.planJourney`, `.manageJourney` |
  | `VisitPlan.journey(poiIDs:places:)`, `VisitStore`, `VisitMeta` | `setJourney(JourneyPlan)`, `deleteJourney()`, `journey` |
  | `.onVisitEvent { VisitEvent }` | `for await event in map.events { ProximiMapEvent }` |
  | `.routeAccessibility(_:)` | `map.routeAccessibility` |
  | `GeofenceNotifier` | `GADSettings.postsGeofenceNotifications` (default `true`) |
  | `DebugLaunch.current.run(with:wristband:)` | `start()` reads the launch arguments in Debug builds. |
  | `VenuePlace`, `Gallery`, `VisitMeta`, `WristbandPairing`, `WristbandPairingView`, the design system (`Palette`, `TextStyle`, button styles, `GADFonts`) | Not for host apps. |

- `ProximiMapEvent` payloads are package types (`ProximiStop`, `ProximiGeofence`) instead of the map
  library's `JourneyStop` and `JourneyEvent`.

Added:

- `ProximiMap`: `start()`, `status`, `connectWristband(code:)`, `endVisit()`, `wristband`,
  `setJourney(_:)`, `deleteJourney()`, `journey`, `open(_:)`, `close()`, `screen`, `events`,
  `isAtMuseum`, `isLocationDenied`, `routeAccessibility`.
- `.proximiMap(_:)` presents the screens and sheets; one at a time, the next after the dismissal of the
  previous.
- Journeys by artwork collection id (`remote_id`) or POI id (`JourneyPlan.artworks`).
- `ProximiMapEvent.geofenceEntered` and `geofenceExited` for every geofence, with or without a journey.
- `nextStop`, `detourEnded`, `offRoute`, `backOnRoute` and `journeyFinished` events from the journey
  navigator.
- Manage journey sends `craftNewJourneyRequested` and, for a curated tour, `curatedTourChangeRequested`.
- `GADConfiguration(apiBaseURL:applicationToken:relayAPIBaseURL:relayAPIAppToken:settings:)` with a URL;
  the host app needs no SDK import.
- `GADSettings.postsGeofenceNotifications`.

- `isAtMuseum` and `arrivedAtMuseum`, moved from the Proximi GAD app. A phone fix counts within 400 m of
  any place of the venue. The app compared it with the mean of all places, which for the two GAD venues
  11 km apart is near neither.

### 0.15.0 (2026-10-15)

Breaking:

- SDK 6.0.0-beta.59 and Map 6.0.0-beta.44. A host app that depends on these packages moves to the
  same versions.
- The SDK's `BlueiotBindingError` has the cases `swapBandsApart`, `swapAtReception` and
  `signingUnavailable(retryAfter:)`. A `switch` over `BlueiotBindingError` without `default` needs the
  cases.
- The App Store privacy details declare Device ID for App Functionality as well as Analytics (see
  "Privacy").

Added:

- `WristbandCopy.message(for:)` has text for the three new binding errors: a refused swap to a new
  wristband ("Hold your current wristband next to the new one and scan again.", "Your wristband isn't
  reachable. Please swap it at the reception desk.") and the relay-api's signing outage ("The
  museum’s server is busy. Try again in a moment.").

Removed:

- The clear map background from 0.4.1. Map 6.0.0-beta.44 draws a clear background by default.

### 0.14.0 (2026-10-15)

Breaking:

- New `VisitEvent.floorWithoutPositioningEntered(level:)` and `floorWithoutPositioningLeft(level:)`. A
  `switch` over `VisitEvent` without `default` needs the cases.

Added:

- Floors without positioning (see the section): the lift or stairs view at the lift or stairs, then
  the map of that floor with the rest of the route, on the journey map and the museum map.
  `GADSettings.levelsWithoutPositioning` ([0]), `levelChangerReachedMeters` (5 m),
  `levelChangeViewSeconds` (5 s) and `floorWithoutPositioningMaximumSeconds` (1800 s).

Fixed:

- An amenity button picks the nearest place in the venue of the nearest one, then prefers the
  visitor's level. From level 1 of the Guggenheim the café button chose the DCT office café, on level 1
  but 11 km away, over the Guggenheim café on level 0.

### 0.13.0 (2026-10-15)

Breaking:

- `VisitView(venue:journey:kind:onClose:)` takes no `wristband`. Remove the argument.
- `wristbandConnectionScreen(_:)` is removed: `VisitView` no longer offers "Connect a wristband".
  Remove the modifier.
- New `VisitEvent.trackingChanged(TrackingHealth)`. A `switch` over `VisitEvent` without `default`
  needs the case.

Removed:

- The tracking alerts "We've lost your place" and "Your wristband has stopped responding", and the
  "Your wristband is no longer connected" sheet with its route to the Welcome Desk. The host app
  handles the wristband states (PM 2026-10-15).
- The level change animation over the map. The map still moves to the visitor's floor.

Added:

- `VisitEvent.trackingChanged(TrackingHealth)`: `tracking`, `lostPlace` after
  `GADSettings.trackingLostAfter`, `stoppedResponding` after `trackingStoppedAfter`.
- `.small(selected:strength:)`: the glass strength of `SmallButtonStyle`, `.light` by default.

Changed:

- Gallery headers in the journey list show the title of the POI whose `remote_id` is the artwork's
  `gallery_id` ("G403 Weaving"), not the name of the gallery geofence.
- The stop card and the instruction name the floor where a ride in one staircase or lift ends ("Take
  the stairs to level 4"). The SDK router splits a ride into one level change per floor, and the card
  named the first one ("level 3").
- Lifts, staircases and escalators show on their floor and on every floor in their `levels`, on the
  journey map and the museum map. The route's next one stays red.
- The amenity menu buttons use the frosted glass.

Fixed:

- An artwork with several geofences of the same `remote_id` is reached in any of them. Each DCT test
  artwork shares its `remote_id` with the Guggenheim artwork, and only the first geofence counted, so
  a visitor in the DCT geofence did not reach "DCT Mother/Earth", at the start of a journey or out of
  order.

### 0.12.0 (2026-10-15)

Added:

- `VenuePlace.galleryID`: the artwork's `metadata.gallery_id`.

Changed:

- Gallery headers in the journey list come from the artwork's `gallery_id`, named by the gallery
  geofence with that `remote_id`; else the gallery outline the stop lies in; else its level ("Level 4").

Fixed:

- The journey list is one flat list. After the journey was ordered again it showed rows of the older
  order (two rows numbered 25).

### 0.11.0 (2026-10-15)

Breaking:

- `VisitEvent.stopChosen` and `VisitEvent.galleryChosen` are removed. Remove these cases from a
  `switch`.
- `GADSettings.nearbyGalleryMeters` is removed.

Added:

- `GADSettings.liftRideDwell` (3 s) and `liftExitFixes` (2).

Changed:

- While the next stop is on another floor, the card names the route's next level change ("Take the
  stairs to level 3"), and the map marks that lift or stairs in red.
- The lift animation takes its floor from the route only when the route uses that lift.
- The amenity detour marker shows the amenity's icon.
- "Change your route?" is a card on the map with "Go here" and "Close", not a bottom sheet.
- A visit closes after its "Journey Complete", exit or wristband sheet is dismissed.

Removed:

- "Which one are you in?" and "Pick my stop manually".

### 0.10.0 (2026-10-14)

Added:

- `GADSettings`: every time and distance of the screens. `GADConfiguration(…, settings:)`, default
  `.standard`, and `VenueService.settings`.

### 0.9.2 (2026-10-14)

Changed:

- Map amenities of a kind the design draws (restrooms, café, help desk, prayer room, shop, stairs,
  elevator) use the design's 30 pt markers.

### 0.9.1 (2026-10-14)

Fixed:

- The journey list scrolls when a drag starts on a row (iOS 18 and later).

### 0.9.0 (2026-10-14)

Added:

- `JourneyKind.keepsOrder`.

Changed:

- A curated tour keeps the curators' order.

### 0.8.0 (2026-10-14)

Breaking:

- New `VisitEvent.accessibleRoutesChanged(Bool)`. A `switch` over `VisitEvent` without `default`
  needs the case.

Added:

- The accessible routes button on both maps, `RouteAccessibility.accessible` and
  `RouteAccessibility.accessibleRoutesKey`.
- Artist and AR and audio badges in the journey list from `metadata` (`VenuePlace.artist`, `hasAR`,
  `hasAudio`).

Removed:

- The tour colour background of curated tours (0.7.0).

### 0.7.0 (2026-10-14)

Added:

- `JourneyKind` and `VisitView(kind:)`, default `.personalised`; `VisitMeta.kind`.

Changed:

- Curated tours go straight to the artwork, list no galleries and have no skip.
- After an artwork visited out of order, the leg to the next stop starts from the visitor.

### 0.6.0 (2026-10-14)

Added:

- `RouteAccessibility` and `routeAccessibility(_:)`: avoid stairs, escalators, revolving doors and
  inaccessible paths.

### 0.5.0 (2026-10-14)

Breaking:

- SDK 6.0.0-beta.58 and Map 6.0.0-beta.43. A host app that depends on these packages moves to the
  same versions.

Changed:

- Geofence events are sent as they happen. See "Privacy".

### 0.4.1 (2026-10-14)

Changed:

- `VenueService.start` caches the map style.
- The map is clear instead of black until MapLibre draws its first frame.

### 0.4.0 (2026-10-14)

Breaking:

- The package is in this repository, not in `proximiio/guggenheim-ios`. Change the package URL.
- `DebugLaunch.openScreen` is removed.

### 0.1.0–0.3.0

Tags of `proximiio/guggenheim-ios`.
