import CryptoKit
import Foundation
import FoundationModels

public enum LabError: Error, LocalizedError, Sendable {
    case invalid(String)
    case unavailable(String)
    case timeout, stale
    public var errorDescription: String? {
        switch self {
        case .invalid(let s), .unavailable(let s): s
        case .timeout: "Operasi melewati batas 20 detik."
        case .stale: "Input telah berubah; hasil lama diabaikan."
        }
    }
}

public enum Codec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func text<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    public static func clock(_ value: String?, zone: String) -> String {
        guard let value, let date = date(value) else { return "Belum diketahui" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

public struct PlaceV1: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Double?
    public var longitude: Double?
    public var category: String
    public var address: String
    public init(
        id: String, name: String, latitude: Double? = nil, longitude: Double? = nil,
        category: String = "unknown", address: String = ""
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
        self.address = address
    }
}

public struct EvidenceV1: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var subjectID: String
    public var key: String
    public var value: String
    public var source: String
    public var observedAt: String
    public var synthetic: Bool
    public init(
        id: String, subjectID: String, key: String, value: String, source: String,
        observedAt: String, synthetic: Bool = false
    ) {
        self.id = id
        self.subjectID = subjectID
        self.key = key
        self.value = value
        self.source = source
        self.observedAt = observedAt
        self.synthetic = synthetic
    }
}

public struct VisitV1: Codable, Identifiable, Hashable, Sendable {
    public var place: PlaceV1
    public var dwellMinutes: Int
    public var exposure: String
    public var id: String { place.id }
    public init(place: PlaceV1, dwellMinutes: Int = 30, exposure: String = "unknown") {
        self.place = place
        self.dwellMinutes = dwellMinutes
        self.exposure = exposure
    }
}

public struct LegV1: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var fromID: String
    public var toID: String
    public var departure: String?
    public var arrival: String?
    public var visit: String?
    public var leave: String?
    public var travelMinutes: Double?
    public var isReturn: Bool
    public init(
        id: String, fromID: String, toID: String, departure: String? = nil,
        arrival: String? = nil, visit: String? = nil, leave: String? = nil,
        travelMinutes: Double? = nil, isReturn: Bool = false
    ) {
        self.id = id
        self.fromID = fromID
        self.toID = toID
        self.departure = departure
        self.arrival = arrival
        self.visit = visit
        self.leave = leave
        self.travelMinutes = travelMinutes
        self.isReturn = isReturn
    }
}

public struct TripContextV1: Codable, Identifiable, Sendable {
    public var schemaVersion = 1
    public var id: String
    public var revision: Int
    public var source: String
    public var synthetic: Bool
    public var generatedAt: String
    public var departure: String
    public var timeZoneID: String
    public var origin: PlaceV1
    public var endpoint: PlaceV1
    public var stops: [VisitV1]
    public var legs: [LegV1]
    public var deadline: String?
    public var complete: Bool
    public var conflicts: [String]
    public var uncertainties: [String]
    public var evidence: [EvidenceV1]
    public var finish: String?
    public var elapsedMinutes: Double?

    public func validate() throws {
        guard schemaVersion == 1, revision >= 0, !id.isEmpty, !source.isEmpty,
              TimeZone(identifier: timeZoneID) != nil, timeZoneID == "Asia/Jakarta",
              let departureDate = Codec.date(departure), Codec.date(generatedAt) != nil,
              stops.count <= 6
        else {
            throw LabError.invalid(
                "Snapshot harus satu hari di Jakarta/WIB, maksimal enam tujuan, dengan metadata valid.")
        }
        let ids = stops.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ !$0.isEmpty }),
              !ids.contains(origin.id), !ids.contains(endpoint.id), !origin.id.isEmpty,
              !endpoint.id.isEmpty, stops.allSatisfy({ (0 ... 1440).contains($0.dwellMinutes) })
        else { throw LabError.invalid("ID tujuan bertabrakan atau durasi tidak valid.") }
        if let deadline {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: timeZoneID)!
            guard let end = Codec.date(deadline), end > departureDate,
                  end <= cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: departureDate))!
            else { throw LabError.invalid("Deadline tidak sesuai dengan hari perjalanan.") }
        }
        if let elapsedMinutes, !elapsedMinutes.isFinite || elapsedMinutes < 0 {
            throw LabError.invalid("Durasi snapshot tidak valid.")
        }
        let places = [origin, endpoint] + stops.map(\.place)
        for place in places {
            guard !place.name.isEmpty else { throw LabError.invalid("Nama tempat kosong.") }
            if let lat = place.latitude, let lon = place.longitude {
                guard JakartaBoundary.contains(latitude: lat, longitude: lon) else {
                    throw LabError.invalid("Pin di luar cakupan Jakarta: \(place.name)")
                }
            } else if place.latitude != nil || place.longitude != nil {
                throw LabError.invalid("Koordinat tidak lengkap.")
            }
        }
        let known = Set(places.map(\.id))
        guard Set(legs.map(\.id)).count == legs.count,
              legs.allSatisfy({
                  known.contains($0.fromID) && known.contains($0.toID)
                      && ($0.travelMinutes.map { $0.isFinite && $0 >= 0 } ?? true)
              }),
              Set(evidence.map(\.id)).count == evidence.count,
              evidence.allSatisfy({
                  !$0.id.isEmpty && !$0.source.isEmpty && !$0.value.isEmpty
                      && Codec.date($0.observedAt) != nil
                      && (known.contains($0.subjectID) || $0.subjectID == "trip")
              })
        else { throw LabError.invalid("Ruas atau sumber snapshot tidak valid.") }
        for leg in legs {
            let timestamps = [leg.departure, leg.arrival, leg.visit, leg.leave].compactMap { $0 }
            let dates = timestamps.compactMap(Codec.date)
            guard dates.count == timestamps.count, zip(dates, dates.dropFirst()).allSatisfy({ $0 <= $1 })
            else {
                throw LabError.invalid("Timestamp ruas tidak valid atau urutannya terbalik.")
            }
        }
        if complete {
            guard legs.count == stops.count + 1, legs.first?.fromID == origin.id,
                  legs.last?.toID == endpoint.id, legs.last?.isReturn == true,
                  legs.dropLast().allSatisfy({ !$0.isReturn }),
                  legs.allSatisfy({ $0.departure != nil && $0.arrival != nil && $0.travelMinutes != nil }),
                  Set(legs.filter { !$0.isReturn }.map(\.toID)) == Set(ids),
                  zip(legs, legs.dropFirst()).allSatisfy({ $0.toID == $1.fromID }),
                  let finish, let finishDate = Codec.date(finish),
                  let lastArrival = legs.last?.arrival.flatMap(Codec.date), finishDate == lastArrival,
                  elapsedMinutes != nil
            else {
                throw LabError.invalid("Snapshot lengkap tidak mempunyai rangkaian jadwal yang konsisten.")
            }
        }
    }

    public var baselineText: String {
        let names = stops.map { $0.place.name }.joined(separator: " → ")
        let status =
            complete && conflicts.isEmpty
                ? "Memenuhi batas yang diketahui pada snapshot" : "Ada konflik atau data belum lengkap"
        return "\(status). \(names). Selesai: \(Codec.clock(finish, zone: timeZoneID)). "
            + "Deadline: \(Codec.clock(deadline, zone: timeZoneID)). Sumber: \(source). "
            + "Informasi harga, suasana dan jam yang tidak diberikan tetap belum diketahui."
    }
}

@Generable public enum Interest: String, Codable, CaseIterable, Sendable {
    case coffee, reading, quiet, indoor, outdoor, culture, food, photography
}
@Generable public enum Pace: String, Codable, CaseIterable, Sendable {
    case relaxed, balanced, packed
}
@Generable public enum VisitWindow: String, Codable, Sendable {
    case morning, midday, afternoon, evening, any, unknown
}
@Generable public struct PreferenceExtraction: Codable, Sendable {
    @Guide(
        description: "Only interests explicitly preferred in the current user's text.", .maximumCount(8)
    )
    public var interests: [Interest]
    @Guide(
        description: "Only interests explicitly avoided in the current user's text.", .maximumCount(8))
    public var avoids: [Interest]
    public var pace: Pace
    @Guide(description: "At most one needed clarification, empty if unnecessary.")
    public var clarification: String
    public init(
        interests: [Interest] = [], avoids: [Interest] = [], pace: Pace = .balanced,
        clarification: String = ""
    ) {
        self.interests = interests
        self.avoids = avoids
        self.pace = pace
        self.clarification = clarification
    }
}
@Generable public struct CandidateFit: Codable, Sendable {
    public var candidateID: String
    @Guide(description: "One short reason using supplied facts only.") public var reason: String
    @Guide(.maximumCount(4)) public var evidenceIDs: [String]
    @Guide(.maximumCount(4)) public var unknowns: [String]
    public init(candidateID: String, reason: String, evidenceIDs: [String], unknowns: [String]) {
        self.candidateID = candidateID
        self.reason = reason
        self.evidenceIDs = evidenceIDs
        self.unknowns = unknowns
    }
}
@Generable public struct CandidateAssessment: Codable, Sendable {
    @Guide(.maximumCount(3)) public var choices: [CandidateFit]
    public var note: String
    public init(choices: [CandidateFit] = [], note: String = "") {
        self.choices = choices
        self.note = note
    }
}
@Generable public struct VisitWindowSuggestion: Codable, Sendable {
    public var stopID: String
    public var window: VisitWindow
    public var reason: String
    @Guide(.maximumCount(4)) public var evidenceIDs: [String]
    public init(stopID: String, window: VisitWindow, reason: String, evidenceIDs: [String]) {
        self.stopID = stopID
        self.window = window
        self.reason = reason
        self.evidenceIDs = evidenceIDs
    }
}
@Generable public struct VisitWindowProposal: Codable, Sendable {
    @Guide(.maximumCount(6)) public var suggestions: [VisitWindowSuggestion]
    public var note: String
    public init(suggestions: [VisitWindowSuggestion] = [], note: String = "") {
        self.suggestions = suggestions
        self.note = note
    }
}
@Generable public struct ItineraryExplanation: Codable, Sendable {
    @Guide(description: "At most three sentences grounded in supplied evidence.") public var summary:
        String
    @Guide(.maximumCount(6)) public var evidenceIDs: [String]
    @Guide(.maximumCount(6)) public var unknowns: [String]
    public init(summary: String, evidenceIDs: [String] = [], unknowns: [String] = []) {
        self.summary = summary
        self.evidenceIDs = evidenceIDs
        self.unknowns = unknowns
    }
}

public struct UserDirection: Codable, Equatable, Sendable {
    public var text: String
    public var persistent: PreferenceExtraction
    public var trip: PreferenceExtraction
    public var paceOverride: Pace?
    public init(
        text: String = "", persistent: PreferenceExtraction = .init(),
        trip: PreferenceExtraction = .init(), paceOverride: Pace? = nil
    ) {
        self.text = text
        self.persistent = persistent
        self.trip = trip
        self.paceOverride = paceOverride
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        (try? Codec.encode(lhs)) == (try? Codec.encode(rhs))
    }
}
