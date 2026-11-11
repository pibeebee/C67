import SwiftUI
import PreferenceQuality

// Semantic surfaces adapt to appearance. Brand values follow the C67 reference.
enum JourneyTheme {
    static let blue = Color(red: 26 / 255, green: 78 / 255, blue: 234 / 255)
    static let mint = Color(red: 25 / 255, green: 235 / 255, blue: 160 / 255)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Gabarito-Regular", size: size, relativeTo: style)
    }
}
struct JourneyPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(JourneyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct JourneyPrimaryButton: View {
    let title: String
    let id: String
    var symbol = "arrow.right"
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(JourneyTheme.font(17).weight(.semibold))
                Spacer()
                Image(systemName: symbol)
            }.padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.white)
            .background(disabled ? Color.secondary : JourneyTheme.blue, in: RoundedRectangle(cornerRadius: 16))
            .disabled(disabled).accessibilityIdentifier(id)
    }
}
struct JourneyInfo: View {
    let symbol: String
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(JourneyTheme.blue).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(JourneyTheme.font(17))
            }
        }
    }
}
extension QualityFeature {
    var journeyTitle: String {
        switch self {
        case .coffee: "Ngopi"
        case .wifi: "Wi-Fi"
        case .reading: "Membaca"
        case .quietPolicy: "Zona hening"
        case .outdoor: "Luar ruang"
        case .nature: "Taman & alam"
        case .art: "Seni"
        case .culture: "Budaya"
        case .smokingArea: "Area merokok"
        }
    }
    var journeySymbol: String {
        switch self {
        case .coffee: "cup.and.saucer"
        case .wifi: "wifi"
        case .reading: "book"
        case .quietPolicy: "speaker.slash"
        case .outdoor: "sun.max"
        case .nature: "leaf"
        case .art: "paintpalette"
        case .culture: "building.columns"
        case .smokingArea: "wind"
        }
    }
}
