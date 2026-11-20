import CoreLocation
import ProximiioMap
import Testing
@testable import ProximiioGADKit

/// `LegEventGate`: `artworkVisited` before `nextStop`, one `nextStop` per visit (T-1870, T-1871).
struct LegEventGateTests {
    private func stop(_ id: String) -> JourneyStop {
        JourneyStop(id: id, title: id, coordinate: .init(latitude: 24.54, longitude: 54.39), floor: FloorKey(level: 1), poiID: id, kind: .planned, state: .pending)
    }

    private func leg(_ id: String) -> JourneyEvent { .legChanged(to: stop(id), reason: .advanced) }

    private func legIDs(_ events: [JourneyEvent]) -> [String] {
        events.map { event in
            if case .legChanged(let stop, _) = event { return stop.id }
            if case .journeyFinished = event { return "finished" }
            return "other"
        }
    }

    @Test func aLegChangeOutsideAVisitIsHandedOnAtOnce() {
        var gate = LegEventGate()
        #expect(legIDs(gate.receive(leg("a"), isHolding: false)) == ["a"])
        #expect(gate.lastLegStopID == "a")
        #expect(gate.release().isEmpty)
    }

    @Test func aVisitGivesOneLegChangeForTheStopOfTheNewOrder() {
        var gate = LegEventGate()
        _ = gate.receive(leg("a"), isHolding: false)
        // Marked done: the next stop of the old order. Ordered again: the stop of the new order.
        #expect(gate.receive(leg("b"), isHolding: true).isEmpty)
        #expect(gate.receive(leg("c"), isHolding: true).isEmpty)
        #expect(legIDs(gate.release()) == ["c"])
        #expect(gate.lastLegStopID == "c")
        #expect(gate.release().isEmpty)
    }

    @Test func aVisitOutOfOrderThatKeepsTheStopGivesNoLegChange() {
        var gate = LegEventGate()
        _ = gate.receive(leg("a"), isHolding: false)
        #expect(gate.receive(leg("a"), isHolding: true).isEmpty)
        #expect(gate.release().isEmpty)
        #expect(gate.isEmpty)
    }

    @Test func theEndOfTheJourneyIsHeldAndNoLegChangeGoesBeforeIt() {
        var gate = LegEventGate()
        _ = gate.receive(leg("a"), isHolding: false)
        #expect(gate.receive(leg("b"), isHolding: true).isEmpty)
        #expect(gate.receive(.journeyFinished, isHolding: true).isEmpty)
        #expect(legIDs(gate.release()) == ["finished"])
    }

    @Test func otherEventsAreNeverHeld() {
        var gate = LegEventGate()
        #expect(gate.receive(.returnedToRoute, isHolding: true).count == 1)
        #expect(gate.isEmpty)
    }
}
