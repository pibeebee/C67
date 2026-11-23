import SwiftUI
import C67Domain

/// One place in the "Places" sheet (Sketch HI-FI `PLACES LIST ADDED LIST`). Mirrors the
/// recommendation card (icon tile, name, one detail line, 30pt trailing control) so a place
/// looks the same in the list and in the sheet. Places already in the trip show no remove control.
struct SelectedPlaceCard: View {
    let place: PlanningPlace
    let detail: RecommendedPlace?
    /// Nil for places already in the trip, which cannot be removed here.
    let remove: (() -> Void)?

    private var detailLine: String {
        let category = detail?.poiPresentation?.label ?? detail?.category ?? String(localized: "Suggested place")
        return [category, detail?.shortAddress ?? detail?.address].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            PlaceThumbnail(imageName: detail?.previewImage, size: 76, systemImage: detail?.poiPresentation?.symbol ?? "mappin.and.ellipse",
                           placeholderBackground: AppColor.surface)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(verbatim: detailLine)
                    .font(.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let remove {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.red, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(place.name)"))
            } else {
                Text("In your trip")
                    .font(.footnote)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(AppColor.canvas, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
