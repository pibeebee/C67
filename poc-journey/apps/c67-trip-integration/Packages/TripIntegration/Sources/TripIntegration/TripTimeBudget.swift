import Foundation

public struct TripTimeBudget: Sendable {
    public var visitMinutes: Int
    public var availableMinutes: Double
    public var remainingMinutes: Double { availableMinutes - Double(visitMinutes) }
    public var visitsExceedBudget: Bool { remainingMinutes < 0 }
    public var message: String {
        if visitsExceedBudget {
            return "Kunjungan memerlukan \(visitMinutes) menit, sedangkan waktu tersedia \(Int(availableMinutes)) menit. Tambah waktu trip atau ubah durasi/pilihan tempat."
        }
        return "Setelah \(visitMinutes) menit kunjungan, tersisa \(Int(remainingMinutes)) menit untuk perjalanan, walking, tunggu bus dan pulang."
    }

    public static func evaluate(_ request: TripRequest, selectedIDs: [String], catalog: IntegrationCatalog) -> Self {
        let venues = Set(selectedIDs.compactMap { catalog.candidate($0)?.venueID })
        let minutes = selectedIDs.isEmpty ? request.desiredCount * request.defaultDuration
            : venues.reduce(0) { $0 + request.duration($1) }
        return .init(visitMinutes: minutes, availableMinutes: max(0, request.deadline.timeIntervalSince(request.departure) / 60))
    }
}
