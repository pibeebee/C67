import SwiftUI

struct PlacesSelectionSheet: View {
    let places: [RecommendedPlace]
    let remove: (RecommendedPlace) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                // Same card as the Recommendations "Places" sheet.
                LazyVStack(spacing: 10) {
                    if places.isEmpty { ContentUnavailableView("No places selected", systemImage: "mappin.and.ellipse") }
                    ForEach(places) { item in
                        SelectedPlaceCard(place: item.place, detail: item) {
                            withAnimation(.snappy) { remove(item) }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("selectedPlacesList")
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
