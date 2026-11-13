import SwiftUI

/// Sketch HI-FI `PREFERENCES Q6`: today's budget, chosen with a native slider.
struct BudgetQuestionView: View {
    let next: (Double) -> Void
    let skip: () -> Void

    @State private var budget: Double

    init(initialBudget: Double?, next: @escaping (Double) -> Void, skip: @escaping () -> Void) {
        self.next = next
        self.skip = skip
        _budget = State(initialValue: BudgetScale.normalized(initialBudget ?? BudgetScale.minimum))
    }

    var body: some View {
        QuestionScaffold(
            title: Text("What’s your \(QuestionTitle.highlight("budget")) for today?"),
            contentSpacing: 160,
            skip: skip
        ) {
            VStack(spacing: 24) {
                Slider(value: $budget, in: BudgetScale.range, step: BudgetScale.step) {
                    Text("Budget")
                } minimumValueLabel: {
                    Text(verbatim: "$")
                        .accessibilityHidden(true)
                } maximumValueLabel: {
                    Text(verbatim: "$$")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(AppColor.secondaryText)
                .tint(AppColor.brand)
                .accessibilityValue(Text(budget, format: BudgetScale.currency))

                Divider()

                Text(budget, format: BudgetScale.currency)
                    .font(AppFont.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accent)
                    .contentTransition(.numericText(value: budget))
                    .animation(.snappy, value: budget)
                    .accessibilityHidden(true)
            }
            .sensoryFeedback(.selection, trigger: budget)
        } footer: {
            QuestionPrimaryButton("Next") {
                next(budget)
            }
        }
    }
}

#if DEBUG
    #Preview("Q6 · Minimum") {
        PreferenceQuestionPreview {
            BudgetQuestionView(initialBudget: nil, next: { _ in }, skip: {})
        }
        .environment(\.locale, Locale(identifier: "id_ID"))
    }

    #Preview("Q6 · Dark, large text") {
        PreferenceQuestionPreview {
            BudgetQuestionView(initialBudget: 250_000, next: { _ in }, skip: {})
        }
        .environment(\.locale, Locale(identifier: "id_ID"))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
