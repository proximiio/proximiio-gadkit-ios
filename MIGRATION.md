# Moving to ProximiioGADKit

This guide is for a host app on SDK 6.0.0-beta.58 and Map 6.0.0-beta.43 that shows its journey with
the map library's `ProximiioMapView` and its own `JourneyNavigator`. ProximiioGADKit 1.15.0 uses SDK
6.0.0-beta.66 and Map 6.0.0-beta.54.

Each change has a mark:

- **Required**: without the change the app does not build or does not work.
- **Check**: a change only if the app uses the named API.
- **Optional**: a feature the app can turn on.
- **Info**: no change in the app.

## 1. SDK and Map changes since SDK 6.0.0-beta.58 and Map 6.0.0-beta.43

### Source break

| Since | Change | In the app | Mark |
|---|---|---|---|
| SDK 6.0.0-beta.59 | `BlueiotBindingError` has three new cases (relay-api 0.11): `swapBandsApart(requestID:)` (code 18), `swapAtReception(requestID:)` (code 19) and `signingUnavailable(retryAfter:requestID:)` (code 20). Before, the first two arrived as `.unexpected(code:status:message:requestID:)` and the third as `.server(status: 503, requestID:)`. | An exhaustive `switch` over `BlueiotBindingError` without `default` does not compile. Add the three cases. The SDK's texts: "Hold your current wristband next to the new one and scan again.", "Your wristband isn't reachable. Please swap it at the reception desk." and, for `signingUnavailable`, a retry after `retryAfter` seconds. | **Required** with an exhaustive `switch` |
| SDK 6.0.0-beta.64, Map 6.0.0-beta.51 | New cases `BlueiotBindingSignal.privacyZone(since:)`, `ProximiioDiagnostics.NoPositionReason.privacyZone` and `PositionStage.privacyZone`. | An exhaustive `switch` over these enums without `default` does not compile. Add the case. | **Required** with an exhaustive `switch` |

The other versions up to SDK 6.0.0-beta.66 and Map 6.0.0-beta.54 have no source break.
`ProximiioConfiguration.init` gains the defaulted `geofenceExitDelay:` in SDK 6.0.0-beta.63; existing
calls compile unchanged.

### Behaviour changes

| Since | Change | In the app | Mark |
|---|---|---|---|
| SDK 6.0.0-beta.59, Map 6.0.0-beta.44 | Every SDK request to `apiBaseURL` and `fallbackAPIBaseURLs` carries `X-Visitor-Id` and `X-Proximiio-SDK`. The map's style, tile, glyph and sprite requests to the API host carry both too. proximiio-api rate-limits per device on `X-Visitor-Id`. | A proxy in front of the on-premises API passes both headers through. | **Required** for the production install |
| SDK 6.0.0-beta.59, Map 6.0.0-beta.44 | The privacy manifests declare Device ID for App Functionality and Analytics, not linked and not used for tracking. | The App Store privacy details declare Device ID for App Functionality and Analytics. | **Required** before an App Store submission |
| SDK 6.0.0-beta.60 | After the relay refuses the refresh token, `BlueiotWristbandBinding` binds the stored wristband again only when the relay reports the session active, or when an earlier refresh with that token got no answer. A session the relay reports closed ends with the relay's reason, for example `.ended(.superseded)`. A session without a verdict ends with `.sessionLost`, where beta.58 bound again. | After `.sessionLost` the app asks the visitor to scan the wristband again. | **Check** |
| SDK 6.0.0-beta.60 | `ComputedRoute.levelChanges` has one entry per lift or stairs ride: level 1 to level 4 is one entry, not three. `instructions` has one `.levelChange` for it. | Code that counts floors with `levelChanges.count` counts rides. | **Check** |
| SDK 6.0.0-beta.60 | A level changer whose feature has `properties.levels` connects exactly those floors. | Routes in a venue whose changers carry `levels` can change. | Info |
| Map 6.0.0-beta.44 | The drop-in map is clear, not black, where the style draws nothing. `options.backgroundColor = .black` keeps black. | Applies to a `ProximiioMapView` the app keeps. | Info |
| SDK 6.0.0-beta.61 | `mapStyle()` answers from the stored style without waiting for the network and checks the service once per run in the background. | An app that needs the service's current style calls `refreshMapStyle()`. | **Check** |
| SDK 6.0.0-beta.61 | `loadRouteNetwork()` sends `If-None-Match`. When every page answers `304`, nothing is downloaded or rebuilt. | | Info |
| SDK 6.0.0-beta.61 | A sync pass that changed features rebuilds the route network. A running `JourneyNavigator` keeps its legs until `routeNetworkChanged()`. | `ProximiMapView` calls it on a change of features. | Info |
| SDK 6.0.0-beta.61 | Audit records are stored under the canonical entity name. The first launch on this version replays the audit feed once, and `syncEvents()` reports every record in it. | An app that acts on each `syncEvents()` record sees one burst after the update. | **Check** |
| SDK 6.0.0-beta.61 | `amenities()` downloads until the store holds the whole catalogue. An install that stored the catalogue with an earlier SDK downloads it once more. | | Info |
| SDK 6.0.0-beta.62 | `journeys()` returns every journey. Before, it returned the API's default page: the 100 most recently edited journeys. | An app that lists journeys gets all of them. | **Check** |
| SDK 6.0.0-beta.62 | A venue feature whose coordinates are not in degrees is left out of the route network. `features()` keeps it. | | Info |
| SDK 6.0.0-beta.63 | A geofence or privacy-zone exit comes `geofenceExitDelay` (3 s by default) after the position left it. Enters come at once. A position back inside within the delay emits nothing. Until the exit, `enteredGeofenceIds` lists the geofence and a privacy zone keeps position reporting suppressed. `stop()` emits every waiting exit. | An app that acts on a `geofenceEvents()` exit, for example the end of an artwork's audio, acts 3 s later. `geofenceExitDelay: 0` in `ProximiioConfiguration` restores the exit at the first position outside. | **Check** |
| Map 6.0.0-beta.47 | An open map follows `venueDataChanges()`: it draws changed features, amenity icons, floors, places, geofences and the stored style. | | Info |
| Map 6.0.0-beta.48 | A venue feature whose coordinates are not in degrees is not drawn. Map 6.0.0-beta.45 ended the app on such a feature when it framed the venue. | | Info |
| SDK 6.0.0-beta.64 | The binding reads relay-api's `private` (a band silent in a privacy zone) as `.privacyZone(since:)`; older SDKs read it as `.ok`. With `withholdsPositionsInPrivacyZones` on, `positions()` yields no fix while private and positioning stays available. | Turn the option on and pass the binding's signal with `setPositioningSourcePrivate(since:)` (README "Privacy zones"). | **Required** for the privacy zones |
| Map 6.0.0-beta.51 | While the SDK is private, the dot stays grey at the last fix before the zone, and `JourneyNavigator` takes no fix: no off-route, re-route, deviation, passed stop or arrival. | | Info |
| SDK 6.0.0-beta.65 | `authenticate()` returns without a connection on a phone where the API accepted the token before (`allowsOfflineStart`, on by default). `tokenStatus` is then `.unverified`: positioning runs on the stored data, nothing is synced or uploaded. `loadRouteNetwork()` still needs the network. | A "no connection" screen tied to the `authenticate()` error no longer shows on such a phone. Install the route network with `loadCachedRouteNetwork()` when `tokenStatus` is not `.verified`. | **Check** |
| SDK 6.0.0-beta.65 | `authenticate()` gives up after 30 s (before: up to about 2 min on a network that does not answer). | | Info |
| SDK 6.0.0-beta.66 | When the API has refused the token for at least two hours (three checks), the SDK emits `syncFailed(reason: "unauthorized")`, stops, returns to `.idle`, deletes the venue data, the map style, the amenities and the waiting uploads, and sets `tokenStatus` to `.rejected`. `start()` throws until an `authenticate()` with an accepted token succeeds. A shorter refusal keeps the data (`.unverified`). | Close `ProximiMapView` and show the app's failure screen. After a new `authenticate()` and `start()`, open a new view. | **Required** |
| Map 6.0.0-beta.54 | On that refusal the map drops the venue, the route, the stops and the dot, and a running `JourneyNavigator` ends. Its `journey` stays. | | Info |
| SDK 6.0.0-beta.66 | Two amenities that differ only in `metadata` or `title_i18n` are no longer equal. A refresh that changes only them names `.amenities` in `venueDataChanges()`. | | Info |

### Added

All Info.

- SDK 6.0.0-beta.59: `Proximiio.apiVisitorID`, `Proximiio.apiSDKToken`,
  `BlueiotBindingPolicy.swapNearMeters`.
- SDK 6.0.0-beta.60: `LevelChanger.levels` and `LevelChanger.init(id:type:coordinate:level:direction:levels:)`.
- Map 6.0.0-beta.44: `MapOptions.backgroundColor` and `MapColor.clear`.
- SDK 6.0.0-beta.61: `Proximiio.venueDataChanges()`, `VenueDataChange`, `VenueDataKind`,
  `refreshMapStyle()` and `cachedMapStyle()`.
- SDK 6.0.0-beta.63: `ProximiioConfiguration.geofenceExitDelay` and `defaultGeofenceExitDelay`,
  `ProximiioDiagnostics.ConfigurationSummary.geofenceExitDelay`.
- SDK 6.0.0-beta.64: `ProximiioConfiguration.withholdsPositionsInPrivacyZones`,
  `Proximiio.setPositioningSourcePrivate(since:)`, `privacyZoneStateChanges()`, `privacyZoneState` and
  `PrivacyZoneState`.
- Map 6.0.0-beta.51: `PositionStyle.privacy` and `PositionPrivacyStyle`.
- Map 6.0.0-beta.52: `MapOptions.minimumZoom`, `maximumZoom` and `with(minimumZoom:maximumZoom:)`.
  ProximiioGADKit sets them from `GADSettings.minimumZoom` and `maximumZoom`.
- SDK 6.0.0-beta.65: `ProximiioConfiguration.allowsOfflineStart`, `Proximiio.tokenStatus` and
  `Proximiio.TokenStatus`, data-only bundled seeds from `proximiio-offline-fetch`.
- SDK 6.0.0-beta.66: `ProximiioAmenity.metadata`, `title(language:)`, `titleTranslations` and
  `init(id:title:category:icon:details:metadata:titleTranslations:)`.
- Map 6.0.0-beta.46: `JourneyNavigator.remove(stopID:)`, `replace(_:)`, `update(to:)`,
  `routeNetworkChanged()` and the initialisers with `hostJourney:`; the same on `JourneyPlan`;
  `JourneyUpdate`; `ProximiioMapSession.reloadVenueData()`.

### Fixed

All Info.

- SDK 6.0.0-beta.59: on `503 signing_unavailable` a token refresh keeps the session and tries again
  after `retryAfter`.
- SDK 6.0.0-beta.60: a wristband session another phone took over no longer binds again by itself.
  The stream binds again only after a refresh that got an answer. A route from level 1 to level 4
  names level 4.
- Map 6.0.0-beta.44: a drop-in map shows no black frame while it is presented.
- Map 6.0.0-beta.45: a ride over several floors draws no stops on the floor it arrives at.
- SDK 6.0.0-beta.61: relay and wristband-binding streams no longer drop after 15 s of silence; a dead
  stream is detected after up to 45 s. A fresh install no longer takes the few amenities of the audit
  feed for the whole catalogue.
- SDK 6.0.0-beta.62: a list page the API cut short no longer loses rows. A venue feature with a
  `"NaN"` level no longer ends the app.
- Map 6.0.0-beta.46: a leg still being routed is no longer dropped by an edit that routes nothing.
- Map 6.0.0-beta.48: a floor level that is NaN, an infinity or beyond about 4.6 × 10¹⁶ no longer ends
  the app.
- Map 6.0.0-beta.52: a map opened after the last fix shows the dot.
- SDK 6.0.0-beta.65: `requestPermissions(always: true)` always returns. A missing Info.plist usage key
  no longer ends the app; the SDK leaves that input off and logs the key.

The SDK and Map changelogs of these versions have the full entries.

## 2. From ProximiioMapView to ProximiMapView

| Step | | Mark |
|---|---|---|
| 1 | Dependencies | **Required** |
| 2 | The SDK and Map changes of section 1 | **Required** / **Check** |
| 3 | Languages | **Check** |
| 4 | The map screen | **Required** |
| 5 | The journey | **Required** |
| 6 | Navigator events and cues | **Required** |
| 7 | Changes of the journey | **Required** |
| 8 | SDK streams | Info |
| 9 | The view's navigator | **Check** |
| 10 | Options | **Optional** |

### Step 1: Dependencies (Required)

- Add `https://github.com/proximiio/proximiio-gadkit-ios`, "Up to Next Major Version" from `1.15.0`,
  and the product `ProximiioGADKit` to the app target.
- Set `proximiio-sdk-ios-binary` to exactly `6.0.0-beta.66` and `proximiio-map-ios-binary` to exactly
  `6.0.0-beta.54`. ProximiioGADKit pins these versions; with other versions the packages do not
  resolve.
- ProximiioGADKit does not re-export the SDK and the Map. Files that use their types keep
  `import Proximiio` and `import ProximiioMap`. The file that shows the map adds
  `import ProximiioGADKit`.

### Step 2: SDK and Map changes (Required / Check)

Section 1: the `BlueiotBindingError` and privacy-zone cases (**Required** with an exhaustive `switch`),
the headers on the on-premises proxy, the privacy details, the privacy zones and the refused token
(**Required**), `.sessionLost`, `levelChanges`, `mapStyle()`, the `syncEvents()` burst, `journeys()`,
the geofence exit delay and the offline start (**Check**).

### Step 3: Languages (Check)

The package ships English and Arabic strings. The app declares English and Arabic
(`CFBundleLocalizations`, or Known Regions in the project), so the app's language applies to the
package's screen. The package registers its fonts itself.

### Step 4: The map screen (Required)

`ProximiMapView` replaces the app's `ProximiioMapSession`, `ProximiioMapView` and `JourneyNavigator`.
It draws the map, the route, the stops, the floors and the level changes, search with the amenity
shortcuts, and the list.

Before:

```swift
@StateObject private var session = ProximiioMapSession(sdk: sdk)

var body: some View {
    ProximiioMapView(session: session)
        .task {
            let navigator = JourneyNavigator(session: session, journey: journey, rules: .visit, guidanceRules: .visit)
            navigator.onCue = { cue in /* … */ }
            eventsTask = Task { for await event in navigator.events { /* … */ } }
            await navigator.start()
        }
}
```

After:

```swift
@State private var journey: ProximiJourney      // step 5
@State private var eventsTask: Task<Void, Never>?

var body: some View {
    ProximiMapView(
        sdk: sdk,                                // the started SDK, as before
        journey: $journey,
        onEvent: { event in
            if case .skipRequested(let stop) = event { setState(.skipped, of: stop) }   // step 7
        },
        onNavigator: { navigator in              // step 6
            navigator.onCue = { cue in /* … */ }
            let events = navigator.events
            eventsTask?.cancel()
            eventsTask = Task { for await event in events { /* … */ } }
        }
    )
}
```

- `sdk` is the app's started `Proximiio` with the wristband binding's position provider attached.
  `proximiio.start()`, `attachPositionProvider(_:)` and `BlueiotWristbandBinding(configuration:)` stay
  as they are. The view does not start, stop or configure the SDK.
- The app no longer creates the map session or the navigator and no longer calls `start()`, `end()`,
  `cameraRules`, `guidanceRules` or `deviationRules` on them.

### Step 5: The journey (Required)

The view shows a `ProximiJourney`: a `kind` and stops in visit order, each with an `id` and a
`state` (`.pending`, `.visited`, `.skipped`). It is `Codable`; the app stores it.

| The app has | `ProximiJourney` |
|---|---|
| A map library `Journey` | `ProximiJourney(kind: .personalised, journey: journey)`. Stop ids stay; `.done` is `.visited`, `.skipped` stays, other states are `.pending`; detour stops are left out. |
| Artwork ids | `ProximiJourney(kind: .curated, artworks: ["GAD.2010.00033", "GAD.2018.00034"])`: collection ids (`remote_id`) or POI ids, all pending. |

- `.curated` keeps the app's order and routes straight to each artwork.
- `.personalised` routes to an artwork's gallery first (README "Gallery first").

### Step 6: Navigator events and cues (Required)

The app's `for await event in navigator.events` loop and its `onCue` closure move into `onNavigator`
(step 4). The code inside them stays.

- The view calls `onNavigator` before the journey starts. Reading `navigator.events` inside the call
  gives a stream with every later event.
- The view calls it again with a new navigator when the screen starts again: a new `kind`, a journey
  without a stop on the map, or the first journey on an empty map. The previous navigator's streams
  finish. The app cancels its old task. Any other change of the journey goes to `update(to:)` of the
  same navigator.
- The view sets neither `onCue` nor `cueRules`.

### Step 7: Changes of the journey (Required)

The app changes the journey through the binding. The view applies each change to the open screen.
It does not see calls on the navigator that change the journey, and its next change can undo them.

| Before, on the app's navigator | After |
|---|---|
| `markDone(stopID:)` | `journey.stops[i].state = .visited` |
| `skip(stopID:)`, `skip()` | `journey.stops[i].state = .skipped` |
| `reopen(stopID:)` | `journey.stops[i].state = .pending` |
| `add(_:)`, `insert(_:at:)` | Append or insert `ProximiJourney.Stop(id:)` |
| `move(stopID:toIndex:)`, `apply(_:)` | Reorder `journey.stops` |
| Remove a stop | Remove it from `journey.stops` |
| `detour(to:)`, `cancelDetour()` | No call. The visitor picks an amenity in the view's search and taps "Go here", or the app sets `destination` (README "Routing to a place") and sets it to `nil` to end the detour. `onEvent` reports `amenitySelected`, `detourStarted` and `detourEnded`. |
| `resumeJourney()` | No call. The route follows a visitor who left it. |
| `setRouteOptions(_:)` | The `routeAccessibility:` parameter (`RouteAccessibility`) |

A swipe on a stop in the list reports `ProximiMapEvent.skipRequested(stop)` on `onEvent` and changes
nothing. The app sets the stop to `.skipped`, or asks the visitor first. Without this the swipe has no
effect. `ProximiStop.id` is the POI id and `ProximiStop.artworkID` the collection id (`remote_id`); the
app matches the one its journey uses.

### Step 8: SDK streams (Info)

`sdk.geofenceEvents()` and `sdk.positions()` stay as they are. Every call returns a new stream. The
view opens its own streams and takes no events from the app's. The view reports no geofence event.
It follows `sdk.venueDataChanges()` itself: the open map draws changed venue data, and the journey
routes again after a change of features.

### Step 9: The view's navigator (Check)

The navigator from `onNavigator` has the view's rules, not the map library's defaults
(README "The navigator"):

| | The view's navigator |
|---|---|
| `.stopSkipped`, `.legChanged`, `.journeyFinished` | Sent when the view applies the app's change of the binding. |
| `.farFromRoute`, `.offRouteTooLong` | After `GADSettings.offRouteMeters` (30 m) and `GADSettings.offRouteSeconds` (300 s). |
| `.stopReached` and the cue `.arrived` | Only for a detour to an amenity. A leg to an artwork never reports an arrival. The visitor reaches an artwork by entering its geofence, which the app's `geofenceEvents()` reports. |
| The cue `.approachingDestination` | 15 m before the end of the leg. In a personalised journey a leg to an artwork in another gallery ends at that gallery; other legs end at the artwork. |

Every time and distance of the view is in `GADSettings` (README "Settings"), passed as `settings:`.

### Step 10: Options (Optional)

`options:` is empty by default: the view draws the journey and reports events.

| `ProximiMapView.Options` | Adds |
|---|---|
| `.bottomBar` | A bar with Back (with `onClose`) and a Map / List button. |
| `.background` | The package's background image around the map card. |
| `.skipPrompt`, `.offRoutePrompt`, `.uncertainPositionPrompt`, `.changeRoutePrompt`, `.leaveTourPrompt` | One of the view's prompts each: skip, off the route, uncertain position, change of route, leave the tour. `.prompts` is all five. |
| `.journeyComplete` | Journey Complete when the last stop is done. |
| `.progress` | The view marks artworks visited, orders a personalised journey and writes the journey to the binding. |
| `.liveActivity` | The journey's Live Activity, with `ProximiioGADLiveActivity` in the widget extension. |
