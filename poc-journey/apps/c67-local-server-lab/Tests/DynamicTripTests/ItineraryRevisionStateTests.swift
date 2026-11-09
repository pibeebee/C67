import Foundation
import XCTest
import DynamicTripContracts
import PlaceContextEngine

@MainActor final class ItineraryRevisionStateTests: XCTestCase {
    func state() async throws -> ItineraryRevisionState {
        var state = ItineraryRevisionState(); state.capture(try await ItineraryRevisionReplay.initial()); try state.begin(); return state
    }
    func newStop(_ id: String) throws -> RevisionStop {
        .init(place: try ItineraryRevisionReplay.place(id), required: true, source: .init(placeID: id, origin: .userSelected))
    }
    func testReplaceAtEveryPositionPreservesOrderAndRequiredStatus() async throws {
        for index in 0 ... 1 {
            var state = try await state(); let previous = state.current!.id; let stop = state.draft!.stops[index]
            var replacement = try newStop("revision-library"); replacement.required = false
            try state.put(replacement, replacing: stop.id)
            XCTAssertEqual(state.draft!.stops[index].id, stop.id)
            XCTAssertTrue(state.draft!.stops[index].required)
            XCTAssertEqual(state.current!.id, previous)
            XCTAssertEqual(state.draft!.stops[index].place.prepared.googlePlaceID, "revision-library")
        }
    }
    func testMoveDeleteAddApplyKeepsPreviousVersion() async throws {
        var state = try await state(); let old = state.current!
        state.move(from: 0, to: 1)
        state.change { $0.stops.removeLast() }
        try state.put(newStop("revision-library"))
        let input = try state.draft!.request()
        let preview = try await ItineraryRevisionReplay.preview(input)
        XCTAssertEqual(preview.result.result.itinerary.visits.map(\.placeID), input.sources.map(\.placeID))
        XCTAssertTrue(state.receive(preview)); XCTAssertTrue(state.canApply())
        try state.apply()
        XCTAssertEqual(state.revisions.count, 2)
        XCTAssertEqual(state.revisions[0].id, old.id)
        XCTAssertEqual(state.current?.parentRevisionID, old.id)
        XCTAssertNil(state.draft)
    }
    func testStaleResponseAndEditedPreviewCannotApply() async throws {
        var state = try await state()
        let preview = try await ItineraryRevisionReplay.preview(state.draft!.request())
        state.move(from: 0, to: 1)
        XCTAssertFalse(state.receive(preview)); XCTAssertThrowsError(try state.apply())
        let fresh = try await ItineraryRevisionReplay.preview(state.draft!.request())
        XCTAssertTrue(state.receive(fresh))
        state.change { $0.transport = .transjakarta }
        XCTAssertNil(state.preview); XCTAssertFalse(state.canApply())
    }
    func testCancelReplacementAndEmptyDraftPreserveAccepted() async throws {
        var state = try await state(); let id = state.current!.id
        state.change { $0.stops.removeAll() }
        XCTAssertThrowsError(try state.draft!.request())
        state.cancel(); XCTAssertEqual(state.current!.id, id); XCTAssertNil(state.draft)
    }
    func testDuplicateOriginAndSixStopLimits() async throws {
        var state = try await state()
        XCTAssertThrowsError(try state.put(state.draft!.stops[0]))
        let origin = state.draft!.origin
        XCTAssertThrowsError(try state.put(.init(place: origin, required: true, source: .init(placeID: origin.prepared.googlePlaceID, origin: .userSelected))))
        for i in 0 ..< 4 { try state.put(newStop("extra-\(i)")) }
        XCTAssertEqual(state.draft!.stops.count, 6)
        XCTAssertThrowsError(try state.put(newStop("seventh")))
    }
    func testPersistenceRestoresDraftAndHistoryButNotApplicablePreview() async throws {
        var state = try await state(); state.move(from: 0, to: 1)
        let preview = try await ItineraryRevisionReplay.preview(state.draft!.request()); _ = state.receive(preview)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ItineraryRevisionStore(url: url); try store.save(state)
        let restored = try store.load()
        XCTAssertEqual(restored.draft!.id, state.draft!.id)
        XCTAssertEqual(restored.current!.id, state.current!.id)
        XCTAssertNil(restored.preview)
        let blocked = ItineraryRevisionStore(url: url.appendingPathComponent("cannot-write.json"))
        XCTAssertThrowsError(try blocked.save(state))
        XCTAssertEqual(try store.load().current!.id, state.current!.id)
    }
    func testDeadlineAndTransitWaitingConflictKeepOldVersion() async throws {
        var state = try await state(); let old = state.current!.id
        state.change { $0.transport = .transjakarta; $0.maximumWaitingMinutes = 0 }
        let preview = try await ItineraryRevisionReplay.preview(state.draft!.request())
        XCTAssertFalse(preview.canApply); _ = state.receive(preview)
        XCTAssertThrowsError(try state.apply()); XCTAssertEqual(state.current!.id, old)
    }
    func testExpiredPlaceOrPreviewRequiresRefresh() async throws {
        var state = try await state()
        state.change { $0.origin.prepared.expiresAt = Date().addingTimeInterval(-1) }
        let preview = try await ItineraryRevisionReplay.preview(state.draft!.request()); _ = state.receive(preview)
        XCTAssertFalse(state.canApply())
    }
    func testSourceCoverageAndFixedOrderRequired() async throws {
        let state = try await state(); var input = try state.draft!.request()
        input.sources.append(input.sources[0])
        XCTAssertThrowsError(try input.validate(placeIDs: state.draft!.stops.map { $0.place.prepared.googlePlaceID }))
        input = try state.draft!.request(); input.plan.order = .optimized
        XCTAssertThrowsError(try input.validate(placeIDs: input.sources.map(\.placeID)))
    }
    func testPairedRevisionCampaign() async throws {
        struct Row: Codable {
            var scenario: String; var transport: String; var expectedApplicable: Bool; var applicable: Bool
            var baselineOrder: [String]; var editedOrder: [String]; var resultOrder: [String]
            var baselineTravelSeconds: Double; var travelSeconds: Double; var walkingSeconds: Double; var totalWaitingSeconds: Double
            var elapsedSeconds: Double?; var milliseconds: Double; var travelCalls: Int
        }
        var rows: [Row] = []
        for mode in ContextTransport.allCases {
            for scenario in ["replace-first", "replace-middle", "replace-last", "reorder", "delete", "add", "deadline-conflict", "waiting-conflict"] {
                var state = try await state()
                try state.put(newStop("revision-library"))
                state.change { $0.transport = mode }
                let baseline = try await ItineraryRevisionReplay.preview(state.draft!.request())
                let baselineOrder = baseline.result.result.itinerary.visits.map(\.placeID)
                if scenario.hasPrefix("replace") {
                    let index = scenario == "replace-first" ? 0 : (scenario == "replace-middle" ? 1 : 2)
                    try state.put(newStop("revision-cafe"), replacing: state.draft!.stops[index].id)
                } else if scenario == "reorder" { state.move(from: 2, to: 0) }
                else if scenario == "delete" { state.change { $0.stops.remove(at: 1) } }
                else if scenario == "add" { try state.put(newStop("revision-cafe")) }
                else if scenario == "deadline-conflict" { state.change { $0.deadline = $0.departure.addingTimeInterval(600) } }
                else if scenario == "waiting-conflict" { state.change { $0.maximumWaitingMinutes = 0 } }
                let input = try state.draft!.request()
                let began = ContinuousClock.now
                let preview = try await ItineraryRevisionReplay.preview(input)
                let duration = began.duration(to: .now).components
                let milliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
                let trip = preview.result.result.itinerary
                let expected = scenario != "deadline-conflict" && !(scenario == "waiting-conflict" && mode == .transjakarta)
                XCTAssertEqual(preview.canApply, expected, "\(mode):\(scenario)")
                if expected {
                    XCTAssertEqual(trip.visits.map(\.placeID), input.sources.map(\.placeID))
                    XCTAssertTrue(Set(input.requiredPlaceIDs).isSubset(of: Set(trip.visits.map(\.placeID))))
                    XCTAssertEqual(trip.elapsedSeconds!, trip.travelSeconds + trip.waitingSeconds + trip.dwellSeconds, accuracy: 0.001)
                }
                rows.append(.init(scenario: scenario, transport: mode.rawValue, expectedApplicable: expected, applicable: preview.canApply, baselineOrder: baselineOrder, editedOrder: input.sources.map(\.placeID), resultOrder: trip.visits.map(\.placeID), baselineTravelSeconds: baseline.result.result.itinerary.travelSeconds, travelSeconds: trip.travelSeconds, walkingSeconds: trip.walkingSeconds, totalWaitingSeconds: trip.totalWaitingSeconds, elapsedSeconds: trip.elapsedSeconds, milliseconds: milliseconds, travelCalls: trip.travelCalls))
            }
        }
        XCTAssertEqual(rows.count, 16)
        if let output = ProcessInfo.processInfo.environment["POC_REVISION_REPORT"] {
            try ContextJSON.encoder().encode(rows).write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }

    func testOmissionDoesNotMislabelAvailableHoursAsFailure() async throws {
        var state = try await state()
        state.change { $0.stops[0].required = false; $0.deadline = $0.departure.addingTimeInterval(70 * 60) }
        let preview = try await ItineraryRevisionReplay.preview(state.draft!.request())
        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.result.omitted.count, 1)
        XCTAssertTrue(preview.result.omitted[0].reason.contains("batas pencarian"))
        XCTAssertFalse(preview.result.omitted[0].reason.contains("operating_hours_options"))
    }

    func testUnscheduledOptionalPlaceSurvivesMultipleRevisionEdits() async throws {
        var state = try await state()
        state.change { $0.stops[0].required = false; $0.deadline = $0.departure.addingTimeInterval(70 * 60) }
        for _ in 0 ..< 3 {
            let preview = try await ItineraryRevisionReplay.preview(state.draft!.request())
            XCTAssertTrue(state.receive(preview)); try state.apply(); try state.begin()
            XCTAssertEqual(state.draft?.omittedStops.map { $0.place.prepared.googlePlaceID }, ["revision-park"])
        }
    }

}
