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
                Group {
                    if let image = item.previewImage {
                        Image(image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title2)
                            .foregroundStyle(AppColor.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AppColor.tertiaryFill)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.category ?? String(localized: "Suggested place"))
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
