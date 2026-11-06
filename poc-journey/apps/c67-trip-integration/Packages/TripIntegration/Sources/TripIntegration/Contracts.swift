import Foundation
import PreferenceQuality
import VisitTiming

public enum IntegrationError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

public enum ProviderDiagnostics {
    public static func message(_ error: Error) -> String {
        var current = error as NSError
        var parts: [String] = []
        for _ in 0 ..< 4 {
            parts.append("\(current.domain) [\(current.code)]: \(current.localizedDescription)")
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError,
                  underlying !== current else { break }
            current = underlying
        }
        return String(parts.joined(separator: " → ").prefix(2000))
    }
}

public struct TripRequest: Codable, Equatable, Sendable {
    public var id = UUID()
    public var revision = 0
    public var departure: Date
    public var deadline: Date
    public var profile = QualityProfile()
    public var requiredCandidateIDs: [String] = []
    public var durationByVenue: [String: Int] = [:]
    public var defaultDuration = 60
    public var desiredCount = 3
    public var useEmbedding = true
    public var allowOpenMeteo = false
    public var goal = TimingGoal.openingOnly
    public var originQuery = "Bundaran HI Jakarta"
    public init(now: Date = .now) {
        let calendar = TripClock.calendar
        let today = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        departure = today >= now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
        deadline = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: departure)!
    }
    public func duration(_ venueID: String) -> Int { durationByVenue[venueID] ?? defaultDuration }
    public func validate(catalog: IntegrationCatalog, now: Date) throws {
        try profile.validate(catalog: catalog.quality)
        guard departure.timeIntervalSince1970.isFinite, deadline.timeIntervalSince1970.isFinite,
              departure < deadline, TripClock.day(departure) == TripClock.day(deadline),
              departure >= now,
              (1 ... 6).contains(desiredCount), (15 ... 360).contains(defaultDuration),
              defaultDuration.isMultiple(of: 15),
              durationByVenue.values.allSatisfy({ (15 ... 360).contains($0) && $0.isMultiple(of: 15) }),
              Set(durationByVenue.keys).isSubset(of: Set(catalog.timing.venues.map(\.id))),
              Set(requiredCandidateIDs).count == requiredCandidateIDs.count,
              requiredCandidateIDs.count <= 6, originQuery == "Bundaran HI Jakarta",
              requiredCandidateIDs.allSatisfy({ id in catalog.quality.candidates.contains { $0.id == id } })
        else { throw IntegrationError.invalid("Input trip tidak valid: satu hari WIB, 1–6 tempat, durasi kelipatan 15 menit. Tanggal lama tidak digeser otomatis.") }
        let venues = requiredCandidateIDs.compactMap { id in catalog.candidate(id)?.venueID }
        guard Set(venues).count == venues.count else {
            throw IntegrationError.invalid("Dua area dalam venue yang sama tidak dihitung sebagai dua destinasi. Pilih satu area.")
        }
    }
}

public enum TripClock {
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return value
    }
    public static func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func minute(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }
    public static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
    public static func label(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = calendar.timeZone
        return date.formatted(style) + " WIB"
    }
}

public struct PlaceSuggestion: Codable, Identifiable, Sendable {
    public var id: String
    public var venueID: String
    public var name: String
    public var area: String
    public var reasons: [String]
    public var issues: [String]
    public var sourceIDs: [String]
    public var timing: TimingRun?
    public var required: Bool
    public var recommended: Bool
    public var selectable: Bool { issues.isEmpty && !(timing?.validStartRanges.isEmpty ?? true) }
}

public struct RecommendationReview: Codable, Sendable {
    public var request: TripRequest
    public var quality: QualityRun
    public var suggestions: [PlaceSuggestion]
    public var warnings: [String]
}

public struct PlacePin: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    public var source = "MapKit search"
    public init(id: String, name: String, address: String, latitude: Double, longitude: Double) {
        self.id = id; self.name = name; self.address = address
        self.latitude = latitude; self.longitude = longitude
    }
}
public struct LocationReview: Codable, Identifiable, Sendable {
    public var id: String
    public var query: String
    public var candidates: [PlacePin]
    public var selected: PlacePin?
    public var manualConfirmation = false
    public var issue: String?
    public init(id: String, query: String, candidates: [PlacePin], selected: PlacePin?,
                manualConfirmation: Bool = false, issue: String? = nil) {
        self.id = id; self.query = query; self.candidates = candidates; self.selected = selected
        self.manualConfirmation = manualConfirmation; self.issue = issue
    }
}
public struct PreparedTrip: Codable, Sendable {
    public var request: TripRequest
    public var selectedIDs: [String]
    public var locations: [LocationReview]
    public var searchRequests: Int
    public var searchSeconds: Double = 0
    public var ready: Bool { locations.allSatisfy { $0.selected != nil } }
    public mutating func choose(_ pinID: String, for locationID: String) throws {
        guard let i = locations.firstIndex(where: { $0.id == locationID }),
              let pin = locations[i].candidates.first(where: { $0.id == pinID }),
              IntegrationCatalog.contains(pin)
        else { throw IntegrationError.invalid("Pin bukan hasil pencarian dalam Jakarta yang diberikan.") }
        locations[i].selected = pin
        locations[i].manualConfirmation = true
        locations[i].issue = nil
    }
}

public struct WeatherHour: Codable, Equatable, Sendable {
    public var start: Date
    public var rainChance: Double
    public var temperatureC: Double?
    public init(start: Date, rainChance: Double, temperatureC: Double? = nil) {
        self.start = start; self.rainChance = rainChance; self.temperatureC = temperatureC
    }
}
public struct WeatherCredit: Codable, Sendable {
    public var name: String
    public var legalURL: URL
    public var markLightURL: URL?
    public var markDarkURL: URL?
}
public struct WeatherEvidence: Codable, Identifiable, Sendable {
    public var id: String
    public var representative: PlacePin
    public var memberIDs: [String]
    public var provider: String
    public var status: String
    public var fetchedAt: Date
    public var retrievedAt: Date
    public var expiresAt: Date
    public var windowStart: Date
    public var windowEnd: Date
    public var hours: [WeatherHour]
    public var sunrise: Date?
    public var sunset: Date?
    public var credit: WeatherCredit?
    public var errors: [String]
    public var cached = false
    public var complete: Bool { status == "available" && credit != nil && !hours.isEmpty }
}
public struct StageMetric: Codable, Sendable {
    public var stage: String
    public var seconds: Double
    public var requests: Int
}
public struct PlannedStop: Codable, Identifiable, Sendable {
    public var id: String
    public var venueID: String
    public var name: String
    public var area: String
    public var pin: PlacePin
    public var arrival: Date
    public var visit: Date
    public var leave: Date
    public var duration: Int
    public var sourceIDs: [String]
    public var weatherProvider: String?
    public var rainChance: Double?
    public var recommendedWindows: [VisitOption]
    public var notes: [String]
}
public struct PlannedLeg: Codable, Identifiable, Sendable {
    public var id: String
    public var from: String
    public var to: String
    public var departure: Date
    public var arrival: Date?
    public var seconds: Double?
    public var providerStatus: String
}
public struct IntegratedPlan: Codable, Identifiable, Sendable {
    public var schemaVersion = 1
    public var id = UUID()
    public var evidenceMode = "live"
    public var createdAt: Date
    public var request: TripRequest
    public var prepared: PreparedTrip
    public var quality: QualityRun
    public var stops: [PlannedStop]
    public var legs: [PlannedLeg]
    public var timing: [TimingRun]
    public var weather: [WeatherEvidence]
    public var status: String
    public var conflicts: [String]
    public var uncertainties: [String]
    public var finish: Date?
    public var travelMinutes: Double
    public var waitingMinutes: Double
    public var metrics: [StageMetric]
    public var summary: String
    public var rawRoutingReport: Data?
    public var providerLog: Data? = nil
    public var baseAcceptedID: UUID?
    public var feasible: Bool { status == "ready" && conflicts.isEmpty && finish != nil }
}

public struct IntegrationSession: Codable, Sendable {
    public var schemaVersion = 1
    public var accepted: IntegratedPlan?
    public var proposal: IntegratedPlan?
    public init() {}
    public mutating func apply(now: Date = .now) throws {
        guard let proposal, proposal.feasible, proposal.baseAcceptedID == accepted?.id else {
            throw IntegrationError.invalid("Usulan belum layak atau dibuat dari versi jadwal yang sudah berubah.")
        }
        try PlanAudit.validate(proposal)
        guard proposal.request.departure >= now, proposal.createdAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(proposal.createdAt) < 900 else {
            throw IntegrationError.invalid("Usulan sudah lama atau waktu berangkat sudah lewat. Hitung ulang sebelum menerapkan.")
        }
        accepted = proposal
        self.proposal = nil
    }
}

public enum IntegrationJSON {
    public static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return value
    }
    public static func decoder() -> JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value
    }
}

public struct OperationEpoch: Sendable {
    public private(set) var current = UUID()
    public init() {}
    public mutating func invalidate() { current = UUID() }
    public func isCurrent(_ token: UUID) -> Bool { token == current }
}
