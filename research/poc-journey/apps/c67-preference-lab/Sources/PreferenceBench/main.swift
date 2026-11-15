import Foundation
import PreferenceCore

struct Config: Codable { var baseURL: String; var token: String }
struct EmbeddingAudit: Decodable { var scoresByQuery: [String: [String: Double]] }
struct Observation: Codable {
    var caseID: String; var arm: String; var mode: String; var topIDs: [String]
    var top1: Bool; var precision3: Double; var intentCaptured: Bool
    var questionID: String?; var answered: Int; var seconds: Double
    var model: String?; var attempts: Int; var errorCode: String?
}
let args = CommandLine.arguments
let live = args.contains("--live")
let replay = args.contains("--replay")
let prior = replay ? try JSONDecoder().decode([Observation].self, from: Data(contentsOf: URL(fileURLWithPath: "artifacts/live.json"))) : []
let out = URL(fileURLWithPath: args.dropFirst().first(where: { !$0.hasPrefix("--") }) ?? "artifacts/controlled.json")
let config = try? JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: ".local/connection.json")))
let audit = try? JSONDecoder().decode(EmbeddingAudit.self, from: Data(contentsOf: URL(fileURLWithPath: "artifacts/e5-audit.json")))
let cases = try LabData.cases(), questions = try LabData.questions()
var observations: [Observation] = []
var legacyRemaining = 6
func scores(_ state: PreferenceState) -> [String: Double] {
    audit?.scoresByQuery[PreferenceEngine.english(state, questions: questions)] ?? [:]
}
func post<T: Encodable, R: Decodable>(_ path: String, _ body: T, as: R.Type) async throws -> R {
    guard let config else { throw LabError.invalid("Missing independent service connection") }
    var r = URLRequest(url: URL(string: config.baseURL + path)!); r.httpMethod = "POST"
    r.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
    r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.timeoutInterval = 11
    r.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: r)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LabError.invalid("HTTP diagnostic failure") }
    return try JSONDecoder().decode(R.self, from: data)
}
func result(_ item: StudyCase, _ state: PreferenceState, arm: String, mode: String, q: String?,
            seconds: Double, model: String? = nil, attempts: Int = 0, error: String? = nil,
            override: [String]? = nil, useE5: Bool = true) -> Observation {
    let ranked = override ?? PreferenceEngine.rank(item.candidates, state: state, semantic: useE5 ? scores(state) : [:]).map(\.id)
    let first = Array(ranked.prefix(3)), expected = Set(item.preferredIDs)
    let captured = item.answers.allSatisfy { qid, choice in
        guard let q = questions.first(where: { $0.id == qid }), let v = q.choices.first(where: { $0.id == choice }) else { return false }
        return state.values[q.axis]?.value == v.value
    }
    return .init(caseID: item.id, arm: arm, mode: mode, topIDs: first,
                 top1: first.first.map(expected.contains) ?? false,
                 precision3: Double(first.filter(expected.contains).count) / 3, intentCaptured: captured,
                 questionID: q, answered: q == nil ? 0 : 1, seconds: seconds, model: model,
                 attempts: attempts, errorCode: error)
}
@MainActor func checkpoint() throws {
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
    try e.encode(observations).write(to: out, options: .atomic)
}
for item in cases {
    var initial = PreferenceState(); initial.interests = item.interests
    for useE5 in [false, true] where !useE5 || audit != nil {
        let began = ContinuousClock.now
        var a = result(item, initial, arm: useE5 ? "A-broad-e5" : "A-broad", mode: "local", q: nil,
                       seconds: 0, useE5: useE5)
        a.seconds = elapsed(began); observations.append(a)
        let rulesBegan = ContinuousClock.now
        var clarified = initial
        let q = PreferenceEngine.eligible(questions, items: item.candidates, state: clarified).first
        if let q, let answer = item.answers[q.id] { try clarified.answer(q, choiceID: answer) }
        var b = result(item, clarified, arm: useE5 ? "B-rules-e5" : "B-rules", mode: "local", q: q?.id,
                       seconds: 0, useE5: useE5)
        b.seconds = elapsed(rulesBegan); observations.append(b)
        var twice = clarified
        let second = PreferenceEngine.eligible(questions, items: item.candidates, state: twice).first
        if let second, let answer = item.answers[second.id] { try twice.answer(second, choiceID: answer) }
        if !useE5 {
            var two = result(item, twice, arm: "B-two-rounds", mode: "local", q: q?.id, seconds: 0, useE5: false)
            two.answered = (q == nil ? 0 : 1) + (second == nil ? 0 : 1)
            two.seconds = elapsed(rulesBegan); observations.append(two)
        }
    }
    if replay, let old = prior.first(where: { $0.caseID == item.id && $0.arm == "C-adaptive" }) {
        var s = initial
        if let q = questions.first(where: { $0.id == old.questionID }), let answer = item.answers[q.id] { try s.answer(q, choiceID: answer) }
        let check = result(item, s, arm: "C-replayed", mode: old.mode, q: old.questionID, seconds: old.seconds, model: old.model, attempts: old.attempts, error: old.errorCode)
        guard check.topIDs == old.topIDs, check.intentCaptured == old.intentCaptured else { throw LabError.invalid("Recorded result could not be reproduced") }
        observations.append(check)
    }
    if live {
        let eligible = PreferenceEngine.eligible(questions, items: item.candidates, state: initial)
        let request = AdvisorRequest(state: initial, questions: eligible)
        var state = initial
        do {
            let response: AdvisorDecision = try await post("/advisor", request, as: AdvisorDecision.self)
            try response.validate(for: request, current: state)
            if let q = eligible.first(where: { $0.id == response.questionID }), let a = item.answers[q.id] { try state.answer(q, choiceID: a) }
            observations.append(result(item, state, arm: "C-adaptive", mode: response.mode, q: response.questionID,
                                       seconds: response.seconds, model: response.model, attempts: response.attempts, error: response.errorCode))
        } catch {
            observations.append(result(item, state, arm: "C-adaptive", mode: "failed", q: nil, seconds: 0, error: String(describing: type(of: error))))
        }
        try checkpoint()
        // Predetermined first six paired cases, irrespective of results; not all themes.
        guard legacyRemaining > 0 else { try checkpoint(); print("Checkpoint \(item.id)"); continue }
        legacyRemaining -= 1
        // The actual current system prompt and list-diversity policy on owned fixtures.
        struct LegacyBody: Encodable { var interests: [String]; var candidates: [Experience]; var semantic: [String: Double] }
        struct LegacyResult: Decodable { var ids: [String]; var mode: String; var model: String?; var seconds: Double; var attempts: Int; var errorCode: String? }
        do {
            let r: LegacyResult = try await post("/legacy-synthetic", LegacyBody(interests: initial.interests,
                                                                                 candidates: item.candidates, semantic: scores(initial)), as: LegacyResult.self)
            observations.append(result(item, initial, arm: "A-current-llm-contract", mode: r.mode, q: nil,
                                       seconds: r.seconds, model: r.model, attempts: r.attempts, error: r.errorCode, override: r.ids))
        } catch {
            observations.append(result(item, initial, arm: "A-current-llm-contract", mode: "failed", q: nil, seconds: 0, error: "transport", override: []))
        }
    }
    try checkpoint()
    print("Checkpoint \(item.id): \(observations.count) observations")
}
print("Saved \(observations.count) observations to \(out.path); E5 audit \(audit == nil ? "absent" : "loaded").")

func elapsed(_ began: ContinuousClock.Instant) -> Double {
    let d = began.duration(to: .now).components
    return Double(d.seconds) + Double(d.attoseconds) / 1e18
}
