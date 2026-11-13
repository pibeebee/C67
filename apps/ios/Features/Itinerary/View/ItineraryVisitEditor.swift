import SwiftUI
import C67Domain

struct ItineraryVisitEditor: View {
    @State private var place: PlanningPlace
    let zone: String
    let startsAt: Date
    let update: (PlanningPlace) -> Void
    @Environment(\.dismiss) private var dismiss

    init(place: PlanningPlace, zone: String, startsAt: Date, update: @escaping (PlanningPlace) -> Void) {
        _place = State(initialValue: place)
        self.zone = zone
        self.startsAt = startsAt
        self.update = update
    }

    var body: some View {
        NavigationStack {
            Form {
                PlanningPlaceEditor(place: $place, zone: zone, defaultStart: startsAt)
                Text("Update your preferences to generate a new itinerary. Arrival times may change as the plan is recalculated.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Edit visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: cancel)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update itinerary", action: apply)
                }
            }
        }
    }

    private func cancel() { dismiss() }
    private func apply() { update(place); dismiss() }
}
