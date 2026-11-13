import SwiftUI

/// A vertical list of single-choice answers.
///
/// The view only reports taps; the owner decides what the selection means.
struct ChoiceOptionList<Option: ChoiceOption>: View {
    let options: [Option]
    let selection: Option?
    let select: (Option) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    select(option)
                } label: {
                    Text(option.title)
                }
                .buttonStyle(ChoiceOptionButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
