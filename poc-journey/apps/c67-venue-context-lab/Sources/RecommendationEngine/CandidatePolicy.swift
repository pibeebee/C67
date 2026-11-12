import Foundation
import PlaceContextEngine
import RecommendationContracts

public enum CandidatePolicy {
    private static let types: [PersonalInterest: Set<String>] = [
        .coffee: ["cafe", "coffee_shop"], .reading: ["library", "book_store"],
        .food: ["restaurant", "food", "bakery", "meal_takeaway", "indonesian_restaurant"],
        .outdoors: ["park", "national_park", "botanical_garden", "garden", "zoo"],
        .culture: ["museum", "historical_landmark", "cultural_center", "historical_place"],
        .shopping: ["shopping_mall", "market", "department_store"],
        .entertainment: ["amusement_park", "movie_theater", "aquarium", "tourist_attraction"],
        .architecture: ["historical_landmark", "historical_place", "cultural_landmark"],
        .arts: ["art_gallery", "art_studio", "art_museum", "performing_arts_theater"]]
    public static func categoryHints(_ interest: PersonalInterest) -> [String] { Array(types[interest] ?? []).sorted() }
    public static func make(_ snapshot: PlaceSnapshot, context: PersonalTripContext) -> PersonalCandidate {
        let p = snapshot.place, id = p.id!, name = p.displayName?.text ?? "Nama tidak tersedia"
        let supplied = Set((p.types ?? []) + (p.primaryType.map{[$0]} ?? []))
        let categories = PersonalInterest.allCases.filter {
            !(types[$0] ?? []).isDisjoint(with: supplied)
        }
        let facets = categories.flatMap { interest in supplied.intersection(types[interest] ?? []).sorted().map { interest.rawValue + ":" + $0 } }
        let hours = VenueHoursResolver.resolve(snapshot, day: context.day, allowRegular: true, now: snapshot.fetchedAt)
        let midnight = ContextClock.day(context.day)!
        let start = midnight.addingTimeInterval(Double(context.departureMinute * 60)), end = midnight.addingTimeInterval(Double(context.deadlineMinute * 60))
        let overlap = hours.intervals.contains{min($0.end, end).timeIntervalSince(max($0.start, start)) >= 15 * 60}
        let state = hours.state == "available" && !overlap ? "outside_window" : hours.state
        var unknowns = ["Penerimaan terakhir, tiket/reservasi, akses dan antrean belum diverifikasi",
                        "Kecocokan gabungan dan durasi penuh baru diperiksa setelah pemilihan"]
        unknowns.append(contentsOf: hours.warnings)
        if snapshot.publicAccess != "supported" { unknowns.append("Akses umum belum terkonfirmasi.") }
        if state != "available" { unknowns.append("Jam kunjungan belum terverifikasi: \(state)") }
        if categories.isEmpty { unknowns.append("Kategori minat belum dapat dibuktikan dari tipe provider") }
        let categorySource = snapshot.source
        let categoryText = "Kategori katalog: " + supplied.sorted().joined(separator: ", ")
        let evidence = [
            CandidateEvidence(id: id + ":category", kind: "category", text: categoryText, source: categorySource,
                              checkedAt: snapshot.fetchedAt),
            CandidateEvidence(id: id + ":hours", kind: "hours", text: "\(hours.source): \(state); hanya pemeriksaan irisan >=15 menit", source: hours.source, checkedAt: snapshot.fetchedAt)]
        let outdoor = !supplied.intersection(types[.outdoors] ?? []).isEmpty
        let activity = snapshot.activity.map { " Source excerpt: " + $0 } ?? ""
        return .init(id: id, name: name, address: p.formattedAddress ?? "Alamat belum diketahui", categories: categories, facetKeys: facets,
                     description: "\(name). Provider types: \(supplied.sorted().joined(separator: ", ")). Mapped interest categories: \(categories.map(\.rawValue).joined(separator: ", ")).\(activity)",
                     hoursState: state, hours: hours.intervals, evidence: evidence, unknowns: unknowns, evidenceURL: p.evidenceURI, exposure: outdoor ? .outdoor : .unknown)
    }
    public static func allowedReasons(_ candidate: PersonalCandidate, profile: PersonalProfile) -> [String] {
        var result: [String] = []
        if !Set(candidate.categories).isDisjoint(with: profile.interests) { result.append("interest_match") }
        if candidate.hoursState == "available" { result.append("hours_overlap") }
        else if candidate.hoursState != "closed" && candidate.hoursState != "outside_window" { result.append("hours_unknown") }
        return result
    }
    public static func validateAndDiversify(_ decision: LLMRecommendation, candidates: [PersonalCandidate], profile: PersonalProfile, limit: Int = 6) throws -> [PersonalRecommendedPlace] {
        guard !candidates.isEmpty, candidates.count <= 12, Set(candidates.map(\.id)).count == candidates.count,
              decision.items.count == candidates.count, Set(decision.items.map(\.id)) == Set(candidates.map(\.id)),
              Set(decision.items.map(\.id)).count == decision.items.count else {
            throw ContextError.invalid("LLM harus menilai tepat setiap ID kandidat yang disediakan; tidak ada fallback")
        }
        let byID = Dictionary(uniqueKeysWithValues: candidates.map{($0.id, $0)})
        var ranked: [PersonalRecommendedPlace] = []
        for (rank, item) in decision.items.enumerated() {
            let c = byID[item.id]!, allowed = Set(allowedReasons(c, profile: profile))
            guard !item.reasonCodes.isEmpty, item.reasonCodes.count <= 3, Set(item.reasonCodes).count == item.reasonCodes.count,
                  Set(item.reasonCodes).isSubset(of: allowed),!item.evidenceIDs.isEmpty,
                  Set(item.evidenceIDs).isSubset(of: Set(c.evidence.map(\.id))) else {
                throw ContextError.invalid("Alasan LLM tidak valid untuk \(c.id): \(item.reasonCodes.joined(separator: ",")); diizinkan \(allowed.sorted().joined(separator: ",")); tanpa fallback")
            }
            for code in item.reasonCodes {
                let required = c.id + (code == "interest_match" ? ":category" : ":hours")
                guard item.evidenceIDs.contains(required) else { throw ContextError.invalid("Alasan LLM tidak memiliki referensi bukti yang sesuai") }
            }
            let reasons = item.reasonCodes.map { code in
                code == "interest_match" ? "Sesuai minat eksplisit: " + c.categories.filter{profile.interests.contains($0)}.map(\.label).joined(separator: ", ") :
                    code == "hours_overlap" ? "Jam provider beririsan dengan waktu perjalanan; belum menjamin durasi dan rute gabungan" :
                    "Jam kunjungan belum pasti; pilihan ini bersyarat"
            }
            ranked.append(.init(candidate: c, reasons: reasons, llmRank: rank + 1))
        }
        // Every output has a successful LLM judgment. Code only enforces list diversity, never fabricates a candidate.
        var result: [PersonalRecommendedPlace] = []
        let interests = PersonalInterest.allCases.filter{profile.interests.contains($0)}
        // Allocate rounds by explicit interests; LLM/learned affinity chooses inside each round.
        // A high learned coffee affinity must not consume every remaining slot across interests.
        while result.count < min(limit, ranked.count) {
            let previous = result.count
            for interest in interests where result.count < min(limit, ranked.count) {
                if let next = ranked.first(where: {row in row.candidate.categories.contains(interest) && !result.contains{$0.id == row.id}}) {
                    result.append(next)
                }
            }
            if result.count == previous { break }
        }
        for row in ranked where result.count < min(limit, ranked.count) && !result.contains(where: {$0.id == row.id}) { result.append(row) }
        return result
    }
}
