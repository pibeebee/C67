import SwiftUI

/// Sketch HI-FI `PLACES MAIN COURSE ADD`: where to spend the most time.
///
/// "Let Travelants decide" as a brand hero card, then the chosen places as the alternative in
/// one grouped card with native-style checkmarks, then Next.
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
            VStack(alignment: .leading, spacing: 24) {
                automaticCard
                if !places.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Or choose one of your places")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.secondaryText)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)
                        placesGroup
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.25), value: selection)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAutomatic: Bool { selection == .automatic }

    /// The default as a filled brand card. Unselected, it settles to a plain surface card with a
    /// brand icon tile, so its text stays readable; selecting it floods the card with brand colour.
    private var automaticCard: some View {
        Button { select(.automatic) } label: {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppColor.onBrand)
                    .symbolEffect(.bounce, value: isAutomatic && !reduceMotion)
                    .frame(width: 52, height: 52)
                    .background(isAutomatic ? Color.white.opacity(0.18) : AppColor.brand,
                                in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Let Travelants decide")
                        .font(AppFont.headline)
                        .foregroundStyle(isAutomatic ? AppColor.onBrand : AppColor.primaryText)
                    Text("Adjust based on route and opening hours")
                        .font(.subheadline)
                        .foregroundStyle(isAutomatic ? AppColor.onBrand.opacity(0.85) : AppColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isAutomatic ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isAutomatic ? AppColor.onBrand : Color(uiColor: .tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .background {
                ZStack {
                    cardShape.fill(AppColor.surface)
                    cardShape.fill(LinearGradient(colors: [AppColor.brand, AppColor.brandGradientEnd],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(isAutomatic ? 1 : 0)
                }
            }
            .scaleEffect(isAutomatic ? 1 : 0.98)
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isAutomatic ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("mainSpotAutomatic")
    }

    private var placesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 64) }
                CheckmarkRow(
                    title: Text(verbatim: item.place.name),
                    subtitle: (item.poiPresentation?.label ?? item.category).map { Text(verbatim: $0) },
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
