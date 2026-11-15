import XCTest
import DynamicTripContracts
import PlaceContextEngine
@testable import C67ContextLab

@MainActor final class ItineraryEditorModelTests: XCTestCase {
    func store() -> ItineraryRevisionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return .init(url: url)
    }
    func setup(_ editor: ItineraryEditorModel) async throws -> PersonalLabModel {
        await editor.seedFixtureIfNeeded()
        let model = PersonalLabModel(editor: editor); model.restoreRevision(); return model
    }
    func testNoOpDateBindingDoesNotCancelPendingPreview() async throws {
        let editor = ItineraryEditorModel(store: store(), fixture: true)
        _ = try await setup(editor); editor.begin()
        let id = try XCTUnwrap(editor.state.draft).id
        editor.calculate()
        editor.edit { $0.departure = $0.departure }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(editor.state.draft?.id, id)
        XCTAssertNotNil(editor.state.preview)
    }
    func testActualEditRejectsDelayedPreview() async throws {
        let editor = ItineraryEditorModel(store: store(), fixture: true)
        _ = try await setup(editor); editor.begin(); editor.calculate()
        editor.edit { $0.transport = .transjakarta }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(editor.state.preview)
    }
    func testInitialPlanSettingsRaceCannotPublish() async throws {
        let editor = ItineraryEditorModel(store: store(), fixture: true)
        let model = try await setup(editor)
        let old = try XCTUnwrap(editor.state.current)
        let settings = model.planSettings
        let input = try old.draft.request().plan
        model.transport = .transjakarta
        XCTAssertThrowsError(try model.publishPlan(old.result, origin: model.origin!, stops: model.stops, input: input, expectedSettings: settings))
        XCTAssertEqual(editor.state.current?.id, old.id)
    }
    func testCaptureUsesEffectiveRainInput() async throws {
        let editor = ItineraryEditorModel(store: store(), fixture: true)
        let model = try await setup(editor)
        let old = try XCTUnwrap(editor.state.current)
        var input = try old.draft.request().plan
        input.stops[0].exposure = .outdoor; input.stops[0].avoidRain = true
        XCTAssertFalse(model.stops[0].stop.avoidRain)
        XCTAssertTrue(editor.capture(origin: model.origin!, stops: model.stops, input: input, result: old.result))
        XCTAssertEqual(editor.state.current?.draft.stops[0].avoidRain, true)
        XCTAssertEqual(editor.state.current?.draft.stops[0].exposure, .outdoor)
    }
    func testLiveEditorDoesNotPersistProviderDetails() async throws {
        let source = ItineraryEditorModel(store: store(), fixture: true)
        let model = try await setup(source)
        let initial = try XCTUnwrap(source.state.current)
        let liveStore = store()
        let live = ItineraryEditorModel(store: liveStore, fixture: false)
        XCTAssertTrue(live.capture(origin: try XCTUnwrap(model.origin), stops: model.stops, input: try initial.draft.request().plan, result: initial.result))
        live.begin()
        XCTAssertNotNil(live.state.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveStore.url.path))
        let restarted = ItineraryEditorModel(store: liveStore, fixture: false)
        XCTAssertNil(restarted.state.draft)
        XCTAssertNil(restarted.state.current)
    }
    final class WriteGate { var fail = false }
    func testFailedCaptureDoesNotPublishDifferentVersion() async throws {
        let storage = store(); let gate = WriteGate()
        let editor = ItineraryEditorModel(store: storage, fixture: true, saveState: { state in
            if gate.fail { throw CocoaError(.fileWriteNoPermission) }
            try storage.save(state)
        })
        let model = try await setup(editor)
        let old = try XCTUnwrap(editor.state.current); gate.fail = true
        XCTAssertThrowsError(try model.publishPlan(old.result, origin: model.origin!, stops: model.stops, input: old.draft.request().plan, expectedSettings: model.planSettings))
        XCTAssertEqual(editor.state.current?.id, old.id)
        XCTAssertEqual(model.planID, old.id)
        XCTAssertNotNil(editor.error)
    }
    func testProviderTimeoutRetainsDraftAndAcceptedVersion() async throws {
        let editor = ItineraryEditorModel(store: store(), fixture: true, requestPreview: { _ in throw URLError(.timedOut) })
        _ = try await setup(editor); editor.begin()
        let accepted = editor.state.current?.id, draft = editor.state.draft?.id
        editor.calculate(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(editor.state.current?.id, accepted)
        XCTAssertEqual(editor.state.draft?.id, draft)
        XCTAssertNil(editor.state.preview); XCTAssertFalse(editor.busy); XCTAssertNotNil(editor.error)
    }
    func testServerRestartExpiryRetainsRecoverableDraft() async throws {
        let editor = ItineraryEditorModel(store: store(), fixture: true, requestPreview: { _ in throw ContextError.invalid("Place selection expired; search again") })
        _ = try await setup(editor); editor.begin()
        let draft = editor.state.draft?.id
        editor.calculate(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(editor.state.draft?.id, draft)
        XCTAssertNotNil(editor.state.current); XCTAssertNil(editor.state.preview)
        XCTAssertTrue(editor.error?.contains("Draft tetap tersimpan") == true)
    }

}
