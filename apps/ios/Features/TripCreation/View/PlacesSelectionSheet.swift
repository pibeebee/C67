import SwiftUI

struct PlacesSelectionSheet: View {
    let places: [RecommendedPlace]
    let remove: (RecommendedPlace) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if places.isEmpty { ContentUnavailableView("No places selected", systemImage: "mappin.and.ellipse") }
                    ForEach(places) { item in
                        AddPlaceRow(item: item, isSelected: true) { remove(item) }
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
