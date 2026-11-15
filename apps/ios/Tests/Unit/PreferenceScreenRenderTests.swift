import SwiftUI
import Testing
import UIKit
@testable import C67

/// Renders the preference screens offscreen with `ImageRenderer`, so layout crashes and missing
/// selection states fail in a test run without stepping through the Simulator UI.
///
/// `ImageRenderer` does not draw UIKit-backed containers such as `ScrollView` or toolbars, so
/// full screens are checked as smoke renders and selection states are compared on the
/// option components directly.
@MainActor
@Suite("Preference screens render")
struct PreferenceScreenRenderTests {
    private static let screenSize = CGSize(width: 402, height: 874)

    @Test("Each question renders in Light and Dark", arguments: PreferenceStep.allCases, [ColorScheme.light, .dark])
    func rendersInBothAppearances(step: PreferenceStep, scheme: ColorScheme) throws {
        let image = try renderImage(screen(for: step).environment(\.colorScheme, scheme), size: Self.screenSize)
        #expect(image.size == Self.screenSize)
    }

    @Test("Each question renders at an accessibility text size", arguments: PreferenceStep.allCases)
    func rendersWithLargeText(step: PreferenceStep) throws {
        let image = try renderImage(screen(for: step).dynamicTypeSize(.accessibility3), size: Self.screenSize)
        #expect(image.size == Self.screenSize)
    }

    @Test("A selected option card renders differently from the unselected list")
    func optionSelectionChangesRender() throws {
        let size = CGSize(width: 360, height: 320)
        let unselected = try renderPNG(
            ChoiceOptionList(options: PlacePopularityPreference.allCases, selection: nil, select: { _ in }),
            size: size
        )
        let selected = try renderPNG(
            ChoiceOptionList(options: PlacePopularityPreference.allCases, selection: .both, select: { _ in }),
            size: size
        )
        #expect(unselected != selected)
    }

    @Test("A selected interest chip renders differently from an unselected one")
    func chipSelectionChangesRender() throws {
        let size = CGSize(width: 160, height: 60)
        let unselected = try renderPNG(
            ChoiceChip(title: "Foodie", systemImage: "fork.knife", isSelected: false, action: {}),
            size: size
        )
        let selected = try renderPNG(
            ChoiceChip(title: "Foodie", systemImage: "fork.knife", isSelected: true, action: {}),
            size: size
        )
        #expect(unselected != selected)
    }

    @Test("Interest chips wrap onto several rows at the Sketch width")
    func interestChipsWrap() throws {
        let chips = FlowLayout(spacing: 8, lineSpacing: 14) {
            ForEach(TripInterest.allCases) { interest in
                ChoiceChip(title: interest.title, systemImage: interest.systemImage, isSelected: false, action: {})
            }
        }
        let renderer = ImageRenderer(content: chips.frame(width: 362))
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        #expect(image.size.width == 362)
        #expect(image.size.height > 100)
    }

    private func screen(for step: PreferenceStep) -> PreferenceQuestionView {
        PreferenceQuestionView(step: step, answers: .everythingAnswered, update: { _ in }, advance: {}, skip: {})
    }

    private func renderImage(_ view: some View, size: CGSize) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return try #require(renderer.uiImage)
    }

    private func renderPNG(_ view: some View, size: CGSize) throws -> Data {
        try #require(renderImage(view, size: size).pngData())
    }
}
