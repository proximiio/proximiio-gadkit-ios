# ProximiioGADKit

ProximiioGADKit is a Swift package with the museum map, the journey (map and list), the stop picker
and Manage journey of the Proximi GAD app (Guggenheim Abu Dhabi), and the wristband binding. It is
built on the Proximi.io iOS SDK and Map.

The host app uses one of two entry points:

- **`ProximiMap`** owns the SDK, the wristband session, the stored journey, the notifications and every
  screen and sheet of the package. The host app creates one `ProximiMap` and starts it, attaches
  `.proximiMap(_:)` to a view that stays on screen, opens screens with `open(_:)` and receives every
  change as a `ProximiMapEvent`. It scans the wristband's QR code itself and passes the code to
  `connectWristband(code:)`. The Proximi GAD app uses the package this way.
- **`ProximiMapView`** is the journey map alone, as a UI component on an SDK the host app has
  started. The host app owns the SDK, the wristband session and the journey, and moves the journey on.
  See [ProximiMapView](#proximimapview). **`ProximiExploreView`** is the Explore Museum map as a UI
  component on the same SDK (see [Explore Museum](#explore-museum)).

| Product | Add to | Content |
|---|---|---|
| `ProximiioGADKit` | The app target | `ProximiMap`, `ProximiMapView`, `ProximiExploreView` and their types, `GADConfiguration`, `GADSettings`, `FieldLog`. |
| `ProximiioGADLiveActivity` | The widget extension | `VisitActivityAttributes` and `VisitActivityWidget`. |

## Requirements

- iOS 16.4 or later. Swift 6 language mode (`swift-tools-version: 6.0`).
- SwiftUI host app.
- Built and tested with Xcode 26.3 and Xcode 27.
- Read access to this repository. The SDK and Map binary packages are public.

## Adding the package

In Xcode: File → Add Package Dependencies → `https://github.com/proximiio/proximiio-gadkit-ios`,
dependency rule "Up to Next Major Version" from `1.0.0`. The versions are the git tags of this
repository. From 1.0.0 a minor or patch version does not break the public API. New `ProximiMapEvent`
cases come in minor versions; a `switch` with `default` keeps compiling. The [Changelog](#changelog)
lists every change; changes that need a change in the host app are marked **Breaking**.

`Package.swift` pins `proximiio-sdk-ios-binary` 6.0.0-beta.68 and `proximiio-map-ios-binary`
6.0.0-beta.59 exactly. The host app needs no dependency on them. A host app that also depends on
these packages must use the same versions.

The package depends on `https://github.com/airbnb/lottie-spm` from 4.5.0, up to the next major
version, for the lift and stairs animations. A host app that uses Lottie adds the same package
(`lottie-spm`), so both share one `Lottie` module; `lottie-ios` next to it gives two modules with that
name.

A host app that draws its journey with the map library's `ProximiioMapView` and its own
`JourneyNavigator` moves to `ProximiMapView` with [MIGRATION.md](MIGRATION.md). It lists the SDK and
Map changes since SDK 6.0.0-beta.58 and Map 6.0.0-beta.43.

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

The package views show Arabic when the language is Arabic, else English. The language is:

- the language of the `\.locale` the host app gives `ProximiMapView`, `ProximiExploreView` or the
  screens of `.proximiMap(_:)`, when it is not the language the app started in;
- else the first of the app's `AppleLanguages` (iOS Settings, or an app that sets it itself).

A change applies at once, also to an open map: the package's texts, the layout direction of its views
(right to left in Arabic) and the map labels. The host app needs no restart for the package views. On
iOS 16 the open package view is built again in the new language: an open map starts again, at the
journey's current state.

```swift
// A host app that switches its language with the SwiftUI environment:
ProximiMapView(sdk: sdk, journey: $journey)
    .environment(\.locale, Locale(identifier: language))   // "ar" or "en"
```

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
    @StateObject private var map = ProximiMap(configuration: GADConfiguration(
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
    @ObservedObject var map: ProximiMap

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

`ProximiMap` is `@MainActor` and an `ObservableObject`. Hold it with `@StateObject`, and pass it to
the views that read its properties as `@ObservedObject`; they update with them.

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
map screen. The package contacts `apiBaseURL`, the relay-api host and the host of the style's raster
tiles.

The maps draw the raster tiles of the organisation's style (map 6.0.0-beta.55): the style's
`metadata["proximiio:raster:tileurl"]` with the other `proximiio:raster:*` keys, as MapTap and the
portal read them. They are drawn below `proximiio:raster:beforelayer`, and below the floor plan
(`proximiio-floors`) when that key is empty. A style without `tileurl` draws no tiles. The tiles come
from the host in `tileurl` and get no token; in the GAD Sandbox style on 2026-10-28 it is
`fra1.digitaloceanspaces.com`.

Without a connection, `start()` succeeds on a phone where the API accepted the token before
(`ProximiioConfiguration.allowsOfflineStart`, SDK 6.0.0-beta.65). The route network then comes from
the features stored on the phone. The SDK syncs and uploads nothing until the API accepts the token
again. On a first launch without a connection, `start()` throws `startFailed`.

When the API has refused the token for at least two hours, the SDK stops and deletes the venue data
on the phone (SDK 6.0.0-beta.66). `ProximiMap` then closes its screens and `status` becomes
`.failed(.startFailed)`. The stored journey is kept. `start()` starts again once the API accepts the
token.

## ProximiMapView

`ProximiMapView` is the journey map as a UI component on an SDK the host app has started: the Map /
List toggle, search with the amenity shortcuts, the map with the floor button, "Centre on me", the
accessible routes button and the stop card, and the list. The host app owns the SDK, the wristband
session and the journey, and decides when a stop is visited or skipped. The view draws the journey
it gets, routes to the first stop still to visit and reports what the visitor does. A host app that
uses it needs no `ProximiMap`.

```swift
import Proximiio
import ProximiioGADKit
import SwiftUI

struct JourneyMapScreen: View {
    let sdk: Proximiio                      // started by the host app, wristband provider attached
    @Binding var journey: ProximiJourney    // owned, stored and moved on by the host app

    var body: some View {
        ProximiMapView(sdk: sdk, journey: $journey) { event in
            switch event {
            case .skipRequested(let stop):  // a swipe on a stop in the list
                // stop.id is the POI id, stop.artworkID the collection id. The host app asks, then
                // sets the stop to .skipped.
                skip(stop)
            default:
                break
            }
        }
    }
}

// A new journey from the audio guide: every stop pending.
journey = ProximiJourney(kind: .personalised, artworks: ["GAD.2010.00033", "GAD.2018.00034"])
// The visitor heard the artwork: the host app marks it visited, the route leads to the next stop.
journey.stops[0].state = .visited
```

| Parameter | |
|---|---|
| `sdk` | The host app's `Proximiio`, started, with the position provider of its wristband session attached. |
| `journey` | `Binding<ProximiJourney>`. The view applies every change to the open screen. It writes to the binding only with `.progress`. |
| `destination` | `Binding<ProximiDestination?>`, default `.constant(nil)`. A place to route the visitor to at once. See [Routing to a place](#routing-to-a-place). |
| `isPaused` | `Binding<Bool>`, default `.constant(false)`. Pauses and resumes the journey. See [Pausing the journey](#pausing-the-journey). |
| `options` | `ProximiMapView.Options`, default none. See below. The view reads them when it opens; a change applies to the next view. |
| `settings` | `GADSettings`, default `.standard`. The view reads them when it opens. `postsGeofenceNotifications` does not apply. |
| `routeAccessibility` | The visitor's accessibility needs for routes, default `.none`. See "Accessibility". |
| `mode` | `.map` (default) or `.list` when the view opens. |
| `onEvent` | `ProximiMapEvent`s of the journey screen, on the main actor. |
| `onClose` | Back on the bottom bar, "Leave the tour" and the close button of Journey Complete. Default `nil`: the bottom bar has no Back, "Leave the tour here" never shows, and the close button of Journey Complete returns to the map. |
| `onNavigator` | The map library's `JourneyNavigator` that draws the journey, on the main actor, before the journey starts and again each time the screen starts again. See [The navigator](#the-navigator). |

The host app:

- creates and starts the SDK and attaches the wristband's position provider. The view does not start,
  stop or configure the SDK and does not change the wristband session;
- uses `proximiio-sdk-ios-binary` 6.0.0-beta.68, the version this package pins;
- closes the view when the SDK stops on a refused token (`syncFailed(reason: "unauthorized")`,
  `tokenStatus == .rejected`). The map drops the venue and the navigator ends. After a new successful
  `authenticate()` and `start()`, a new view draws the journey again;
- turns on the SDK's privacy-zone option and passes the wristband's privacy signal to the SDK (see
  [Privacy zones](#privacy-zones));
- lays the view out and closes it; draws the background and the bottom bar (for example the audio
  guide's controls);
- stores the journey and moves it on. The view stores nothing but the accessible routes button
  (`UserDefaults`, key `ProximiioGADKit.accessibleRoutes`).

The first `ProximiMapView` or `ProximiExploreView` on an SDK installs the route network from the SDK's
feature cache, or downloads it when the cache has no path. The views keep the venue's features,
geofences and amenities in memory and follow the SDK's `venueDataChanges()`, also after they closed,
so the next view on the same SDK opens without reading them again (see "Venue data changes"). After
the SDK stopped, the next view installs the route network and reads the data again. The view
requests no permission and posts no notification.

`ProximiMapView.prepare(sdk:)` does the first view's work ahead. It is optional. Call it after the SDK
started, for example when the visitor finishes onboarding; the first view then opens like the later
ones. With the GAD venue a read of the features takes about 0.5 s on the simulator, and the map
library's own read of them waits behind it.

```swift
try await sdk.authenticate()
try await sdk.start()
await ProximiMapView.prepare(sdk: sdk)
```

### Options

Each option turns on something the view does beyond drawing the journey. `ProximiMap` uses `.all`.

| `ProximiMapView.Options` | With it | Without it (default) |
|---|---|---|
| `.bottomBar` | A bar with Back (with `onClose`) and a Map / List button. | No bar. The host app draws its own. |
| `.background` | The package's background image around the map card. | Transparent. |
| `.skipPrompt` | "Skip this artwork?" after a swipe on a stop. "Skip artwork" reports `stopSkipped`; the stop is skipped with `.progress`, else the host app skips it. | A swipe reports `skipRequested` only. |
| `.offRoutePrompt` | "Looks like you've left your route" with "Dismiss", in place of the stop card, for `GADSettings.offRouteWarningSeconds` unless the visitor closes it. It shows `GADSettings.offRouteMeters` (12 m) off the leg to the current destination, also where a later leg of the journey passes, before any routing: the navigator routes nothing by itself. After it, with `.progress`, a personalised journey keeps the leg where the visitor left it until another open artwork is the nearest stop; then the stops ahead are ordered again from the visitor. A curated tour, and a journey without `.progress`, is routed again from the visitor. A visitor on a floor the route does not take for `GADSettings.wrongFloorSeconds` gets the warning too, and the leg is drawn again from the visitor: to the nearest open artwork in a personalised journey, to the next stop in a curated tour. | The route follows a visitor who left it. `offRoute` reports it. |
| `.uncertainPositionPrompt` | "Probably at …" when the position is uncertain near the active stop. | `positionUncertain` reports it. |
| `.leaveTourPrompt` | "Leave the tour here" after Back on the bottom bar during a journey in progress (with `.bottomBar` and `onClose`). | Back calls `onClose` at once. |
| `.prompts` | All four prompts above. | |
| `.progress` | The view moves the journey on and writes it to the binding: an artwork is visited when the visitor enters its geofence (`artworkReached`) or, in a personalised journey, stays at it out of order (`artworkVisitedOutOfOrder`); a personalised journey is ordered floor by floor and gallery by gallery; a stop whose POI is deleted is skipped. | Only the host app's journey changes the stops. The view keeps the host app's order and writes nothing. |
| `.liveActivity` | The journey's Live Activity. The widget extension needs `ProximiioGADLiveActivity`. | No Live Activity. |
| `.journeyComplete` | Journey Complete when the last stop is done. | `journeyFinished` reports the end; nothing shows. |

### ProximiJourney

`ProximiJourney` is `Codable`: the host app can store it as JSON.

| Member | |
|---|---|
| `kind` | `.personalised` or `.curated`. See "Journeys". |
| `stops` | `[ProximiJourney.Stop]` in visit order. A stop has the `id` the host app gave (a collection id `remote_id` or a Proximi.io POI id) and a `state`: `.pending`, `.visited` or `.skipped`. |
| `init(kind:artworks:)` | A journey whose stops are all pending. |
| `init(kind:stops:)` | A journey with its progress. |
| `init(kind:journey:)` | The stops of a map library `Journey`, with their ids. `.done` is `.visited`, `.skipped` is `.skipped`, `.pending`, `.active` and `.reached` are `.pending`. Detour stops are left out. |

- The route leads to the first pending stop in the journey's order. In a `.personalised` journey it
  leads to the stop's gallery first (see "Gallery first").
- The open screen applies a change of the binding in place, with the navigator's `update(to:)`: a
  stop visited, skipped, pending again, added, removed or moved. The map, the camera, the navigator
  and the route of an unchanged leg stay. Changes apply one after another; while one applies, only
  the latest waits.
- These changes start the screen again (new map session, navigator, camera and mode): a new `kind`, a
  journey without a stop on the map, and the first journey on a map without one, because that map
  has no navigator.
- A journey without stops, or without a stop on the map, shows the map alone: search, floors and
  "Centre on me", no Map / List toggle and no stop card, in either `mode`. "Go here" on an amenity
  draws the route to it.
- A stop whose POI is deleted on the backend while the view is open is reported as
  `stopPlaceDeleted`. Without `.progress` it stays on the screen until the next change of the
  binding, which leaves it out.
- A stop whose POI changes on the backend while the view is open takes the new title, position,
  floor and gallery (see "Venue data changes").
- A stop whose id matches no POI, and a second stop of the same POI, are not on the map.
- Detours to amenities are not stops of `ProximiJourney`.

With `.progress` the view also writes:

- the journey after every change of the order or of a stop state. A personalised journey is ordered
  from the visitor at the start, so the first write can be the new order;
- `.visited` when the visitor leaves the artwork's geofence (`advancesOnArtworkExit`), or
  `artworkAdvanceDelay` after the arrival without it. The stop the route leads to is `.pending`;
- the stops that match no POI unchanged, after the other stops;
- nothing at Journey Complete: the journey already holds the last states.

### Events of ProximiMapView

`onEvent` receives the journey screen's events of the [Events](#events) table: `trackingChanged`,
`nextStop`, `stopNearby`, `positionUncertain`, `stopPlaceDeleted`, `skipRequested`, the amenity and
detour events, `destinationUnavailable`, `journeyPaused`, `journeyResumed`, `offRoute`, `backOnRoute`,
`journeyFinished`, the floor without positioning events, `modeChanged`, `recentred` and
`accessibleRoutesChanged`; with `.skipPrompt` also `stopSkipped` and `skipCancelled`; with `.progress`
also `artworkReached`, `artworkVisitedOutOfOrder` and `stopOrderChanged`; with `.bottomBar`,
`.leaveTourPrompt` and `onClose` also the exit events. Screen, wristband,
arrival, geofence and `journeyChanged` events come only from `ProximiMap`; geofence enter and exit
events are on the host app's SDK (`geofenceEvents()`).

### Routing to a place

The host app sets `destination` to route the visitor to a place at once, for example the place of the
audio guide's proximiio-mcp answer (`route_to_place`, `route_to_nearest_amenity`). The visitor agreed
in the conversation, so no card and no prompt show.

```swift
@State private var destination: ProximiDestination?

ProximiMapView(sdk: sdk, journey: $journey, destination: $destination, routeAccessibility: needs) { event in
    if case .destinationUnavailable(let poiID, let reason) = event {
        guide.say(poiID, reason)            // .unknownPlace, .noRoute or .noPosition
    }
}

// The audio guide's "show the way", with the id of the MCP result:
destination = ProximiDestination(poiID: target.id)
```

- `poiID` is the feature id or its `properties.id`. On Proximi.io data the feature id is
  `<organisation id>:<properties.id>`, and proximiio-mcp returns `properties.id`. The events carry the
  feature id (`ProximiStop.id`).
- During a journey the place is a detour, as after "Go here": `detourStarted`, then `detourEnded`. A
  stop of the journey still to visit becomes the next stop instead (`nextStop`).
- Without a journey the map draws the route from the visitor, as "Go here" does. It needs a position
  (`.noPosition`).
- The route avoids what `routeAccessibility` and the accessible routes button avoid. Pass the same
  needs to proximiio-mcp (`avoid`), so the spoken route and the map's route match.
- The view sets `destination` back to `nil` when the route ends: "Resume your Journey", "Close",
  another place picked on the map, or `destinationUnavailable`. The host app sets it to `nil` to end
  the route; another destination replaces it.

### Pausing the journey

The host app sets `isPaused` to pause the journey, for example from the audio guide's pause button, and
back to `false` to resume it.

```swift
@State private var isPaused = false

ProximiMapView(sdk: sdk, journey: $journey, isPaused: $isPaused) { event in
    switch event {
    case .journeyPaused: guide.pause()       // "Add a stop" on an amenity
    case .journeyResumed: guide.resume()     // "Resume your Journey"
    default: break
    }
}

// The audio guide's pause button:
isPaused = true
```

- While paused, the dot moves and the route stays. No artwork is visited, no off-route warning or
  wrong floor shows, "Probably at …" does not ask, and the leg is not routed again. The view reports
  no `offRoute`, `backOnRoute` or `positionUncertain`. The stop card
  shows "Journey paused", the next stop and "Resume your Journey".
- On resume the leg is drawn again from the visitor. With `.progress` a personalised journey is
  ordered again from the visitor first, as after a detour.
- "Resume your Journey" on the card sets `isPaused` back to `false` and reports `journeyResumed`.
- "Add a stop" on an amenity sets `isPaused` to `true` and reports `journeyPaused` after
  `detourStarted`: the journey waits while the visitor goes there. The card shows the amenity and
  "Resume your Journey", not "Journey paused".
- After "Add a stop", the host app's `false` ends the detour as "Resume your Journey" on the detour's
  card does. That button sets `isPaused` to `false` and reports `journeyResumed`. When the detour ends
  otherwise, the view sets `isPaused` to `false`.
- "Add a stop" while the host app has paused the journey: the card shows "Journey paused". Its resume,
  on the card or by the host app, shows the detour's card, and the view sets `isPaused` to `true`
  again until the detour ends.
- A change of `isPaused` by the host app, and a detour to the host app's `destination`, report no
  event.

### The navigator

`onNavigator` gives the host app the map library's `JourneyNavigator` that draws the journey. The host
app reads its `events` and sets its `onCue` as on a navigator of its own.

```swift
@State private var navigatorTask: Task<Void, Never>?

ProximiMapView(sdk: sdk, journey: $journey, onNavigator: { navigator in
    let events = navigator.events           // read here: the stream gets every later event
    navigatorTask?.cancel()                 // a new navigator replaces the previous one
    navigatorTask = Task {
        for await event in events {
            switch event {
            case .stopSkipped(let stop): print("skipped", stop.id)
            case .offRouteTooLong(let duration): print("off route for", duration)
            case .journeyFinished: print("finished")
            default: break
            }
        }
    }
    navigator.onCue = { cue in
        if cue.kind == .approachingDestination { print("approaching", cue.text) }
    }
})
```

- The view calls `onNavigator` before the journey starts. Each time the screen starts again (see
  "ProximiJourney") it calls it with a new navigator, and the streams of the previous one finish.
  A change of the binding that the open screen takes goes to `update(to:)` of the same navigator.
- Every access to `events` returns a new stream. The view's own stream takes no events from it.
- The view sets neither `onCue` nor `cueRules`. `cueRules` is the map library's default
  (`.venueWalk`: a cue 15 m before each manoeuvre).
- The host app changes the journey through the `journey` binding only. The view does not see calls
  that change the navigator (`markDone(stopID:)`, `skip(stopID:)`, `reopen(stopID:)`, `add(_:)`,
  `move(stopID:toIndex:)`, `apply(_:)`, `detour(to:)`, `resumeJourney()`, `setRouteOptions(_:)`), and its
  next change of the journey can undo them.

The view's navigator differs from a navigator with the map library's default rules:

| | The view's navigator |
|---|---|
| `.stopSkipped`, `.legChanged`, `.journeyFinished` | Sent when the view applies a change of the binding (`update(to:)`). |
| `.leftRoute`, `.offRouteTooLong` | After `GADSettings.offRouteMeters` (12 m, for 3 fixes) off every leg still to walk, and `GADSettings.offRouteSeconds` (300 s). `.farFromRoute` at the map library's 30 m. The warning of `.offRoutePrompt` also follows the leg to the current destination (`RouteGuidance.isOffRoute`). |
| Off the route | With `.offRoutePrompt` the navigator routes nothing by itself (`deviationPolicy` `.askApp`); the view routes after the warning. Without it the route follows the visitor (`.automatic`). |
| `.stopReached` and the cue `.arrived` | Only for a detour to an amenity. A leg to an artwork never reports an arrival (`arrivalDwellSeconds` is infinite): the visitor reaches an artwork by entering its geofence, which the host app's `geofenceEvents()` reports. |
| The cue `.approachingDestination` | 15 m before the end of the leg. In a personalised journey a leg to an artwork in another gallery ends at that gallery (see "Gallery first"); other legs end at the artwork. |

#### Any change of the journey

With `.progress`, `stopOrderChanged(ProximiJourney)` reports each new order the view gives the stops: from
the visitor's first position, after `artworkVisitedOutOfOrder` and after a detour. It carries the journey
in your ids, as the binding gets it. A change of the states alone sends no `stopOrderChanged`.

The navigator's `journey` (`@Published`) reports every change of the stops, with or without `.progress`:

- The map library republishes it when the stops change: a stop is added, removed, replaced, moved or
  changes state, or a detour starts or ends. A position fix does not republish it.
- A subscription gets the current value at once.
- Subscribe in each `onNavigator` call: a new navigator replaces the previous one.

```swift
@State private var journeyChanges: AnyCancellable?

ProximiMapView(sdk: sdk, journey: $journey, onNavigator: { navigator in
    journeyChanges = navigator.$journey.sink { journey in
        print("stops", journey.stops.map(\.id))
    }
})
```

With `.progress` the view also writes the `journey` binding: the order of the stops and the visited and
skipped stops, also the new order of a personalised journey. The binding has no detour stops, and an active
or reached stop is pending in it. Without `.progress` the view does not reorder the journey and does not
write the binding.

## Screens

`open(_:)` shows a screen over the view with `.proximiMap(_:)`. A screen already on screen closes
first. Nothing opens before `start()` has finished.

| `ProximiMap.Screen` | Shows | Inside the flow |
|---|---|---|
| `.museumMap` | The Explore Museum map, without the visitor's position: "Level N" and the floor changer, the galleries in the level colour, the Spaces, Highlights and Amenities lists, and a card for a picked place (see [Explore Museum](#explore-museum)). | Back closes it. |
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
| Route | Leads to the gallery of the next artwork first, then to the artwork (see "Gallery first"). | Leads to the artwork. |
| Stop card | Names the gallery of the next stop until the visitor is in it, then the artwork. | Names the artwork. |
| List | Stops under gallery names. | Stops without gallery names. |
| Skip | The visitor can skip an artwork. | No skip. |
| Order | Ordered floor by floor and gallery by gallery from the visitor, at the start and after a detour or an artwork visited out of order. | The curators' order. |
| Another artwork | An artwork further on that the visitor stays at counts as visited (`artworkVisitedOutOfOrder`). | Ignored: only the next artwork counts. An artwork the visitor passes stays open. |

The map and the background are the same for both.

### Gallery first

In a personalised journey, a leg to an artwork in a gallery the visitor is not in ends at that
gallery. The artwork's `metadata.gallery_id` names the gallery: the gallery geofence
(`metadata.geofence_type` `gallery`) and the gallery's POI both have it in `remote_id`. The route ends
at the POI. The map fills the gallery's polygon feature (else the geofence's outline) with the floor's
colour. At the POI it draws a red pill with a white border and the POI's title in white ("G303
Language"), no icon, and the numbered artwork markers are hidden (PM, Monday "Gallery numbers in
gallery navigation", 2026-10-28). The stop card names the POI with the icon of its amenity and no stop
number. Every other gallery's POI is a white pill with a black outline and the title; the POIs' own
icons are hidden. The gallery the visitor is in has no pill (PM, Monday "Navigation to a gallery",
2026-10-26) and no fill: the venue's own gallery colour, under the artworks and furniture, with the
artwork numbers (2026-10-28). The numbered artwork markers also stay hidden while the visitor is
outside every gallery, unless the active artwork is outside every gallery too. The destination
gallery is filled over the venue's artworks, furniture and inner walls (2026-10-27). Every other
gallery is filled with the venue style's gallery colour (`proximiio-gallery`) over its artworks and
furniture, under the inner walls: the artworks and furniture show only in the gallery the visitor is
in (PM, Monday "Artwork + furniture polygons", 2026-10-29).

A curated tour routes straight to the artwork, but shows the galleries as a personalised journey
does: the gallery of the active artwork is the destination, pill and fill (PM, Monday "Gallery
numbers in gallery navigation", 2026-10-29).

A gallery is visited when its artworks of the journey are all visited or skipped, at least one is
visited (the customer, 2026-10-28), and the visitor is out of it (PM, 2026-10-29): the map fills it
with the floor's light colour (level 0 #80FFD9, 1 #B7D3FF, 2 #DDC3F9, 3 #FFF291, 4 #FDC1A8), over the
venue's artworks, furniture and inner walls. Its POI is a white pill with a red outline and the title
(PM, Monday "Gallery numbers in gallery navigation", 2026-10-28).

The first fix inside the gallery geofence routes the leg again from the visitor, to the artwork. A
leg that starts in the artwork's gallery ends at the artwork. An artwork without `gallery_id`, or
whose gallery has no geofence polygon or no POI, is routed to directly. The GAD venue data on
2026-10-19 has 14 such galleries.

An artwork on another floor than its gallery, or more than `GADSettings.galleryFirstMarginMeters` (50 m)
outside the gallery's geofence, is routed to directly. In the GAD data of 2026-10-19, 34 artworks lie
5–29 m outside their gallery's geofence. When the gallery has no route from the visitor, the leg ends at
the artwork, and so do the later legs to that artwork. The field log names both cases ("gallery first:").

### Venue data changes

The backend changes POIs, paths, lifts and geofences while the app runs. The SDK's audit sync applies
the changes every `ProximiioConfiguration.syncInterval` (300 s by default). The screens follow
`Proximiio.venueDataChanges()` (SDK 6.0.0-beta.61) and download nothing themselves. The SDK names
changed features only while its store holds the whole feature collection, that is after a
`loadRouteNetwork()` on this install. The package keeps the features, geofences and amenities in
memory and reads a kind again only when `venueDataChanges()` names it. After a change:

- The open map draws the new POIs, amenity icons, floors, places and geofences (map 6.0.0-beta.47).
- The SDK has rebuilt the route network from the changed features. The open journey routes its legs
  again (`JourneyNavigator.routeNetworkChanged()`); a leg on the line already drawn stays as it is.
- The stop picker, the Explore Museum lists, the journey list, the galleries, the artwork geofences
  and the lift outlines use the new data. The amenity icons and lists also follow a change of the
  amenity catalogue (`.amenities`).
- On the open journey screen a stop whose POI changed takes the new title, position, floor and
  gallery (`JourneyNavigator.replace(_:)`), and the leg to it is routed again when it moved. A
  reached or done stop keeps its values.
- On the open journey screen of `ProximiMap` (and of `ProximiMapView` with `.progress`), a stop whose
  POI was deleted is skipped and reported as `stopPlaceDeleted`. The stored journey of `ProximiMap`
  removes it when the screen closes.
- The stored journey of `ProximiMap` follows its POIs. A done stop keeps its title and position.
  Another stop whose POI was deleted is removed; another stop whose POI changed takes the new title,
  position, floor and gallery. A journey with no stop left is deleted.
  `ProximiMapEvent.journeyChanged(_:)` follows.

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
- A session that the relay-api gives no verdict on ends with `.sessionLost`: the
  `wristband` becomes `.notConnected(notice:)` with "The connection to your wristband was lost. Connect
  it again." The SDK does not bind again on its own (since SDK 6.0.0-beta.60); the visitor scans the
  wristband again.
- Positions arrive only while `wristband` is `.connected`. A session stored by the SDK is confirmed
  with the relay-api after `start()`.
- The package shows no wristband alerts. `ProximiMapEvent.wristbandChanged(_:)` and
  `trackingChanged(_:)` let the host app show its own.

## Privacy zones

Privacy zones are drawn in the Proximi portal (Privacy zones), for example over the restrooms and the
prayer room. These rooms have no positioning anchors, so the wristband falls silent at the zone.

- relay-api (0.17.0 and later) syncs the organization's privacy zones every hour. A band that falls
  silent with its last position inside a privacy zone, or within the site's `privacy_margin_m` (3 m by
  default), gets the signal `private` instead of `lost`. While private, relay-api does not close the
  binding for silence (`TIMEOUT`) or for leaving the venue (`LEFT_VENUE`). The other end reasons stay.
- The SDK (since 6.0.0-beta.64) is private (`Proximiio.privacyZoneState`, `privacyZoneStateChanges()`)
  while its last fix is inside a privacy zone or the relay says `private`. With
  `ProximiioConfiguration.withholdsPositionsInPrivacyZones`, `positions()` yields no fix while private,
  and positioning stays available.
- The map (since 6.0.0-beta.51) holds the dot at the last fix before the zone, grey
  (`PositionStyle.privacy`), with the accuracy ring of that fix. While private the journey reports no
  off-route, re-route or arrival.
- The journey screen reports `trackingChanged(.privacyZone)` and no `lostPlace` or
  `stoppedResponding` while private.

`ProximiMap` turns the option on and passes the binding's signal to its SDK. A host app with
`ProximiMapView` does both on its own SDK:

```swift
var configuration = ProximiioConfiguration.relayOnly(token: token, runsInBackground: true)
configuration.withholdsPositionsInPrivacyZones = true

// In the loop over the wristband binding's states:
for await state in binding.stateChanges() {
    var privateSince: Date?
    if case let .active(_, _, .privacyZone(since)) = state { privateSince = since }
    await sdk.setPositioningSourcePrivate(since: privateSince)
}
```

## Explore Museum

`open(.museumMap)` shows the Explore Museum map (Figma "Explore Museum", node 12129:102006) with the
package's title "Explore Museum" and Back. `ProximiExploreView` is the same map as a UI component on
the host app's started SDK, without title, Back and background: the host app draws them.

```swift
ProximiExploreView(sdk: sdk)                           // settings: GADSettings, default .standard
```

`ProximiExploreView` reads the venue data the SDK holds and follows its `venueDataChanges()`. It does
not start, stop or configure the SDK and reports no event.

The visitor is not at the museum there: the map has no position dot, no route, and its camera does not
follow.

- At the top: "Level N" and the floor changer (the level in a tile of the level colour). A tap opens a
  glass button for each of the museum's levels, highest first, the shown level in bold. The map opens on
  the lowest level with a gallery, framed on the museum.
- The galleries of the shown level are filled with the level colour (`Palette.level(_:)`). Artworks
  have no marker.
- At the bottom: the legend button and the tabs Spaces, Highlights and Amenities. A tab opens its list
  over the map, grouped by level. The legend button opens the map legend: the facilities and the
  galleries the museum's POIs use, with their map icons, and "Elevator" and "Stairs" when the venue
  has lifts or staircases. A second tap, or a drag down on the panel's
  top, closes it.
- Icons: the design's glyph of an amenity kind (restrooms, café, help desk, prayer room, shop,
  stairs, lift), else the icon of the POI's amenity in the venue data, the icon the map draws.
  - Spaces: the galleries. The gallery geofence (`geofence_type` gallery) gives the outline, the POI
    with the same `remote_id` the name, the level, the category (its amenity, such as "Thematic
    Gallery") and the description.
  - Highlights: the artworks that list the "Highlight" amenity in `included_amenities`
    (`VenuePlace.highlightAmenityID`), with `metadata.artist_name` and the gallery.
  - Amenities: restrooms, café, help desk, prayer room and shop. Stairs and lifts are not listed.
  - Only the museum's POIs are listed: the `place_id` of the gallery POIs. The GAD organisation also
    holds the DCT office.
- The map draws no amenity icons: the Amenities list and the callout show them. A gallery's icon
  is on a circle of white at 30 % with a white border; an icon in the venue data without a circle of
  its own shows the design best. The circle has the data icon's size in points, which the style's
  `icon-size` scales: a 120 px icon at 0.2 is 24 pt, as in MapTap.
- A gallery is filled on its polygon feature (`type` `gallery`): the one whose `metadata.gallery_id`
  is the gallery's id, else the one around the gallery's POI. Without one, its geofence is filled.
- A row, or a tap on a gallery or a listed POI on the map, shows its level and frames the place at
  31 % of the width and 75 % of the height of the map. A card over the map names it, with its icon,
  its description (else a gallery's category) and its level; a line leads from the card to the place,
  drawn as a black dot in a ring with its title. The line follows the place when the visitor moves the
  map. With a gallery's card open, the other galleries are lighter. An amenity gets the same black dot.
- The texts and map labels follow a change of the app language at once (see [Languages](#languages)).
- The design's About the Building and Collections tabs are not in the package: their content is not in
  the venue data.

The map of Journey Complete (the map button of its bottom bar) is the museum map with the visitor's
position, search and routes.

## Events

`ProximiMap` performs every action itself; the events report them. They arrive on the main actor.

| Event | When |
|---|---|
| `opened(Screen)`, `closed(Screen)` | A screen opened or closed, by `open(_:)` or inside a flow. |
| `craftNewJourneyRequested` | "Craft a new journey" on Manage journey, after it closed. The host app shows its journey crafting. |
| `curatedTourChangeRequested` | "Edit stops" on Manage journey for a curated tour, after it closed. The host app shows its tour choice. |
| `arrivedAtMuseum` | `isAtMuseum` became `true`. Once per launch. |
| `wristbandChanged(WristbandStatus)` | The wristband session changed. |
| `trackingChanged(TrackingHealth)` | During a journey: the wristband's positions stopped (`lostPlace` after `trackingLostAfter`, `stoppedResponding` after `trackingStoppedAfter`), came back (`tracking`), or the visitor is in a privacy zone (`privacyZone`, never lost there). |
| `geofenceEntered(ProximiGeofence)`, `geofenceExited(ProximiGeofence)` | Every geofence enter and exit, with or without a journey. An artwork geofence has `type` `artwork` and the collection id in `artworkID`. An exit comes `GADSettings.geofenceExitDelay` (5 s) after the position left the geofence (SDK 6.0.0-beta.63). |
| `journeyChanged(JourneySummary?)` | A new, planned, edited or deleted (`nil`) journey, and the progress after the journey screen closed. |
| `nextStop(ProximiStop)` | The route leads to this stop now. |
| `stopNearby(ProximiStop)` | The active stop is less than `stopNearbyMeters` away on the visitor's level. Once per stop. The package posts no notification for it. |
| `positionUncertain(ProximiStop)` | `ProximiMapView` without `.uncertainPositionPrompt`: the position's accuracy is worse than `uncertainAccuracyMeters` and the active stop is within it. At most once per `locationQuestionQuietPeriod`. With `.uncertainPositionPrompt` the view asks "Probably at …" instead. |
| `artworkReached(ProximiStop)` | The visitor was in the artwork geofence of the active stop (they entered it, a fix lies in it, or the SDK counts them inside it: `enteredGeofenceIds`, also for a journey opened inside it) and left it: the SDK's `geofenceExited`, `geofenceExitDelay` outside it without that event, or a fix in another open artwork's geofence. The stop is done and the route leads to the next stop. With `advancesOnArtworkExit` `false`: `artworkAdvanceDelay` after the arrival. Every fix is checked, also on a leg without a route. `geofenceEntered` arrives at the enter. |
| `artworkVisitedOutOfOrder(ProximiStop)` | Personalised journeys only: the visitor stayed at an artwork further down the journey. It counts as visited, and the stops ahead are ordered again. A curated tour ignores such an artwork. |
| `stopOrderChanged(ProximiJourney)` | `ProximiMapView` with `.progress`: the view ordered the stops again, from the visitor's first position, after `artworkVisitedOutOfOrder` or after a detour. The journey in the host app's ids and its new order; the `journey` binding already holds it. A change of the states alone does not send it. |
| `skipRequested`, `stopSkipped`, `skipCancelled` (`ProximiStop`) | A swipe on a stop in the list, "Skip artwork", "Keep it". `ProximiMapView` without `.skipPrompt` sends only `skipRequested`. `skipUndone` is not sent since 1.13.0. |
| `stopPlaceDeleted(ProximiStop)` | The stop's POI was deleted on the backend while the journey screen is open. Once per stop. With `.progress` (and in `ProximiMap`) the stop is skipped. |
| `amenitySelected(ProximiStop)` | An amenity picked on the map. A card shows it with "Go here"; the map marks it in red and shows it with the visitor, or its own floor around it (`amenityFramingMinimumMeters`). |
| `detourStarted(ProximiStop)`, `detourEnded(ProximiStop, completed:)` | "Add a stop" on an amenity's card during a journey, or the host app's `destination`; the detour reached (`completed`) or left. |
| `destinationUnavailable(poiID:reason:)` | `ProximiMapView` does not route to the host app's `destination`: `.unknownPlace`, `.noRoute` or `.noPosition`. `poiID` is the id the host app gave. The view sets the binding back to `nil`. |
| `journeyPaused` | "Add a stop" on an amenity's card during a journey, after `detourStarted`: the journey waits for "Resume your Journey" or the host app's `isPaused` `false`. `isPaused` is `true` before it. |
| `journeyResumed` | "Resume your Journey": after a detour, or on the card of a journey the host app paused (`ProximiMapView`'s `isPaused`). |
| `offRoute(duration:)`, `backOnRoute` | The visitor has been off the route for `offRouteSeconds`; the visitor is on the route again. |
| `journeyFinished` | Every stop is visited or skipped. Journey Complete shows with `ProximiMap` and with `ProximiMapView.Options.journeyComplete`. |
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
| `advancesOnArtworkExit` | `true` | The route leads to the next stop when the visitor leaves the active artwork's geofence (Nagarro, 2026-10-30). `false`: `artworkAdvanceDelay` after entering it. |
| `artworkAdvanceDelay` | 2 s | With `advancesOnArtworkExit` `false`: from the arrival at an artwork (its geofence) to the route to the next stop. |
| `outOfOrderDwell` | 0 s | Time inside another artwork's geofence before it counts as visited out of order (personalised journeys only). |
| `amenityArrivalMinimumMeters`, `amenityArrivalMaximumMeters`, `amenityArrivalDwell` | 5 m, 10 m, 5 s | An amenity is reached within 2.5 × the position accuracy, within these bounds, for this time. |
| `geofenceExitDelay` | 5 s | Time outside an entered geofence or privacy zone before the SDK reports the exit (`ProximiioConfiguration.geofenceExitDelay`, SDK default 3 s). Enters are reported at once. `ProximiMap` sets it when it starts the SDK; `ProximiMapView` uses the host app's SDK configuration. 0 reports the exit at the first position outside. |
| `stopNearbyMeters` | 5 m | The distance of `ProximiMapEvent.stopNearby`. |
| `offRouteMeters`, `offRouteSeconds` | 12 m, 300 s | "Looks like you've left your route": this far from the leg to the current destination, or off the journey this long. Back within two thirds of the distance the visitor is on the leg again. |
| `offRouteWarningSeconds` | 10 s | How long "Looks like you've left your route" stays open, unless the visitor closes it. |
| `wrongFloorSeconds` | 10 s | Time on a floor the route does not take before the visitor counts as off the route. |
| `routeSnapMeters` | 0.5 m | The dot is drawn on the route within this distance. Display only. |
| `followZoom` | 18.8 | Zoom of "Centre on me", of the first position and of the follow. |
| `galleryFollowZoom` | 20 | Zoom of the follow while the visitor is in a gallery during a personalised journey; `nil` for `followZoom`. A camera the visitor moved stays. |
| `startZoom` | 18 | The journey map shows the visitor at this zoom for `startZoomSeconds`, then follows them: when the journey starts, on the first fix and when the position comes back. `nil` follows at once. |
| `startZoomSeconds` | 2 | How long the journey map stays at `startZoom`. |
| `groupsStopMarkers` | `true` | Journey stop markers that would overlap show as one marker, with a black badge holding the number of the others. |
| `bearingSettlingTime` | 1.5 s | Time the heading-up map takes to turn to a new heading (`MapOptions.bearingSettlingTime`, map default 0.9 s). |
| `bearingDeadband` | 5° | Heading changes smaller than this do not turn the map (`MapOptions.bearingDeadband`, map default 0°). |
| `minimumZoom`, `maximumZoom` | `nil` | The zoom levels the visitor cannot go beyond on every map of the package, or the map library's limits. The frames the map sets keep to them too (`MapOptions.minimumZoom`, `maximumZoom`, map 6.0.0-beta.52). |
| `smoothsPosition` | `false` | `true` slides the position dot toward each fix; `false` draws it on each fix, without the delay of the sliding. |
| `mapLoadingTimeout` | 20 s | The longest time a map shows its spinner while the venue's features are not on the map. |
| `amenityFramingMinimumMeters` | 40 m | The smallest area the map shows for an amenity picked in the menu. |
| `galleryFirstMarginMeters` | 50 m | Gallery first: an artwork farther than this outside its gallery's geofence, or on another floor, is routed to directly. |
| `liftRideDwell`, `liftExitFixes` | 3 s, 2 | Seconds of fixes inside a lift outline before the visitor counts as riding it, and the fixes outside that end the ride. The field log records the rides. |
| `levelsWithoutPositioning` | [0] | Floors without positioning. See "Floors without positioning". |
| `levelChangerReachedMeters` | 5 m | Distance from the lift or stairs to a floor without positioning at which the lift or stairs view shows. |
| `levelChangeViewSeconds` | 5 s | How long the lift or stairs view shows before the map shows the floor without positioning. |
| `rideFloorHoldMeters` | 20 m | After the lift or stairs view of a ride, the map shows the floor the ride ends on until a fix on another floor than the ride's start, or a fix on that floor this far from the lift or stairs. |
| `floorWithoutPositioningMaximumSeconds` | 1800 s | After this time on a floor without positioning with the same destination, the map follows the visitor again. |
| `uncertainAccuracyMeters`, `locationQuestionQuietPeriod` | 8 m, 120 s | "Probably at …": an uncertain position near the next stop, and how long an answered prompt stays quiet. |
| `firstFixWait`, `lateOrderWindow` | 5 s, 60 s | A new personalised journey waits this long for a fix before it is ordered without one, and the first fix within the window orders it again. |
| `liveActivityMinimumInterval` | 5 s | The shortest gap between two Live Activity updates of the instruction. |
| `postsGeofenceNotifications` | `true` | A notification for every enter and exit of a geofence with a name, and the notification authorization request once a wristband is connected. The package posts no "next stop" notification; a host app can post one for `ProximiMapEvent.stopNearby`. It sets the `UNUserNotificationCenter` delegate, which shows them in the foreground. A host app with its own delegate turns it off. |
| `notifiesGeofenceEvents` | `true` | With `postsGeofenceNotifications`: `false` posts no geofence notification; the authorization and the foreground banners stay. |
| `venueDataRefreshInterval` | 300 s | Deprecated, no effect since 1.8.0. The SDK's `ProximiioConfiguration.syncInterval` sets how often changes arrive. See "Venue data changes". |

## Artwork details in the list

A journey list row shows the artist and "AR" and audio badges from the artwork's POI
`properties.metadata`. Without `artist_name` the row shows the level. The stop card shows the same
badges while it names the artwork.

| Key | Value | Shows |
|---|---|---|
| `artist_name` | String, or an i18n object like `title_i18n` | The artist under the title. |
| `augmented_reality` or `has_ar` | `"enabled"` or `true` | "AR". |
| `audio` or `has_audio` | `"enabled"` or `true` | A note. |

In the GAD venue data on 2026-10-15 one artwork has `augmented_reality` and `audio` (Tongari-kun).

### Gallery headers

In a personalised journey the list shows a header before the stops of each gallery. The gallery of
an artwork is its `metadata.gallery_id`, named by the title of the POI whose
`remote_id` is that id ("G403 Weaving"). An artwork without one is under the gallery outline it lies
in, else under its level ("Level 4"). The GAD venue data on 2026-10-15 has `gallery_id` on artworks in
18 galleries; 14 of the 18 have a gallery POI.

## Floors without positioning

A floor in `GADSettings.levelsWithoutPositioning` has no positioning. In stage 1 that is the GAD
level 0, with the café and the prayer room. A route there, on the journey map and the museum map of
Journey Complete:

1. leads to the lift or stairs as usual;
2. within `levelChangerReachedMeters` of the lift or stairs, shows the lift or stairs view ("Take the
   stairs to level 0", "Your position is not shown on this level.") for `levelChangeViewSeconds`; a tap
   ends it;
3. shows that floor without the route, with the destination highlighted. The map does not follow the
   visitor there, no off-route warning shows, the position is not checked against artwork geofences
   (their enter events still count), and the card says that the position is not shown;
4. on the journey map, "Resume your Journey" there starts the way back: the map stays on that floor
   without the route and highlights the lift or stairs to the next stop's floor nearest the destination.
   The card reads "NEXT STOP IS LEVEL 1", the stop and "Head to Level 1 by lift or stairs". The first
   new fix ends it.

The map follows the visitor again when the destination changes (another stop or route), on "Centre on
me" or the floor button, after the way back, or after `floorWithoutPositioningMaximumSeconds`.
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
- The journey map and the museum map of Journey Complete have an accessible routes button (a wheelchair,
  with a black outline while on). While it is on, routes avoid all four (`RouteAccessibility.accessible`), whatever the host app set.
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

`FieldLog` writes relay positions, positions during a visit, tracking health, artwork arrivals, journey,
binding and `ProximiMap` events, and the state of each map when it changes (venue features on the map,
features left out, style source, floor, zoom, the style's fonts the glyph server does not have, last
error), to `Documents/gad-debug.log`. It does not write the SDK's geofence
events. It is off by default. Turn it on at launch, before `start()`, in test builds only:

```swift
FieldLog.isEnabled = true
FieldLog.logLaunch()
```

`FieldLogShareButton()` opens the share sheet with the file. A line is `[GAD] <time stamp> <message>`;
the time stamp is ISO 8601 in UTC with the date and milliseconds (`FieldLog.timeStamp`).

Each bind writes `wristband bind: tag <label> · binding <id>`, or `tag <label> · failed: <error>`. The label
is the band's id as scanned; the relay team looks the band up by it.

Two lines time the start and each map:

- `map: ready · 237 places · start 4.92 s`: the time `start()` took.
- `map timing explore: style cache 0.01 s · features 968 1.32 s · camera ready 1.32 s · shown 1.32 s · drawn 1.80 s, 2.82 s after open()`:
  the time from the map view's appearance to each style the map took, the first venue features on the
  map, the camera framing the venue, and the first frame MapLibre drew with the venue's features,
  tiles, icons and labels (`drawn`, the map's `venueDrawing`, map 6.0.0-beta.56). `shown` is the last of
  the first venue style, the features and the camera. After a screen opened with `open(_:)`, the time
  from that call follows `drawn`. A view closed earlier writes `closed … before drawn`. A style the
  map takes later gets a line with `after drawn`, and a second drawing a line `drawn again`: the style
  was loaded twice.

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
| `-openMap` | Opens the Explore Museum map. |
| `-hostedMap` | With `-visit` or alone: the journey in `ProximiMapView` with the default options and a debug bar. With `-openMap`: `ProximiExploreView`. |
| `-hostedDestination <title>` | With `-hostedMap`: after 5 s sets `destination` to the place with this title, else the first whose title contains it, by its `properties.id`. |
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
- The maps load the style's raster tiles from the host in `proximiio:raster:tileurl`, without the
  token and the visitor headers.

## Tests

```
xcodebuild test -scheme ProximiioGADKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Changelog

Every version is a git tag. **Breaking** marks a change that needs a change in the host app's code or
dependencies; the entry says what to change. Entries before 1.0.0 name the types of the API before
`ProximiMap`.

### 1.30.1 (2026-10-30)

No change for host apps' code.

Fixed (PM, iPhone X and iPhone SE, 2026-10-30):

- On a 375 pt wide screen the amenity list under search pushed the journey map card past the screen's right
  edge: the Map / List control and the list's column stood in one row, and with the widest chip ("Learning &
  Engagement") they were wider than the card. The list now reaches under the control's column instead.
- On a screen wider than the background image's aspect (iPhone SE, 375 × 667 pt), the filled background made
  the screen taller than the display: the bottom bar and the bottom of the stop card were below it. The
  background now fills the screen without sizing it. The Hub and Journey Complete use the same background.
- Checked on an iPhone SE (3rd generation) simulator, iOS 26.3: the search button, the chips and the bottom bar
  are on the screen (`AddStopUITests.testTheAmenityListStaysOnScreen`).
- Debug builds: `-visitSearch` opens the journey with the amenity list open.

### 1.30.0 (2026-10-30)

**Breaking** (only for an app that uses `ProximiMap`; `ProximiMapView` and `ProximiExploreView` are
unchanged):
- `ProximiMap` is an `ObservableObject`, no longer `@Observable`. Hold it with `@StateObject` instead of
  `@State`, and pass it as `@ObservedObject` instead of `@Bindable` or a plain property.

Changed:

- The package and its Live Activity target support iOS 16.4 and later, was iOS 17 (owner, 2026-10-30:
  the PM tests on an iPhone X, whose last iOS is 16.7). The SDK and the map support iOS 15.
- The package's classes are `ObservableObject`s; Observation needs iOS 17.
- On iOS 16 a change of the app language builds the open package view again: an open map starts again,
  at the journey's current state. iOS 17 and later update the texts in place, as in 1.28.0.
- On iOS 16 the amenity list's chips are clipped at the list's edges, and the bottom space of the
  scrolling lists is a safe-area inset (`contentMargins` and `scrollClipDisabled` need iOS 17).

### 1.29.0 (2026-10-30)

No change for host apps' code.

Added:

- `GADSettings.advancesOnArtworkExit` (`true`): the journey moves to the next stop when the visitor leaves
  the active artwork's geofence, not when they enter it (Nagarro call, 2026-10-30: the next stop comes from
  the exit event). The audio guide can play while the visitor is at the artwork. It leaves on the SDK's
  `geofenceExited`, after `geofenceExitDelay` outside it without that event, or at once at a fix in
  another open artwork's geofence. `artworkReached` and the stop's `.visited` come at that moment. While
  the visitor is at the artwork, the card and the route still show it as the next stop. `false` keeps the
  move `artworkAdvanceDelay` after the enter.
- Field log: `artwork geofence arrival: … · next stop at the exit` and `artwork left (<exit event | outside
  for n s | in another artwork>): … · next stop`.

### 1.28.0 (2026-10-30)

No change for host apps' code. `ProximiMapView` now writes `isPaused` on "Add a stop".

Changed (Nagarro, 2026-10-30: after their play button the card still offered "Resume your Journey"):

- "Add a stop" sets `isPaused` to `true` before `journeyPaused`. The card shows the amenity and "Resume your
  Journey", not "Journey paused". The host app's `false` ends the detour as "Resume your Journey" does, and
  the card shows the next stop. "Resume your Journey" on the detour's card, and a detour that ends otherwise,
  set `isPaused` back to `false`. Before, a host app that set `isPaused` to `true` on `journeyPaused` got
  "Journey paused", and its `false` left the detour's card with "Resume your Journey".
- "Add a stop" while the host app has paused the journey: resuming the pause shows the detour's card, and
  `isPaused` is `true` again until the detour ends.

Changed (Nagarro, 2026-10-30: the language changed wrongly while the app ran):

- The package's texts follow a change of the app language at once, also on an open map. Before, only the
  map labels did; the texts changed at the next launch.
- The language is the one of the `\.locale` the host app gives a package view, when it is not the language
  the app started in, else the first of `AppleLanguages`. Before, the package read only `AppleLanguages`.
- The package views' layout direction follows the language: right to left in Arabic.
- Field log: `app language <ar|en> (host locale <id>)` or `(AppleLanguages)` on each change.

Changed: the journey map screen is laid out as the Figma frame 10889:108085 (iPhone 17 Pro, 402 × 874 pt). Each
value was measured on the simulator against the frame and is within 1 pt of it (owner, 2026-10-30: as close to
the design as possible).

- The map card starts 3 pt below the status bar (8 pt before). The bottom bar is 11.5 pt under the card (10 pt
  before), 93.5 pt high (93 pt), and ends 21 pt into the bottom safe area (14 pt). The card is 691 pt high on the
  iPhone 17 Pro (681 pt before).
- The card has the design's shadow outside it (blur 50, y −3, 15 % black), and its 1 pt white stroke is outside
  the card (inside before).
- The controls in the card are 21 pt from its sides (20 pt before). The stop card is 23 pt above the card's bottom
  edge (20 pt) and 12 pt under the compass, accessible routes and floor buttons (10 pt).
- The stop card's instruction line is 18.5 pt high, as in the design; the card is 105.5 pt high (101 pt before).
- The Map / List control keeps the style of the PM's 2026-10-28 frame (Monday "Native elements").

### 1.27.1 (2026-10-30)

No change for host apps' code.

Changed (Nagarro, 2026-10-30: the controls at the top of the journey map sat too close to the drag
handle):

- On the journey map the Map / List control and the search button are 32 pt below the card's top edge,
  as in the Figma frame 10889:108085. They were 22 pt below it, 8 pt under the handle; now 17 pt.
- The drag handle is drawn as in the design: 60 × 6 pt at 20 % black, a 2 pt white stroke outside it,
  9 pt below the card's top edge. Before, the white stroke was inside the 6 pt, so only 2 pt of grey
  showed.

### 1.27.0 (2026-10-30)

**Breaking:**
- `proximiio-map-ios-binary` 6.0.0-beta.59 (SDK 6.0.0-beta.68 unchanged). A host app that depends on it
  sets the same version.

Changed:

- The maps ask for no floor-plan tile outside the area and zoom range the venue style names. Map
  6.0.0-beta.59 reads `proximiio:raster:bounds` (`[west, south, east, north]` in degrees) from the style
  metadata; `proximiio:raster:minzoom` and `maxzoom` were read before. Before, the Explore Museum map asked
  on every launch for 3 tiles outside the GAD tiles, which the tile store refused, and MapLibre asked them
  again after 1, 2 and 4 s; above zoom 20.5 it asked for z22 tiles, which do not exist. The GAD style has
  bounds [54.393654, 24.535255, 54.40361, 24.543376], min zoom 9 and max zoom 21 since 2026-10-30.
  Explore Museum drawn 0.82–1.01 s after `open()` (0.92–1.69 s with map 6.0.0-beta.58; simulator, cold
  launch).

### 1.26.1 (2026-10-30)

No change for host apps' code.

Changed:

- The journey map puts its camera at the SDK's last position (`Proximiio.lastPosition`), at the start
  zoom and without animation, and selects that position's floor, before the venue's features are on the
  map (proposal of the proximiio-ios-sdk measurement, 2026-10-29). A position older than
  `GADSettings.trackingLostAfter` is not used. The start zoom's move to the visitor has no animation
  either. On the simulator, with the visitor on level 1, the drawn map came 0.74–0.98 s after the
  screen appeared (0.78–0.91 s with 1.26.0): no measurable change there.

### 1.26.0 (2026-10-29)

No change for host apps' code.

Changed:

- The maps' amenity search lists every amenity with `metadata.in_search` true that has a place, also
  one that is none of the built-in kinds (Women's restroom, Men's restroom, Café, Help Desk, Prayer
  Room, Stairs, Elevator, Museum Shop). Such an amenity shows with its title in the app language and
  its icon from the venue data, in its `search_order`, and the shortcut leads to its nearest place.
  Before, only the built-in kinds showed: "Learning & Engagement", "Single Artist Gallery",
  "Performance Gallery" and "Artwork" did not (PM, 2026-10-29). Without an amenity flagged true the
  shortcuts stay the built-in ones.
- A chip's title stays on one line.

### 1.25.0 (2026-10-29)

**Breaking:**
- `proximiio-sdk-ios-binary` 6.0.0-beta.68 and `proximiio-map-ios-binary` 6.0.0-beta.58. A host app that
  depends on them sets the same versions. SDK 6.0.0-beta.68 returns `features()` and `geofences()` from
  memory until the store changes; map 6.0.0-beta.58 reads `features()` once per map screen. With
  DerivedData of an earlier map version, the build reports "value of type 'JourneyStopMarkerStyle' has no
  member 'groupsOverlapping'"; Product › Clean Build Folder clears it.

Added:

- Journey stop markers that would overlap show as one marker: the active stop if it is in the group,
  else the first in journey order, with a 16 pt black badge at its top-right corner holding the number
  of the others in white (RPR design; PM, Monday "Clustering", 2026-10-29; map 6.0.0-beta.58). Only
  stops on the same floor group; the detour marker never does. A tap on a group zooms in until it
  splits. `GADSettings.groupsStopMarkers` (`true`) turns it off.
- `GADSettings.bearingSettlingTime` (1.5 s) and `bearingDeadband` (5°): the heading-up map turns more
  slowly and ignores small heading changes (Nagarro: the rotation is too fast, 2026-10-29). The map
  library's defaults are 0.9 s and 0°.

Changed:

- Map start with SDK 6.0.0-beta.68 and map 6.0.0-beta.58 (simulator, cold launch, from the screen's
  opening to the drawn map): journey 1.13–1.29 s (2.46–2.76 s with 1.22.2), Explore Museum 0.87–1.41 s
  (2.41–2.64 s), `ProximiMapView` 0.9–1.2 s without `prepare(sdk:)` (about 3.7 s). The venue's features
  are on the map 0.03–0.12 s after the screen appears. Installing the route network for a hosted view
  takes 0.01 s.
- The galleries' names give way to each other and to the stop markers: of names that would overlap, one
  shows, a visited gallery's first. The destination's name always shows. Zoomed out, every name showed
  over the others (the PM's screenshot, 2026-10-29).

### 1.24.1 (2026-10-29)

No change for host apps' code.

Changed:

- A long amenity list under the search button scrolls and fades out at the bottom, above the map's
  buttons, on the journey map and the museum map (PM, Monday "Amenity search when list is long",
  2026-10-29). A list that fits does not scroll.

### 1.24.0 (2026-10-29)

No change for host apps' code.

Added:

- `GADSettings.startZoom` (18) and `startZoomSeconds` (2): the journey map shows the visitor at zoom 18
  for 2 s, then follows them at the follow zoom. It does this when the journey starts, on the first fix
  and when the position comes back. `nil` follows at once (PM, Monday "Zoom level at start +
  navigation", 2026-10-29).

Changed (PM, Monday, 2026-10-29):

- The journey map fills every gallery but the visitor's: the gallery the leg ends at with the
  destination colour, a visited gallery with the visited colour, every other gallery with the venue
  style's gallery colour over its artworks and furniture. The artworks and furniture show only in the
  gallery the visitor is in; artworks outside the galleries show as before ("Artwork + furniture
  polygons").
- A curated tour shows the galleries' pills and fills as a personalised journey does: the gallery of
  the active artwork is the destination, a visited gallery is visited ("Gallery numbers in gallery
  navigation"). Its route, list and instructions are unchanged.
- A gallery is marked as visited once the visitor is out of it ("Visited gallery visualization").
- Field log: `gallery fills: visitor in <gallery> · destination <gallery> · <n> visited · <n> standard`
  on each change, and `start zoom (<reason>) · zoom <z> for <s> s`.

### 1.23.0 (2026-10-29)

No change for host apps' code.

Added:

- `ProximiMapView.prepare(sdk:)`: installs the route network and reads the venue's features,
  geofences and amenities for the `ProximiMapView`s and `ProximiExploreView`s on the SDK, before the
  first one opens. Optional; without it the first view does this when it opens. From the view's
  opening to the drawn map (simulator, cold launch, the host app's SDK started): `ProximiMapView`
  about 3.7 s with 1.22.2, 1.3–1.55 s after `prepare(sdk:)`; `ProximiExploreView` 2.41–2.64 s with
  1.22.2, 1.53–2.00 s after `prepare(sdk:)`.

Changed (Nagarro: "the map takes 2–2.5 s to start"):

- The package reads the venue's features, geofences and amenities from the SDK once and keeps them in
  memory. It reads a kind again only when `venueDataChanges()` names it. Each screen used to read them
  itself: the journey screen read the features two or three times. The SDK decodes every stored feature
  on each `features()` call (0.5 s for the GAD venue's 995 features on the simulator) and serves one
  call at a time, so the map library's own read of the features waited behind them. Venue on the map
  after the screen appeared (simulator, cold launch): Explore Museum 1.05–1.29 s before, 0.60–0.79 s
  after; journey 1.53–1.72 s before, 0.74–0.89 s after; `ProximiMapView` 1.55–1.75 s before,
  0.56–0.83 s after.
- `ProximiMapView` and `ProximiExploreView` keep the route network and the venue data for the next view
  on the same SDK. They follow `venueDataChanges()` also after they closed. The first view installs the
  route network; after the SDK stopped, the next view does it again.
- A change of the amenity catalogue (`.amenities` in `venueDataChanges()`) updates the screens' amenity
  icons and lists.
- Field log: `venue data: <n> features read in <s>` (also geofences and amenities; the time includes
  the wait for the SDK's earlier calls) and `hosted map: route network <n> paths in <s>`.

Fixed:

- Since 1.22.0 the map library never reported the venue as drawn (`ProximiioMapSession.venueDrawing`),
  so the field log's `map timing` line had no `drawn`. The cones of the other floors were hidden
  layers; MapLibre does not load the image source of a hidden layer, and a source that is not loaded
  keeps every frame from counting as fully rendered. The other floors' cones are now taken off the map.

### 1.22.2 (2026-10-29)

No change for host apps' code.

Changed:

- The cones' outline is a hairline, as in the Figma kiosk: 0.3 pt at zoom 16, 0.6 pt at 19 and 1.2 pt
  at 21 (1.22.1: 1.28 pt at every zoom, far stronger than the design; the user's comparison of
  2026-10-29).

### 1.22.1 (2026-10-29)

No change for host apps' code.

Changed (closer to the Figma kiosk "Spaces - level 3", the user's comparison of 2026-10-29):

- A cone image starts with the design's floor colour #FAFAFB under the gradient; the cones were grey
  where the venue's floor showed through.
- The cones are under the venue style's galleries (`proximiio-gallery`), so a cone that is a gallery
  keeps the gallery's colour on every map.
- The cones' outline is the design's: the style's `proximiio-cones` line in #95A6B5 at 48 % opacity,
  1.28 pt (was #B2B2B2, 1 px).
- The white edge inside the outline is 0.34 m, half the design's 3.2 px line.

### 1.22.0 (2026-10-29)

No change for host apps' code.

Added:

- The journey map, the Explore Museum map and the museum map fill the building's cones (polygon
  features of type `cone`) with the design's metal gradient: #D4DEE6, #F8FAFC, #E8EEF2, #CBD6DF,
  #AEBCC9 across the cone, at 32 % opacity, with a white edge inside the outline (Figma "0 - DPT Map
  Kiosk"; PM, Monday "Cone visualization", 2026-10-29). A map style fills a polygon with one colour
  only, so the package draws each cone as an image over the floor plan, under the gallery fills; the
  venue style keeps the cones' grey outline (`proximiio-cones`).

### 1.21.1 (2026-10-29)

No change for host apps' code.

Fixed:

- "Looks like you've left your route" follows the leg to the current destination: 12 m off it shows
  the warning, also where a later leg of the journey passes (Monday "Personalized tour: off-route and
  re-route behaviour"). The PM's log of 2026-10-28, 22:39 UTC: a visitor 56 m off the leg, heading to
  another artwork, got no warning, because the map library's `leftRoute` measures against every leg
  still to walk. 1.20.0 said the warning came at 12 m from the route to the current destination; it
  did not. The leg follow rules now use `GADSettings.offRouteMeters` too.

### 1.21.0 (2026-10-29)

No change for host apps' code. The items come from the GAD PM's Monday notes of 28 October evening.

Added:

- `GADSettings.rideFloorHoldMeters` (20 m). After the lift or stairs view the map shows the floor the
  ride ends on and keeps it until a fix on another floor than the ride's start, or a fix on that floor
  this far from the lift or stairs (Monday "Elevator/Staircase animation"). The PM drew privacy zones
  around the lifts and stairs, so the dot is hidden during the ride.
- The Map / List selection slides with the finger to the other part, as on the system's segmented
  control (Monday "Native elements").
- The field log names how many Explore Museum galleries are filled on their polygon and how many on
  their geofence.

Changed:

- Every gallery's POI is a pill with its title: red with a white border for the gallery the leg leads
  to, white with a red outline for a visited gallery, white with a black outline for the others. A
  curated tour shows every pill in the white style. Before, only the destination and the visited
  galleries had a marker, a visited one the amenity icon in a circle (Monday "Gallery numbers in
  gallery navigation").
- The gallery the visitor is in has no destination fill: the venue's own gallery colour, under the
  artworks and furniture, with the artwork numbers (Monday "Navigation to a gallery").

### 1.20.1 (2026-10-28)

No change for host apps' code.

Added:

- The field log names the band at each bind: `wristband bind: tag <label> · binding <id>` (relay-api,
  2026-10-28: the PM's log had the binding but not the band).

### 1.20.0 (2026-10-28)

**Breaking:**
- `proximiio-sdk-ios-binary` 6.0.0-beta.67 and `proximiio-map-ios-binary` 6.0.0-beta.57. A host app that
  depends on them sets the same versions. SDK 6.0.0-beta.67: venue records deleted on the server leave
  the phone within about 15 minutes. Map 6.0.0-beta.56: no second load of a stored style that equals the
  organisation's. With DerivedData of an earlier map version, Xcode 26.3 and 27.0 reported "value of type
  'ProximiioMapSession' has no member '$venueDrawing'"; Product › Clean Build Folder clears it.
- For a host app that depends on `lottie-ios`: the package depends on `lottie-spm` (from 4.5.0), the
  package Nagarro's app uses, in place of `lottie-ios` of 1.19.0. Such an app moves to `lottie-spm`.

Changed:

- The journey map draws the stop numbers over the visitor's dot (`drawsAbovePosition`, map
  6.0.0-beta.56; RPR, Monday "Stop markers.", 2026-10-28).
- Off the route (PM, Monday "Personalized tour: off-route and re-route behaviour" and "Curated tour:
  off-route and recalculation", 2026-10-28): "Looks like you've left your route" shows
  `GADSettings.offRouteMeters` off the route to the current destination, now 12 m (was 30 m), also when
  the visitor heads to another artwork. With `.offRoutePrompt` the navigator routes nothing by itself;
  the warning comes first, then a curated tour is routed again from the visitor and a personalised
  journey is ordered again when another artwork is nearer. Before, a curated tour was routed again every
  10 s before the warning.
- The lift or stairs view, with its animation and "Take the stairs to level 3", shows at every ride of
  the route, not only on the way to a floor without positioning (PM, Monday "Elevator/Staircase
  animation", 2026-10-28). "Your position is not shown on this level." stays for those floors.
- The amenity glyphs of the detour markers are added to the map style at every style load. Added once
  before the style had loaded, they were missing (PM, Monday "Amenity icon disappears sometimes").
- The floor on the journey map is a label, not a button (PM, Monday "Current level button").
- "Skip this artwork?" has less space under "Keep it" (PM, Monday "Skip artwork popup too large").
- Explore Museum: the lists fade out over 90 pt above the tab bar, was 30 pt (PM, Monday "Explore museum:
  spaces list fade").
- The Map / List control is two buttons on glass with 16 pt corners; the selected part has a black
  outline (PM, Monday "Native elements", Figma frame of 2026-10-28).
- The map fades out under the controls at the top and the card at the bottom (RPR, Monday "Map fade at
  top & bottom").
- The field log's map timing ends at the first frame the map drew with the venue (`drawn`,
  `venueDrawing`).
- A gallery is visited when its artworks of the journey are all visited or skipped and at least one is
  visited (the customer, Monday "Visited gallery visualization", 2026-10-28). Before, one visited
  artwork was enough.
- The accessible routes button, when on, has a black outline and no blue fill (RPR, Monday "Accessible
  routing", 2026-10-28).
- The stop card keeps its instruction line while the route is routed again, so the card and the buttons
  above it no longer jump when the accessible routes button is pressed (same item).
- The glass buttons are `glassSurface` with a 1 pt ink outline while pressed or selected, not Apple's
  glass button style, which grew on a press (PM, Monday "Buttons to have black border when pressed",
  2026-10-28). The search shortcuts, "Centre on me" and the accessible routes button show the outline
  while pressed.
- The search shortcuts have a white haze behind them (RPR, Monday "White blur behind amenity list").
- `GADSettings.followZoom` is 18.8, was 19 (RPR, Monday "Need to determine correct zoom levels
  on-site").
- The destination gallery is a red pill with a white border and its title in white, no icon (RPR and
  the PM, Monday "Gallery numbers in gallery navigation", 2026-10-28).
- The journey map knows every gallery with a `gallery_id`, named by its POI. The gallery outlines were
  named by a POI whose title says "gallery"; after the GAD POIs were renamed ("G101 Pop Culture") only
  three galleries were known, so no other gallery showed as visited (PM, Monday "Visited gallery
  visualization").

### 1.19.0 (2026-10-28)

**Breaking** for a host app that depends on `lottie-spm`: the package now depends on `lottie-ios`
(from 4.5.0). Such an app moves to `lottie-ios`. Other host apps change nothing.

Added:

- The lift and stairs view on the way to a floor without positioning plays RPR's animation of a lift or
  stairs going up or down (Lottie; PM, Monday "Elevator/Staircase animation"). Escalators use the
  stairs.

Changed:

- Explore Museum: the floor changer opens a glass button for each level, highest first, the shown
  level in bold, with a chevron that closes it, not a menu of "Level N" rows (PM, Monday "Explore
  museum: Level selector dropdown", 2026-10-28).

### 1.18.1 (2026-10-28)

No change for host apps' code.

Changed (PM's answers, 2026-10-28):

- When an amenity has `metadata.in_search` true, the search shortcuts are only the amenities with it.
  Without one, they are the built-in ones (women's and men's restroom, café, help desk, prayer room,
  museum shop), without those whose flag is false. `in_facilities` does the same for the Explore Museum
  Amenities list and the legend's facilities. On 2026-10-28 only Museum Shop has `in_search` true.
- A gallery is visited when it holds a visited artwork of the journey. Being in the gallery no longer
  counts.

### 1.18.0 (2026-10-28)

No change for host apps' code.

Changed:

- The search shortcuts, the Explore Museum amenities and the legend find a place by its amenity, not
  by its title. The prayer room shortcut led to the artwork "Endless Prayers XIII" (PM, Monday "Amenity
  search & Map legend views", 2026-10-28).
- Gallery first: the gallery the leg ends at is the icon of the gallery POI's amenity in the red circle
  with its title under it, not the red label "G303" (PM, Monday "Gallery numbers in gallery
  navigation", 2026-10-28). The stop card shows the same icon (Monday "Gallery icons missing from
  instructions").
- A visited gallery is filled over the venue's artworks, furniture and inner walls, and its POI is the
  amenity's icon in the white circle with the red border, with its title (Monday "Visited gallery
  visualization").

### 1.17.0 (2026-10-28)

No change for host apps' code.

Added:

- `ProximiMapView(isPaused:)`: the host app pauses and resumes the journey, for example from the audio
  guide (Nagarro, 2026-10-28). See [Pausing the journey](#pausing-the-journey).
- `ProximiMapEvent.journeyPaused`: "Add a stop" on an amenity, after `detourStarted`. `journeyResumed`
  also comes from "Resume your Journey" on the card of a paused journey.

### 1.16.1 (2026-10-28)

No change for host apps' code.

Added:

- The field log times `start()` (`map: ready · … · start 4.92 s`) and each map, from the map view's
  appearance until it shows the venue (`map timing`). See "Field log".

### 1.16.0 (2026-10-28)

**Breaking:** `proximiio-map-ios-binary` 6.0.0-beta.55. A host app that depends on it sets the same
version.

Added:

- The maps draw the raster tiles of the organisation's style, the illustrated map of the GAD venue
  (map 6.0.0-beta.55; PM, Monday "Illustrated map not visible"). See "ProximiMap".
- The field log's map state names the style's fonts the glyph server does not have ("missing fonts").

Changed:

- Gallery first keeps hiding the artworks' numbers with the invisible style of 1.15.3, so the detour
  keeps its marker. Map 6.0.0-beta.55 takes the markers off the map with a stop marker style of `nil`.

### 1.15.4 (2026-10-27)

No change for host apps' code.

Changed:

- Explore Museum: a selected amenity is the black dot in a ring, as a gallery and an artwork, not the
  red marker with its icon (PM, Monday "Explore Museum view: gallery POI view", 2026-10-27).

### 1.15.3 (2026-10-27)

No change for host apps' code.

Added:

- `GADSettings.offRouteWarningSeconds` (10 s): "Looks like you've left your route" stays open this
  long, unless the visitor closes it. The routing after it no longer closes it (PM, Monday
  "Personalized tour: off-route and re-route behaviour" and "Curated tour: off-route and
  recalculation", 2026-10-27).
- `GADSettings.wrongFloorSeconds` (10 s): a visitor on a floor the route ahead does not take counts as
  off the route. The warning shows, and the leg is drawn again from the visitor: to the nearest open
  artwork in a personalised journey, to the next stop in a curated tour (PM, Monday "Wrong floor to
  trigger off-route and re-routing").

- The amenity's `metadata` chooses and orders the lists (PM, Monday "Amenity search & Map legend
  views", 2026-10-27): `in_search` and `search_order` the search shortcuts of the journey map and the
  museum map, `in_facilities` and `facilities_order` the Explore Museum map's Amenities list (within a
  level) and the legend's facilities. Metadata and both keys are optional: a flag `false` leaves an
  amenity out, `true` puts in one the list does not show by itself, and an amenity without an order
  comes after the ordered ones in the list's own order. The legend's galleries keep the data's order.

Changed:

- Gallery first: the numbers of the artworks are hidden while the visitor is outside every gallery and
  the active artwork is in a gallery, as well as while the leg ends at a gallery. A detour keeps its
  marker (PM, Monday "Navigation to a gallery", 2026-10-27).
- The destination gallery is filled over the venue's artworks, furniture and inner walls
  (`proximiio-inner_wall`), not only over the floor fills (same item).
- "Add a stop" takes the map back to the visitor (PM, Monday "Adding amenity -> focus back on my
  location").
- While the next stop is on another floor, the stop card shows the lift or stairs icon of the next
  level change (PM, Monday "Stairs&elevator icon disappeared from instructions").
- Map icons from the venue data take one point per pixel, as MapTap and the portal draw them, so the
  style's `icon-size` gives the same size on both: a 120 px icon at `icon-size` 0.2 is 24 pt. Before,
  the icon took the screen's scale and was a third of that size (PM, 2026-10-27: gallery icons at 0.2
  were dots). The design's amenity markers and the Explore Museum circles take the size of the data
  icon they replace.

Fixed:

- The artworks' numbers showed on every floor after the leg had once ended at a gallery (PM, Monday
  "Artwork numbers shown on all the floors"). The view no longer sets the map's stop marker style to
  `nil`: map 6.0.0-beta.54 then keeps the marker layer on the map with the floor it showed. It hides
  the markers with an invisible style instead.

### 1.15.2 (2026-10-27)

No change for host apps' code.

Added:

- Field log: the state of each map when it changes, checked every second: "map state journey:
  features 968 · dropped 0 · style organization · L1 · zoom 19.0 · camera ready true", with the last
  error when there is one. The journey map, the museum map and the Explore Museum map write it (PM,
  Monday "Floorplan disappears zometimes", 2026-10-27).

### 1.15.1 (2026-10-27)

No change for host apps' code.

Fixed:

- Arabic texts of the strings added in 1.15.0: "Add a stop", "Looks like you've left your route", "Your
  next stop is …", "Head back to your route.", "Rerouting you…", "NEXT STOP IS LEVEL n" and "Head to
  Level n by lift or stairs". In 1.15.0 they showed in English in Arabic.

### 1.15.0 (2026-10-27)

Breaking:

- SDK 6.0.0-beta.66 and Map 6.0.0-beta.54. A host app that depends on these packages moves to the
  same versions. No source change: the SDK and the map add API only. SDK 6.0.0-beta.65 is not for end
  users (it deletes the venue data at the first refused token); 6.0.0-beta.66 replaces it.

Added:

- `ProximiMapEvent.stopOrderChanged(ProximiJourney)`: `ProximiMapView` with `.progress` reports a new order
  of the stops (Nagarro, 2026-10-26). A `switch` over `ProximiMapEvent` with `default` keeps compiling.
- README "The navigator" → "Any change of the journey": `stopOrderChanged` and the navigator's `journey`.
- `ProximiMap.start()` without a connection, on a phone where the API accepted the token before. The
  route network comes from the stored features. See [ProximiMap](#proximimap).
- One `ProximiMapView.Options` per prompt (Nagarro, 2026-10-27): `.skipPrompt`, `.offRoutePrompt`,
  `.uncertainPositionPrompt` and `.leaveTourPrompt`. `.prompts` is all four; code that passes it keeps
  compiling.
- `GADSettings.galleryFollowZoom` (20): the follow zooms in while the visitor is in a gallery during a
  personalised journey (PM, Monday "Navigation to a gallery", 2026-10-27).
- "Rerouting you…" in the middle of the map while the journey is routed again for longer than 0.5 s
  (PM, Monday "Rerouting calculation view").
- The open maps take a new `AppleLanguages` at once, for an app that switches its language itself
  (PM, Monday "Language switching option missing", 2026-10-26). The package's texts follow at the
  next launch.
- `ProximiMapView(destination:)`: the host app routes the visitor to a place at once, for example from
  the audio guide's proximiio-mcp answer, and `ProximiMapEvent.destinationUnavailable(poiID:reason:)`.
  The place's id can be the feature id or its `properties.id`, which proximiio-mcp returns. See
  [Routing to a place](#routing-to-a-place).
- `ProximiExploreView`: the Explore Museum map as a UI component on the host app's SDK, without title,
  Back and background (Nagarro, 2026-10-27). See [Explore Museum](#explore-museum).

Changed:

- During a journey the amenity card has "Add a stop" and "Close". "Add a stop" starts the detour at
  once; "Change your route?" is gone (PM, Monday "Add stop confirmation", 2026-10-26).
- Off the route (`.offRoutePrompt`): "Looks like you've left your route" with "Dismiss" takes the
  stop card's place, instead of the "You've left your route" sheet with "Show the route from here".
  A personalised journey keeps the leg until another open artwork is the nearest stop, then orders
  the stops ahead again from the visitor; a curated tour is routed again from the visitor (PM, Monday
  "Personalized tour: off-route and re-route behaviour" and "Curated tour: off-route and
  recalculation", 2026-10-26).
- An artwork visited out of order moves before the stops still to visit: the numbers in the list and
  on the map follow the visit order (1 A, 2 C, 3 B; PM, Monday "Personalized tour: renumbering
  artworks", 2026-10-26). `nextStop` is not sent for the moment the navigator walks to that artwork.
- `GADSettings.followZoom` is 19, was 21 (PM, Monday "Curated tours: zoom level", 2026-10-27).
- Explore Museum (PM, Monday, 2026-10-26): the card of a picked place is over the map with a line to
  the place, drawn as a black dot; the text under a gallery's name is its description; the map draws
  no amenity icons and larger gallery icons; a gallery is filled on its polygon, not its geofence;
  the legend's title is SemiBold 14.
- The position dot disappears when the position is lost, and in a privacy zone, instead of turning
  grey (PM, Monday "Privacy zone to have the same position marker as position disappearing").
- Floors without positioning (PM, Monday "POIs on floors with no positioning", 2026-10-26): the floor
  shows no route, with the destination highlighted; "Resume your Journey" there starts the way back,
  with the lift or stairs to the next stop's floor highlighted. See [Floors without
  positioning](#floors-without-positioning).
- Gallery first (PM, Monday "Navigation to a gallery", 2026-10-26): no numbered artwork markers while
  the leg ends at a gallery, the gallery's polygon is filled, and the POI of the gallery the visitor is
  in is not drawn.
- The top 44 pt of the map card, around its handle, do not pan the map. With `.bottomBar` and
  `onClose`, a drag down there is Back; otherwise a sheet that holds the view can be pulled down
  there (PM, Monday "More space for the pull down functionality", 2026-10-26).
- A token the API has refused for at least two hours: the SDK deletes the venue data, `ProximiMap`
  closes its screens and `status` becomes `.failed(.startFailed)`. `start()` starts again.
  `ProximiMapView`: the host app closes the view (see [ProximiMapView](#proximimapview)).
- `GADSettings.minimumZoom` and `maximumZoom` are `MapOptions.minimumZoom` and `maximumZoom`. The
  opening frame, "Centre on me", the follow and the journey's leg frames keep to them too.

Fixed:

- iOS 26: since 1.14.0 the glass took touches only where its content was. The accessible routes button
  took a tap only on its symbol (Monday "Accessible routing", 2026-10-27), a drag on the empty part of a
  journey list row did not reveal Skip, and the Skip panel took no tap. The glass surfaces take touches
  on their whole shape again; iOS 27 is unchanged.

From SDK 6.0.0-beta.65 and 6.0.0-beta.66, without a change in this package:

- `authenticate()` gives up after 30 s.
- `ProximiioAmenity.metadata`, `title(language:)` and `titleTranslations` (`title_i18n`). The package
  does not read them yet.

### 1.14.0 (2026-10-26)

No change for host apps' code. The look changes on iOS 26 and later.

Changed:

- On iOS 26 and later the buttons are Apple's glass button style (`.buttonStyle(.glass)`), and the
  cards, bars and panels are Apple's Regular glass (`glassEffect(.regular)`). The design's gradient,
  white border and shadow are gone. The system draws the pressed state. A selected button has a 1 pt
  ink outline; a disabled one is at 40 % (RPR, Figma "Glass review: iOS 26, iOS 27 and Android",
  2026-10-24: the app uses native iOS components). iOS 17 and 18 keep the design's glass.
- The Map / List toggle of the journey map is the system's segmented control.
- The Explore Museum lists fade out above the tab bar, so the rows do not show through its glass.

### 1.13.1 (2026-10-26)

No change for host apps' code.

Added:

- `GADSettings.mapLoadingTimeout` (default 20 s): the longest time the maps show their loading spinner.

Changed:

- The journey map, the Explore Museum map and the museum map show the spinner in the middle until
  the venue's features are on the map, the map reports an error or `mapLoadingTimeout` passes. Before,
  only the journey map had a spinner, and only while the first leg was routed (PM, Monday "Spinner on
  map loading center", 2026-10-26).

### 1.13.0 (2026-10-26)

No change for host apps' code. The behaviour changes below need a look.

Added:

- `ProximiMapView.Options.journeyComplete`: Journey Complete when the last stop is done. Before, it came
  with `.prompts` (Nagarro, Monday "Journey finished view", 2026-10-26). `.all` includes it.
- `GADSettings.minimumZoom` and `maximumZoom` (default `nil`): zoom limits for every map of the package.
- `GADSettings.smoothsPosition` (default `false`) and `notifiesGeofenceEvents` (default `true`).
- The Explore Museum map legend: the button left of the tabs opens it (PM, Monday "Explore Museum: Map
  legend missing"). The lists, the cards and the legend use the amenity icons of the venue data, the
  icons the map draws (PM, Monday "Explore Museum: thematic gallery icon").

Changed:

- `.prompts` no longer shows Journey Complete; add `.journeyComplete` to keep it.
- The position dot is drawn on each fix, not slid toward it (PM, Monday "Visual delay", 2026-10-23).
  `smoothsPosition = true` restores the sliding.
- While the first leg is routed, a spinner shows in the middle of the screen; the stop card shows an
  arrow (PM, Monday "Spinner on map loading center", 2026-10-26).

Removed:

- "Undo skip" in the journey list (PM, Monday "Undo skip removed", 2026-10-23).
  `ProximiMapEvent.skipUndone` is deprecated and not sent.

### 1.12.0 (2026-10-24)

No change for host apps' code.

Changed:

- A curated tour ignores the artworks further on (PM, Monday "Curated tours: ignore other artworks",
  2026-10-23). Only the next artwork counts as visited; an artwork the visitor passes or stays at
  out of order stays open, and no `artworkVisitedOutOfOrder` is sent. Personalised journeys are
  unchanged. Applies to `ProximiMap` and to `ProximiMapView` with `.progress`.

### 1.11.2 (2026-10-23)

No change for host apps' code.

Fixed:

- The Explore Museum map shows its floor changer once the museum's levels are loaded. Before, a tap
  right after the map opened showed an empty menu.

### 1.11.1 (2026-10-23)

No change for host apps' code.

Changed:

- The journey map and the Explore Museum map fade out over about 28 pt at every edge, so the background
  behind the view shows through (Figma map card; PM 2026-10-23). The cards and buttons over the map do
  not fade. Taps on the faded edge still reach the map.

Fixed:

- `ProximiMapView` without `.background` shows its spinner in the middle of the view while the venue
  loads, not at the leading edge (Nagarro, 2026-10-23).

### 1.11.0 (2026-10-23)

No change for host apps' code.

Changed:

- `open(.museumMap)` shows the [Explore Museum](#explore-museum) map of the PM's screens (2026-10-23):
  "Explore Museum" with the back button, "Level N" and a new floor changer, the galleries in the level
  colour, the Spaces, Highlights and Amenities lists and a card for a picked place. It has no position
  dot, no route, no search and no gallery legend.

Added:

- `VenuePlace.includedAmenityIDs` and `isHighlight` (internal): the "Highlight" amenity in
  `included_amenities`.

### 1.10.0 (2026-10-23)

Breaking:

- SDK 6.0.0-beta.64 and Map 6.0.0-beta.51. A host app that depends on these packages moves to the
  same versions. The SDK adds `BlueiotBindingSignal.privacyZone(since:)` and
  `ProximiioDiagnostics.NoPositionReason.privacyZone`, the map `PositionStage.privacyZone`: a `switch`
  over them without `default` adds the case.
- New `TrackingHealth.privacyZone`. A `switch` over `TrackingHealth` without `default` adds the case.

Added:

- [Privacy zones](#privacy-zones): `ProximiMap` turns on `withholdsPositionsInPrivacyZones` and passes
  the wristband binding's `private` signal to the SDK (`setPositioningSourcePrivate(since:)`). The map
  holds a grey dot at the last fix before the zone.
- `trackingChanged(.privacyZone)` while the visitor is in a privacy zone, instead of `lostPlace` or
  `stoppedResponding`.

### 1.9.0 (2026-10-22)

No change for host apps' code. SDK 6.0.0-beta.63 and Map 6.0.0-beta.50, as in 1.8.0.

Added:

- `GADSettings.geofenceExitDelay` (default 5 s): the time outside an entered geofence or privacy zone
  before the SDK reports the exit. `ProximiMap` sets it in the SDK's configuration
  (`ProximiioConfiguration.geofenceExitDelay`). `ProximiMapView` runs on the host app's SDK and does
  not change it.

Changed:

- `ProximiMap`: a geofence exit comes 5 s after the position left the geofence, not 3 s (the SDK
  default in 1.8.0).

### 1.8.0 (2026-10-22)

Breaking:

- SDK 6.0.0-beta.63 and Map 6.0.0-beta.50. A host app that depends on these packages moves to the
  same versions. [MIGRATION.md](MIGRATION.md) lists the changes since SDK 6.0.0-beta.58 and Map
  6.0.0-beta.43.

Changed:

- The screens follow `Proximiio.venueDataChanges()`. The package no longer downloads the venue's
  features every 300 s and when the app returns to the foreground. The SDK's audit sync brings the
  changes (`ProximiioConfiguration.syncInterval`, 300 s by default).
  `GADSettings.venueDataRefreshInterval` is deprecated and has no effect.
- After a change of features the open journey routes its legs again
  (`JourneyNavigator.routeNetworkChanged()`). A stop whose POI changed takes the new title,
  position, floor and gallery on the open screen (`replace(_:)`), not only when the screen closes.
- `ProximiMapView` hands every change of the binding to the navigator's `update(to:)`. A stop the
  host app removes leaves the open screen; the screen no longer starts again and `onNavigator` is
  not called again. The navigator keeps a detour and the steps it has already made.

From SDK 6.0.0-beta.61 to beta.63 and Map 6.0.0-beta.46 to beta.50, without a change in this package:

- A geofence or privacy-zone exit comes `ProximiioConfiguration.geofenceExitDelay` (3 s by default)
  after the position left it. A position back inside within the delay emits nothing.
  `geofenceExited` comes later, and `enteredGeofenceIds` keeps the geofence until then. With
  `GADSettings.outOfOrderDwell` above 0 an artwork the visitor crosses counts as inside up to 3 s
  longer. `geofenceExitDelay = 0` restores the exit at the first position outside.
- A venue feature whose coordinates are not in degrees is not drawn. Map 6.0.0-beta.45 ended the app
  on such a feature when it framed the venue. The GAD venue data had four lift outlines in
  projected metres from 2026-10-20 to 2026-10-22.
- `loadRouteNetwork()` sends `If-None-Match`; unchanged pages answer 304 and nothing is downloaded.
- The map opens on the style the SDK stored, without waiting for the network. The SDK checks the
  service once per run, and the open map draws a changed style.
- The first launch on SDK 6.0.0-beta.61 replays the audit feed once: `syncEvents()` reports every
  record in it.
- `journeys()` returns every journey, not the 100 most recently edited.

### 1.7.0 (2026-10-21)

No change for host apps' code. SDK 6.0.0-beta.60 and Map 6.0.0-beta.45, as in 1.6.0.

Added:

- `ProximiMapView`'s `onNavigator`: the `JourneyNavigator` that draws the journey. The host app reads
  its `events` and sets `onCue` itself. See [The navigator](#the-navigator).
- `ProximiJourney.init(kind:journey:)`: a `ProximiJourney` from a map library `Journey`.
- [MIGRATION.md](MIGRATION.md): moving from `ProximiioMapView` and an own `JourneyNavigator` on SDK
  6.0.0-beta.58 and Map 6.0.0-beta.43 to `ProximiMapView`.

### 1.6.0 (2026-10-19)

No change for host apps' code. Fixes from the GAD field test of 2026-10-19 in the DCT test area.

Added:

- `GADSettings.galleryFirstMarginMeters` (50 m).

Changed:

- The arrival at an artwork and out of order are checked on every fix. Before, they were checked only
  when the map updated its guidance, which it does only on a leg with a route: on a leg without a route
  a visitor inside an artwork's geofence was not marked.
- A geofence that the SDK counts the visitor inside (`Proximiio.enteredGeofenceIds`) counts as inside.
  The SDK leaves a geofence only beyond 1.2 × its radius, and its events do not repeat a geofence
  entered before the journey opened. A journey opened inside the first artwork's geofence now marks the
  arrival.
- Gallery first: a leg ends at the artwork when its gallery has no route from the visitor, or when the
  artwork lies on another floor or more than `galleryFirstMarginMeters` outside the gallery's geofence.
- The arrival, out of order, gallery first and "Resume your Journey" change the journey one after
  another. Before, an order proposed before an artwork visited out of order was marked could make it
  active again for a moment.

### 1.5.1 (2026-10-19)

Documentation only: the README describes `.sessionLost` in "Wristband" (since 1.4.0), the gallery first
route in "ProximiJourney" and the amenity marker in the `amenitySelected` event (since 1.5.0).

### 1.5.0 (2026-10-19)

No change for host apps' code.

Added:

- Gallery first in personalised journeys (PM, Monday "Navigation to a gallery"): a leg to an artwork
  in another gallery ends at the gallery's POI, with the gallery filled and a red label on the map;
  the first fix inside the gallery routes the leg to the artwork. See "Gallery first".
- An amenity picked in the menu of the journey map or the museum map gets the red marker with its
  white icon. On the visitor's floor the map shows the visitor and the amenity; on another floor it
  shows the amenity's floor around the amenity (PM, Monday "When selecting an amenity from the menu,
  zoom to location"). `GADSettings.amenityFramingMinimumMeters`, 40 m.
- "AR" and audio badges on the stop card.

Changed:

- The badges also read `metadata.augmented_reality` and `metadata.audio` with the value
  `"enabled"`, the keys of the GAD venue data.
- The stop card names the gallery of the next artwork only while the leg ends at that gallery. The
  gallery comes from the artwork's `gallery_id`, not from the gallery outline that holds the artwork.

### 1.4.2 (2026-10-19)

- `FieldLog` time stamps have the date: `2026-10-19T12:52:10.123Z` instead of `12:52:10.123Z`.
  `FieldLog.timeStamp` is their format.
- `FieldLog` no longer writes the SDK's geofence events during a visit. The Proximi GAD app writes every
  geofence and privacy zone event itself.
- `ProximiMap.sdk` is `@_spi(GADApp)`: the Proximi GAD app logs the SDK's events from it.

### 1.4.1 (2026-10-19)

No change for host apps. `ProximiMap.wristbandBindingStates()` is `@_spi(GADApp)`: the Proximi GAD app
reads the relay signal of the wristband from it for a test notification.

### 1.4.0 (2026-10-19)

Breaking:

- SDK 6.0.0-beta.60 and Map 6.0.0-beta.45. A host app that depends on these packages moves to the
  same versions.

Changed:

- A lift, staircase or escalator is drawn on the floors in its `properties.levels` only, the floors the
  SDK router connects it to since 6.0.0-beta.60. Its own floor is used only when `levels` is missing,
  empty or unreadable. 1.3.0 also drew it on its own floor: in the GAD data lift 9f411e5a and stairs
  488d5bd3 (level 0, `levels` [1, 2, 3, 4]) showed on level 0.

From SDK 6.0.0-beta.60 and Map 6.0.0-beta.45, without a change in this package:

- A level changer with `properties.levels` connects exactly those floors. Routes in a venue whose
  changers carry `levels` can change. A place without a route shows "No route from here." on the
  museum map; a journey stop without a route has no route line.
- A ride over several floors is one level change. The map draws one floor-change marker for it and
  nothing on the floors in between.
- A wristband session that the relay-api gives no verdict on ends with `.sessionLost`, where the SDK
  used to bind again. `ProximiMap.wristband` becomes `.notConnected(notice:)` with "The connection to
  your wristband was lost. Connect it again." The visitor scans the wristband again.

### 1.3.0 (2026-10-16)

`ProximiMapView` is a UI component: the host app moves the journey on (2026-10-16: Nagarro handles
visits, prompts, the bottom bar and the background itself).

Added:

- `ProximiMapView.Options`: `.bottomBar`, `.background`, `.prompts`, `.progress`, `.liveActivity`,
  `.all`. See "ProximiMapView".
- The open screen applies a change of the journey binding in place (visited, skipped, pending again,
  added, moved). 1.2.0 started the screen again.
- A journey without stops, or without a stop on the map, shows the map alone. 1.2.0 showed "None of
  these artworks is on the museum map."
- `ProximiMapEvent.positionUncertain(ProximiStop)` and `stopPlaceDeleted(ProximiStop)`.
- `onClose` of `ProximiMapView` is optional (default `nil`): without it there is no Back.

Changed:

- `ProximiMapView` has none of the options by default: no bottom bar, no background, no prompts, no
  journey logic, no Live Activity. 1.2.0 had all of them; `options: .all` gives the 1.2.0 behaviour.
- Without `.progress` the view writes nothing to the journey binding; the host app marks stops visited
  and skipped. A swipe in the list reports `skipRequested` only.
- The package posts no "next stop nearby" notification. `ProximiMapEvent.stopNearby` is unchanged; the
  Proximi GAD app posts the notification itself.

Not breaking for Nagarro's app: the public API is source compatible, and the changed defaults concern
only the `ProximiMapView` of 1.2.0, which no host app had integrated. The notification change concerns
hosts of `ProximiMap`; only the Proximi GAD app is one.

### 1.2.0 (2026-10-16)

Added:

- `ProximiMapView`: the journey screen on the host app's SDK, with the journey in a binding (Nagarro,
  2026-10-16: "one UI component for the map view … that plugs into our existing SDK session and event
  setup"). See "ProximiMapView".
- `ProximiJourney`: the journey and its progress for `ProximiMapView`.

Fixed:

- The journey screen starts its journey once. Before, its start ran again when the screen appeared
  again after a full-screen cover over it closed.

Not breaking. `ProximiMap` is unchanged.

### 1.1.0 (2026-10-16)

Added:

- Venue data changes while the app runs: the features are downloaded every 300 s in the foreground
  and when the app returns to the foreground; routes, screens and the stored journey follow. See
  "Venue data changes".
- `GADSettings.venueDataRefreshInterval` (default 300 s; 0 turns the downloads off).

Changed:

- The stored journey drops a stop whose POI was deleted and moves a stop whose POI moved. Before, it
  kept the stop as it was when the journey was planned.
- Journey ready → "Start the Journey" starts the stored journey, not the one shown when the screen
  opened.

Not breaking. One download of `GET /v7/geo/features` is about 90 KB compressed (450 KB of JSON, GAD data of 2026-10-16).

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
