# ProximiioGADKit

ProximiioGADKit is a Swift package with the museum map and the journey (map and list) screens of the
Proximi GAD app (Guggenheim Abu Dhabi) and the wristband binding, built on the Proximi.io iOS SDK and
Map. A host app with its own QR scanner passes the scanned wristband code to
`WristbandSession.connect(code:)`. The Proximi GAD app uses the package the same way a host app does.

| Product | Add to | Content |
|---|---|---|
| `ProximiioGADKit` | The app target | Screens, design system, SDK start, wristband session, field log. |
| `ProximiioGADLiveActivity` | The widget extension | `VisitActivityAttributes` and `VisitActivityWidget`. |

## Requirements

- iOS 17 or later. Swift 6 language mode (`swift-tools-version: 6.0`).
- Built and tested with Xcode 26.3 and Xcode 27.
- Read access to this repository. The SDK and Map binary packages are public.

## Adding the package

In Xcode: File → Add Package Dependencies → `https://github.com/proximiio/proximiio-gadkit-ios`,
dependency rule "Up to Next Minor Version" from `0.15.0`. The versions are the git tags of this
repository. Before 1.0, a minor version can change the API. The [Changelog](#changelog) lists every
change of each version; changes that need a change in the host app are marked **Breaking**.

`Package.swift` pins `proximiio-sdk-ios-binary` 6.0.0-beta.59 and `proximiio-map-ios-binary`
6.0.0-beta.44 exactly. A host app that also depends on these packages must use the same versions.

## Host app setup

### Info.plist

| Key | Why |
|---|---|
| `NSLocationWhenInUseUsageDescription` | `VenueService.start` requests location authorization. The relay-api needs a fix for a wristband take-over. |
| `NSLocationTemporaryUsageDescriptionDictionary` → `WristbandTakeover` | Asked when the visitor allowed approximate location only and a take-over needs a precise fix. |
| `NSCameraUsageDescription` | The host app's QR code scanner, or `WristbandPairingView`, which has one. |
| `UIBackgroundModes` → `location` | Positions keep arriving while the phone is locked. |
| `NSSupportsLiveActivities` = `YES` | The visit Live Activity. |
| `NSBluetoothAlwaysUsageDescription`, `NSMotionUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSNearbyInteractionUsageDescription` | Never requested. App Store processing requires them because the SDK binary references these APIs (ITMS-90683). |

### Languages

The package ships English and Arabic strings. The host app also declares English and Arabic
(`CFBundleLocalizations`, or Known Regions in the project), so the language setting of the app applies
to the package screens too.

### Fonts

The app target lists no fonts. The package registers Guggenheim Sans Display for the process when the
first text style is drawn (`GADFonts`). Call `GADFonts.register()` before `UIFont(name:size:)` with
these fonts.

The widget extension does not register fonts. Add `GuggenheimSansDisplay-Regular.ttf`, `-Medium.ttf`
and `-Bold.ttf` from `Sources/ProximiioGADKit/Resources/Fonts` to the extension and list them in its
`UIAppFonts`.

## Starting

```swift
import ProximiioGADKit

let configuration = GADConfiguration(
    apiBaseURL: URL(string: "https://api.example.com")!,
    applicationToken: applicationToken,
    relayAPI: BlueiotCloudRelayEndpoint(text: "https://relay-api.example.com")!,
    relayAPIAppToken: relayAPIAppToken
)
let wristband = WristbandSession(configuration: configuration)
Task { await wristband.run() }   // Follows the binding state. Call once at launch.
let venue = try await VenueService.start(configuration: configuration, binding: wristband.binding)
```

- `VenueService.start` creates the SDK (`ProximiioConfiguration.relayOnly`, no fallback host), requests
  location authorization, authenticates, starts positioning, loads the route network and attaches the
  wristband's position provider. Visitor reporting is on.
- Call `VenueService.start` at launch, before the first map screen. After the start it fetches the
  organisation's map style in the background, and the map library writes it to Caches. A map screen
  then starts on that style instead of an empty one, and the venue data is already loaded.
- On the first map screen after an install, MapLibre downloads the basemap tiles while the map is on
  screen. Until they arrive, the map shows the style's white background. MapLibre keeps the tiles in
  its cache for later screens and launches.
- Until MapLibre draws the first frame, the map is clear and the screen behind it shows.
- `venue.sdk` is the app's only `Proximiio` instance. Other features of the host app, such as the audio
  guide, use it. Do not create a second `Proximiio`.
- The package contacts only `apiBaseURL` and the relay-api host.

### Settings

Every time and distance of the screens is in `GADSettings`. Set them in the configuration, or later
in `venue.settings`; a screen reads them when it opens, so a change applies to the next screen:

```swift
var settings = GADSettings()
settings.offRouteMeters = 50
settings.trackingLostAfter = 90
let configuration = GADConfiguration(
    apiBaseURL: apiBaseURL, applicationToken: applicationToken,
    relayAPI: relayAPI, relayAPIAppToken: relayAPIAppToken,
    settings: settings
)
```

| Setting | Default | Effect |
|---|---|---|
| `trackingLostAfter` | 110 s | Seconds without positioning before `VisitEvent.trackingChanged(.lostPlace)`. The SDK reports positioning unavailable about 10 s after the last fix: about 2 min. |
| `trackingStoppedAfter` | 170 s | Seconds without positioning before `VisitEvent.trackingChanged(.stoppedResponding)` (about 3 min). |
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

Notifications for geofence enter and exit:

```swift
let notifier = GeofenceNotifier()
await notifier.requestAuthorization()
Task { await notifier.run(sdk: venue.sdk) }
```

`run(sdk:)` sets the `UNUserNotificationCenter` delegate, which shows notifications while the app is in
the foreground. A host app with its own delegate sets it again after this call and presents the
notifications with the thread identifiers `geofence` and `journey` itself.

## Wristband

The host app scans the wristband's QR code, or the visitor types the code printed on it. Pass the
result to `connect(code:)`:

```swift
do {
    try await wristband.connect(code: scannedCode)
} catch {
    errorText = WristbandCopy.message(for: error)   // the text for the visitor, English or Arabic
}
```

- `connect(code:)` trims the code and sends it to the relay-api, which resolves every label format.
  When the relay-api needs the phone's location for a take-over, the iOS location dialog comes first.
  It returns when the session is active and throws `BlueiotBindingError` otherwise (`.invalidTagID`
  for an empty code).
- A wristband that another phone follows is taken over when the relay-api allows it. The other phone's
  session ends.
- `isActive`, `state` and `endNotice` describe the session. Positions arrive only while it is active.
- `VisitView` shows no wristband alerts: the host app handles the wristband states, for example an
  ended session (`state`, `endNotice`). `VisitView` reports lost and returning positions as
  `VisitEvent.trackingChanged(TrackingHealth)`.

## Screens

| View | Content |
|---|---|
| `MuseumMapScreen(venue:onBack:)` | The museum map: floors, amenities, the visitor's position, a route to a tapped place. |
| `VisitView(venue:journey:kind:onClose:)` | The journey: map and list with a toggle, skip and undo, the stop card, the Live Activity. `kind` is `.personalised` (default) or `.curated`. |
| `WristbandPairingView(pairing:onFinish:)` | Optional: the pairing flow of the Proximi GAD app, with its QR scanner. Create the pairing with `WristbandPairing(connector: wristband)`. |
| `VisitPlanPicker(places:onStart:onCancel:)` | Choosing stops by hand. |

A journey from Proximi.io POI ids, for example from the audio guide:

```swift
let places = VenuePlace.all(in: await venue.sdk.features())
let journey = VisitPlan.journey(poiIDs: poiIDs, places: places)
```

`VisitStore.save(_:)` and `VisitStore.load()` keep the journey in progress across launches. `VisitView`
saves it on every change.

### Personalised and curated journeys

A journey the visitor built with the guide is `.personalised`; a tour by the museum's curators is
`.curated` (Figma "Personalised" and "Guided"):

| | `.personalised` | `.curated` |
|---|---|---|
| Stop card | Names the gallery of the next stop until the visitor is in it, then the artwork. | Names the artwork. |
| List | Stops under gallery names. | Stops without gallery names. |
| Skip | The visitor can skip an artwork. | No skip. |
| Order | Ordered floor by floor and gallery by gallery from the visitor, at the start and after a detour or an artwork visited out of order. | The curators' order. An artwork visited out of order is marked visited; the rest keep their order. |

The map and the background are the same for both.

`VisitMeta.kind` stores the kind with the journey for the host app's own screens.

## Artwork details in the list

A journey list row shows the artist and "AR" and audio badges from the artwork's POI
`properties.metadata`. Without `artist_name` the row shows the level.

| Key | Value | Shows |
|---|---|---|
| `artist_name` | String, or an i18n object like `title_i18n` | The artist under the title. |
| `has_ar` | `true` | "AR". |
| `has_audio` | `true` | A note. |

`VenuePlace.artist`, `hasAR` and `hasAudio` hold the values. The GAD venue data on 2026-10-14 has
none of the three keys.

### Gallery headers

In a personalised journey the list shows a header before the stops of each gallery. The gallery of
an artwork is its `metadata.gallery_id` (`VenuePlace.galleryID`), named by the title of the POI whose
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
   off-route warning shows, and the card says that the position is not shown.

The map follows the visitor again when the destination changes ("Resume your Journey", another stop
or route), on "Centre on me" or "Follow my floor", or after `floorWithoutPositioningMaximumSeconds`.
`VisitView` reports `VisitEvent.floorWithoutPositioningEntered(level:)` and
`floorWithoutPositioningLeft(level:)`. The view shows the lift or stairs icon until the animation
from the design team exists.

## Accessibility

The host app passes the visitor's accessibility needs to the map and journey screens. Every route
then avoids what they name, and a change re-routes the route on screen:

```swift
ContentView()
    .routeAccessibility(RouteAccessibility(avoidsStairs: true, avoidsRevolvingDoors: true))
```

| Need | Avoids, where the venue data marks it |
|---|---|
| `avoidsStairs` | Level changers with `type` `staircase`. |
| `avoidsEscalators` | Level changers with `type` `escalator`. |
| `avoidsRevolvingDoors` | Path pieces within `radius` of a `door` point feature. |
| `avoidsInaccessiblePaths` | Routing paths with `narrowPath: true`. |

- The GAD venue data on 2026-10-14 has staircases and elevators. It has no escalators, no `door`
  features and no `narrowPath` paths, so only `avoidsStairs` changes routes until the data has them.
- `RouteAccessibility.routeOptions` is the SDK's `RouteOptions` for the needs, for routes the host app
  computes itself.
- The museum map and the journey map have an accessible routes button (a wheelchair, blue while on).
  While it is on, routes avoid all four (`RouteAccessibility.accessible`), whatever the host app
  passed. Its state is kept in `UserDefaults` under `RouteAccessibility.accessibleRoutesKey`, for both
  maps and later launches. `VisitView` reports `VisitEvent.accessibleRoutesChanged(_:)`.
- When no route meets the needs, the museum map shows "No route from here with your accessibility
  settings." In a journey, the stop card shows "No route to this stop with your accessibility
  settings." and the stop keeps its place; in a personalised journey the visitor can skip it in the
  list.

## Events from VisitView

`VisitView` performs every action itself. The host app receives a `VisitEvent` for each visitor action
and each journey change:

```swift
VisitView(venue: venue, journey: journey) { isVisiting = false }
    .onVisitEvent { event in
        switch event {
        case .skipRequested(let stop): print("Swiped \(stop.title)")
        case .stopSkipped(let stop): print("Skipped \(stop.title)")
        case .artworkReached(let stop): print("At \(stop.title)")
        default: break
        }
    }
```

| Event | When |
|---|---|
| `modeChanged(VisitMode)` | The Map / List toggle. |
| `skipRequested(JourneyStop)` | A swipe on a stop in the list, or its "Skip" accessibility action. "Skip artwork?" follows. |
| `stopSkipped(JourneyStop)` | "Skip artwork" confirmed. |
| `skipCancelled(JourneyStop)` | "Keep it". |
| `skipUndone(JourneyStop)` | "Undo skip" in the list. |
| `amenitySelected(VenuePlace)` | An amenity picked on the map. A card shows it. |
| `detourStarted(VenuePlace)` | "Change your route?" confirmed. |
| `journeyResumed` | "Resume your Journey" or "Show the route from here". |
| `recentred` | "Centre on me". |
| `accessibleRoutesChanged(Bool)` | The accessible routes button turned on (`true`) or off. |
| `exitRequested` | Back during a visit in progress. "Leave" or "Carry on" follows. |
| `exitConfirmed` | "Leave". `onClose` follows. |
| `exitCancelled` | "Carry on". |
| `stopNearby(JourneyStop)` | The active stop is less than 5 m away on the visitor's level. Once per stop per visit. |
| `artworkReached(JourneyStop)` | The visitor entered the artwork geofence of the active stop, or stands in its area. The stop is done 2 s later, when the event arrives, and the route leads to the next stop. |
| `artworkVisitedOutOfOrder(JourneyStop)` | The visitor stayed at an artwork further down the journey. The stop is done and the stops ahead are ordered again. |
| `floorWithoutPositioningEntered(level:)` | The map shows a floor without positioning after the lift or stairs view. |
| `floorWithoutPositioningLeft(level:)` | The map follows the visitor again. |
| `trackingChanged(TrackingHealth)` | The wristband's positions stopped (`lostPlace` after `trackingLostAfter`, `stoppedResponding` after `trackingStoppedAfter`) or came back (`tracking`). `VisitView` shows no alert. |
| `journey(JourneyEvent)` | Every event of the journey navigator: `legChanged`, `stopSkipped`, `rerouted`, `detourStarted`, `stopReached` (detours only), `journeyFinished` and others. The navigator does not report artworks reached: use `artworkReached`. |

Handlers of enclosing views are called first. Events arrive on the main actor.

## Live Activity

`VisitView` starts, updates and ends the Live Activity. The widget extension shows it:

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

`FieldLog` writes positions, tracking health, geofence, journey and binding events to
`Documents/gad-debug.log`. It is off by default. Turn it on at launch, before `VenueService.start`, in
test builds only:

```swift
FieldLog.isEnabled = true
FieldLog.logLaunch()
```

`FieldLogShareButton()` opens the share sheet with the file.

## Debug builds

In the Debug configuration `DebugLaunch` reads launch arguments. The SDK-dependent arguments take
effect when the host app calls `run(with:wristband:)` after `VenueService.start`:

```swift
#if DEBUG
await DebugLaunch.current.run(with: venue, wristband: wristband)
#endif
```

| Argument | Effect |
|---|---|
| `-journeyPlayback <journey id>` | Plays a journey stored on Proximi.io instead of the wristband. |
| `-journeySpeed <x>` | Playback speed. Default 1. |
| `-journeyLoop` | Restarts playback after the last waypoint. |
| `-listJourneys` | Prints the organisation's places and journeys with their ids. |
| `-pairWristband <code>` | Binds the wristband after the SDK starts. Ignored with `-journeyPlayback`. |
| `-visitList` | `VisitView` opens in List mode. |
| `-visitAutoAdvance` | `VisitView` advances 5 m after the visitor leaves a stop, without the Continue tap. |
| `-visitKind personalised\|curated` | Sets `DebugLaunch.visitKind`. The host app passes it to `VisitView`. |
| `-routeTo <title>` | `MuseumMapScreen` routes to the first place whose title matches, after the first position. |
| `-routeAvoid stairs,escalators,revolvingDoors,inaccessiblePaths` | Sets `DebugLaunch.routeAccessibility`. The host app passes it to `routeAccessibility(_:)`. |

`DebugLaunch` also parses `-demoWristbandPairing`, `-hubPage`, `-openMap` and `-visit`. The package
does not act on them; the Proximi GAD app reads them.

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
- `VenueService.start` asks for "While Using the App" location only.

## Tests

```
xcodebuild test -scheme ProximiioGADKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Changelog

Every version is a git tag. **Breaking** marks a change that needs a change in the host app's code or
dependencies; the entry says what to change. `VisitEvent` gets new cases in minor versions: a `switch`
over `VisitEvent` with a `default` case compiles with every version.

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
