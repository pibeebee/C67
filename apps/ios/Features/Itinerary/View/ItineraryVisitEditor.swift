import SwiftUI
import C67Domain

struct ItineraryVisitEditor: View {
    private static let durationChoices = [60] + Array(stride(from: 300, through: 86_400, by: 300))

    @State private var place: PlanningPlace
    private let durations: [Int]
    let zone: String
    let startsAt: Date
    let orderingOnly: Bool
    let update: (PlanningPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var pickerHeight = 143.0

    init(place: PlanningPlace, zone: String, startsAt: Date, orderingOnly: Bool = false, update: @escaping (PlanningPlace) -> Void) {
        var draft = place
        if orderingOnly { draft.visitSeconds = min(max(place.visitSeconds, 60), 86_400) }
        _place = State(initialValue: draft)
        // Keep an existing custom duration selectable alongside the standard five-minute choices.
        durations = (Self.durationChoices.filter { $0 / 60 != draft.visitSeconds / 60 } + [draft.visitSeconds]).sorted()
        self.zone = zone
        self.startsAt = startsAt
        self.orderingOnly = orderingOnly
        self.update = update
    }

    var body: some View {
        NavigationStack {
            Group {
                if orderingOnly {
                    durationEditor
                } else {
                    Form {
                        PlanningPlaceEditor(place: $place, zone: zone, defaultStart: startsAt)
                        Text("Update your preferences to generate a new itinerary. Arrival times may change as the plan is recalculated.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", action: cancel)
                        .labelStyle(.iconOnly)
                }
                if !orderingOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Update itinerary", action: apply)
                    }
                }
            }
        }
        .presentationDetents(orderingOnly ? [.height(405), .large] : [.large])
        .presentationDragIndicator(orderingOnly ? .visible : .automatic)
    }

    private var durationEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: RecommendedPlace(place: place).poiPresentation?.symbol ?? "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColor.accent)
                        .accessibilityHidden(true)
                    Text(place.name)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("itineraryVisitPlace")
                }
                .padding(.horizontal, 2)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Your visit length")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 13)
                        .accessibilityHidden(true)
                    Picker("Your visit length", selection: $place.visitSeconds) {
                        ForEach(durations, id: \.self) { seconds in
                            Text("\(seconds / 60) min").tag(seconds)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: pickerHeight)
                    .clipped()
                }
                .background(AppColor.surface, in: .rect(cornerRadius: 17))

                Text("Your chosen visit length will be preserved. This does not set an arrival time.")
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .bottomActionBar {
            Button("Update itinerary", action: apply)
                .buttonStyle(TripPrimaryButtonStyle())
        }
        .background(AppColor.canvas)
    }

    private func cancel() { dismiss() }
    private func apply() { update(place); dismiss() }
}
