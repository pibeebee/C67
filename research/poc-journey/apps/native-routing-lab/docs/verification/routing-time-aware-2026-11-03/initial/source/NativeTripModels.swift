import CoreLocation
import Foundation

enum NativeTripMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case walking, transit, automobile
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walking: "Jalan kaki"
        case .transit: "Transit · ETA"
        case .automobile: "Mobil · ETA"
        }
    }
    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .transit: "tram"
        case .automobile: "car"
        }
    }
}

enum NativeTripCarUse: String, Codable, CaseIterable, Identifiable {
    case privateCar, onDemand
    var id: String { rawValue }
    var title: String { self == .privateCar ? "Mobil pribadi" : "Taksi / ride-hailing" }
}

enum NativeTripRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case visit, transfer
    var id: String { rawValue }
    var title: String { self == .visit ? "Kunjungan" : "Titik transfer" }
}

enum NativeTripExposure: String, CaseIterable, Codable, Identifiable, Sendable {
    case outdoor, indoor, mixed, unknown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .outdoor: "Outdoor"
        case .indoor: "Indoor"
        case .mixed: "Campuran"
        case .unknown: "Belum diketahui"
        }
    }
    var factor: Double? {
        switch self {
        case .outdoor: 1
        case .indoor: 0
        case .mixed: 0.5
        case .unknown: nil
        }
    }
}

struct NativeTripSearchRegion: Codable, Equatable, Sendable {
    var label: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double = 30_000
}

struct NativeTripPoint: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var query: String
    var latitude: Double?
    var longitude: Double?
    var resolvedName: String?
    var address: String?
    var referenceNote: String?
    var searchRegion: NativeTripSearchRegion?
    var queryAliases: [String]?
    var selectionSource: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(value) ? value : nil
    }

    func distance(to other: Self) -> Double {
        guard let a = coordinate, let b = other.coordinate else { return .infinity }
        return CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

struct NativeTripOpening: Codable, Equatable, Sendable {
    // A known opening time must not imply a made-up closing time (or vice versa).
    var opensMinute: Int? = nil
    var closesMinute: Int? = nil
    var serviceDate: String? = nil
    var timeZoneID: String? = nil
    var sourceNote: String? = nil

    var summary: String {
        let opens = opensMinute.map { "Buka \(Self.clock($0))" } ?? "Jam buka belum diisi"
        let closes = closesMinute.map { "tutup \(Self.clock($0))" } ?? "jam tutup belum diisi"
        return "\(opens) · \(closes)"
    }
    var validationMessage: String? {
        if opensMinute == nil && closesMinute == nil {
            return "Isi setidaknya jam buka atau jam tutup, atau nonaktifkan input jam operasional."
        }
        if let opensMinute, !(0 ..< 1440).contains(opensMinute) {
            return "Jam buka harus berada antara 00.00 dan 23.59."
        }
        if let closesMinute, !(1 ... 1440).contains(closesMinute) {
            return "Jam tutup harus berada setelah 00.00 hingga 24.00."
        }
        if let opensMinute, let closesMinute, closesMinute <= opensMinute {
            return "Jam tutup harus setelah jam buka pada hari yang sama."
        }
        return nil
    }

    static func dateKey(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func matchesTrip(_ departure: Date, timeZone: TimeZone) -> Bool {
        // Older drafts have no date metadata; retain their explicit manual bounds.
        (serviceDate == nil || serviceDate == Self.dateKey(departure, timeZone: timeZone))
            && (timeZoneID == nil || timeZoneID == timeZone.identifier)
    }

    func issue(for departure: Date, timeZone: TimeZone) -> String? {
        if let validationMessage { return validationMessage }
        guard matchesTrip(departure, timeZone: timeZone) else {
            return "Tanggal atau zona waktu trip berubah. Periksa dan konfirmasi ulang jam operasional."
        }
        return nil
    }

    private static func clock(_ minutes: Int) -> String {
        String(format: "%02d.%02d", minutes / 60, minutes % 60)
    }
}

struct NativeTripStop: Identifiable, Codable, Equatable, Sendable {
    var point: NativeTripPoint
    var role: NativeTripRole = .visit
    var dwellOverride: Int?
    var exposure: NativeTripExposure = .unknown
    var opening: NativeTripOpening?
    var id: String { point.id }
    func dwell(defaultMinutes: Int) -> Int { role == .transfer ? 0 : dwellOverride ?? defaultMinutes }
}

struct NativeTripDraft: Codable, Equatable, Sendable {
    var departure: Date
    var timeZoneID = TimeZone.current.identifier
    var searchContext = ""
    var origin: NativeTripPoint
    var returnsToOrigin = true
    var end: NativeTripPoint
    var stops: [NativeTripStop]
    var defaultDwell = 30
    var walking = true
    var transit = true
    // Optional for decoding drafts saved before automobile support. Never enable silently.
    var automobile: Bool? = nil
    var carUse: String? = nil
    var usesPrivateCar: Bool { automobile == true && carUse != NativeTripCarUse.onDemand.rawValue }
    var maximumWalkingMinutes = 45
    var extraWeatherMinutes = 15
    var rainWeight = 2.0
    var routingAlgorithm: String?
    var routingSeed: Int?
    var routingRequestLimit: Int?
    var routingEvaluationLimit: Int?
    var routingSecondsLimit: Double?
    var routingBeamWidth: Int?

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)! }
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }
    var endPoint: NativeTripPoint { returnsToOrigin ? origin : end }
    var endOfDay: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: departure))!
    }
    var modes: [NativeTripMode] {
        (walking ? [.walking] : []) + (transit ? [.transit] : [])
            + (automobile == true ? [.automobile] : [])
    }
    var allPoints: [NativeTripPoint] {
        var ids = Set<String>()
        return ([origin] + stops.map(\.point) + [endPoint]).filter { ids.insert($0.id).inserted }
    }
    func clockDate(minutes: Int) -> Date {
        calendar.startOfDay(for: departure).addingTimeInterval(Double(minutes) * 60)
    }
    func clockMinutes(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    func clock(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    func validate() throws {
        guard TimeZone(identifier: timeZoneID) != nil else {
            throw NativeTripError.message("Pilih zona waktu trip yang valid.")
        }
        guard
            allPoints.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw NativeTripError.message("Isi nama setiap tujuan dan titik awal/akhir.")
        }
        if let carUse, NativeTripCarUse(rawValue: carUse) == nil {
            throw NativeTripError.message("Pilihan akses mobil tidak valid.")
        }
        guard !modes.isEmpty else { throw NativeTripError.message("Pilih setidaknya satu moda.") }
        guard (1 ... 20).contains(stops.count) else {
            throw NativeTripError.message("PoC menerima 1–20 tujuan.")
        }
        guard Set(stops.map(\.id)).count == stops.count else {
            throw NativeTripError.message("ID tujuan harus unik.")
        }
        guard allPoints.allSatisfy({ $0.coordinate != nil }) else {
            throw NativeTripError.message(
                "Pilih hasil MapKit atau pin manual untuk semua tujuan dan titik awal/akhir terlebih dahulu."
            )
        }
        guard (1 ... 240).contains(defaultDwell), (5 ... 240).contains(maximumWalkingMinutes) else {
            throw NativeTripError.message("Durasi default atau batas berjalan di luar rentang PoC.")
        }
        for stop in stops {
            guard (0 ... 480).contains(stop.dwell(defaultMinutes: defaultDwell)) else {
                throw NativeTripError.message("Durasi singgah tidak valid.")
            }
            if stop.role == .visit, let opening = stop.opening,
               let issue = opening.issue(for: departure, timeZone: timeZone)
            {
                throw NativeTripError.message("\(stop.point.title): \(issue)")
            }
        }
    }
}

enum NativeTripError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
}

struct NativeTripMatch: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

struct NativeTripETA: Identifiable, Sendable {
    var id: String
    var mode: NativeTripMode
    var seconds: Double?
    var distance: Double?
    var expectedDeparture: Date?
    var expectedArrival: Date?
    var status: String
    var note: String
    var usable: Bool { seconds.map { $0.isFinite && $0 >= 0 } == true && status == "available" }
}

struct NativeTripLeg: Identifiable, Sendable {
    var id: String
    var from: NativeTripPoint
    var to: NativeTripPoint
    var departure: Date
    var arrival: Date?
    var visit: Date?
    var leave: Date?
    var dwellMinutes: Int
    var dwellSource: String
    var isReturn: Bool
    var chosen: NativeTripETA?
    var options: [NativeTripETA]
    var rainChance: Double?
    var notes: [String]
    var weatherProvider: NativeTripWeatherProvider? = nil
}

struct NativeTripCandidate: Identifiable, Sendable {
    var id: String
    var order: [String]
    var legs: [NativeTripLeg] = []
    var travelMinutes = 0.0
    var dwellMinutes = 0
    var waitingMinutes = 0.0
    var rainExposureMinutes = 0.0
    var unknownWeatherMinutes = 0.0
    var conflicts: [String] = []
    var uncertainties: [String] = []
    var finish: Date?
    var complete = false
    var feasible: Bool { complete && conflicts.isEmpty }
    var elapsedMinutes: Double { travelMinutes + waitingMinutes + Double(dwellMinutes) }
    static func better(_ a: Self, _ b: Self) -> Bool {
        if a.complete != b.complete { return a.complete }
        if a.feasible != b.feasible { return a.feasible }
        if a.conflicts.count != b.conflicts.count { return a.conflicts.count < b.conflicts.count }
        if a.elapsedMinutes != b.elapsedMinutes { return a.elapsedMinutes < b.elapsedMinutes }
        if a.travelMinutes != b.travelMinutes { return a.travelMinutes < b.travelMinutes }
        return a.order.lexicographicallyPrecedes(b.order)
    }
}

struct NativeTripReport: Sendable {
    var draft: NativeTripDraft
    var candidates: [NativeTripCandidate]
    var fastest: NativeTripCandidate?
    var weatherChoice: NativeTripCandidate?
    var forecasts: [NativeTripForecast]
    var requests: Int
    var generatedAt = Date()
    var weatherNote: String
    var optimizerNote: String? = nil
    var status: String {
        guard let fastest else { return "Data rute belum mencukupi" }
        return fastest.feasible ? "Draf tersedia · periksa data bersyarat" : "Belum memenuhi batas trip"
    }
}

extension NativeTripDraft {
    static func japanExample() -> Self {
        let origin = NativeTripPoint(
            id: "origin", title: "Stasiun Funabashi", query: "JR Funabashi Station Chiba Japan",
            searchRegion: .init(label: "Funabashi, Chiba", latitude: 35.70, longitude: 139.98))
        let definitions: [(String, String, String, NativeTripRole, NativeTripExposure, String?)] = [
            ("P01", "Cape Inamuragasaki", "鎌倉海浜公園 稲村ガ崎地区 鎌倉市", .visit, .outdoor, nil),
            ("P02", "Stasiun Inamuragasaki", "稲村ヶ崎駅 鎌倉市", .transfer, .outdoor, nil),
            (
                "P03", "Toko Suvenir Enoshima Station", "江ノ島駅 江ノ島電鉄 藤沢市", .visit, .mixed,
                "Toko belum dipilih. Stasiun hanya titik pendekatan area; pilih toko yang dimaksud untuk memperjelas lokasi."
            ),
            ("P04", "Enoshima Ohashi Bridge", "江の島大橋 藤沢市", .visit, .outdoor, nil),
            ("P05", "Enoshima Sea Candle", "江の島シーキャンドル 神奈川県藤沢市", .visit, .mixed, nil),
            ("P06", "Stasiun Kamakurakokomae · foto", "鎌倉高校前駅 鎌倉市", .visit, .outdoor, nil),
            ("P07", "Tsurugaoka Hachimangu", "鶴岡八幡宮 鎌倉市", .visit, .outdoor, nil),
            ("P08", "Shichirigahama Beach", "七里ヶ浜海岸 鎌倉市", .visit, .outdoor, nil),
            ("P09", "Fujisawa City Tourist Center", "藤沢市観光センター 片瀬海岸2-20-13", .visit, .indoor, nil),
            (
                "P10", "Stasiun Fujisawa · menara jam", "藤沢駅 神奈川県藤沢市", .visit, .outdoor,
                "Titik menara jam belum dipastikan; stasiun hanya referensi area."
            ),
            ("P11", "Stasiun Enoshima", "江ノ島駅 江ノ島電鉄 藤沢市", .transfer, .outdoor, nil),
            (
                "P12", "Oiwayamichi Street", "中村屋羊羹店 江の島2丁目5-25", .visit, .outdoor,
                "Nakamuraya adalah titik referensi jalan dari konteks sebelumnya, bukan penggantian aktivitas menjadi kunjungan toko."
            ),
            ("P13", "Stasiun Katase-Enoshima", "片瀬江ノ島駅 藤沢市", .transfer, .outdoor, nil),
            ("P14", "Komachi Street", "小町通り 鎌倉市", .visit, .outdoor, nil),
            ("P15", "Stasiun Kamakura", "鎌倉駅 神奈川県鎌倉市", .transfer, .outdoor, nil),
        ]
        let aliases: [String: String] = [
            "P01": "Inamuragasaki Park, Kamakura, Japan", "P02": "Inamuragasaki Station, Kamakura, Japan",
            "P03": "Enoshima Station, Fujisawa, Japan", "P04": "Enoshima Ohashi Bridge, Fujisawa, Japan",
            "P05": "Enoshima Sea Candle, Fujisawa, Japan",
            "P06": "Kamakurakokomae Station, Kamakura, Japan",
            "P07": "Tsurugaoka Hachimangu, Kamakura, Japan",
            "P08": "Shichirigahama Beach, Kamakura, Japan",
            "P09": "Fujisawa City Tourist Center, Katasekaigan, Japan", "P10": "Fujisawa Station, Japan",
            "P11": "Enoshima Station, Fujisawa, Japan", "P12": "Nakamuraya, Enoshima, Japan",
            "P13": "Katase-Enoshima Station, Fujisawa, Japan", "P14": "Komachi Street, Kamakura, Japan",
            "P15": "Kamakura Station, Japan",
        ]
        let stops = definitions.map { id, title, query, role, exposure, note in
            NativeTripStop(
                point: .init(
                    id: id, title: title, query: query, referenceNote: note,
                    searchRegion: .init(
                        label: "Kamakura–Enoshima", latitude: 35.32, longitude: 139.50, radiusMeters: 20_000),
                    queryAliases: aliases[id].map { [$0] }), role: role,
                exposure: exposure)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 7))!
        return Self(
            departure: date, timeZoneID: "Asia/Tokyo", origin: origin,
            end: .init(id: "end", title: "Titik akhir", query: ""),
            stops: stops)
    }
}
