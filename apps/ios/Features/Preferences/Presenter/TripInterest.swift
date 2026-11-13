import Foundation

/// Q1 "What sounds good today?" — the kinds of places the traveller wants. Multi-select.
enum TripInterest: String, CaseIterable, Hashable, Identifiable, Sendable {
    case foodie
    case nature
    case photoSpot
    case culture
    case lifestyle
    case art
    case entertainment

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .foodie: "Foodie"
        case .nature: "Nature"
        case .photoSpot: "Photo Spot"
        case .culture: "Culture"
        case .lifestyle: "Lifestyle"
        case .art: "Art"
        case .entertainment: "Entertainment"
        }
    }

    /// SF Symbol matching the Sketch glyph.
    var systemImage: String {
        switch self {
        case .foodie: "fork.knife"
        case .nature: "tree.circle.fill"
        case .photoSpot: "camera.aperture"
        case .culture: "building.columns.fill"
        case .lifestyle: "bag.fill"
        case .art: "paintpalette.fill"
        case .entertainment: "theatermasks.fill"
        }
    }
}
