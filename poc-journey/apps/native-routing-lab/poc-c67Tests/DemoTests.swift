import XCTest
@testable import poc_c67

@MainActor final class DemoTests: XCTestCase {
    func testRegroupHasExpectedUnresolvedAndOpenCase() throws {
        let run = try DemoScenario.regroup.run()
        XCTAssertEqual(run.mode, .simulation)
        XCTAssertEqual(run.sessions[0].counts, SessionCounts(total: 4, expected: 3, verified: 2, unresolved: 1, excluded: 1, openCases: 1))
        XCTAssertFalse(run.sessions[0].participants[0].verified)
        XCTAssertTrue(run.sessions[0].participants[0].followUpOpen)
    }
    func testReviewedScenarioUsesExplicitEventsAndRequiresClosure() throws {
        let run = try DemoScenario.reviewed.run()
        XCTAssertEqual(run.sessions[0].counts.verified, 4)
        XCTAssertEqual(run.sessions[0].events.count, 4)
        XCTAssertTrue(run.sessions[0].counts.canCloseNormally)
        XCTAssertNil(run.sessions[0].closedAt)
    }
    func testDemoLoadDoesNotModifyStateWhenSaveFails() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        let original = app.store.state.runID
        app.store.failNextSave = true
        XCTAssertThrowsError(try app.loadDemo(.regroup))
        XCTAssertEqual(app.store.state.runID, original)
        XCTAssertEqual(app.store.state.sessions[0].counts.verified, 0)
        XCTAssertNil(app.received)
    }
    func testDemoCannotOverwriteBoundRealRun() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        let ref = app.cloud.makeReference(runID: app.store.state.runID, participantID: "P01")
        try app.store.commit { $0.mode = .real; $0.binding = ref }
        let original = app.store.state.runID
        XCTAssertFalse(app.canReplaceRun)
        XCTAssertThrowsError(try app.loadDemo(.reviewed))
        XCTAssertEqual(app.store.state.runID, original)
        XCTAssertEqual(app.store.state.binding, ref)
    }
    func testDemoStaleLocationIsSimulatedAndDoesNotVerifyP01() throws {
        let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
        try app.loadDemo(.stale)
        XCTAssertEqual(app.received?.simulated, true)
        XCTAssertTrue(LocationRules.freshness(app.received).contains("Kedaluwarsa"))
        XCTAssertFalse(app.store.state.sessions[0].participants[0].verified)
        XCTAssertEqual(app.store.state.sessions[0].counts.verified, 2)
    }
    func testAllDemoScenariosAreConsistentAndResetLocalSession() throws {
        for scenario in DemoScenario.allCases {
            let app = try POCController(container: SessionStore.container(inMemory: true), testing: true)
            try app.loadDemo(scenario)
            let s = app.store.state.sessions[0]
            XCTAssertEqual(app.store.state.sessions.count, 1)
            XCTAssertEqual(s.counts.expected, s.counts.verified + s.counts.unresolved)
            XCTAssertEqual(s.counts.total, s.counts.expected + s.counts.excluded)
            XCTAssertNil(app.store.state.owner); XCTAssertNil(app.store.state.binding)
        }
    }
    func testFilteringDoesNotChangeSummaryAndDuplicateNameSearchWorks() throws {
        let s = try DemoScenario.regroup.run().sessions[0]
        let counts = s.counts
        XCTAssertEqual(ParticipantFilter.unverified.results(in: s.participants, search: "").map(\.id), ["P01"])
        XCTAssertEqual(ParticipantFilter.followUp.results(in: s.participants, search: "").map(\.id), ["P01"])
        XCTAssertEqual(ParticipantFilter.excluded.results(in: s.participants, search: "").map(\.id), ["P04"])
        XCTAssertEqual(ParticipantFilter.all.results(in: s.participants, search: " Ayu ").map(\.id), ["P01", "P03"])
        XCTAssertEqual(ParticipantFilter.all.results(in: s.participants, search: "P03").map(\.id), ["P03"])
        XCTAssertEqual(s.counts, counts)
    }
}
