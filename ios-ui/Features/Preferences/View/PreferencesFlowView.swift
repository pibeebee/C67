import SwiftUI

/// Q1–Q7 trip preference questions in a native navigation stack.
///
/// Single-choice answers move to the next question immediately; Q1 and Q6 use Next.
/// `finish` is called once, after the last question.
struct PreferencesFlowView: View {
    let cancel: () -> Void
    let finish: (PreferenceAnswers) -> Void

    @State private var flow: PreferenceFlow

    init(
        flow: PreferenceFlow = PreferenceFlow(),
        cancel: @escaping () -> Void,
        finish: @escaping (PreferenceAnswers) -> Void
    ) {
        _flow = State(initialValue: flow)
        self.cancel = cancel
        self.finish = finish
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            question(for: .interests)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.backward", action: cancel)
                    }
                }
                .navigationDestination(for: PreferenceStep.self) { step in
                    question(for: step)
                }
        }
    }

    private func question(for step: PreferenceStep) -> some View {
        PreferenceQuestionView(
            step: step,
            answers: flow.answers,
            update: { flow.answers = $0 },
            advance: {
                if let answers = flow.advance(from: step) {
                    finish(answers)
                }
            },
            skip: {
                if let answers = flow.skip(step) {
                    finish(answers)
                }
            }
        )
    }
}

#if DEBUG
#Preview("Flow · Q1–Q7") {
    PreferencesFlowView(cancel: {}, finish: { _ in })
        .environment(\.locale, Locale(identifier: "id_ID"))
}

#Preview("Flow · Dark") {
    PreferencesFlowView(cancel: {}, finish: { _ in })
        .preferredColorScheme(.dark)
}
#endif
