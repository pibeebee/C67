import SwiftUI
import MapKit
import C67Domain

struct AddPlaceRow: View {
    let item: RecommendedPlace
    let isSelected: Bool
    var isDisabled = false
    var origin: PlanningPoint?
    let toggle: () -> Void
    @State private var showsMap = false

    var body: some View {
        HStack(spacing: 14) {
            PlaceThumbnail(imageName: item.previewImage, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.place.name).font(.subheadline.weight(.semibold))
                if let category = item.category { Text(category).font(.footnote).foregroundStyle(.secondary) }
                if let address = item.address ?? item.place.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(address).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Full address unavailable").font(.footnote).foregroundStyle(.secondary)
                }
                if item.straightLineDistance(from: origin) != nil {
                    Text(item.distanceDescription(from: origin)).font(.footnote).foregroundStyle(.secondary)
                }
                Button("View on map") { showsMap = true }.font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggle) {
                if isSelected { Image(systemName: "checkmark.circle.fill").font(.title2) }
                else { Image(systemName: "plus.circle.fill").font(.title2) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.accent)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isDisabled && !isSelected)
            .accessibilityLabel(isSelected ? "Remove \(item.place.name)" : "Add \(item.place.name)")
            .accessibilityIdentifier("placeToggle-\(item.id)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.surface, in: .rect(cornerRadius: 26))
        .sheet(isPresented: $showsMap) {
            NavigationStack {
                Map(initialPosition: .region(.init(center: .init(latitude: item.place.location.latitude, longitude: item.place.location.longitude), latitudinalMeters: 1000, longitudinalMeters: 1000))) {
                    Marker(item.place.name, coordinate: .init(latitude: item.place.location.latitude, longitude: item.place.location.longitude))
                }
                .navigationTitle(item.place.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsMap = false } } }
            }
        }
    }
}
