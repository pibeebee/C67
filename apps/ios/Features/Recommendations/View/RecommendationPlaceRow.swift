import SwiftUI
import C67Domain

struct RecommendationPlaceRow: View {
    let item: RecommendedPlace
    var userLocation: PlanningPoint?
    let isSelected: Bool
    let isExisting: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var accessibilityValue: String {
        let state = isExisting ? String(localized: "Already in your trip") : isSelected ? String(localized: "Added") : String(localized: "Not selected")
        guard item.straightLineDistance(from: userLocation) != nil else { return state }
        return "\(item.distanceDescription(from: userLocation)), \(state)"
    }

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
                    if item.straightLineDistance(from: userLocation) != nil {
                        Text(item.distanceDescription(from: userLocation))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected || isExisting {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(isExisting ? Color.secondary : AppColor.accent)
                        .font(.title2)
                        .accessibilityHidden(true)
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
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(isSelected ? Text("Remove from selection") : Text("Add to selection"))
        .accessibilityIdentifier("recommendation-\(item.id)")
    }
}
