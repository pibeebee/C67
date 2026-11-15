import Foundation
import Testing
@testable import PreferenceCore

@Test func catalogueSourceDateUsesJakartaCalendarDay() {
    let place = CatalogPlace(id: "owned", name: "Owned", category: "library", address: "Owned",
                             sourceURL: "https://example.org", latitude: -6.19, longitude: 106.83, checks: [], status: "unknown",
                             checkedAt: "2026-11-09T23:21:00.123456+00:00")
    #expect(place.checkedDateLabel == "10 Nov 2026")
}

@Test func pairedCasesShareInputsAndDoNotRevealAnswers() throws {
    let cases = try LabData.cases()
    for i in stride(from: 0, to: cases.count, by: 2) {
        #expect(cases[i].candidates == cases[i + 1].candidates)
        #expect(cases[i].interests == cases[i + 1].interests)
        #expect(Set(cases[i].preferredIDs).isDisjoint(with: cases[i + 1].preferredIDs))
        var s = PreferenceState(); s.interests = cases[i].interests
        let request = AdvisorRequest(state: s, questions: try LabData.questions())
        let text = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(!text.contains("preferredIDs")); #expect(!text.contains("answers")); #expect(!text.contains("brief"))
    }
}
@Test func clarificationCapturesActivityAndDoesNotInventBounds() throws {
    let qs = try LabData.questions()
    for c in try LabData.cases().filter({ !$0.id.hasPrefix("mixed") }) {
        var s = PreferenceState(); s.interests = c.interests
        let q = try #require(PreferenceEngine.eligible(qs, items: c.candidates, state: s).first)
        let answer = try #require(c.answers[q.id]); try s.answer(q, choiceID: answer)
        #expect(PreferenceEngine.rank(c.candidates, state: s).prefix(3).allSatisfy { c.preferredIDs.contains($0.id) })
        #expect(s.values.count == 1); #expect(s.values.values.allSatisfy { !$0.must })
        #expect(!PreferenceEngine.english(s, questions: qs).contains("90 minutes"))
    }
}
@Test func twoIndependentAmbiguitiesNeedTwoExplicitAnswers() throws {
    let qs = try LabData.questions()
    for c in try LabData.cases().filter({ $0.id.hasPrefix("mixed") }) {
        var s = PreferenceState(); s.interests = c.interests
        for _ in 0 ..< 2 {
            let q = try #require(PreferenceEngine.eligible(qs, items: c.candidates, state: s).first)
            try s.answer(q, choiceID: try #require(c.answers[q.id]))
        }
        #expect(PreferenceEngine.rank(c.candidates, state: s).prefix(2).allSatisfy { c.preferredIDs.contains($0.id) })
        #expect(s.trip.count == 2)
    }
}
@Test func coffeeIsNotIntroducedWhenOnlyReadingWasSelected() throws {
    let q = try LabData.questions(), cases = try LabData.cases()
    var s = PreferenceState(); s.interests = ["reading"]
    #expect(!PreferenceEngine.eligible(q, items: cases.flatMap(\.candidates), state: s).contains { $0.id == "q-coffee-reading" })
}
@Test func correctingARequiredActivityKeepsItsStrength() throws {
    let q = try LabData.questions()[0]; var s = PreferenceState()
    try s.answer(q, choiceID: q.choices[0].id, must: true)
    try s.answer(q, choiceID: q.choices[1].id)
    #expect(s.values[q.axis]?.must == true)
}
@Test func realIntentQuestionsDoNotDependOnSyntheticVenues() throws {
    let qs = try LabData.questions(); var s = PreferenceState(); s.interests = ["reading", "coffee"]
    #expect(PreferenceEngine.intentQuestions(qs, state: s).map(\.id) == ["q-reading", "q-coffee-reading"])
    try s.answer(qs[0], choiceID: qs[0].choices[0].id)
    #expect(PreferenceEngine.intentQuestions(qs, state: s).map(\.id) == ["q-coffee-reading"])
}
@Test func liveRequestPreservesEveryNeedAndRequiredStrength() throws {
    let qs = try LabData.questions(); var s = PreferenceState(); s.interests = ["reading", "coffee"]
    try s.answer(qs[0], choiceID: qs[0].choices[0].id, must: true)
    try s.answer(qs[1], choiceID: qs[1].choices[0].id)
    let r = LivePlaceRequest(state: s, area: "Jakarta Pusat")
    #expect(r.needs.count == 2); #expect(r.needs["readingActivity"]?.must == true)
    #expect(r.visitAt == nil); #expect(r.durationMinutes == nil)
}
@Test func unknownIsConditionalAndMustContradictionExcluded() throws {
    let c = try LabData.cases()[0], q = try LabData.questions()[0]
    var s = PreferenceState(); s.interests = c.interests
    try s.answer(q, choiceID: q.choices[0].id, must: true)
    var unknown = c.candidates[0]; unknown.id = "unknown"; unknown.attributes = [:]
    let rows = PreferenceEngine.rank(c.candidates + [unknown], state: s)
    #expect(rows.contains { $0.id == "unknown" && $0.unknown == [q.axis] })
    #expect(rows.allSatisfy { $0.contradicted.isEmpty })
}
@Test func allUnknownAndUniformPoolsDoNotCauseQuestions() throws {
    let q = try LabData.questions(), c = try LabData.cases()[0]
    var s = PreferenceState(); s.interests = c.interests
    var pool = c.candidates; for i in pool.indices { pool[i].attributes = [:] }
    #expect(PreferenceEngine.eligible(q, items: pool, state: s).isEmpty)
    let uniform = c.candidates.filter { $0.attributes[q[0].axis] == q[0].choices[0].value }
    #expect(PreferenceEngine.eligible(q, items: uniform, state: s).isEmpty)
}
@Test func skipScopePersistenceAndUndo() throws {
    let q = try LabData.questions()[0]; var s = PreferenceState(); s.interests = ["reading"]
    s.savedIDs = ["keep-me"]; let before = s
    try s.answer(q, choiceID: q.choices[0].id)
    #expect(s.savedIDs == ["keep-me"])
    let restored = try JSONDecoder().decode(PreferenceState.self, from: JSONEncoder().encode(s))
    #expect(restored == s)
    s = before; #expect(s.trip.isEmpty)
    try s.answer(q, choiceID: q.choices[0].id); s.newTrip(); #expect(s.trip.isEmpty)
    try s.answer(q, choiceID: q.choices[1].id); s.remember(q.axis); s.newTrip()
    #expect(s.values[q.axis]?.value == q.choices[1].value)
}
@Test func invalidChoicesAndStaleResponsesAreRejected() throws {
    let q = try LabData.questions()[0]; var s = PreferenceState(); s.interests = ["reading"]
    #expect(throws: LabError.self) { try s.answer(q, choiceID: "injected-id") }
    let r = AdvisorRequest(state: s, questions: [q])
    let d = AdvisorDecision(requestID: r.requestID, revision: r.revision, questionID: q.id, reason: "resolve_activity", mode: "llm", seconds: 0, attempts: 1)
    try d.validate(for: r, current: s); s.skip(q.id)
    #expect(throws: LabError.self) { try d.validate(for: r, current: s) }
}
@Test func skipsNotRepeatedAndQuestionBudgetIsBounded() throws {
    let qs = try LabData.questions(), c = try LabData.cases()[0]
    var s = PreferenceState(); s.interests = c.interests; s.skip(qs[0].id)
    #expect(!PreferenceEngine.eligible(qs, items: c.candidates, state: s).contains { $0.id == qs[0].id })
    s.skipped = ["first", "second"]
    #expect(PreferenceEngine.eligible(qs, items: c.candidates, state: s).isEmpty)
}
