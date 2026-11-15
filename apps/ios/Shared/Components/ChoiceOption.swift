import Foundation

/// A value that can be shown as one answer in a single-choice question.
protocol ChoiceOption: Hashable, Identifiable {
    /// Visible, localizable answer text.
    var title: LocalizedStringResource { get }
}
