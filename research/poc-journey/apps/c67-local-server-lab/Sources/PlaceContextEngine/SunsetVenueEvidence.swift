import Foundation

/// Source-backed venue metadata for the pilot. Search and opening hours still come from the providers.
public enum SunsetVenueEvidence {
    public static let placeID = "ChIJjcjh8Lkfai4RGhTBaOVFCNw"
    public static let sourceName = "Jakarta Tourism · Pantai Ancol"
    public static let sourceURL = URL(string: "https://enjoy.jakarta.go.id/article/ancol-jakarta")!

    public static func discoveryQuery(area: String) -> String? {
        guard area.range(of: #"\bancol\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return "Pantai Indah Ancol Jakarta"
    }

    /// Do not accept businesses that merely include the beach name in their own name.
    public static func beachNameMatch(placeID: String, appleName: String, separationMeters: Double) -> Bool? {
        let names: Set<String>
        switch placeID {
        case Self.placeID: names = ["pantai indah", "pantai indah ancol", "indah beach", "indah beach ancol"]
        case "ChIJlbPSLzweai4RnJzpPilccgg": names = ["pantai festival", "pantai festival ancol", "festival beach", "festival beach ancol"]
        default: return nil
        }
        let words = appleName.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        return (0 ... 100).contains(separationMeters) && names.contains(words)
    }

}
