import SwiftUI

struct RecommendationPlaceRow: View {
    let item: RecommendedPlace
    let isSelected: Bool
    let isExisting: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                PlaceThumbnail(imageName: nil, size: 76, systemImage: item.poiPresentation?.symbol ?? "mappin.and.ellipse")

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.poiPresentation?.label ?? item.category ?? String(localized: "Suggested place"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let address = item.address {
                        Text(address)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected || isExisting {
                    Text("Added")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 28, height: 28)
                        .background(AppColor.tertiaryFill, in: .circle)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(AppColor.surface, in: .rect(cornerRadius: 22))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isExisting)
        .accessibilityLabel(item.place.name)
        .accessibilityValue(isExisting ? Text("Already in your trip") : isSelected ? Text("Added") : Text("Not selected"))
        .accessibilityHint(isSelected ? Text("Remove from selection") : Text("Add to selection"))
        .accessibilityIdentifier("recommendation-\(item.id)")
    }
}
