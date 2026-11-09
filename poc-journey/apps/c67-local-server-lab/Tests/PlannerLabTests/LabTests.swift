import PreferenceLearning

import XCTest
import CryptoKit
@testable import PlannerEngine
import PlannerContracts
import PlannerStorage

@MainActor final class LabTests: XCTestCase {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("C67LabTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func query(_ to: String = "b", departure: Date = LabMatrix.now, from: String = "a") -> LabETAQuery {
        .init(fromID: from, toID: to, fromLatitude: -6.2, fromLongitude: 106.8,
              toLatitude: -6.21, toLongitude: 106.81 + Double(to.utf8.first! % 20) / 1000,
              mode: "automobile", departure: departure)
    }
    func input(_ operation: String = "operation") throws -> JobInput {
        .init(operationID: operation, runID: "test", variant: .B, snapshotHash: try LabSnapshot.hash(), request: LabMatrix.cases()[0].request)
    }
    func testExactTimeRoundTrip() throws {
        var r = try input(); r.request.departure.addTimeInterval(0.123456)
        let data = try LabJSON.encoder().encode(r)
        let decoded = try LabJSON.decoder().decode(JobInput.self, from: data)
        XCTAssertEqual(decoded.request.departure, r.request.departure)
    }
    func testBatchGroupsAndDeduplicatesWithoutMergingTimesOrDirections() async throws {
        let oracle = LabOracle(); let acquisition = LabAcquisition(oracle)
        let q = query(); let later = query(departure: LabMatrix.now.addingTimeInterval(0.5))
        var reversed = query("a", from: "b"); reversed.fromLatitude = -6.21; reversed.fromLongitude = 106.81
        let values = try await acquisition.fetch([q, query("c"), q, later, reversed], bulk: true)
        XCTAssertEqual(values.count, 5); XCTAssertEqual(oracle.metrics.cells, 4)
        XCTAssertEqual(oracle.metrics.calls, 3)
        XCTAssertEqual(values[0].seconds, values[2].seconds)
    }
    func testMaximumTenDestinationsPerBatch() async throws {
        let oracle = LabOracle()
        let queries = (0 ..< 23).map { query("node\($0)") }
        _ = try await LabAcquisition(oracle).fetch(queries, bulk: true)
        XCTAssertEqual(oracle.metrics.calls, 3); XCTAssertEqual(oracle.metrics.cells, 23)
        XCTAssertTrue(oracle.metrics.requests.allSatisfy { $0.count <= 10 })
    }
    func testRESTMapsReorderedAndPartialResponseByCoordinates() throws {
        let queries = [query("b"), query("c")]
        let q = queries[1]
        let json: [String: Any] = ["etas": [["destination": ["latitude": q.toLatitude, "longitude": q.toLongitude],
                                             "transportType": "AUTOMOBILE", "distanceMeters": 200, "expectedTravelTimeSeconds": 100]]]
        let values = try LabRESTETA.parse(JSONSerialization.data(withJSONObject: json), queries: queries)
        XCTAssertNil(values[0].seconds); XCTAssertEqual(values[1].seconds, 100)
    }
    func testInvalidModeAndNegativeETAIsUnknown() throws {
        let q = query()
        let json: [String: Any] = ["etas": [["destination": ["latitude": q.toLatitude, "longitude": q.toLongitude],
                                             "transportType": "WALKING", "distanceMeters": 200, "expectedTravelTimeSeconds": -1]]]
        XCTAssertNil(try LabRESTETA.parse(JSONSerialization.data(withJSONObject: json), queries: [q])[0].seconds)
    }
    func testBudgetNeverExceedsCap() throws {
        let budget = LabProviderBudget(callLimit: 2, cellLimit: 3)
        try budget.consume(cells: 2)
        XCTAssertThrowsError(try budget.consume(cells: 2))
        try budget.consume(cells: 1)
        XCTAssertThrowsError(try budget.consume()); XCTAssertEqual(budget.calls, 2)
    }
    func testJWTSignatureAndWeatherClaims() throws {
        let key = P256.Signing.PrivateKey()
        let token = try LabJWT.sign(team: "TEAM", keyID: "KEY", pem: key.pemRepresentation, service: "SERVICE", now: LabMatrix.now)
        let parts = token.split(separator: ".").map(String.init)
        func data(_ value: String) -> Data {
            var s = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while s.count % 4 != 0 { s += "=" }; return Data(base64Encoded: s)!
        }
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: data(parts[2]))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)))
        let claims = try JSONSerialization.jsonObject(with: data(parts[1])) as! [String: Any]
        XCTAssertEqual(claims["sub"] as? String, "SERVICE")
        XCTAssertEqual(claims["iss"] as? String, "TEAM")
        XCTAssertNil(claims["scope"])
        let header = try JSONSerialization.jsonObject(with: data(parts[0])) as! [String: Any]
        XCTAssertEqual(header["id"] as? String, "TEAM.SERVICE")
        let maps = try LabJWT.sign(team: "TEAM", keyID: "KEY", pem: key.pemRepresentation, now: LabMatrix.now)
        let mapsParts = maps.split(separator: ".").map(String.init)
        let mapsClaims = try JSONSerialization.jsonObject(with: data(mapsParts[1])) as! [String: Any]
        XCTAssertEqual(mapsClaims["scope"] as? String, "server_api")
        XCTAssertNil(mapsClaims["sub"])
        let mapsHeader = try JSONSerialization.jsonObject(with: data(mapsParts[0])) as! [String: Any]
        XCTAssertNil(mapsHeader["id"])
        let mapsSignature = try P256.Signing.ECDSASignature(rawRepresentation: data(mapsParts[2]))
        XCTAssertTrue(key.publicKey.isValidSignature(mapsSignature, for: Data((mapsParts[0] + "." + mapsParts[1]).utf8)))
    }
    func testJobIdempotencyConflictAndCapacity() throws {
        let dir = try directory(); let store = try JobStore(path: dir.appendingPathComponent("db").path)
        defer { store.close() }
        let i = try input(); let first = try store.submit(i, snapshot: i.snapshotHash)
        XCTAssertEqual(try store.submit(i, snapshot: i.snapshotHash).id, first.id)
        var changed = i; changed.request.defaultDuration = 90
        XCTAssertThrowsError(try store.submit(changed, snapshot: i.snapshotHash))
        _ = try store.submit(input("two"), snapshot: i.snapshotHash)
        _ = try store.submit(input("three"), snapshot: i.snapshotHash)
        XCTAssertThrowsError(try store.submit(input("four"), snapshot: i.snapshotHash))
    }
    func testRestartMarksInterruptedJobs() throws {
        let path = try directory().appendingPathComponent("db").path
        let first = try JobStore(path: path); let i = try input()
        let job = try first.submit(i, snapshot: i.snapshotHash); first.close()
        let second = try JobStore(path: path); defer { second.close() }
        XCTAssertEqual(try second.get(job.id)?.state, .failed)
        XCTAssertEqual(try second.get(job.id)?.error, "interrupted_by_restart")
    }
    func testSnapshotMismatchRejected() throws {
        let dir = try directory(); let store = try JobStore(path: dir.appendingPathComponent("db").path)
        defer { store.close() }
        XCTAssertThrowsError(try store.submit(input(), snapshot: "wrong"))
    }
    func testStaleBaseRejectedBeforeWork() throws {
        let dir = try directory(); let store = try JobStore(path: dir.appendingPathComponent("db").path)
        defer { store.close() }
        var i = try input(); i.baseRevision = 1
        XCTAssertThrowsError(try store.submit(i, snapshot: i.snapshotHash))
    }
    func testCancellationProtectsTerminalState() async throws {
        let dir = try directory(); let store = try JobStore(path: dir.appendingPathComponent("db").path)
        let worker = try LabWorker(store: store, directory: dir, mode: .replay)
        let job = try worker.submit(input())
        _ = try worker.cancel(job.id)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(try store.get(job.id)?.state, .cancelled)
        XCTAssertNil(try store.get(job.id)?.result)
        worker.shutdown(); store.close()
    }
    func testDeadlineCancelsLateCompletion() async throws {
        let dir = try directory(); let store = try JobStore(path: dir.appendingPathComponent("db").path)
        let worker = try LabWorker(store: store, directory: dir, mode: .replay, timeoutSeconds: 0.000001)
        let job = try worker.submit(input())
        for _ in 0 ..< 100 {
            if try store.get(job.id)?.state.terminal == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try store.get(job.id)?.state, .timedOut)
        worker.shutdown()
        try await Task.sleep(for: .milliseconds(100)); store.close()
    }
    func testExplicitRESTCannotFallBackToReplay() async throws {
        let runtime = try LabRuntime(embeddingDirectory: directory())
        do {
            _ = try await runtime.run(LabMatrix.cases()[0].request, variant: .B, mode: .rest,
                                      now: LabMatrix.now, directory: directory())
            XCTFail("Missing REST configuration must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("REST")) }
    }
    func testUnknownMustDoesNotProducePlan() async throws {
        let runtime = try LabRuntime(embeddingDirectory: directory())
        let result = try await runtime.run(LabMatrix.cases().last!.request, variant: .C, mode: .replay,
                                           now: LabMatrix.now, directory: directory())
        XCTAssertEqual(result.outcome, "needs_places"); XCTAssertNil(result.plan)
        XCTAssertEqual(result.providerMetrics.calls, 0)
    }
    func testAllETAFailureCannotBecomeInfeasibleProof() async throws {
        let runtime = try LabRuntime(embeddingDirectory: directory())
        let result = try await runtime.run(LabMatrix.cases()[0].request, variant: .B, mode: .replay,
                                           now: LabMatrix.now, directory: directory(), eta: LabOracle(fault: "all_eta_unavailable"))
        XCTAssertEqual(result.outcome, "provider_unavailable"); XCTAssertNil(result.lowerBoundSeconds)
    }
    func testApplyIdempotencyAndStaleProposal() async throws {
        let dir = try directory(); let runtime = try LabRuntime(embeddingDirectory: dir)
        let i = try input()
        let result = try await runtime.run(i.request, variant: .B, mode: .replay, now: LabMatrix.now, directory: dir)
        let plan = try XCTUnwrap(result.plan); XCTAssertTrue(plan.feasible)
        let store = try JobStore(path: dir.appendingPathComponent("db").path); defer { store.close() }
        var first = try store.submit(i, snapshot: i.snapshotHash)
        var otherInput = i; otherInput.operationID = "other"
        var other = try store.submit(otherInput, snapshot: i.snapshotHash)
        first.state = .completed; first.result = result; try store.save(first)
        let apply = ApplyInput(clientID: i.clientID, baseRevision: 0, requestHash: try LabJSON.hash(plan.request))
        XCTAssertEqual(try store.apply(first.id, input: apply, now: LabMatrix.now).revision, 1)
        XCTAssertEqual(try store.apply(first.id, input: apply, now: LabMatrix.now).revision, 1)
        var changed = result; changed.plan?.id = UUID(); other.state = .completed; other.result = changed; try store.save(other)
        XCTAssertThrowsError(try store.apply(other.id, input: apply, now: LabMatrix.now))
        XCTAssertEqual(try store.accepted(i.clientID)?.plan.id, plan.id)
    }
}

@MainActor final class CampaignTests: XCTestCase {
    func testReplayAndLiveSchedulesAreSeparatedAndBounded() {
        XCTAssertEqual(LabCampaign.replay().count, 51)
        let live = LabCampaign.live(now: LabMatrix.now)
        XCTAssertEqual(live.count, 75)
        XCTAssertEqual(live.filter { $0.condition == "fresh" }.count, 36)
        XCTAssertEqual(live.filter { $0.condition == "warm" }.count, 12)
        XCTAssertEqual(live.filter { $0.condition == "priming" }.count, 12)
        XCTAssertEqual(live.filter { $0.condition == "edge" }.count, 15)
        XCTAssertEqual(live.first?.test.family, "N3")
        for variant in ["A", "B", "C"] { XCTAssertEqual(live.filter { $0.variant == variant }.count, 25) }
        for index in live.indices where live[index].condition == "warm" {
            XCTAssertEqual(live[index - 1].condition, "priming")
            XCTAssertEqual(live[index - 1].variant, live[index].variant)
            XCTAssertEqual(live[index - 1].test.family, live[index].test.family)
        }
    }
}

@MainActor final class EmbeddingParityTests: XCTestCase {
    func testSingleRuntimeMatchesOriginalE5AndAreaCacheDoesNotPersistQueries() async throws {
        let upstream = PreferenceLearning.E5Embedding()
        let runtime = LabE5Embedding()
        let text = "Perpustakaan untuk membaca dan belajar budaya di Jakarta"
        let expected = try await upstream.encode(text, query: false)
        let actual = try await runtime.encode(text, query: false)
        XCTAssertEqual(expected.count, 384)
        XCTAssertLessThan(zip(expected, actual).map { abs($0 - $1) }.max()!, 0.0000001)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LabEmbeddingCache-\(UUID())")
        let first = LabEmbeddingCache(directory: directory, runtime: runtime, areaIDs: [text: "area-a"])
        let second = LabEmbeddingCache(directory: directory, runtime: runtime, areaIDs: [text: "area-b"])
        _ = try await first.encode(text, query: false)
        _ = try await second.encode(text, query: false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        _ = try await first.encode("query user", query: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        let reloaded = try await first.encode(text, query: false)
        XCTAssertEqual(reloaded, actual)
    }
}

@MainActor final class SharedPinTests: XCTestCase {
    func testSharedPinSnapshotIsExplicitFreshAndRejectsUnknownQueries() async throws {
        let ids = ["origin", "cikini", "bdt-rbbj", "erasmus", "ragunan", "gbk"]
        let pins = Dictionary(uniqueKeysWithValues: ids.map { id in (id, PlacePin(id: id, name: id,
                                                                                  address: "Jakarta", latitude: -6.2, longitude: 106.83)) })
        struct Payload: Encodable {
            var schemaVersion = 1; var observedAt: Date; var evidence = "Synthetic unit test only"
            var pins: [String: PlacePin]; var queries: [String: String]
        }
        let payload = Payload(observedAt: .now, pins: pins,
                              queries: Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) }))
        var snapshot = try LabJSON.decoder().decode(LabPinSnapshot.self, from: LabJSON.encoder().encode(payload))
        let provider = try LabPinnedSearch(snapshot: snapshot)
        let result = try await provider.search(query: "cikini")
        XCTAssertEqual(result.first?.id, "cikini")
        do { _ = try await provider.search(query: "different branch"); XCTFail("Unknown query must not get a pin") }
        catch { XCTAssertTrue(error.localizedDescription.contains("does not cover")) }
        snapshot.observedAt = Date().addingTimeInterval(-86401)
        XCTAssertThrowsError(try LabPinnedSearch(snapshot: snapshot))
    }
}
