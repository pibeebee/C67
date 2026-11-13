import Foundation

@MainActor final class ContextTravelMemo: ContextTravelProvider {
    struct Key: Hashable { var from: String; var to: String; var departure: Date }
    let base: any ContextTravelProvider
    let limit: Int
    var calls = 0
    var exhausted = false
    var values: [Key: ContextTravelTime] = [:]
    var missing = Set<Key>()
    init(base: any ContextTravelProvider, limit: Int) { self.base = base; self.limit = limit }
    func travel(from: String, to: String, departure: Date) async throws -> ContextTravelTime? {
        try Task.checkCancellation(); let key = Key(from: from, to: to, departure: departure)
        if let value = values[key] { return value }; if missing.contains(key) { return nil }
        guard calls < limit else { exhausted = true; return nil }
        calls += 1
        let value = try await base.travel(from: from, to: to, departure: departure)
        if let value { values[key] = value } else { missing.insert(key) }
        return value
    }
}

/// Bounded optional-subset search around the unchanged required-stop planner.
/// Every actual ETA call shares one per-operation budget and exact-departure cache.
@MainActor public enum OptionalItineraryPlanner {
    public static func plan(_ input: ContextPlanRequest, requiredIDs: Set<String>, provider: any ContextTravelProvider, now: Date = .now) async throws -> ContextItineraryResult {
        guard (1 ... 6).contains(input.stops.count), requiredIDs.isSubset(of: Set(input.stops.map{$0.request.placeID})),
              Set(input.stops.map{$0.request.placeID}).count == input.stops.count, (1 ... 512).contains(input.maxTravelCalls) else {
            throw ContextError.invalid("Subset wajib/opsional tidak valid")
        }
        if requiredIDs.count == input.stops.count { return try await ContextItineraryPlanner.plan(input, provider: provider, now: now) }
        let contexts = try input.stops.map{try VisitContextEngine.evaluate(snapshot: $0.snapshot, request: $0.request, weather: $0.weather, now: now)}
        let eligible = input.stops.indices.filter{ !contexts[$0].options.isEmpty}
        if requiredIDs.contains(where: {id in !eligible.contains{input.stops[$0].request.placeID == id}}) {
            var blocked = try await ContextItineraryPlanner.plan(input, provider: provider, now: now)
            blocked.warnings.append("Tujuan wajib kekurangan jendela/bukti; tidak dihapus dan jam tidak dibuat-buat")
            return blocked
        }
        let stable = input.order == .fixed ? eligible : eligible.sorted{input.stops[$0].request.placeID < input.stops[$1].request.placeID}
        var subsets: [[Int]] = []
        if !stable.isEmpty {
            for mask in 1 ..< (1 << stable.count) {
                let rows = stable.indices.filter{mask & (1 << $0) != 0}.map{stable[$0]}
                if requiredIDs.isSubset(of: Set(rows.map{input.stops[$0].request.placeID})) { subsets.append(rows) }
            }
        }
        subsets.sort { a, b in a.count != b.count ? a.count > b.count : a.map{input.stops[$0].request.placeID}.lexicographicallyPrecedes(b.map{input.stops[$0].request.placeID}) }
        let mandatory = stable.filter{requiredIDs.contains(input.stops[$0].request.placeID)}
        if !mandatory.isEmpty, let index = subsets.firstIndex(of: mandatory) { subsets.remove(at: index); subsets.insert(mandatory, at: 0) }
        let memo = ContextTravelMemo(base: provider, limit: input.maxTravelCalls)
        var best: ContextItineraryResult?, last: ContextItineraryResult?, attempted = 0
        func better(_ a: ContextItineraryResult, _ b: ContextItineraryResult) -> Bool {
            if a.penaltyByPriority != b.penaltyByPriority { return a.penaltyByPriority.lexicographicallyPrecedes(b.penaltyByPriority) }
            if a.visits.count != b.visits.count { return a.visits.count > b.visits.count }
            return (a.finish ?? .distantFuture) < (b.finish ?? .distantFuture)
        }
        for subset in subsets {
            if memo.exhausted || attempted >= 12 { break }
            var request = input; request.stops = subset.map{input.stops[$0]}; request.maxTravelCalls = 512
            let result = try await ContextItineraryPlanner.plan(request, provider: memo, now: now)
            attempted += 1; last = result
            if !result.visits.isEmpty && requiredIDs.isSubset(of: Set(result.visits.map(\.placeID))), best.map({better(result, $0)}) ?? true { best = result }
        }
        var result: ContextItineraryResult
        if let chosen = best ?? last { result = chosen }
        else { result = try await ContextItineraryPlanner.plan(input, provider: memo, now: now) }
        result.contexts = contexts; result.travelCalls = memo.calls
        result.searchTruncated = result.searchTruncated || memo.exhausted || attempted < subsets.count
        result.warnings.removeAll{$0.hasPrefix("All requested stops retained")}
        result.warnings.append("Semua tujuan wajib dipertahankan; tujuan opsional dipilih dengan pencarian subset terbatas")
        result.warnings.append("Kebijakan eksperimen: utamakan penalti preferensi lebih rendah, lalu jumlah opsional, lalu waktu selesai; belum tervalidasi manusia")
        if memo.exhausted { result.warnings.append("Anggaran ETA gabungan tercapai; penghilangan opsional bukan bukti global tidak mungkin") }
        return result
    }
}
