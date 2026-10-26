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
  See [ProximiMapView](#proximimapview).

| Product | Add to | Content |
|---|---|---|
| `ProximiioGADKit` | The app target | `ProximiMap`, `ProximiMapView` and their types, `GADConfiguration`, `GADSettings`, `FieldLog`. |
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

`Package.swift` pins `proximiio-sdk-ios-binary` 6.0.0-beta.64 and `proximiio-map-ios-binary`
6.0.0-beta.51 exactly. The host app needs no dependency on them. A host app that also depends on
these packages must use the same versions.

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
- uses `proximiio-sdk-ios-binary` 6.0.0-beta.64, the version this package pins;
- turns on the SDK's privacy-zone option and passes the wristband's privacy signal to the SDK (see
  [Privacy zones](#privacy-zones));
- lays the view out and closes it; draws the background and the bottom bar (for example the audio
  guide's controls);
- stores the journey and moves it on. The view stores nothing but the accessible routes button
  (`UserDefaults`, key `ProximiioGADKit.accessibleRoutes`).

The view installs the route network from the SDK's feature cache when it opens, or downloads it when
the cache has no path. While it is on screen it follows the SDK's `venueDataChanges()` and downloads
nothing (see "Venue data changes"). It requests no permission and posts no notification.

### Options

Each option turns on something the view does beyond drawing the journey. `ProximiMap` uses `.all`.

| `ProximiMapView.Options` | With it | Without it (default) |
|---|---|---|
| `.bottomBar` | A bar with Back (with `onClose`) and a Map / List button. | No bar. The host app draws its own. |
| `.background` | The package's background image around the map card. | Transparent. |
| `.prompts` | "Skip this artwork?" ("Skip artwork" reports `stopSkipped`; the stop is skipped with `.progress`, else the host app skips it), "You've left your route" (the route stays until "Show the route from here"), "Probably at …", "Change your route?" and "Leave the tour here" (with `onClose`). | No prompt. A swipe reports `skipRequested`; the route follows a visitor who left it and `offRoute` reports it; an uncertain position reports `positionUncertain`; "Go here" on an amenity starts the detour; `journeyFinished` reports the end. |
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
- `.visited` `artworkAdvanceDelay` after the arrival at an artwork. The stop the route leads to is
  `.pending`;
- the stops that match no POI unchanged, after the other stops;
- nothing at Journey Complete: the journey already holds the last states.

### Events of ProximiMapView

`onEvent` receives the journey screen's events of the [Events](#events) table: `trackingChanged`,
`nextStop`, `stopNearby`, `positionUncertain`, `stopPlaceDeleted`, `skipRequested`, the amenity and
detour events, `journeyResumed`, `offRoute`, `backOnRoute`, `journeyFinished`, the floor without
positioning events, `modeChanged`, `recentred` and `accessibleRoutesChanged`; with `.prompts` also
`stopSkipped` and `skipCancelled`; with `.progress`
also `artworkReached` and `artworkVisitedOutOfOrder`; with `.bottomBar`, `.prompts` and `onClose` also
the exit events. Screen, wristband,
arrival, geofence and `journeyChanged` events come only from `ProximiMap`; geofence enter and exit
events are on the host app's SDK (`geofenceEvents()`).

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
| `.farFromRoute`, `.offRouteTooLong` | After `GADSettings.offRouteMeters` (30 m) and `GADSettings.offRouteSeconds` (300 s). |
| Off the route | Without `.prompts` the route follows the visitor (`deviationPolicy` `.automatic`); with `.prompts` the view asks (`.askApp`). |
| `.stopReached` and the cue `.arrived` | Only for a detour to an amenity. A leg to an artwork never reports an arrival (`arrivalDwellSeconds` is infinite): the visitor reaches an artwork by entering its geofence, which the host app's `geofenceEvents()` reports. |
| The cue `.approachingDestination` | 15 m before the end of the leg. In a personalised journey a leg to an artwork in another gallery ends at that gallery (see "Gallery first"); other legs end at the artwork. |

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
at the POI. The map fills the geofence's outline with the floor's colour and marks the POI with a red
label, the first word of its title ("G303"); the POI's own icon is hidden. The stop card names the
POI ("G303 Language") with a gallery icon and no stop number.

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
`loadRouteNetwork()` on this install. After a change:

- The open map draws the new POIs, amenity icons, floors, places and geofences (map 6.0.0-beta.47).
- The SDK has rebuilt the route network from the changed features. The open journey routes its legs
  again (`JourneyNavigator.routeNetworkChanged()`); a leg on the line already drawn stays as it is.
- The stop picker, the Explore Museum lists, the journey list, the galleries, the artwork geofences
  and the lift outlines use the new data.
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
- The SDK (6.0.0-beta.64) is private (`Proximiio.privacyZoneState`, `privacyZoneStateChanges()`)
  while its last fix is inside a privacy zone or the relay says `private`. With
  `ProximiioConfiguration.withholdsPositionsInPrivacyZones`, `positions()` yields no fix while private,
  and positioning stays available.
- The map (6.0.0-beta.51) holds the dot at the last fix before the zone, grey
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

`open(.museumMap)` shows the Explore Museum map (Figma "Explore Museum", node 12129:102006). The visitor
is not at the museum there: the map has no position dot, no route, and its camera does not follow.

- At the top: "Level N" and the floor changer (the level in a tile of the level colour). The changer
  lists the museum's levels. The map opens on the lowest level with a gallery, framed on the museum.
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
- A row, or a tap on a gallery or a listed POI on the map, shows its level and a card with its icon,
  title, lines and level. With a gallery's card open, the other galleries are lighter. An amenity gets
  the red marker with its icon.
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
| `positionUncertain(ProximiStop)` | `ProximiMapView` without `.prompts`: the position's accuracy is worse than `uncertainAccuracyMeters` and the active stop is within it. At most once per `locationQuestionQuietPeriod`. With `.prompts` the view asks "Probably at …" instead. |
| `artworkReached(ProximiStop)` | `artworkAdvanceDelay` after the visitor entered the artwork geofence of the active stop, or a fix lies in it, or the SDK counts the visitor inside it (`enteredGeofenceIds`, also for a journey opened inside it): the stop is done and the route leads to the next stop. Every fix is checked, also on a leg without a route. `geofenceEntered` arrives at the enter. |
| `artworkVisitedOutOfOrder(ProximiStop)` | Personalised journeys only: the visitor stayed at an artwork further down the journey. It counts as visited, and the stops ahead are ordered again. A curated tour ignores such an artwork. |
| `skipRequested`, `stopSkipped`, `skipCancelled` (`ProximiStop`) | A swipe on a stop in the list, "Skip artwork", "Keep it". `ProximiMapView` without `.prompts` sends only `skipRequested`. `skipUndone` is not sent since 1.13.0. |
| `stopPlaceDeleted(ProximiStop)` | The stop's POI was deleted on the backend while the journey screen is open. Once per stop. With `.progress` (and in `ProximiMap`) the stop is skipped. |
| `amenitySelected(ProximiStop)` | An amenity picked on the map. A card shows it with "Go here"; the map marks it in red and shows it with the visitor, or its own floor around it (`amenityFramingMinimumMeters`). |
| `detourStarted(ProximiStop)`, `detourEnded(ProximiStop, completed:)` | "Change your route?" confirmed; the detour reached (`completed`) or left. |
| `journeyResumed` | "Resume your Journey" or "Show the route from here". |
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
| `artworkAdvanceDelay` | 2 s | From the arrival at an artwork (its geofence) to the route to the next stop. |
| `outOfOrderDwell` | 0 s | Time inside another artwork's geofence before it counts as visited out of order (personalised journeys only). |
| `amenityArrivalMinimumMeters`, `amenityArrivalMaximumMeters`, `amenityArrivalDwell` | 5 m, 10 m, 5 s | An amenity is reached within 2.5 × the position accuracy, within these bounds, for this time. |
| `geofenceExitDelay` | 5 s | Time outside an entered geofence or privacy zone before the SDK reports the exit (`ProximiioConfiguration.geofenceExitDelay`, SDK default 3 s). Enters are reported at once. `ProximiMap` sets it when it starts the SDK; `ProximiMapView` uses the host app's SDK configuration. 0 reports the exit at the first position outside. |
| `stopNearbyMeters` | 5 m | The distance of `ProximiMapEvent.stopNearby`. |
| `offRouteMeters`, `offRouteSeconds` | 30 m, 300 s | "You've left your route": this far from the route, or off it this long. |
| `routeSnapMeters` | 0.5 m | The dot is drawn on the route within this distance. Display only. |
| `followZoom` | 21 | Zoom of "Centre on me" and of the first position. |
| `minimumZoom`, `maximumZoom` | `nil` | The zoom levels the visitor cannot go beyond on every map of the package, or the map library's limits. |
| `smoothsPosition` | `false` | `true` slides the position dot toward each fix; `false` draws it on each fix, without the delay of the sliding. |
| `mapLoadingTimeout` | 20 s | The longest time a map shows its spinner while the venue's features are not on the map. |
| `amenityFramingMinimumMeters` | 40 m | The smallest area the map shows for an amenity picked in the menu. |
| `galleryFirstMarginMeters` | 50 m | Gallery first: an artwork farther than this outside its gallery's geofence, or on another floor, is routed to directly. |
| `liftRideDwell`, `liftExitFixes` | 3 s, 2 | Seconds of fixes inside a lift outline before the visitor counts as riding it, and the fixes outside that end the ride. The field log records the rides. |
| `levelsWithoutPositioning` | [0] | Floors without positioning. See "Floors without positioning". |
| `levelChangerReachedMeters` | 5 m | Distance from the lift or stairs to a floor without positioning at which the lift or stairs view shows. |
| `levelChangeViewSeconds` | 5 s | How long the lift or stairs view shows before the map shows the floor without positioning. |
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
- The journey map and the museum map of Journey Complete have an accessible routes button (a wheelchair,
  blue while on).
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

`FieldLog` writes relay positions, positions during a visit, tracking health, artwork arrivals, journey,
binding and `ProximiMap` events to `Documents/gad-debug.log`. It does not write the SDK's geofence
events. It is off by default. Turn it on at launch, before `start()`, in test builds only:

```swift
FieldLog.isEnabled = true
FieldLog.logLaunch()
```

`FieldLogShareButton()` opens the share sheet with the file. A line is `[GAD] <time stamp> <message>`;
the time stamp is ISO 8601 in UTC with the date and milliseconds (`FieldLog.timeStamp`).

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
