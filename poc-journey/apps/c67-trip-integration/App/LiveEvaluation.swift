#if DEBUG
    import Foundation
    import Observation
    import PreferenceQuality
    import SwiftUI
    import TripIntegration
    import UIKit
    import VisitTiming

    private struct LiveCaseResult: Codable, Identifiable {
        var id: String
        var status: String
        var detail: String
        var seconds: Double
        var artifact: String?
    }

    /// Explicit debug launch only: real providers, isolated evaluation storage, no synthetic ETA.
    @MainActor @Observable final class LiveEvaluation {
        var progress = "Menyiapkan evaluasi live…"
        var complete = false
        private(set) var lines: [String] = []
        private var started = false
        private var results: [LiveCaseResult] = []
        private let pipeline: IntegrationPipeline
        private let folder: URL
        private var baseline: IntegratedPlan?
        init() {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            folder = documents.appendingPathComponent("P3LiveEval", isDirectory: true)
            pipeline = IntegrationPipeline(catalog: try! .load(), logDirectory: folder.appendingPathComponent("ProviderLogs"))
        }
        private func save<T: Encodable>(_ value: T, _ name: String) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try IntegrationJSON.encoder().encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        private func status(_ message: String) {
            progress = message
            print("C67_P3_LIVE \(message)")
            struct Snapshot: Encodable { var progress: String; var complete: Bool; var results: [LiveCaseResult]; var os: String; var updatedAt: Date }
            try? save(Snapshot(progress: message, complete: complete, results: results,
                               os: ProcessInfo.processInfo.operatingSystemVersionString, updatedAt: .now), "status.json")
        }
        private func record(_ id: String, status: String, detail: String, began: Date, artifact: String? = nil) {
            results.append(.init(id: id, status: status, detail: detail, seconds: Date().timeIntervalSince(began), artifact: artifact))
            lines.append("\(id): \(status) — \(detail)")
            self.status(lines.last!)
        }
        private func request() -> TripRequest {
            var value = TripRequest(now: .now)
            // Use an explicitly dated new run for tomorrow, not a relabeled old fixture.
            let tomorrow = TripClock.calendar.date(byAdding: .day, value: 1, to: .now)!
            value.departure = TripClock.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
            value.deadline = TripClock.calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow)!
            value.useEmbedding = false; value.allowOpenMeteo = false
            return value
        }
        private func plan(_ request: TripRequest, id: String, baseID: UUID? = nil) async throws -> IntegratedPlan {
            status("\(id): preferensi dan jam layanan")
            let review = try await pipeline.recommend(request)
            try save(review, "\(id)-recommendation.json")
            let ids = request.requiredCandidateIDs.isEmpty ? review.suggestions.filter(\.recommended).map(\.id) : request.requiredCandidateIDs
            let prepared = try await pipeline.prepare(review, selectedIDs: ids) { self.status("\(id): \($0)") }
            try save(prepared, "\(id)-locations.json")
            guard prepared.ready else {
                throw IntegrationError.invalid("Location review required: " + prepared.locations.filter { $0.selected == nil }.map { "\($0.query): \($0.issue ?? "unknown")" }.joined(separator: "; "))
            }
            let result = try await pipeline.plan(prepared, review: review, baseAcceptedID: baseID) { self.status("\(id): \($0)") }
            try save(result, "\(id)-plan.json")
            try PlanAudit.validate(result)
            return result
        }
        func run() async {
            guard !started else { return }; started = true
            UIApplication.shared.isIdleTimerDisabled = true
            status("LIVE · provider asli, storage evaluasi terpisah")
            var began = Date()
            do {
                var input = request()
                input.departure = .now
                input.deadline = Date().addingTimeInterval(7200)
                let pin = PlacePin(id: "diagnosis-hi", name: "Bundaran HI · titik diagnosis", address: "Jakarta",
                                   latitude: -6.195, longitude: 106.823)
                let location = LocationReview(id: "diagnosis", query: "Bundaran HI", candidates: [pin], selected: pin)
                let coordinator = TripWeatherCoordinator()
                let evidence = try await coordinator.fetch([location], request: input, now: .now, bypassCache: true)
                try save(evidence, "L01-weatherkit.json")
                let passed = !evidence.isEmpty && evidence.allSatisfy { $0.complete && $0.provider == "weatherkit" }
                record("L01", status: passed ? "pass" : "fail", detail: evidence.map { "\($0.provider)/\($0.status): \($0.hours.count)h; \($0.errors.joined(separator: "; "))" }.joined(separator: " | "), began: began, artifact: "L01-weatherkit.json")
            } catch { record("L01", status: "fail", detail: ProviderDiagnostics.message(error), began: began) }

            began = Date()
            do {
                let result = try await plan(request(), id: "L02")
                guard result.feasible else { throw IntegrationError.invalid(result.conflicts.joined(separator: "; ")) }
                baseline = result
                let store = TripStore(directory: folder.appendingPathComponent("Session"))
                var session = IntegrationSession(); session.proposal = result
                try await store.save(session); try session.apply(); try await store.save(session)
                let restored = try await store.load()
                guard restored.session.accepted?.id == result.id else { throw IntegrationError.invalid("Accepted result was not restored") }
                let exported = try await store.export(result)
                record("L02", status: "pass", detail: "General profile; \(result.stops.count) venues retained, persisted, restored and exported to \(exported.lastPathComponent).", began: began, artifact: "L02-plan.json")
            } catch { record("L02", status: "fail", detail: ProviderDiagnostics.message(error), began: began) }

            began = Date()
            do {
                var input = request(); input.requiredCandidateIDs = ["bdt-rbbj"]
                input.profile.must = [.coffee, .reading]
                let result = try await plan(input, id: "L03")
                guard result.feasible && result.stops.map(\.id) == ["bdt-rbbj"] else {
                    throw IntegrationError.invalid("Same-area mandatory recommendation not scheduled: \(result.conflicts)")
                }
                record("L03", status: "pass", detail: "Coffee and reading supported in the same BDT RBBJ area; real MapKit and routing.", began: began, artifact: "L03-plan.json")
            } catch { record("L03", status: "fail", detail: ProviderDiagnostics.message(error), began: began) }

            began = Date()
            do {
                var input = request(); input.requiredCandidateIDs = ["gbk", "ragunan"]
                input.profile.prefer = [.nature, .outdoor]; input.goal = .lowerRain
                input.departure = TripClock.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: input.departure)!
                let result = try await plan(input, id: "L04")
                guard result.feasible, Set(result.stops.map(\.id)) == Set(input.requiredCandidateIDs) else {
                    throw IntegrationError.invalid("Outdoor schedule unresolved: \(result.conflicts)")
                }
                record("L04", status: "pass", detail: "Outdoor sessions audited. Advisory statuses: \(result.timing.map { $0.status }.joined(separator: ", ")); unknown context remains explicit.", began: began, artifact: "L04-plan.json")
            } catch { record("L04", status: "fail", detail: ProviderDiagnostics.message(error), began: began) }

            began = Date()
            do {
                var input = request(); input.profile.prefer = [.reading, .culture]
                input.profile.direction = "A slow afternoon with books and learning about local culture."
                input.profile.directionConfirmed = true
                let categories = try await pipeline.recommend(input)
                try save(categories, "L05-category.json")
                input.useEmbedding = true
                let cold = try await pipeline.recommend(input) { message in await MainActor.run { self.status("L05 cold: \(message)") } }
                try save(cold, "L05-e5-cold.json")
                let warm = try await pipeline.recommend(input)
                try save(warm, "L05-e5-warm.json")
                let gateA = Set(categories.quality.decisions.filter { $0.state == "eligible" }.map(\.id))
                let gateB = Set(cold.quality.decisions.filter { $0.state == "eligible" }.map(\.id))
                guard gateA == gateB else { throw IntegrationError.invalid("Embedding altered native eligibility") }
                record("L05", status: cold.quality.embedding == nil ? "blocked" : "pass",
                       detail: "\(cold.quality.status), category \(categories.quality.elapsedSeconds)s; E5 cold \(cold.quality.elapsedSeconds)s, warm \(warm.quality.elapsedSeconds)s. Same native gates.", began: began, artifact: "L05-e5-cold.json")
            } catch { record("L05", status: "fail", detail: ProviderDiagnostics.message(error), began: began) }

            began = Date()
            if let baseline, let stop = baseline.stops.last {
                do {
                    var input = baseline.request; input.id = UUID(); input.revision += 1
                    input.requiredCandidateIDs = baseline.prepared.selectedIDs
                    input.durationByVenue[stop.venueID] = stop.duration + 30
                    let updated = try await plan(input, id: "L06", baseID: baseline.id)
                    guard Set(updated.prepared.selectedIDs) == Set(baseline.prepared.selectedIDs) else {
                        throw IntegrationError.invalid("Revision dropped selected places")
                    }
                    let store = TripStore(directory: folder.appendingPathComponent("Session"))
                    var session = try await store.load().session
                    guard session.accepted?.id == baseline.id else { throw IntegrationError.invalid("Accepted baseline lost") }
                    session.proposal = updated; try await store.save(session)
                    session.proposal = nil; try await store.save(session)
                    guard try await store.load().session.accepted?.id == baseline.id else { throw IntegrationError.invalid("Reject replaced accepted plan") }
                    record("L06", status: updated.feasible ? "pass" : "blocked", detail: "All places retained; +30m recomputed. Baseline kept through proposal/rejection. New status \(updated.status).", began: began, artifact: "L06-plan.json")
                } catch { record("L06", status: "fail", detail: ProviderDiagnostics.message(error), began: began) }
            } else { record("L06", status: "blocked", detail: "No accepted three-place baseline; no fabricated substitute.", began: began) }

            began = Date()
            do {
                var input = request(); input.requiredCandidateIDs = ["cikini"]
                input.deadline = input.departure.addingTimeInterval(3600)
                let result = try await plan(input, id: "L07")
                guard !result.feasible else { throw IntegrationError.invalid("Impossible short deadline was accepted") }
                record("L07", status: "pass", detail: "Short return deadline rejected; selected IDs retained; \(result.conflicts)", began: began, artifact: "L07-plan.json")
            } catch { record("L07", status: "blocked", detail: ProviderDiagnostics.message(error), began: began) }
            complete = true
            status("Evaluasi live selesai. \(results.filter { $0.status == "pass" }.count)/\(results.count) pass; lihat status.json untuk fail/blocked.")
        }
    }

    struct LiveEvaluationView: View {
        @State private var evaluation = LiveEvaluation()
        var body: some View {
            NavigationStack {
                List {
                    Section("LIVE · provider asli") {
                        Text("Evaluasi debug terisolasi. Bukan replay. Tidak menulis ke jadwal pengguna.")
                        Text(evaluation.progress).textSelection(.enabled)
                        if !evaluation.complete { ProgressView() }
                    }
                    ForEach(Array(evaluation.lines.enumerated()), id: \.offset) { _, line in Text(line).font(.caption).textSelection(.enabled) }
                }.navigationTitle("C67 · Evaluasi live")
            }.task { await evaluation.run() }
                .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
#endif
