import Foundation

public enum CandidateSelector {
    // Model IDs must be valid before native category validation can refine the choice.
    // Category/name tags are transparent heuristics, not verified historical claims.
    public static func select(places: [Place], proposed: [Recommendation], theme: Theme, count: Int) throws -> [Recommendation] {
        guard (1 ... 6).contains(count) else { throw PlanningError.invalidInput }
        let ids = proposed.map(\.placeID)
        let catalog = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(ids).count == ids.count, ids.count <= 6, ids.allSatisfy({ catalog[$0] != nil }) else { throw PlanningError.invalidIDs }
        guard !places.isEmpty, !proposed.isEmpty else { throw PlanningError.noPlaces }
        var selected = Array(proposed.filter { theme == .mixed || catalog[$0.placeID]!.themes.contains(theme) }.prefix(count))
        let eligible = places.filter { theme == .mixed || $0.themes.contains(theme) }
        for place in eligible where selected.count < count && !selected.contains(where: { $0.placeID == place.id }) {
            selected.append(.init(place.id, reason: "Native category match: \(place.category). Added from retrieved results; specific historical facts are unverified."))
        }
        if theme == .mixed {
            var pool = proposed
            for place in eligible where !pool.contains(where: { $0.placeID == place.id }) {
                pool.append(.init(place.id, reason: "Native variety match: \(place.category), from retrieved results."))
            }
            selected = []
            var seen: Set<Theme> = []
            while selected.count < count && !pool.isEmpty {
                let best = pool.indices.max { a, b in
                    let first = catalog[pool[a].placeID]!.themes.subtracting(seen).count
                    let second = catalog[pool[b].placeID]!.themes.subtracting(seen).count
                    return first == second ? a > b : first < second
                }!
                let choice = pool.remove(at: best)
                selected.append(choice)
                seen.formUnion(catalog[choice.placeID]!.themes)
            }
        }
        guard !selected.isEmpty else { throw PlanningError.noPlaces }
        return selected
    }
}
