import Foundation

public enum ContextError: Error, LocalizedError, Sendable {
    case invalid(String), missingKey, provider(Int, String), budget, response
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .missingKey: "Konfigurasi provider belum tersedia."
        case .provider(let status, let code): "Provider tempat HTTP \(status) (\(code)); no automatic retry or fallback."
        case .budget: "Provider tempat request budget exhausted."
        case .response: "Provider tempat response incomplete, mismatched, or invalid."
        }
    }
}
public enum ContextJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }
}
public struct PlacesText: Codable, Sendable {
    public var text: String?
    public var languageCode: String?
    public init(text: String?, languageCode: String? = nil) { self.text = text; self.languageCode = languageCode }
}
public struct PlacesCoordinate: Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}
public struct PlacesDate: Codable, Sendable { public var year: Int?; public var month: Int?; public var day: Int? }
public struct PlacesPoint: Codable, Sendable {
    public var date: PlacesDate?; public var truncated: Bool?; public var day: Int?; public var hour: Int?; public var minute: Int?
}
public struct PlacesPeriod: Codable, Sendable { public var open: PlacesPoint?; public var close: PlacesPoint? }
public struct PlacesSpecialDay: Codable, Sendable { public var date: PlacesDate?; public var exceptionalHours: Bool? }
public struct PlacesHours: Codable, Sendable {
    public var openNow: Bool?; public var periods: [PlacesPeriod]?; public var weekdayDescriptions: [String]?
    public var specialDays: [PlacesSpecialDay]?
}
public struct PlacesTimeZone: Codable, Sendable { public var id: String?; public var version: String? }
public struct PlacesAuthor: Codable, Sendable { public var displayName: String?; public var uri: String?; public var photoUri: String? }
public struct PlacesReview: Codable, Sendable {
    public var name: String?; public var text: PlacesText?; public var originalText: PlacesText?; public var rating: Double?
    public var authorAttribution: PlacesAuthor?; public var publishTime: String?; public var visitDate: PlacesDate?; public var evidenceURI: String?
}
public struct PlacesAttribution: Codable, Sendable { public var provider: String?; public var providerUri: String? }
public struct VenuePlace: Codable, Sendable {
    public var id: String?; public var displayName: PlacesText?; public var formattedAddress: String?; public var location: PlacesCoordinate?
    public var businessStatus: String?; public var evidenceURI: String?; public var types: [String]?; public var primaryType: String?
    public var utcOffsetMinutes: Int?; public var timeZone: PlacesTimeZone?
    public var currentOpeningHours: PlacesHours?; public var regularOpeningHours: PlacesHours?
    public var rating: Double?; public var userRatingCount: Int?; public var outdoorSeating: Bool?
    public var reviews: [PlacesReview]?; public var attributions: [PlacesAttribution]?
    public init(id: String, name: String, address: String, latitude: Double, longitude: Double, types: [String] = []) {
        self.id = id; displayName = PlacesText(text: name); formattedAddress = address
        location = PlacesCoordinate(latitude: latitude, longitude: longitude); self.types = types
    }
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (65 ... 90).contains($0) || (97 ... 122).contains($0) || [45, 95, 46, 58].contains($0)
        }
    }
}
public struct PlaceSnapshot: Codable, Sendable {
    public var place: VenuePlace; public var fetchedAt: Date; public var expiresAt: Date; public var fieldMask: String
    public var source: String; public var attribution: String
    public var verifiedHours: OperatingResolution?
    public var hoursDay: String?
    public var hoursFreshUntil: Date?
    public var publicAccess: String?
    public var activity: String?
    public init(place: VenuePlace, fetchedAt: Date, fieldMask: String, source: String = "Katalog independen") {
        self.place = place; self.fetchedAt = fetchedAt; expiresAt = fetchedAt.addingTimeInterval(900); self.fieldMask = fieldMask
        self.source = source; attribution = "Sumber fakta tempat tercantum pada hasil."
    }
}
