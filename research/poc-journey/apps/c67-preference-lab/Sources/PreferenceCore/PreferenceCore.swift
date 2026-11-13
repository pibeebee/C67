import Foundation

public struct Experience: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var detail: String
    public var english: String
    public var interests: [String]
    public var attributes: [String: String]
    public var provenance: String
}
public struct Choice: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var value: String
    public var label: String
    public var summary: String
    public var english: String
}
public struct Clarification: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var axis: String
    public var text: String
    public var interests: [String]
    public var requiresAllInterests: Bool
    public var choices: [Choice]
}
public struct PreferenceValue: Codable, Sendable, Equatable {
    public var value: String
    public var must: Bool
    public var eventID: UUID
    public init(value: String, must: Bool = false, eventID: UUID = UUID()) {
        self.value = value; self.must = must; self.eventID = eventID
    }
}
public struct PreferenceState: Codable, Sendable, Equatable {
    public var version = 1
    public var revision = 0
    public var interests: [String] = []
    public var pace = "balanced"
    public var reusable: [String: PreferenceValue] = [:]
    public var trip: [String: PreferenceValue] = [:]
    public var skipped: [String] = []
    public var asked: [String] = []
    public var savedIDs: [String] = []
    public var aiConsent = false
    public init() {}
    public var values: [String: PreferenceValue] { reusable.merging(trip) { _, new in new } }
    public mutating func answer(_ question: Clarification, choiceID: String, must: Bool? = nil) throws {
        guard let choice = question.choices.first(where: { $0.id == choiceID }) else { throw LabError.invalid("Pilihan tidak dikenal") }
        let strength = must ?? values[question.axis]?.must ?? false
        trip[question.axis] = .init(value: choice.value, must: strength)
        if !asked.contains(question.id) { asked.append(question.id) }
        revision += 1
    }
    public mutating func skip(_ id: String) {
        if !skipped.contains(id) { skipped.append(id) }; revision += 1
    }
    public mutating func newTrip() { trip = [:]; asked = []; skipped = []; savedIDs = []; revision += 1 }
    public mutating func remember(_ axis: String) {
        guard let v = trip.removeValue(forKey: axis) else { return }; reusable[axis] = v; revision += 1
    }
}
public enum LabError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let s): s } }
}
public struct RankedExperience: Identifiable, Sendable {
    public var experience: Experience
    public var score: Int
    public var unknown: [String]
    public var contradicted: [String]
    public var id: String { experience.id }
}
public enum PreferenceEngine {
    public static let interests: [(String, String)] = [
        ("coffee", "Kopi"), ("reading", "Membaca"), ("culture", "Museum & budaya"),
        ("architecture", "Arsitektur"), ("outdoors", "Alam & taman"), ("food", "Kuliner"),
        ("shopping", "Belanja"), ("arts", "Seni"), ("entertainment", "Hiburan")]
    public static func rank(_ items: [Experience], state: PreferenceState,
                            semantic: [String: Double] = [:]) -> [RankedExperience] {
        let chosen = Set(state.interests)
        return items.enumerated().compactMap { index, item -> (Int, RankedExperience)? in
            let overlap = chosen.intersection(item.interests).count
            guard chosen.isEmpty || overlap > 0 else { return nil }
            var score = overlap, unknown: [String] = [], contradicted: [String] = []
            for (axis, need) in state.values {
                guard let actual = item.attributes[axis] else { unknown.append(axis); continue }
                if actual == need.value { score += 8 }
                else { if need.must { return nil }; score -= 8; contradicted.append(axis) }
            }
            return (index, .init(experience: item, score: score, unknown: unknown.sorted(), contradicted: contradicted.sorted()))
        }.sorted { lhs, rhs in
            if lhs.1.score != rhs.1.score { return lhs.1.score > rhs.1.score }
            let l = semantic[lhs.1.id] ?? 0, r = semantic[rhs.1.id] ?? 0
            return l != r ? l > r : lhs.0 < rhs.0
        }.map(\.1)
    }
    /// Ask only when answer branches alter the top three on our owned example facts.
    /// No model-reported confidence is treated as a probability.
    public static func eligible(_ questions: [Clarification], items: [Experience], state: PreferenceState,
                                enforceCap: Bool = true) -> [Clarification] {
        guard !enforceCap || state.asked.count + state.skipped.count < 2 else { return [] }
        let relevant = rank(items, state: state).map(\.experience)
        return questions.filter { q in
            guard state.values[q.axis] == nil, !state.skipped.contains(q.id), !state.asked.contains(q.id),
                  (q.requiresAllInterests ? Set(q.interests).isSubset(of: Set(state.interests)) : !Set(q.interests).isDisjoint(with: state.interests)) else { return false }
            let known = Set(relevant.compactMap { $0.attributes[q.axis] })
            guard known.count >= 2 else { return false }
            let branches = q.choices.map { c -> String in
                var s = state; s.trip[q.axis] = .init(value: c.value)
                return rank(items, state: s).prefix(3).map(\.id).joined(separator: ",")
            }
            return Set(branches).count >= 2
        }
    }
    public static func english(_ state: PreferenceState, questions: [Clarification]) -> String {
        let broad = state.interests.sorted().joined(separator: ", ")
        let explicit = state.values.sorted { $0.key < $1.key }.compactMap { axis, need in
            questions.first { $0.axis == axis }?.choices.first { $0.value == need.value }?.english
        }
        return "Find experiences for these interests: \(broad). " + explicit.joined(separator: ". ")
    }
    public static func summary(_ state: PreferenceState, questions: [Clarification]) -> [String] {
        state.values.sorted { $0.key < $1.key }.compactMap { axis, value in
            guard let c = questions.first(where: { $0.axis == axis })?.choices.first(where: { $0.value == value.value }) else { return nil }
            return c.summary + (value.must ? " · wajib" : " · diutamakan") + (state.reusable[axis] != nil && state.trip[axis] == nil ? " · tersimpan" : " · perjalanan ini")
        }
    }
}
public struct StudyCase: Codable, Identifiable, Sendable {
    public var id: String
    public var theme: String
    public var brief: String
    public var interests: [String]
    public var candidates: [Experience]
    /// Evaluator-only fields. Never included in advisor requests.
    public var answers: [String: String]
    public var preferredIDs: [String]
}
public enum LabData {
    public static func questions() throws -> [Clarification] { try load("questions") }
    public static func cases() throws -> [StudyCase] { try load("cases") }
    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let u = Bundle.module.url(forResource: name, withExtension: "json") else { throw LabError.invalid("Data pengujian hilang") }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: u))
    }
}
public struct AdvisorRequest: Codable, Sendable {
    public var requestID: UUID
    public var revision: Int
    public var interests: [String]
    public var explicit: [String: String]
    public var eligibleQuestions: [Clarification]
    public init(state: PreferenceState, questions: [Clarification]) {
        requestID = UUID(); revision = state.revision; interests = state.interests
        explicit = state.values.mapValues(\.value); eligibleQuestions = questions
    }
}
public struct AdvisorDecision: Codable, Sendable {
    public var requestID: UUID
    public var revision: Int
    public var questionID: String?
    public var reason: String
    public var mode: String
    public var model: String?
    public var provider: String?
    public var seconds: Double
    public var attempts: Int
    public var costUSD: Double?
    public var errorCode: String?
    public func validate(for request: AdvisorRequest, current: PreferenceState) throws {
        guard requestID == request.requestID, revision == request.revision, revision == current.revision,
              questionID == nil || request.eligibleQuestions.contains(where: { $0.id == questionID }),
              ["resolve_activity", "already_clear", "local_fallback"].contains(reason),
              mode != "llm" || (questionID != nil && reason == "resolve_activity") || (questionID == nil && reason == "already_clear")
        else { throw LabError.invalid("Hasil AI tidak berlaku atau konteks berubah") }
    }
}
