import SwiftUI

struct AddPlaceRow: View {
    let item: RecommendedPlace
    let isSelected: Bool
    var isDisabled = false
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlaceThumbnail(imageName: item.previewImage, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.place.name).font(.subheadline.weight(.semibold))
                if let category = item.category { Text(category).font(.footnote).foregroundStyle(.secondary) }
                if let address = item.address { Text(address).font(.footnote).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggle) {
                if isSelected { Text("Added").font(.caption) }
                else { Image(systemName: "plus.circle.fill").font(.title2) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? Color.secondary : AppColor.accent)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(isDisabled && !isSelected)
            .accessibilityLabel(isSelected ? "Remove \(item.place.name)" : "Add \(item.place.name)")
            .accessibilityIdentifier("placeToggle-\(item.id)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.surface, in: .rect(cornerRadius: 26))
    }
}
