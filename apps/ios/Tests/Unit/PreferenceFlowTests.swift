import Testing
@testable import C67

@Suite("Preference flow navigation")
struct PreferenceFlowTests {
    @Test("Questions follow the Sketch order Q1 to Q7")
    func stepsFollowSketchOrder() {
        #expect(PreferenceStep.allCases.map(\.rawValue) == Array(1 ... 7))
        #expect(PreferenceStep.interests.next == .popularity)
        #expect(PreferenceStep.transport.next == nil)
    }

    @Test("Advancing pushes the next question")
    func advancePushesNextQuestion() {
        var flow = PreferenceFlow()
        #expect(flow.currentStep == .interests)

        let result = flow.advance(from: .interests)

        #expect(result == nil)
        #expect(flow.path == [.popularity])
        #expect(flow.currentStep == .popularity)
    }

    @Test("A repeated tap on the same question pushes only once")
    func duplicateAdvanceIsIgnored() {
        var flow = PreferenceFlow()
        flow.advance(from: .interests)
        flow.advance(from: .interests)

        #expect(flow.path == [.popularity])
    }

    @Test("Going back lets the earlier question advance again")
    func advanceAfterGoingBack() {
        var flow = PreferenceFlow()
        flow.advance(from: .interests)
        flow.advance(from: .popularity)
        flow.path.removeLast()

        flow.advance(from: .popularity)

        #expect(flow.path == [.popularity, .pace])
    }

    @Test("The last question returns the answers exactly once")
    func finishReturnsAnswersOnce() {
        var flow = PreferenceFlow()
        flow.answers.transport = .motorcycle
        for step in PreferenceStep.allCases.dropLast() {
            let result = flow.advance(from: step)
            #expect(result == nil)
        }

        let finished = flow.advance(from: .transport)
        let repeated = flow.advance(from: .transport)

        #expect(finished?.transport == .motorcycle)
        #expect(repeated == nil)
        #expect(flow.isFinished)
    }

    @Test("Skipping clears that question's answer and moves on")
    func skipClearsAnswer() {
        var flow = PreferenceFlow()
        flow.answers.toggle(.art)

        flow.skip(.interests)

        #expect(flow.answers.interests.isEmpty)
        #expect(flow.currentStep == .popularity)
    }

    @Test("Skipping a question that is not on top changes nothing")
    func skipIgnoresStaleQuestion() {
        var flow = PreferenceFlow()
        flow.answers.toggle(.art)
        flow.advance(from: .interests)

        flow.skip(.interests)

        #expect(flow.answers.interests == [.art])
        #expect(flow.path == [.popularity])
    }
}
