import SwiftUI
import C67Domain

/// One place in the "Places" sheet (Sketch HI-FI `PLACES LIST ADDED LIST`): photo, name,
/// category and area, with a native destructive remove button when the place can be removed.
struct SelectedPlaceCard: View {
    let place: PlanningPlace
    let detail: RecommendedPlace?
    /// Nil for places already in the trip, which cannot be removed here.
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            PlaceThumbnail(imageName: detail?.previewImage, size: 76)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name)
                    .font(AppFont.subheadline.bold())
                    .foregroundStyle(AppColor.primaryText)
                if let category = detail?.category {
                    Text(verbatim: category)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }
                if let address = detail?.address {
                    Text(verbatim: address)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let remove {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(.red)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .accessibilityLabel(Text("Remove \(place.name)"))
            } else {
                Text("In your trip")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 93, alignment: .leading)
        .background(AppColor.secondaryBackground, in: .rect(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
