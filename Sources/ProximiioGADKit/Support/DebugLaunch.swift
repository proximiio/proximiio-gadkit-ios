//
//  DebugLaunch.swift
//  ProximiioGADKit
//
//  Debug builds only. Launch arguments for testing away from the museum. Results are
//  printed to the console with the prefix `[GAD]`.
//
//    -demoWristbandPairing succeed|fail   pairing UI with a fake connection, no SDK
//    -pairWristband <code>                bind the wristband through the relay-api at launch
//    -journeyPlayback <journey id>        play a stored journey instead of the wristband
//    -journeySpeed <x>                    playback speed, default 1
//    -journeyLoop                         restart after the last waypoint
//    -listJourneys                        print the organisation's journeys
//    -hubPage welcome|craft               open the Hub on that page
//    -openMap                             open the museum map after launch
//    -visitList                           with -visit: open the journey in List mode
//    -visitKind personalised|curated      with -visit: the kind of journey, default personalised
//    -visitAutoAdvance                    with -visit: advance 5 m after leaving a stop
//    -routeTo <title>                     with -openMap: route to the first place whose title matches
//    -routeAvoid stairs,escalators,revolvingDoors,inaccessiblePaths   accessibility needs for routes
//    -visit "<title>,<title>,…"            start a visit through the first place matching each title
//
#if DEBUG
import Foundation

public struct DebugLaunch: Equatable, Sendable {
    public var demoPairingSucceeds: Bool?
    public var pairWristband: String?
    public var journeyID: String?
    public var journeySpeed: Double = 1
    public var journeyLoops = false
    public var listJourneys = false
    public var openMap = false
    public var hubPage: String?
    public var routeTo: String?
    /// `-routeAvoid`. The host app applies it with `routeAccessibility(_:)`.
    public var routeAccessibility = RouteAccessibility.none
    public var visitStops: [String] = []
    public var visitAutoAdvance = false
    public var visitList = false
    /// `-visitKind`. The host app passes it to `VisitView`.
    public var visitKind = JourneyKind.personalised

    public static let current = DebugLaunch(arguments: ProcessInfo.processInfo.arguments)

    public init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            let value = arguments[index + 1]
            return value.hasPrefix("-") ? nil : value
        }
        if arguments.contains("-demoWristbandPairing") {
            demoPairingSucceeds = value(after: "-demoWristbandPairing") == "succeed"
        }
        pairWristband = value(after: "-pairWristband")
        journeyID = value(after: "-journeyPlayback")
        journeySpeed = value(after: "-journeySpeed").flatMap(Double.init) ?? 1
        journeyLoops = arguments.contains("-journeyLoop")
        listJourneys = arguments.contains("-listJourneys")
        openMap = arguments.contains("-openMap")
        hubPage = value(after: "-hubPage")
        routeTo = value(after: "-routeTo")
        let avoid = Set(value(after: "-routeAvoid")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [])
        routeAccessibility = RouteAccessibility(
            avoidsStairs: avoid.contains("stairs"),
            avoidsEscalators: avoid.contains("escalators"),
            avoidsRevolvingDoors: avoid.contains("revolvingDoors"),
            avoidsInaccessiblePaths: avoid.contains("inaccessiblePaths")
        )
        visitAutoAdvance = arguments.contains("-visitAutoAdvance")
        visitList = arguments.contains("-visitList")
        visitKind = value(after: "-visitKind").flatMap(JourneyKind.init(rawValue:)) ?? .personalised
        visitStops = value(after: "-visit")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    }

    /// Writes to `FieldLog`. Copy the file with `xcrun devicectl device copy from --domain-type
    /// appDataContainer --domain-identifier <bundle id> --source Documents/gad-debug.log`.
    public static func log(_ message: String) {
        FieldLog.log(message)
    }

    /// Runs the SDK-dependent actions after the SDK has started.
    @MainActor
    public func run(with venue: VenueService, wristband: WristbandSession) async {
        if listJourneys {
            let titles = VenuePlace.all(in: await venue.sdk.features()).map { "\($0.title) [L\(Int($0.level))]" }
            Self.log("places: \(titles.joined(separator: ", "))")
            do {
                for journey in try await venue.sdk.journeys() {
                    let status = journey.validationFailure().map { "not playable: \($0)" } ?? "playable"
                    Self.log("journey \(journey.id ?? "?") · \(journey.name ?? "unnamed") · \(journey.waypoints.count) waypoints · \(status)")
                }
            } catch {
                Self.log("journeys failed: \(error.localizedDescription)")
            }
        }
        if let journeyID {
            do {
                try await venue.playJourney(id: journeyID, speed: journeySpeed, loops: journeyLoops)
                Self.log("journey playback started: \(journeyID)")
            } catch {
                Self.log("journey playback failed: \(error.localizedDescription)")
            }
        } else if let pairWristband {
            Self.log("binding wristband \(pairWristband)")
            do {
                try await wristband.bind(pairWristband)
                Self.log("wristband \(pairWristband): bound")
            } catch {
                Self.log("wristband \(pairWristband): \(WristbandCopy.message(for: error))")
            }
        }
    }
}
#endif
