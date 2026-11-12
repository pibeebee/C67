import SwiftUI

/// Sketch HI-FI `PLACES MAIN COURSE ADD`: where to spend the most time.
///
/// "Let Travelant decide" or one of the chosen places, with a native-style checkmark on the
/// selection, then Next.
struct MainSpotQuestionView: View {
    let places: [RecommendedPlace]
    let selection: MainSpotChoice
    let select: (MainSpotChoice) -> Void
    let next: () -> Void
    let skip: () -> Void

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    var body: some View {
        QuestionScaffold(
            title: Text("Where do you want to spend the \(QuestionTitle.highlight("most time"))?"),
            contentSpacing: 24,
            skip: skip
        ) {
            VStack(alignment: .leading, spacing: 0) {
                CheckmarkRow(
                    title: Text("Let Travelant decide"),
                    subtitle: Text("Adjust based on route and opening hours"),
                    isSelected: selection == .automatic
                ) {
                    select(.automatic)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppColor.surface, in: cardShape)

                if !places.isEmpty {
                    Text("Or pick a main spot")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, 4)
                        .padding(.top, 22)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(places) { item in
                            CheckmarkRow(
                                title: Text(verbatim: item.place.name),
                                subtitle: item.category.map { Text(verbatim: $0) },
                                titleFont: AppFont.headline,
                                isSelected: selection == .place(item.id)
                            ) {
                                select(.place(item.id))
                            } leading: {
                                PlaceThumbnail(imageName: item.previewImage, size: 48)
                            }
                            .padding(.vertical, 5)

                            if item.id != places.last?.id {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .background(AppColor.surface, in: cardShape)
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
        } footer: {
            QuestionPrimaryButton("Next", action: next)
        }
    }
}

#if DEBUG
    #Preview("PLACES MAIN COURSE ADD") {
        @Previewable @State var selection = MainSpotChoice.automatic
        PreferenceQuestionPreview {
            MainSpotQuestionView(
                places: Array(RecommendationsPreviewData.batch.places.prefix(3)),
                selection: selection,
                select: { selection = $0 },
                next: {},
                skip: {}
            )
        }
    }

    #Preview("Place picked · Dark, large text") {
        @Previewable @State var selection = MainSpotChoice.place(RecommendationsPreviewData.ids[2])
        PreferenceQuestionPreview {
            MainSpotQuestionView(
                places: Array(RecommendationsPreviewData.batch.places.prefix(3)),
                selection: selection,
                select: { selection = $0 },
                next: {},
                skip: {}
            )
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
