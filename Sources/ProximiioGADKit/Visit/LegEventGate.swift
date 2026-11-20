import Foundation
import ProximiioMap

/// Holds the navigator's `legChanged` and `journeyFinished` while the controller marks an artwork
/// visited and orders the stops ahead again (`VisitController.holdsLegEvents`).
///
/// The navigator sends `legChanged` before it routes, so the event reaches the view before the
/// controller reports `artworkVisited`. Marking a stop done and ordering the rest are two navigator
/// calls and give two `legChanged`: the first names the next stop of the old order.
///
/// The gate hands on one `legChanged`, the last one, after the controller is done. It drops that
/// event when it names the stop of the last `legChanged` handed on: the stop walked to did not
/// change (an artwork visited out of order).
///
/// Pure; covered by tests.
struct LegEventGate {
    private var heldLeg: JourneyEvent?
    private var heldFinish = false
    /// The stop of the last `legChanged` handed on.
    private(set) var lastLegStopID: String?

    /// The events to hand on for `event`, in order.
    mutating func receive(_ event: JourneyEvent, isHolding: Bool) -> [JourneyEvent] {
        switch event {
        case .legChanged(let stop, _):
            if isHolding {
                heldLeg = event
                return []
            }
            lastLegStopID = stop.id
            return [event]
        case .journeyFinished:
            if isHolding {
                heldFinish = true
                return []
            }
            return [event]
        default:
            return [event]
        }
    }

    /// The held events to hand on once the controller is done, in order.
    mutating func release() -> [JourneyEvent] {
        var events: [JourneyEvent] = []
        if let leg = heldLeg, case .legChanged(let stop, _) = leg, !heldFinish, stop.id != lastLegStopID {
            lastLegStopID = stop.id
            events.append(leg)
        }
        if heldFinish { events.append(.journeyFinished) }
        heldLeg = nil
        heldFinish = false
        return events
    }

    /// Whether the gate holds an event.
    var isEmpty: Bool { heldLeg == nil && !heldFinish }

}
