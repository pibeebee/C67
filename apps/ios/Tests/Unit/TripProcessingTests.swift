import SwiftUI
import Testing
import UIKit
@testable import C67

@Suite("Trip processing messages (PREFERENCES PROCESSING 2–4)")
struct TripProcessingTests {
    @Test("Messages go trip, weather, then traffic, and stop on the last one")
    func stageOrder() {
        #expect(TripProcessingStage.allCases == [.puttingTogether, .checkingWeather, .scanningTraffic])
        #expect(TripProcessingStage.puttingTogether.next == .checkingWeather)
        #expect(TripProcessingStage.checkingWeather.next == .scanningTraffic)
        #expect(TripProcessingStage.scanningTraffic.next == nil)
    }

    @MainActor
    @Test("Each message renders a different screen", arguments: [
        (TripProcessingStage.puttingTogether, TripProcessingStage.checkingWeather),
        (.checkingWeather, .scanningTraffic),
    ])
    func messagesDiffer(first: TripProcessingStage, second: TripProcessingStage) throws {
        #expect(try png(first) != png(second))
    }

    @MainActor
    private func png(_ stage: TripProcessingStage) throws -> Data {
        let renderer = ImageRenderer(
            content: TripProcessingView.message(for: stage)
                .font(AppFont.title1)
                .frame(width: 360, height: 120)
        )
        renderer.scale = 1
        return try #require(renderer.uiImage?.pngData())
    }
}
