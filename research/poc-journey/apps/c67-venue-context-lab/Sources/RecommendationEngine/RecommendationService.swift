import Foundation
import DynamicTripContracts
import PlaceContextEngine
import PlannerEngine
import RecommendationContracts
import VenueDiscovery

@MainActor public final class RecommendationService {
    private struct Pending {
        var input: RecommendationStart
        var prepared: PreparedRecommendation
        var began: ContinuousClock.Instant
        var browse: Browse? = nil
        var consumed = false
    }
    private struct Pool {
        var query: String; var categoryHints: [String]; var fetched = false; var queue: [String] = []
        var needsPage: Bool { queue.isEmpty && !fetched }
    }
    private struct Browse {
        var pools: [Pool]; var nextPool = 0; var examined = Set<String>(); var issued = Set<String>()
        var carry: [PersonalCandidate] = []; var rounds = 0
        var hasMore: Bool { rounds < 8 && (!carry.isEmpty || pools.contains{ !$0.queue.isEmpty || $0.needsPage }) }
        mutating func takeID() -> String? {
            for _ in pools.indices {
                let i = nextPool; nextPool = (nextPool + 1) % pools.count
                while !pools[i].queue.isEmpty {
                    let id = pools[i].queue.removeFirst()
                    if examined.insert(id).inserted { return id }
                }
            }
            return nil
        }
    }
    private struct Proof {
        var result: PersonalRecommendationResult; var profile: PersonalProfile; var browse: Browse?
        var issued: Set<String> { browse?.issued ?? Set(result.places.map(\.id)) }
    }
    private let directory: VenueDirectory
    private let apple: LabAppleREST
    private let llm: any RecommendationLLM
    private var pending: [UUID: Pending] = [:]
    private var proofs: [UUID: Proof] = [:]
    private var busy = false
    public init(directory: VenueDirectory, apple: LabAppleREST, llm: any RecommendationLLM) {
        self.directory = directory; self.apple = apple; self.llm = llm
    }
    private func begin() throws {
        guard !busy else { throw ContextError.invalid("Rekomendasi lain masih berjalan") }
        pending = pending.filter{$0.value.prepared.expiresAt > Date()}; proofs = proofs.filter{$0.value.result.validUntil > Date()}
        guard pending.count < 20, proofs.count < 30 else { throw ContextError.invalid("Kapasitas sesi rekomendasi tercapai") }
        busy = true
    }
    private static func seconds(_ clock: ContinuousClock.Instant) -> Double {
        let c = clock.duration(to: .now).components; return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
    public func start(_ input: RecommendationStart) async throws -> PreparedRecommendation {
        try begin(); defer{busy = false}
        try input.profile.validate(); try input.context.validate()
        let began = ContinuousClock.now, started = Date()
        let interests = input.profile.interests.isEmpty ? [.culture, .coffee, .outdoors] : input.profile.interests
        let pools = interests.map { interest in
            Pool(query: interest.searchTerm + " " + input.context.area,
                 categoryHints: CandidatePolicy.categoryHints(interest))
        }
        var browse = Browse(pools: pools)
        if let parent = input.continuationID {
            guard let proof = proofs[parent], proof.result.context == input.context,
                  proof.profile.interests == input.profile.interests, proof.profile.pace == input.profile.pace,
                  let previous = proof.browse else { throw ContextError.invalid("Pilihan lama tetap tersimpan di layar, tetapi sesi pencarian sudah berakhir. Mulai pencarian baru untuk melanjutkan.") }
            browse = previous
        }
        var candidates = browse.carry.filter { candidate in
            candidate.evidence.allSatisfy { started.timeIntervalSince($0.checkedAt) < 900 }
        }
        browse.carry = []
        var warnings: [String] = []
        if browse.rounds < 8 {
            for i in browse.pools.indices where browse.pools[i].needsPage {
                try Task.checkCancellation()
                if Self.seconds(began) > 6 { warnings.append("Sebagian pencarian ditunda karena batas waktu"); break }
                let pool = browse.pools[i]
                let places = try await directory.search(pool.query, limit: 9, categoryHints: pool.categoryHints, independentOnly: true, area: input.context.area)
                browse.pools[i].fetched = true
                browse.pools[i].queue = places.compactMap(\.id).filter { !browse.examined.contains($0) }
            }
            let detailLimit = 9 - candidates.count
            for _ in 0 ..< detailLimit {
                try Task.checkCancellation()
                if Self.seconds(began) > 10 { warnings.append("Detail kandidat dibatasi waktu pencarian"); break }
                guard let id = browse.takeID() else { break }
                let snapshot = try directory.snapshot(id: id, day: input.context.day)
                let candidate = CandidatePolicy.make(snapshot, context: input.context)
                if ["closed", "outside_window"].contains(candidate.hoursState) || snapshot.publicAccess == "contradicted" { continue }
                if !input.profile.interests.isEmpty && Set(candidate.categories).isDisjoint(with: input.profile.interests) { continue }
                candidates.append(candidate)
            }
            browse.rounds += 1
        }
        if candidates.isEmpty, let parent = input.continuationID {
            // No cards were produced; advance the search without making an unjudged recommendation.
            proofs[parent]?.browse = browse
            return .init(id: parent, profileRevision: input.profile.revision, context: input.context,
                         expiresAt: started.addingTimeInterval(19), candidates: [], acquisitionSeconds: Self.seconds(began),
                         weatherSummary: "", warnings: warnings, hasMore: browse.hasMore)
        }
        guard !candidates.isEmpty else { throw ContextError.invalid("Belum ada kandidat dengan dukungan minat/jam yang memadai; coba area atau waktu lain") }
        var weather = "Cuaca area belum tersedia; tidak diasumsikan cerah"
        if Self.seconds(began) < 8 {
            do {
                if let pin = try await LabRESTSearch(apple: apple).search(query: input.context.area).first {
                    let day = ContextClock.day(input.context.day)!, date = day.addingTimeInterval(Double(input.context.departureMinute * 60))
                    let hour = ContextClock.calendar.dateInterval(of: .hour, for: date)!.start
                    let value = try await LabRESTWeather(apple: apple).fetch(pin: pin, memberIDs: ["recommendation-area"], start: hour,
                                                                             end: day.addingTimeInterval(Double(input.context.deadlineMinute * 60)), allowFallback: false, now: Date())
                    if value.complete, let maximum = value.hours.map(\.rainChance).max(), let credit = value.credit {
                        weather = "WeatherKit area \(pin.name): maksimum peluang presipitasi per jam \(Int(maximum * 100))%; bukan prakiraan terverifikasi tiap tempat. \(credit.name) \(credit.legalURL.absoluteString)"
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { warnings.append("Akuisisi cuaca area gagal; cuaca tetap belum diketahui") }
        }
        let id = UUID()
        let prepared = PreparedRecommendation(id: id, profileRevision: input.profile.revision, context: input.context,
                                              expiresAt: started.addingTimeInterval(19), candidates: candidates, acquisitionSeconds: Self.seconds(began), weatherSummary: weather,
                                              warnings: warnings + ["Pilot Jakarta; maksimal 9 kandidat dinilai, 6 ditampilkan; cakupan bukan seluruh tempat",
                                                                    "Pace belum diubah menjadi batas menunggu atau durasi tersembunyi", weather], hasMore: browse.hasMore)
        guard prepared.expiresAt.timeIntervalSinceNow > 0.5 else { throw ContextError.invalid("Akuisisi melewati anggaran rekomendasi; coba lagi") }
        pending[id] = Pending(input: input, prepared: prepared, began: began, browse: browse)
        return prepared
    }
    public func startFixture(_ input: RecommendationStart, scenario: String) throws -> PreparedRecommendation {
        try begin(); defer{busy = false}; try input.profile.validate(); try input.context.validate()
        guard ["balanced", "unknown_hours", "diversity", "weather"].contains(scenario) else { throw ContextError.invalid("Skenario tetap tidak dikenal") }
        let clock = ContinuousClock.now, day = ContextClock.day(input.context.day)!
        var candidates: [PersonalCandidate] = []
        for interest in [PersonalInterest.coffee, .culture, .outdoors] {
            for index in 1 ... 2 {
                let id = "fixture-\(interest.rawValue)-\(index)", unknown = scenario == "unknown_hours" && index == 2
                let type = interest == .coffee ? (index == 1 ? "coffee_shop" : "cafe") : interest == .culture ? (index == 1 ? "museum" : "historical_landmark") : (index == 1 ? "park" : "botanical_garden")
                candidates.append(.init(id: id, name: "SIMULASI \(interest.label) \(index)", address: "Data sintetis, bukan lokasi nyata", categories: [interest], facetKeys: [interest.rawValue + ":" + type],
                                        description: "Synthetic \(type), no real venue claim", hoursState: unknown ? "unknown" : "available",
                                        hours: unknown ? [] : [OperatingInterval(start: day, end: day.addingTimeInterval(86400))],
                                        evidence: [.init(id: id + ":category", kind: "category", text: type, source: "synthetic-v1", checkedAt: Date()),
                                                   .init(id: id + ":hours", kind: "hours", text: unknown ? "unknown" : "available", source: "synthetic-v1", checkedAt: Date())],
                                        unknowns: unknown ? ["Jam sintetis sengaja dihilangkan"] : [], evidenceURL: nil, exposure: interest == .outdoors ? .outdoor : .unknown))
            }
        }
        if !input.profile.interests.isEmpty { candidates = candidates.filter{ !Set($0.categories).isDisjoint(with: input.profile.interests)} }
        let prepared = PreparedRecommendation(id: UUID(), profileRevision: input.profile.revision, context: input.context, expiresAt: Date().addingTimeInterval(19),
                                              candidates: candidates, acquisitionSeconds: Self.seconds(clock), weatherSummary: scenario == "weather" ? "SYNTHETIC area rain chance 90%; not venue-specific" : "Synthetic weather unavailable",
                                              warnings: ["FIXTURE INPUT: synthetic places/hours; LLM invocation remains real; not a live place benchmark"])
        pending[prepared.id] = Pending(input: input, prepared: prepared, began: clock); return prepared
    }
    public func complete(_ input: RecommendationComplete) async throws -> PersonalRecommendationResult {
        try begin(); defer{busy = false}
        guard var job = pending[input.id],!job.consumed, job.prepared.expiresAt > Date(), input.profileRevision == job.input.profile.revision,
              Set(input.scores.map(\.id)) == Set(job.prepared.candidates.map(\.id)), Set(input.scores.map(\.id)).count == input.scores.count,
              input.embeddingSeconds.isFinite, (0 ... 20).contains(input.embeddingSeconds), input.embeddingStatus.count <= 100,
              input.scores.allSatisfy({$0.semanticScore.map{$0.isFinite && (-1 ... 1).contains($0)} ?? true}) else {
            throw ContextError.invalid("Sesi rekomendasi kedaluwarsa, berubah atau skor lokal tidak sah")
        }
        job.consumed = true; pending[input.id] = job
        let result = try await llm.review(profile: job.input.profile, context: job.input.context, candidates: job.prepared.candidates,
                                          scores: input.scores, weather: job.prepared.weatherSummary, timeout: min(17, job.prepared.expiresAt.timeIntervalSinceNow))
        try Task.checkCancellation()
        guard Date() < job.prepared.expiresAt else { throw ContextError.invalid("Rekomendasi melewati deadline; hasil terlambat tidak diterapkan") }
        let places = try CandidatePolicy.validateAndDiversify(result.decision, candidates: job.prepared.candidates, profile: job.input.profile)
        let metrics = RecommendationMetrics(acquisitionSeconds: job.prepared.acquisitionSeconds, embeddingSeconds: input.embeddingSeconds,
                                            llmSeconds: result.seconds, serverElapsedSeconds: Self.seconds(job.began), llmModel: result.model, llmProvider: result.provider,
                                            promptTokens: result.promptTokens, completionTokens: result.completionTokens, costUSD: result.costUSD, embeddingStatus: input.embeddingStatus)
        var warnings = job.prepared.warnings
        let represented = Set(places.flatMap{$0.candidate.categories})
        let missing = job.input.profile.interests.filter{ !represented.contains($0)}
        if !missing.isEmpty { warnings.append("Minat belum terwakili dengan bukti yang tersedia: " + missing.map(\.label).joined(separator: ", ")) }
        let shown = Set(places.map(\.id))
        job.browse?.carry = job.prepared.candidates.filter{ !shown.contains($0.id) }
        job.browse?.issued.formUnion(shown)
        let value = PersonalRecommendationResult(id: input.id, profileRevision: input.profileRevision, context: job.input.context,
                                                 validUntil: Date().addingTimeInterval(900), places: places, metrics: metrics, warnings: warnings, judgments: result.decision.items, hasMore: job.browse?.hasMore)
        proofs[input.id] = Proof(result: value, profile: job.input.profile, browse: job.browse); pending.removeValue(forKey: input.id); return value
    }
    public func authorize(recommendationID: UUID, profileRevision: Int, placeIDs: [String], context: PersonalTripContext) throws {
        guard let proof = proofs[recommendationID], proof.result.validUntil > Date(), proof.result.profileRevision == profileRevision,
              proof.result.context == context,!placeIDs.isEmpty, Set(placeIDs).count == placeIDs.count,
              Set(placeIDs).isSubset(of: proof.issued),!placeIDs.contains(where: {$0.hasPrefix("fixture-")}) else {
            throw ContextError.invalid("Pilihan harus berasal dari rekomendasi LLM live yang masih berlaku pada konteks yang sama")
        }
    }
    @discardableResult public func authorizePlan(recommendationID: UUID, profileRevision: Int, placeIDs: [String], departure: Date, deadline: Date) throws -> PersonalProfile {
        guard let proof = proofs[recommendationID], let day = ContextClock.day(proof.result.context.day),
              abs(departure.timeIntervalSince(day) - Double(proof.result.context.departureMinute * 60)) < 0.001,
              abs(deadline.timeIntervalSince(day) - Double(proof.result.context.deadlineMinute * 60)) < 0.001 else {
            throw ContextError.invalid("Tanggal/waktu berubah; buat rekomendasi baru sebelum itinerary")
        }
        try authorize(recommendationID: recommendationID, profileRevision: profileRevision, placeIDs: placeIDs, context: proof.result.context)
        return proof.profile
    }
    public func chooseItinerary(_ choices: DynamicPlanChoices, profile: PersonalProfile) async throws -> (DynamicPlanResponse, MomentPlanReview?) {
        try await PersonalMomentReview.select(choices, profile: profile, llm: llm as? OpenRouterClient)
    }
    public var counters: [String: Int] { ["appleHTTPCalls": apple.budget.calls, "etaCells": apple.budget.cells, "llmCalls": (llm as? OpenRouterClient)?.calls ?? 0] }
}
