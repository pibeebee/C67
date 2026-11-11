import SwiftUI
import C67Domain

/// Sketch HI-FI `PLACES LIST ADDED LIST`: the "Places" sheet opened from My Places.
///
/// A native sheet with a close button. Places already in the trip are listed without a remove
/// button; selected recommendations can be removed.
struct SelectedPlacesView: View {
    let existing: [PlanningPlace]
    @Binding var selected: [PlanningPlace]
    /// Photo, category and area for each recommendation, when available.
    var details: [UUID: RecommendedPlace] = [:]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if existing.isEmpty && selected.isEmpty {
                    ContentUnavailableView(
                        "No places selected",
                        systemImage: "mappin.and.ellipse",
                        description: Text("Choose a recommendation to add it here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(existing) { place in
                                SelectedPlaceCard(place: place, detail: details[place.id], remove: nil)
                            }
                            ForEach(selected) { place in
                                SelectedPlaceCard(place: place, detail: details[place.id]) {
                                    remove(place)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selected.count)
    }

    private func remove(_ place: PlanningPlace) {
        withAnimation(.snappy) {
            selected.removeAll { $0.id == place.id }
        }
    }
}

#if DEBUG
private struct SelectedPlacesPreview: View {
    @State private var selected = Array(RecommendationsPreviewData.batch.places.prefix(3).map(\.place))

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                SelectedPlacesView(
                    existing: [],
                    selected: $selected,
                    details: Dictionary(
                        RecommendationsPreviewData.batch.places.map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                )
            }
    }
}

#Preview("PLACES LIST ADDED LIST") {
    SelectedPlacesPreview()
}

#Preview("PLACES LIST ADDED LIST · Dark") {
    SelectedPlacesPreview()
        .preferredColorScheme(.dark)
}
#endif
