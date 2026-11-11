import Foundation

/// Explicit catalog coverage, not a claim of complete venue coverage in an area.
public enum TripArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case blokM, cikini, tebet, senayan, kemang, kebonJeruk, ragunan, kuningan
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .blokM: "Blok M"
        case .cikini: "Cikini"
        case .tebet: "Tebet"
        case .senayan: "Senayan / SCBD"
        case .kemang: "Kemang"
        case .kebonJeruk: "Kebon Jeruk"
        case .ragunan: "Ragunan"
        case .kuningan: "Kuningan"
        }
    }
    public func contains(_ candidateID: String) -> Bool {
        switch self {
        case .blokM: candidateID.hasPrefix("bm")
        case .cikini: ["cikini", "bakoel-cikini"].contains(candidateID)
        case .tebet: candidateID.hasPrefix("bdt-")
        case .senayan: ["gbk", "ashta-reading"].contains(candidateID)
        case .kemang: ["newsroom", "dialogue"].contains(candidateID)
        case .kebonJeruk: candidateID.hasPrefix("macan-")
        case .ragunan: candidateID == "ragunan"
        case .kuningan: candidateID == "erasmus"
        }
    }
}

extension TripRequest {
    public func includesArea(candidateID: String) -> Bool {
        (targetAreas ?? []).isEmpty || targetAreas!.contains { $0.contains(candidateID) }
    }
}
