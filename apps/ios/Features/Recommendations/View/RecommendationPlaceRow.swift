import SwiftUI
import C67Domain

struct RecommendationPlaceRow: View {
    let item: RecommendedPlace
    var userLocation: PlanningPoint?
    let isSelected: Bool
    let isExisting: Bool
    let isDisabled: Bool
    /// Dimmed because the selection is full; still tappable so the tap can explain why.
    var isLocked = false
    let action: () -> Void

    private var accessibilityValue: String {
        let state = isExisting ? String(localized: "Already in your trip") : isSelected ? String(localized: "Added") : String(localized: "Not selected")
        var details: [String] = []
        if let address = item.shortAddress { details.append(address) }
        if item.straightLineDistance(from: userLocation) != nil { details.append(item.distanceDescription(from: userLocation)) }
        details.append(state)
        return details.joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                PlaceThumbnail(imageName: nil, size: 76, systemImage: item.poiPresentation?.symbol ?? "mappin.and.ellipse")

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let address = item.shortAddress {
                        (Text(item.poiPresentation?.label ?? item.category ?? String(localized: "Suggested place")) + Text(" · ") + Text(address))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(item.poiPresentation?.label ?? item.category ?? String(localized: "Suggested place"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if item.straightLineDistance(from: userLocation) != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin").imageScale(.small)
                            Text(item.distanceDescription(from: userLocation))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                selectionIndicator
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                shape.fill(AppColor.surface)
                    .overlay { shape.strokeBorder(AppColor.accent, lineWidth: 1.5).opacity(isSelected ? 1 : 0) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: isSelected)
        .opacity(isLocked ? 0.45 : 1)
        .disabled(isDisabled || isExisting)
        .accessibilityLabel(item.place.name)
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(isSelected ? Text("Remove from selection")
            : isLocked ? Text("Remove a place to add this one.") : Text("Add to selection"))
        .accessibilityIdentifier("recommendation-\(item.id)")
    }

    /// Plus becomes a filled check; an existing trip place keeps a neutral check.
    private var selectionIndicator: some View {
        let isChecked = isSelected || isExisting
        return ZStack {
            Circle().fill(isChecked ? (isExisting ? Color.secondary : AppColor.brand) : AppColor.tertiaryFill)
            Image(systemName: isChecked ? "checkmark" : "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(isChecked ? AppColor.onBrand : AppColor.accent)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
        }
        .frame(width: 30, height: 30)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}
