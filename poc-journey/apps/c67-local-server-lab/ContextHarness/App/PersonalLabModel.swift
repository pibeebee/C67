import Foundation
import Observation
import SwiftUI
import PlaceContextEngine
import DynamicTripContracts
import RecommendationContracts
import PreferenceLearning

struct PersonalStopDraft: Identifiable {
    var stop: StopDraft
    var required: Bool
    var id: UUID { stop.id }
}
struct PersonalObservation: Codable {
    var campaignLabel: String? = ProcessInfo.processInfo.environment["PERSONAL_CAMPAIGN_LABEL"]
    var date: Date
    var mode: String
    var success: Bool
    var clientSeconds: Double
    var displayReadySeconds: Double? = nil
    var interests: [PersonalInterest]
    var context: PersonalTripContext
    var metrics: RecommendationMetrics?
    var candidates: [Summary]
    var error: String?
    var judgments: [LLMPlaceChoice]? = nil
    var allCandidateFacts: [Summary]? = nil
    var recommendationID: UUID? = nil
    var parentRecommendationID: UUID? = nil
    struct Summary: Codable { var id: String; var categories: [PersonalInterest]; var hoursState: String; var llmRank: Int; var evidenceCount: Int; var evidenceIDs: [String]? = nil }
}
struct PersonalPlanObservation: Codable {
    var clientSeconds: Double
    var input: PersonalPlanInput
    var operatingBounds: [String: [OperatingInterval]]
    var response: PersonalPlanResult
    var preparedPlaceIDs: [String: String] = [:]
    var originPlaceID: String? = nil
    var identities: [Identity]? = nil
    struct Identity: Codable { var id: String; var googleName: String; var googleAddress: String; var appleName: String; var appleAddress: String; var separationMeters: Double; var nameSupported: Bool }
}
private struct SavedPersonalState: Codable {
    var onboarded: Bool
    var learning: PersonalLearningState
}

@MainActor @Observable final class PersonalLabModel {
    var learning = PersonalLearningState()
    var onboarded = false
    var selectedTab = 0
    var area = "Gambir Jakarta"
    var day = ContextClock.calendar.startOfDay(for: Date()).addingTimeInterval(86400)
    var departureMinute = 540
    var deadlineMinute = 1140
    var busy = false
    var status = "Isi konteks perjalanan untuk rekomendasi personal"
    var error: String?
    var recommendation: PersonalRecommendationResult?
    var browsePlaces: [PersonalRecommendedPlace] = []
    var canLoadMore = false
    var rainAdjustmentEnabled = true
    var planID = UUID()
    let simpleLayout = !ProcessInfo.processInfo.arguments.contains("--personal-full-layout")
    var candidateDetail: PersonalRecommendedPlace?
    var pending: DynamicPreparedPlace?
    var pendingRequired = false
    var pendingOrigin = false
    var origin: ChosenPlace?
    var originQuery = ""
    var originResults: [GooglePlace] = []
    var appleQuery = ""
    var stops: [PersonalStopDraft] = []
    var waitingMinutes = 30
    var grid = 15
    var policy = ContextSearchPolicy.beam
    var planOutput: PersonalPlanResult?
    var observations: [PersonalObservation] = []
    var embeddingInfo = "E5 belum dijalankan"
    var task: Task<Void, Never>?
    @ObservationIgnored private let embedding = E5Embedding()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var timedOut = false
    @ObservationIgnored private var observationLoaded = false
    @ObservationIgnored private var displayClock: ContinuousClock.Instant?
    @ObservationIgnored private var shownIDs = Set<String>()
    @ObservationIgnored private var placeProofs: [String: UUID] = [:]
    @ObservationIgnored private var priorPage: PersonalRecommendationResult?
    var operationIdentity: String { generation.uuidString }
    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let filename = ProcessInfo.processInfo.arguments.contains("--personal-ui-test") ? "personal-state-ui-test.json" : "personal-state.json"
        return dir.appendingPathComponent(filename)
    }
    init() {
        if ProcessInfo.processInfo.arguments.contains("--personal-reset-test"), ProcessInfo.processInfo.arguments.contains("--personal-ui-test") { try? FileManager.default.removeItem(at: storeURL) }
        if let bytes = try? Data(contentsOf: storeURL), let saved = try? ContextJSON.decoder().decode(SavedPersonalState.self, from: bytes),
           (try? saved.learning.profile.validate()) != nil { learning = saved.learning; onboarded = saved.onboarded }
        if let testDay = ProcessInfo.processInfo.environment["PERSONAL_TEST_DAY"], let date = ContextClock.day(testDay) { day = date }
    }
    struct PlanSettings: Equatable {
        struct Stop: Equatable {
            let id: UUID; let minutes: Int; let exposure: ActivityExposure; let afternoon: Bool; let required: Bool
        }
        let stops: [Stop]; let waitingMinutes: Int; let rainAdjustmentEnabled: Bool
    }
    var planSettings: PlanSettings {
        .init(stops: stops.map{.init(id: $0.id, minutes: $0.stop.durationMinutes, exposure: $0.stop.exposure,
                                     afternoon: $0.stop.afternoon, required: $0.required)}, waitingMinutes: waitingMinutes, rainAdjustmentEnabled: rainAdjustmentEnabled)
    }
    var context: PersonalTripContext { .init(area: area, day: ContextClock.label(day), departureMinute: departureMinute, deadlineMinute: deadlineMinute) }
    func saveProfile() {
        do {
            try learning.profile.validate()
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ContextJSON.encoder().encode(SavedPersonalState(onboarded: onboarded, learning: learning)).write(to: storeURL, options: .atomic)
        } catch { self.error = "Profil lokal gagal disimpan; \(error.localizedDescription)" }
    }
    func toggle(_ interest: PersonalInterest) {
        var values = learning.profile.interests
        if let index = values.firstIndex(of: interest) { values.remove(at: index) } else { values.append(interest) }
        learning.setExplicit(interests: values, pace: learning.profile.pace); invalidate(); saveProfile()
    }
    func setPace(_ pace: PersonalPace) { learning.setExplicit(interests: learning.profile.interests, pace: pace); invalidate(); saveProfile() }
    func finishOnboarding() { onboarded = true; saveProfile() }
    func invalidate() {
        generation = UUID(); recommendation = nil; browsePlaces = []; placeProofs = [:]; canLoadMore = false
        stops = []; planOutput = nil; pending = nil; candidateDetail = nil; error = nil; shownIDs = []
    }
    func record(_ kind: PersonalEventKind, _ candidate: PersonalCandidate) {
        guard let rec = recommendation else { return }
        learning.record(.init(recommendationID: placeProofs[candidate.id] ?? rec.id, candidate: candidate, kind: kind, context: rec.context)); saveProfile()
    }
    func open(_ row: PersonalRecommendedPlace) { record(.opened, row.candidate); candidateDetail = row }
    func recommend(fixture: String? = nil, more: Bool = false) {
        guard !busy else { return }
        let parent = more ? recommendation : nil
        if more && (parent == nil || !canLoadMore) { return }
        let input = RecommendationStart(profile: learning.profile, context: context, continuationID: parent?.id), id = UUID()
        let mode = fixture.map{"fixture-" + $0} ?? (more ? "live-more" : "live")
        if !more { recommendation = nil; browsePlaces = []; placeProofs = [:]; canLoadMore = false; planOutput = nil; stops = []; shownIDs = [] }
        generation = id; error = nil; busy = true; timedOut = false; priorPage = parent
        let began = ContinuousClock.now
        displayClock = began
        task = Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            let timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, self.generation == id else { return }
                self.timedOut = true; self.task?.cancel()
            }
            defer { timer.cancel(); busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                try input.profile.validate(); try input.context.validate()
                let api = try ContextAPI(namespace: "recommendation")
                status = fixture == nil ? "Mencari kandidat berdasarkan profil dan waktu…" : "Data tempat sintetis; menjalankan E5 dan LLM asli…"
                let prepared: PreparedRecommendation
                if let fixture {
                    struct Fixture: Encodable { var input: RecommendationStart; var scenario: String }
                    prepared = try await api.request("fixture", body: Fixture(input: input, scenario: fixture), as: PreparedRecommendation.self, timeout: 19)
                } else { prepared = try await api.request("start", body: input, as: PreparedRecommendation.self, timeout: 19) }
                try Task.checkCancellation()
                guard generation == id, context == input.context else { throw CancellationError() }
                if more && prepared.candidates.isEmpty {
                    canLoadMore = prepared.hasMore ?? false
                    status = canLoadMore ? "Belum ada pilihan baru pada pencarian ini. Anda masih bisa mencari lagi." : "Belum ada pilihan lain untuk area dan waktu ini."
                    return
                }
                status = "Mencocokkan \(prepared.candidates.count) kandidat dengan E5 lokal…"
                let embeddingClock = ContinuousClock.now
                var scores: [LocalCandidateScore] = [], embeddingStatus = "unavailable_category_signal_only"
                do {
                    let metadata = try await embedding.metadata()
                    embeddingInfo = "\(metadata.model) · \(metadata.dimensions) dimensi · \(metadata.runtime) · E5 English inputs \(PersonalEmbeddingText.version)"
                    let query = try await embedding.encode(PersonalEmbeddingText.query(profile: input.profile), query: true)
                    for candidate in prepared.candidates {
                        try Task.checkCancellation()
                        let vector = try await embedding.encode(PersonalEmbeddingText.passage(candidate: candidate), query: false)
                        scores.append(.init(id: candidate.id, semanticScore: try PreferenceRanker.cosine(query, vector)))
                    }
                    embeddingStatus = "actual_e5_" + metadata.revision + "_en_v1"
                } catch is CancellationError { throw CancellationError() }
                catch {
                    scores = prepared.candidates.map{.init(id: $0.id, semanticScore: nil)}
                    embeddingInfo = "E5 tidak tersedia; sinyal kategori digunakan, LLM tetap wajib"
                }
                try Task.checkCancellation(); status = "Menilai kandidat melalui LLM gratis; memeriksa bukti…"
                let remaining = 20 - ContextLabModel.seconds(began)
                guard remaining > 0.5 else { throw ContextError.invalid("Anggaran rekomendasi 20 detik tercapai") }
                let result = try await api.request("complete", body: RecommendationComplete(id: prepared.id, profileRevision: prepared.profileRevision,
                                                                                            scores: scores, embeddingStatus: embeddingStatus, embeddingSeconds: ContextLabModel.seconds(embeddingClock)), as: PersonalRecommendationResult.self, timeout: remaining)
                try Task.checkCancellation()
                guard generation == id, context == input.context, ContextLabModel.seconds(began) < 20 else { throw ContextError.invalid("Hasil terlambat atau konteks berubah; tidak diterapkan") }
                guard Set(result.places.map(\.id)).isDisjoint(with: Set(browsePlaces.map(\.id))) else {
                    throw ContextError.invalid("Pilihan tambahan mengulang hasil lama. Daftar dan tujuan sebelumnya tetap tersimpan.")
                }
                try appendObservation(.init(date: Date(), mode: mode, success: true, clientSeconds: ContextLabModel.seconds(began), interests: input.profile.interests,
                                            context: input.context, metrics: result.metrics, candidates: result.places.map{.init(id: $0.id, categories: $0.candidate.categories, hoursState: $0.candidate.hoursState, llmRank: $0.llmRank, evidenceCount: $0.candidate.evidence.count, evidenceIDs: $0.candidate.evidence.map(\.id))}, error: nil, judgments: result.judgments,
                                            allCandidateFacts: prepared.candidates.map{.init(id: $0.id, categories: $0.categories, hoursState: $0.hoursState, llmRank: 0, evidenceCount: $0.evidence.count, evidenceIDs: $0.evidence.map(\.id))}, recommendationID: result.id, parentRecommendationID: parent?.id))
                browsePlaces.append(contentsOf: result.places)
                for place in result.places { placeProofs[place.id] = result.id }
                canLoadMore = result.hasMore ?? false
                recommendation = result
                status = more ? "\(result.places.count) pilihan baru ditambahkan" : "\(result.places.count) kandidat siap dipilih · \(String(format: "%.2f", ContextLabModel.seconds(began))) detik"
            } catch {
                if generation != id { return }
                let message = timedOut ? "Rekomendasi melewati 20 detik. Coba lagi; tidak ada fallback non-LLM." : error.localizedDescription
                self.error = message; status = more ? "Pilihan sebelumnya tetap tersimpan" : "Rekomendasi belum tersedia · coba lagi"
                try? appendObservation(.init(date: Date(), mode: mode, success: false, clientSeconds: ContextLabModel.seconds(began), interests: input.profile.interests,
                                             context: input.context, metrics: nil, candidates: [], error: message, parentRecommendationID: parent?.id))
            }
        }
    }
    func candidateAppeared(_ row: PersonalRecommendedPlace) {
        if !shownIDs.contains(row.id) { shownIDs.insert(row.id); record(.shown, row.candidate) }
        guard let clock = displayClock, let rec = recommendation, placeProofs[row.id] == rec.id,
              !observations.isEmpty, observations[observations.count - 1].recommendationID == rec.id, observations[observations.count - 1].success,
              observations[observations.count - 1].displayReadySeconds == nil else { return }
        let seconds = ContextLabModel.seconds(clock)
        observations[observations.count - 1].displayReadySeconds = seconds
        if seconds >= 20 {
            let lateIDs = Set(rec.places.map(\.id))
            browsePlaces.removeAll{lateIDs.contains($0.id)}
            for id in lateIDs { placeProofs.removeValue(forKey: id) }
            recommendation = priorPage; canLoadMore = priorPage?.hasMore ?? false
            error = "Daftar baru belum tampil dalam 20 detik. Pilihan lama tetap tersimpan."
            observations[observations.count - 1].success = false; observations[observations.count - 1].error = error
        }
        priorPage = nil
        try? write(observations, name: "recommendations.json")
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; error = nil; busy = true
        task = Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await operation() } catch { self.error = error.localizedDescription; status = "Perlu diperiksa" }
        }
    }
    func choose(_ row: PersonalRecommendedPlace, required: Bool) {
        candidateDetail = nil
        if let index = stops.firstIndex(where: {$0.stop.place.prepared.googlePlaceID == row.id}) {
            if stops[index].required != required { stops[index].required = required; planOutput = nil }
            return
        }
        guard stops.count < 6 else { error = "Maksimal enam tujuan dalam satu rencana."; return }
        guard !row.id.hasPrefix("fixture-") else { error = "Kandidat sintetis tidak dapat dipakai untuk routing live"; return }
        perform {
            self.status = "Mengambil konteks dan mencari identitas Apple untuk \(row.candidate.name)…"
            self.pendingOrigin = false; self.pendingRequired = required
            self.pending = try await ContextAPI().request("prepare", body: DynamicPrepareInput(googlePlaceID: row.id, day: self.context.day,
                                                                                               appleQuery: self.appleQuery.isEmpty ? nil : self.appleQuery), as: DynamicPreparedPlace.self)
        }
    }
    func searchOrigin() {
        let query = originQuery
        perform { self.status = "Mencari lokasi awal…"; self.originResults = try await ContextAPI().request("search", body: DynamicSearchInput(query: query), as: [GooglePlace].self) }
    }
    func prepareOrigin(_ id: String) {
        perform {
            self.pendingOrigin = true; self.pendingRequired = true
            self.pending = try await ContextAPI().request("prepare", body: DynamicPrepareInput(googlePlaceID: id, day: self.context.day), as: DynamicPreparedPlace.self)
        }
    }
    func confirm(_ apple: DynamicAppleCandidate) {
        guard let pending, apple.canConfirm else { error = "Padanan terlalu jauh; cari identitas Apple lain"; return }
        let chosen = ChosenPlace(prepared: pending, apple: apple)
        if pendingOrigin { origin = chosen; originResults = []; planOutput = nil }
        else if stops.count < 6,!stops.contains(where: {$0.stop.place.prepared.googlePlaceID == pending.googlePlaceID}) {
            var stop = StopDraft(place: chosen)
            if let row = browsePlaces.first(where: {$0.id == pending.googlePlaceID}) {
                record(.selected, row.candidate)
                if simpleLayout { stop.exposure = row.candidate.suggestedOutdoorActivity ? .outdoor : .unknown }
            }
            stops.append(.init(stop: stop, required: pendingRequired)); planOutput = nil
        }
        self.pending = nil; appleQuery = ""; status = "Pilihan tersimpan; periksa durasi dan batas perjalanan"
    }
    func retryAppleIdentity() {
        guard let current = pending,!appleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform {
            self.pending = try await ContextAPI().request("prepare", body: DynamicPrepareInput(googlePlaceID: current.googlePlaceID, day: self.context.day, appleQuery: self.appleQuery), as: DynamicPreparedPlace.self)
        }
    }
    func remove(_ id: UUID) {
        if let item = stops.first(where: {$0.id == id}), let row = browsePlaces.first(where: {$0.id == item.stop.place.prepared.googlePlaceID}) { record(.removed, row.candidate) }
        stops.removeAll{$0.id == id}; planOutput = nil
    }
    func makePlan() {
        perform {
            guard let rec = self.recommendation, let origin = self.origin,!self.stops.isEmpty, rec.context == self.context else {
                throw ContextError.invalid("Pilih rekomendasi, lokasi awal, dan tujuan pada konteks yang sama")
            }
            let base = ContextClock.day(rec.context.day)!
            let inputs = self.stops.map { row -> DynamicStopInput in
                var input = row.stop.input
                if self.simpleLayout { input.avoidRain = self.rainAdjustmentEnabled && input.exposure == .outdoor }
                return input
            }
            let plan = DynamicPlanInput(origin: origin.endpoint, stops: inputs, departure: base.addingTimeInterval(Double(self.departureMinute * 60)),
                                        deadline: base.addingTimeInterval(Double(self.deadlineMinute * 60)), maximumWaitingMinutes: self.waitingMinutes, startStepMinutes: self.grid, policy: self.policy, maxTravelCalls: 64)
            let request = PersonalPlanInput(recommendationID: rec.id, profileRevision: rec.profileRevision,
                                            requiredPlaceIDs: self.stops.filter(\.required).map{$0.stop.place.prepared.googlePlaceID}, plan: plan, considerMoments: self.simpleLayout)
            self.status = "Menghitung jadwal wajib/opsional dan ETA aktual…"
            let began = ContinuousClock.now
            let value = try await ContextAPI(namespace: "recommendation").request("plan", body: request, as: PersonalPlanResult.self)
            self.planID = UUID(); self.planOutput = value
            var sanitized = value
            let bounds = Dictionary(uniqueKeysWithValues: value.result.itinerary.contexts.map{($0.placeID, $0.hours.intervals)})
            sanitized.result.itinerary.contexts = []
            try self.write(PersonalPlanObservation(clientSeconds: ContextLabModel.seconds(began), input: request, operatingBounds: bounds, response: sanitized,
                                                   preparedPlaceIDs: Dictionary(uniqueKeysWithValues: self.stops.map{($0.id.uuidString, $0.stop.place.prepared.googlePlaceID)}), originPlaceID: origin.prepared.googlePlaceID,
                                                   identities: ([origin] + self.stops.map{$0.stop.place}).map{.init(id: $0.prepared.googlePlaceID, googleName: $0.prepared.name, googleAddress: $0.prepared.address, appleName: $0.apple.name, appleAddress: $0.apple.address, separationMeters: $0.apple.distanceFromGoogleMeters, nameSupported: $0.apple.nameSupported ?? false)}), name: "personal-plan-latest.json")
            self.status = value.result.itinerary.visits.isEmpty ? "Rencana belum terverifikasi; periksa tujuan wajib dan bukti" : "Jadwal siap ditinjau; periksa tujuan opsional dan ketidakpastian"
        }
    }
    private func appendObservation(_ row: PersonalObservation)throws {
        if !observationLoaded {
            let path = benchmarkDirectory.appendingPathComponent("recommendations.json")
            if let data = try? Data(contentsOf: path), let old = try? ContextJSON.decoder().decode([PersonalObservation].self, from: data) { observations = old }
            observationLoaded = true
        }
        observations.append(row); try write(observations, name: "recommendations.json")
    }
    private var benchmarkDirectory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PersonalBenchmark") }
    private func write<T: Encodable>(_ value: T, name: String)throws {
        try FileManager.default.createDirectory(at: benchmarkDirectory, withIntermediateDirectories: true)
        try ContextJSON.encoder().encode(value).write(to: benchmarkDirectory.appendingPathComponent(name), options: .atomic)
    }
}
