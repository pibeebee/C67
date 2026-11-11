import C67Domain

struct ItineraryReviewRoute: Hashable {
    let proposal: PlanProposal

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.proposal.id == rhs.proposal.id }
    func hash(into hasher: inout Hasher) { hasher.combine(proposal.id) }
}
