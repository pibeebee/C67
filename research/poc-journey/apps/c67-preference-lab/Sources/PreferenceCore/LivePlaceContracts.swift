import Foundation

public struct LiveNeed: Codable, Sendable { public var value: String; public var must: Bool }
public struct LivePlaceRequest: Codable, Sendable {
    public var requestID: UUID
    public var revision: Int
    public var interests: [String]
    public var needs: [String: LiveNeed]
    public var area: String
    public var visitAt: String?
    public var durationMinutes: Int?
    public var pageTokens: [String: String]?
    public init(state: PreferenceState, area: String, visitAt: Date? = nil, durationMinutes: Int? = nil, pageTokens: [String: String]? = nil) {
        requestID = UUID(); revision = state.revision; interests = state.interests
        needs = state.values.mapValues { .init(value: $0.value, must: $0.must) }
        self.area = area; self.visitAt = visitAt.map { ISO8601DateFormatter().string(from: $0) }
        self.durationMinutes = durationMinutes; self.pageTokens = pageTokens
    }
}
public struct LivePlaceCheck: Codable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var status: String
    public var text: String
    public var field: String
    public var sourceURL: String
    public var checkedAt: String
    public var must: Bool
    public var scope: String?
    public var statusLabel: String {
        if scope == "other_activity" { return "Dinilai pada kegiatan lain" }
        if scope == "trip" { return "Berlaku untuk rangkaian perjalanan" }
        return status == "supported" ? "Didukung data" : status == "contradicted" ? "Bertentangan" : "Belum diketahui"
    }
}
public struct LivePlace: Codable, Sendable, Identifiable {
    public struct Attribution: Codable, Sendable { public var provider: String?; public var providerUri: String? }
    public var id: String
    public var name: String
    public var address: String
    public var googleMapsURL: String?
    public var types: [String]
    public var searchGroups: [String]
    public var providerPosition: Int
    public var checks: [LivePlaceCheck]
    public var status: String
    public var requiredStatus: String
    public var attributions: [Attribution]
    public var statusLabel: String { status == "supported" ? "Kegiatan ini didukung data" : status == "conflict" ? "Ada kebutuhan yang bertentangan" : "Sebagian kebutuhan belum diketahui" }
}
public struct LivePlaceResponse: Codable, Sendable {
    public struct Search: Codable, Identifiable, Sendable {
        public var id: String; public var label: String; public var query: String; public var count: Int; public var error: String?
    }
    public var requestID: UUID
    public var revision: Int
    public var places: [LivePlace]
    public var searches: [Search]
    public var pageTokens: [String: String]
    public var warnings: [String]
    public var notice: String
    public var seconds: Double
    public var providerCalls: Int
    public var checkedAt: String
    public mutating func append(_ page: LivePlaceResponse) {
        var seen = Set(places.map(\.id))
        places.append(contentsOf: page.places.filter { seen.insert($0.id).inserted })
        pageTokens = page.pageTokens; warnings = Array(Set(warnings + page.warnings)).sorted()
        seconds += page.seconds; providerCalls += page.providerCalls
    }
}
extension PreferenceEngine {
    /// Intent clarification uses authored activity meaning, never fictitious venue facts.
    public static func intentQuestions(_ questions: [Clarification], state: PreferenceState) -> [Clarification] {
        guard state.asked.count + state.skipped.count < 2 else { return [] }
        return questions.filter { q in
            state.values[q.axis] == nil && !state.skipped.contains(q.id) && !state.asked.contains(q.id)
                && (q.requiresAllInterests ? Set(q.interests).isSubset(of: Set(state.interests)) : !Set(q.interests).isDisjoint(with: state.interests))
        }
    }
}
