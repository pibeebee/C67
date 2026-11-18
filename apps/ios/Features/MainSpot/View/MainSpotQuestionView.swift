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
    var showsNext = true
    var researchesWithLuna = false
    var usesV41 = false
    var scheduleSummary: String?
    var editSchedule: (() -> Void)?

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
    }

    var body: some View {
        QuestionScaffold(
            title: Text("Where do you want to spend the \(QuestionTitle.highlight("most time"))?"),
            contentSpacing: 24
        ) {
            VStack(alignment: .leading, spacing: 0) {
                CheckmarkRow(
                    title: Text("Let Travelant decide"),
                    subtitle: Text(usesV41 ? "Plan the visits around your schedule" : (researchesWithLuna ? "Let Luna arrange your experience" : "Adjust based on route and opening hours")),
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
                                subtitle: (item.poiPresentation?.label ?? item.category).map { Text(verbatim: $0) },
                                titleFont: AppFont.headline,
                                isSelected: selection == .place(item.id)
                            ) {
                                select(.place(item.id))
                            } leading: {
                                PlaceThumbnail(imageName: nil, size: 48, systemImage: item.poiPresentation?.symbol ?? "mappin.and.ellipse")
                            }
                            .padding(.vertical, 5)
                            .accessibilityIdentifier("mainSpot-\(item.id)")

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
            VStack(spacing: 12) {
                if let scheduleSummary, let editSchedule {
                    Button(action: editSchedule) { Label(scheduleSummary, systemImage: "calendar") }
                        .accessibilityIdentifier("tripDateSummary")
                }
                if usesV41 {
                    Text("Travelant arranges your trip using Apple travel estimates and available hours. Hours checks send selected Apple place IDs to Pocket. If you choose Luna assistance, selected places, pins, candidate dates and preferences are sent to Pocket and Luna for activity and duration suggestions. Recommendations are estimates.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                } else if researchesWithLuna {
                    Text("Your selected places, pins and preferences are sent to the Pocket server and Luna to suggest an order and visit lengths. Weather providers may receive your starting point and selected places; forecasts may use Apple Weather or Open-Meteo. Recommendations are estimates.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                }
                if showsNext { QuestionPrimaryButton("Next", action: next) }
            }
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
                next: {}
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
                next: {}
            )
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
    }
#endif
