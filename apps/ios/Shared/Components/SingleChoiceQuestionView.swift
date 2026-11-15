import SwiftUI

/// A preference question answered by tapping one full-width option.
struct SingleChoiceQuestionView<Option: ChoiceOption>: View {
    let title: Text
    let options: [Option]
    let selection: Option?
    let select: (Option) -> Void
    let skip: () -> Void

    var body: some View {
        QuestionScaffold(title: title, skip: skip) {
            ChoiceOptionList(options: options, selection: selection, select: select)
        }
    }
}
