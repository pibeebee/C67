import Foundation

/// Answer to "Where do you want to spend the most time?": let Travelant decide, or one chosen place.
enum MainSpotChoice: Hashable, Sendable {
    case automatic
    case place(UUID)

    /// The chosen place, or nil when Travelant decides.
    var placeID: UUID? {
        if case let .place(id) = self { id } else { nil }
    }

    /// Only a chosen place gets the follow-up "How long…" question.
    var asksForStay: Bool { placeID != nil }
}
