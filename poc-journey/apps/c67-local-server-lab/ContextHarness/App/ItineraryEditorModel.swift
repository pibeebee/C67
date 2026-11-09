import Foundation
import Observation
import SwiftUI
import PlaceContextEngine
import DynamicTripContracts
import RecommendationContracts

@MainActor @Observable final class ItineraryEditorModel {
    private(set) var state = ItineraryRevisionState()
    var presented = false
    var busy = false
    var error: String?
    var query = ""
    var appleQuery = ""
    var results: [GooglePlace] = []
    var pending: DynamicPreparedPlace?
    var replacingID: UUID?
    var refreshingOrigin = false
    var refreshingID: UUID?
    var required = true
    var picking = false
    var pendingSource: RevisionPlaceSource?
    private var operation = UUID()
    private var task: Task<Void, Never>?
    private let store: ItineraryRevisionStore
    private let writeState: @MainActor (ItineraryRevisionState) throws -> Void
    private let requestPreview: (@MainActor (ItineraryRevisionInput) async throws -> ItineraryRevisionPreview)?
    private let fixtureMode: Bool
    var fixture: Bool { fixtureMode }
    init(store overrideStore: ItineraryRevisionStore? = nil, fixture: Bool? = nil, saveState: (@MainActor (ItineraryRevisionState) throws -> Void)? = nil, requestPreview: (@MainActor (ItineraryRevisionInput) async throws -> ItineraryRevisionPreview)? = nil) {
        self.requestPreview = requestPreview
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testing = ProcessInfo.processInfo.arguments.contains("--revision-ui-test")
        fixtureMode = fixture ?? testing
        let selectedStore = overrideStore ?? ItineraryRevisionStore(url: dir.appendingPathComponent(testing ? "itinerary-revisions-test.json" : "itinerary-revisions.json"))
        store = selectedStore; writeState = saveState ?? { try selectedStore.save($0) }
        if testing && ProcessInfo.processInfo.arguments.contains("--revision-reset") { try? FileManager.default.removeItem(at: store.url) }
        do { state = try store.load() } catch { self.error = "Perjalanan tersimpan belum dapat dibaca: \(error.localizedDescription)" }
    }
    @discardableResult private func persist(_ transform: (inout ItineraryRevisionState) throws -> Void) -> Bool {
        do {
            var next = state; try transform(&next); try writeState(next); state = next; return true
        } catch { self.error = "Perubahan belum disimpan: \(error.localizedDescription)"; return false }
    }
    @discardableResult func capture(origin: ChosenPlace, stops: [PersonalStopDraft], input: DynamicPlanInput, result: PersonalPlanResult) -> Bool {
        guard result.result.itinerary.status.hasPrefix("candidate"), !result.result.itinerary.visits.isEmpty, stops.count == input.stops.count,
              origin.endpoint.preparedID == input.origin.preparedID,
              zip(stops, input.stops).allSatisfy({ $0.stop.place.endpoint.preparedID == $1.endpoint.preparedID && $0.stop.place.endpoint.appleCandidateID == $1.endpoint.appleCandidateID }) else { return false }
        let rows = zip(stops, input.stops).map { row, effective in
            RevisionStop(place: .init(prepared: row.stop.place.prepared, apple: row.stop.place.apple), required: row.required, durationMinutes: effective.durationMinutes, exposure: effective.exposure, preferredTime: effective.preferredTime, avoidRain: effective.avoidRain, source: .init(placeID: row.stop.place.prepared.googlePlaceID, origin: .previousPlan))
        }
        let draft = ItineraryEditDraft(parentRevisionID: UUID(), origin: .init(prepared: origin.prepared, apple: origin.apple), stops: rows, departure: input.departure, deadline: input.deadline, maximumWaitingMinutes: input.maximumWaitingMinutes, transport: input.transport ?? .automobile)
        return persist { $0.capture(.init(draft: draft, result: result)) }
    }
    func begin() {
        invalidateOperation()
        if state.draft == nil { persist { try $0.begin() } }
        presented = state.draft != nil
    }
    func invalidateOperation() { operation = UUID(); task?.cancel(); task = nil; busy = false; error = nil }
    func edit(_ change: (inout ItineraryEditDraft) throws -> Void) {
        guard let draft = state.draft else { return }
        do {
            var next = draft; try change(&next); guard next != draft else { return }
            fixtureTrace("actual edit")
            invalidateOperation(); persist { $0.change { $0 = next } }
        } catch { self.error = error.localizedDescription }
    }
    func move(_ index: Int, by offset: Int) { invalidateOperation(); persist { $0.move(from: index, to: index + offset) } }
    func move(_ indices: IndexSet, to destination: Int) { edit { $0.stops.move(fromOffsets: indices, toOffset: destination) } }
    func remove(_ id: UUID) { edit { $0.stops.removeAll { $0.id == id } } }
    func cancel() { invalidateOperation(); if persist({ $0.cancel() }) { presented = false } }
    func close() { invalidateOperation(); presented = false }
    func apply() { persist { try $0.apply() }; if state.draft == nil { presented = false } }
    func pick(replacing id: UUID? = nil) {
        invalidateOperation(); replacingID = id; refreshingID = nil; refreshingOrigin = false
        pending = nil; pendingSource = nil; results = []; query = ""; appleQuery = ""; required = true; picking = true
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        invalidateOperation(); let id = operation; busy = true
        task = Task { @MainActor in
            defer { if operation == id { busy = false; task = nil } }
            do { try await work() } catch {
                if operation == id, !Task.isCancelled { self.error = "\(error.localizedDescription). Draft tetap tersimpan; segarkan tempat atau koneksi lalu coba lagi." }
            }
        }
    }
    func search() {
        let text = query
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        run {
            let generation = self.operation
            let values = self.fixture ? RevisionFixtures.search(text) : try await ContextAPI().request("search", body: DynamicSearchInput(query: text), as: [GooglePlace].self)
            guard self.operation == generation, !Task.isCancelled else { return }
            self.results = values
        }
    }
    func prepare(_ placeID: String, source: RevisionPlaceSource? = nil, appleQuery: String? = nil) {
        let day = state.draft.map { ContextClock.label($0.departure) } ?? ""
        run {
            let generation = self.operation
            let place = self.fixture ? try RevisionFixtures.prepared(placeID) : try await ContextAPI().request("prepare", body: DynamicPrepareInput(googlePlaceID: placeID, day: day, appleQuery: appleQuery), as: DynamicPreparedPlace.self)
            guard self.operation == generation, !Task.isCancelled else { return }
            self.pending = place; self.pendingSource = source ?? .init(placeID: placeID, origin: .userSelected)
        }
    }
    func retryIdentity() {
        guard let pending, !appleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        prepare(pending.googlePlaceID, source: pendingSource, appleQuery: appleQuery)
    }
    func refresh(_ id: UUID?) {
        guard let draft = state.draft else { return }
        let place = id.flatMap { value in draft.stops.first { $0.id == value }?.place } ?? draft.origin
        pick(); refreshingID = id; refreshingOrigin = id == nil; query = place.prepared.name
        // Re-register the selected ID through search; an expired server session cannot reuse its old prepared handle.
        run {
            let generation = self.operation
            let values: [GooglePlace] = self.fixture ? RevisionFixtures.search(place.prepared.name) : try await ContextAPI().request("search", body: DynamicSearchInput(query: place.prepared.name), as: [GooglePlace].self)
            guard self.operation == generation, !Task.isCancelled else { return }
            self.results = values
            guard values.contains(where: { $0.id == place.prepared.googlePlaceID }) else { throw ContextError.invalid("Identitas lama tidak ditemukan; pilih hasil dan periksa kembali") }
            let prepared = self.fixture ? try RevisionFixtures.prepared(place.prepared.googlePlaceID) : try await ContextAPI().request("prepare", body: DynamicPrepareInput(googlePlaceID: place.prepared.googlePlaceID, day: ContextClock.label(draft.departure)), as: DynamicPreparedPlace.self)
            guard self.operation == generation, !Task.isCancelled else { return }
            self.pending = prepared; self.pendingSource = .init(placeID: place.prepared.googlePlaceID, origin: .previousPlan)
        }
    }
    func confirm(_ apple: DynamicAppleCandidate) {
        guard let pending, apple.canConfirm else { return }
        let place = RevisionPlace(prepared: pending, apple: apple)
        if refreshingOrigin { edit { $0.origin = place } }
        else if let id = refreshingID {
            edit { draft in
                guard let index = draft.stops.firstIndex(where: { $0.id == id }), draft.stops[index].place.prepared.googlePlaceID == pending.googlePlaceID else { throw ContextError.invalid("Identitas tempat berubah; gunakan Ganti tempat") }
                draft.stops[index].place = place
                draft.stops[index].source = .init(placeID: pending.googlePlaceID, origin: .previousPlan)
            }
        } else {
            invalidateOperation()
            let value = RevisionStop(place: place, required: required, source: pendingSource ?? .init(placeID: pending.googlePlaceID, origin: .userSelected))
            persist { try $0.put(value, replacing: replacingID) }
        }
        if error == nil { self.pending = nil; picking = false }
    }
    private func fixtureTrace(_ event: String) {
        guard fixture else { return }
        let url = store.url.deletingLastPathComponent().appendingPathComponent("editor-fixture-trace.log")
        let prior = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (prior + "\(Date()) \(event)\n").write(to: url, atomically: true, encoding: .utf8)
    }
    func calculate() {
        fixtureTrace("calculate")
        guard let draft = state.draft else { return }
        do {
            let input = try draft.request()
            guard persist({ $0.discardPreview() }) else { return }
            run {
                let generation = self.operation
                let value: ItineraryRevisionPreview
                if let requestPreview = self.requestPreview { value = try await requestPreview(input) }
                else if self.fixture { value = try await RevisionFixtures.preview(input) }
                else { value = try await ContextAPI(namespace: "itinerary").request("revisions/preview", body: input, as: ItineraryRevisionPreview.self) }
                guard self.operation == generation, !Task.isCancelled else { self.fixtureTrace("stale preview rejected"); return }
                self.fixtureTrace("preview completed")
                self.persist { state in _ = state.receive(value) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func seedFixtureIfNeeded() async {
        guard fixture, state.current == nil else { return }
        do { let revision = try await RevisionFixtures.initial(); persist { $0.capture(revision) } }
        catch { self.error = error.localizedDescription }
    }
}
