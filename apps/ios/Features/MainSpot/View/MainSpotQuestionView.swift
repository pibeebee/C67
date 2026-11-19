import SwiftUI

/// Sketch HI-FI `PLACES MAIN COURSE ADD`: where to spend the most time.
///
/// "Let Travelants decide" or one of the chosen places, with a native-style checkmark on the
/// selection, then Next.
struct MainSpotQuestionView: View {
    let places: [RecommendedPlace]
    let selection: MainSpotChoice
    let select: (MainSpotChoice) -> Void
    let next: () -> Void
    var showsNext = true
    var researchesWithLuna = false
    var usesV41 = false
    var usesFoundationModels = false
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
                    title: Text("Let Travelants decide"),
                    subtitle: Text("Adjust based on route and opening hours"),
                    isSelected: selection == .automatic
                ) {
                    select(.automatic)
                } leading: {
                    PlaceThumbnail(imageName: nil, size: 48, systemImage: "sparkle")
                }
                .padding(.vertical, 5)
                .accessibilityIdentifier("mainSpotAutomatic")

                ForEach(places) { item in
                    Divider().padding(.leading, 64)
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(AppColor.surface, in: cardShape)
            .sensoryFeedback(.selection, trigger: selection)
        } footer: {
            VStack(spacing: 12) {
                if let scheduleSummary, let editSchedule {
                    Button(action: editSchedule) { Label(scheduleSummary, systemImage: "calendar") }
                        .accessibilityIdentifier("tripDateSummary")
                }
                if usesFoundationModels {
                    Text("Apple Foundation Models estimates activities and visit durations on your device. Travelants uses Apple travel estimates and may send selected Apple place IDs to Pocket to check opening hours.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                } else if researchesWithLuna, !usesV41 {
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
