import Foundation

public struct CatalogCheck: Decodable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var status: String
    public var must: Bool
    public var reason: String
    public var evidence: [String]
    public var sourceURL: String
    public var checkedAt: String
    public var explanation: String {
        switch reason {
        case "missing_evidence": "Informasi untuk memastikan kegiatan ini belum tersedia."
        case "conflicting_sources": "Ada informasi yang saling bertentangan."
        case "conditions_require_verification": "Ada ketentuan yang masih perlu diperiksa untuk kunjungan Anda."
        case "stale_source": "Informasi sudah perlu diperiksa kembali."
        case "dated_hours_not_available": "Jam untuk tanggal dan durasi kunjungan belum dapat dipastikan."
        case "source_and_models_agree": "Penilaian sesuai dengan bukti yang tercatat."
        case "explicit_source_prohibition": "Sumber mencatat batasan yang bertentangan dengan kegiatan ini."
        default: "Informasi belum cukup konsisten untuk memastikan kegiatan ini."
        }
    }
}

public struct CatalogPlace: Decodable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var category: String
    public var address: String
    public var sourceURL: String
    public var latitude: Double
    public var longitude: Double
    public var checks: [CatalogCheck]
    public var status: String
    public var checkedAt: String
    public var regularHours: String?
    public var checkedDateLabel: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: checkedAt) ?? ISO8601DateFormatter().date(from: checkedAt) else {
            return "Belum diketahui"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
    public var categoryLabel: String {
        switch category {
        case "cafe": "Kafe atau kedai kopi"
        case "library": "Perpustakaan atau ruang baca"
        case "book_store": "Toko buku"
        default: "Tempat"
        }
    }
    public var statusLabel: String {
        switch status {
        case "supported": "Kebutuhan yang diperiksa didukung bukti"
        case "conflict": "Ada preferensi yang belum cocok"
        default: "Sebagian kebutuhan belum bisa dipastikan"
        }
    }
}

public struct CatalogResponse: Decodable, Sendable {
    public var requestID: UUID
    public var revision: Int
    public var places: [CatalogPlace]
    public var warnings: [String]
    public var scope: String
    public var runID: String
    public var seconds: Double
    public var totalPlaces: Int
    public var excludedCount: Int
    public var notice: String
    public var pipeline: String
}
