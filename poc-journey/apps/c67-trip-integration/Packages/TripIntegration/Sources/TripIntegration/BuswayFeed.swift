import Foundation

public enum TripTransport: String, Codable, CaseIterable, Sendable, Identifiable {
    case automobile, transjakartaBRT
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automobile: "Mobil/taksi"
        case .transjakartaBRT: "TransJakarta + jalan"
        }
    }
}

public struct BuswaySource: Codable, Equatable, Sendable {
    public var id: String
    public var sourceURL: URL
    public var attributionURL: URL
    public var licenseURL: URL
    public var publisher: String
    public var checkedAt: Date
    public var lastModified: String
    public var sourceSHA256: String
    public var modification: String
    public func validate() throws {
        guard !id.isEmpty, publisher == "PT Transportasi Jakarta", !modification.isEmpty,
              sourceURL.absoluteString == "https://gtfs.transjakarta.co.id/files/file_gtfs.zip",
              licenseURL.absoluteString == "https://creativecommons.org/licenses/by/4.0/",
              attributionURL.absoluteString == "https://ppid.transjakarta.co.id/informasi/berkala",
              sourceSHA256.count == 64, sourceSHA256.allSatisfy(\.isHexDigit),
              checkedAt.timeIntervalSince1970.isFinite else {
            throw IntegrationError.invalid("Atribusi/sumber GTFS tidak valid.")
        }
    }
}

public struct BuswayService: Codable, Equatable, Sendable {
    public var id: String
    public var startDate: String
    public var endDate: String
    public var weekdays: [Int]
    public func operates(on date: Date) -> Bool {
        let day = TripClock.day(date).replacingOccurrences(of: "-", with: "")
        let weekday = (TripClock.calendar.component(.weekday, from: date) + 5) % 7 + 1
        return startDate <= day && day <= endDate && weekdays.contains(weekday)
    }
}

public struct BuswayStop: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var parentStation: String
    public var platform: String
    public var pin: PlacePin {
        var value = PlacePin(id: id, name: name, address: "Halte/platform GTFS TransJakarta",
                             latitude: latitude, longitude: longitude)
        value.source = "Published TransJakarta GTFS boarding coordinate"
        return value
    }
}

public struct BuswayFrequency: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var headway: Int
    public var exactTimes: Int
}

public struct BuswayCall: Codable, Equatable, Sendable {
    public var stopID: String
    public var sequence: Int
    public var arrivalOffset: Int
    public var departureOffset: Int
    public var pickupAllowed: Bool? = nil
    public var dropOffAllowed: Bool? = nil
}

public struct BuswayPattern: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var serviceID: String
    public var headsign: String
    public var directionID: String
    public var shapeID: String
    public var calls: [BuswayCall]
    public var frequencies: [BuswayFrequency]
    public var routeID: String? = nil
    public var category: String? = nil
    public var effectiveRouteID: String { routeID ?? "1" }
    public var effectiveCategory: String { category ?? "BRT" }
}

public struct BuswayTransfer: Codable, Equatable, Sendable {
    public var fromStopID: String
    public var toStopID: String
    public var minimumSeconds: Double
    public var evidence: String
}

public struct BuswayFeed: Codable, Sendable {
    public var schemaVersion: Int
    public var source: BuswaySource
    public var agencyID: String
    public var routeID: String
    public var routeName: String
    public var category: String
    public var timeZone: String
    public var stops: [BuswayStop]
    public var services: [BuswayService]
    public var patterns: [BuswayPattern]
    public var transfers: [BuswayTransfer]? = nil

    public static func network() throws -> Self {
        guard let url = Bundle.module.url(forResource: "transjakarta-network", withExtension: "json") else {
            throw IntegrationError.invalid("Snapshot jaringan TJ belum tersedia.")
        }
        let feed = try IntegrationJSON.decoder().decode(Self.self, from: Data(contentsOf: url))
        try feed.validate()
        return feed
    }

    public static func load() throws -> Self {
        guard let url = Bundle.module.url(forResource: "transjakarta-corridor-1", withExtension: "json") else {
            throw IntegrationError.invalid("Snapshot GTFS TransJakarta belum tersedia.")
        }
        let feed = try IntegrationJSON.decoder().decode(Self.self, from: Data(contentsOf: url))
        try feed.validate()
        return feed
    }

    public func validate() throws {
        try source.validate()
        let stopIDs = Set(stops.map(\.id))
        let serviceIDs = Set(services.map(\.id))
        let legacy = schemaVersion == 1 && routeID == "1" && category == "BRT"
        let network = schemaVersion == 2 && routeID == "network" && category == "TJ"
        guard (legacy || network), agencyID == "Tije",
              timeZone == "Asia/Jakarta", !source.id.isEmpty,
              source.sourceURL.absoluteString == "https://gtfs.transjakarta.co.id/files/file_gtfs.zip",
              source.licenseURL.absoluteString == "https://creativecommons.org/licenses/by/4.0/",
              source.attributionURL.absoluteString == "https://ppid.transjakarta.co.id/informasi/berkala",
              source.sourceSHA256.count == 64, source.sourceSHA256.allSatisfy(\.isHexDigit),
              source.checkedAt.timeIntervalSince1970.isFinite,
              !stops.isEmpty, stopIDs.count == stops.count,
              stops.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && IntegrationCatalog.contains($0.pin) }),
              serviceIDs.count == services.count, !services.isEmpty,
              services.allSatisfy({ service in
                  service.startDate.count == 8 && service.endDate.count == 8
                      && service.startDate.allSatisfy(\.isNumber) && service.endDate.allSatisfy(\.isNumber)
                      && service.startDate <= service.endDate && !service.weekdays.isEmpty
                      && service.weekdays.allSatisfy { (1 ... 7).contains($0) }
              }),
              !patterns.isEmpty, Set(patterns.map(\.id)).count == patterns.count else {
            throw IntegrationError.invalid("Identitas/sumber snapshot GTFS tidak valid.")
        }
        for pattern in patterns {
            guard serviceIDs.contains(pattern.serviceID), pattern.calls.count >= 2,
                  ["0", "1"].contains(pattern.directionID), !pattern.headsign.isEmpty,
                  pattern.calls.first?.departureOffset == 0,
                  pattern.calls.allSatisfy({ stopIDs.contains($0.stopID) && $0.arrivalOffset <= $0.departureOffset
                          && (0 ... 172800).contains($0.departureOffset) }),
                  zip(pattern.calls, pattern.calls.dropFirst()).allSatisfy({
                      $0.sequence < $1.sequence && $0.departureOffset <= $1.arrivalOffset
                  }),
                  (legacy || (pattern.routeID?.isEmpty == false && ["BRT", "Angkutan Umum Integrasi", "Mikrotrans", "Royaltrans", "Rusun", "Bus Wisata", "Transjabodetabek"].contains(pattern.effectiveCategory))),
                  !pattern.frequencies.isEmpty,
                  pattern.frequencies.allSatisfy({ $0.exactTimes == 0 && $0.start >= 0 && $0.start < $0.end
                          && $0.end <= 172800 && (1 ... 86400).contains($0.headway) }) else {
                throw IntegrationError.invalid("Pola/frekuensi GTFS tidak valid: \(pattern.id).")
            }
        }
        guard (transfers ?? []).allSatisfy({
            stopIDs.contains($0.fromStopID) && stopIDs.contains($0.toStopID)
                && $0.minimumSeconds.isFinite && (120 ... 1200).contains($0.minimumSeconds)
                && !$0.evidence.isEmpty
        }) else { throw IntegrationError.invalid("Bukti transfer TJ tidak valid.") }
    }

    public func requireFresh(at now: Date) throws {
        guard now.timeIntervalSince1970.isFinite, source.checkedAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(source.checkedAt) < 7 * 86400 else {
            throw IntegrationError.invalid("Snapshot GTFS perlu diperbarui. Batas pemeriksaan POC adalah tujuh hari.")
        }
    }
}

public struct BuswayWalk: Codable, Sendable {
    public var from: PlacePin
    public var to: PlacePin
    public var seconds: Double
    public var distanceMeters: Double
    public var provider: String
    public init(from: PlacePin, to: PlacePin, seconds: Double, distanceMeters: Double, provider: String) {
        self.from = from; self.to = to; self.seconds = seconds; self.distanceMeters = distanceMeters; self.provider = provider
    }
}

public struct BuswayRide: Codable, Sendable {
    public var pattern: BuswayPattern
    public var patternID: String
    public var headsign: String
    public var directionID: String
    public var board: BuswayStop
    public var alight: BuswayStop
    public var boardSequence: Int
    public var alightSequence: Int
    public var boardOffset: Int
    public var alightOffset: Int
    public var service: BuswayService
    public var serviceDay: Date
    public var frequency: BuswayFrequency
    public var boardAt: Date
    public var alightAt: Date
}

public struct BuswayConnection: Codable, Sendable {
    public var walk: BuswayWalk
    public var bufferSeconds: Double
    public var evidence: String
    public var ride: BuswayRide
}

public struct BuswayJourney: Codable, Sendable {
    public var source: BuswaySource
    public var departure: Date
    public var arrival: Date
    public var access: BuswayWalk
    public var ride: BuswayRide?
    public var egress: BuswayWalk?
    public var connection: BuswayConnection? = nil
    public var rides: [BuswayRide] { (ride.map { [$0] } ?? []) + (connection.map { [$0.ride] } ?? []) }
    public var walks: [BuswayWalk] { [access] + (connection.map { [$0.walk] } ?? []) + (egress.map { [$0] } ?? []) }
    public var seconds: Double { arrival.timeIntervalSince(departure) }
    public var walkingSeconds: Double { walks.reduce(0) { $0 + $1.seconds } }
    public var waitingSeconds: Double { seconds - walkingSeconds - ridingSeconds }
    public var ridingSeconds: Double { rides.reduce(0) { $0 + $1.alightAt.timeIntervalSince($1.boardAt) } }
    public var summary: String {
        guard let ride else { return "Jalan kaki penuh · \(Int(ceil(walkingSeconds / 60))) menit" }
        let route = rides.map { "\($0.pattern.effectiveRouteID) arah \($0.headsign)" }.joined(separator: " → ")
        let last = rides.last ?? ride
        return "Koridor \(route) · \(ride.board.name) [\(ride.board.id)] → \(last.alight.name) [\(last.alight.id)]. "
            + "Jalan \(Int(ceil(walkingSeconds / 60))) menit, buffer tunggu \(Int(ceil(waitingSeconds / 60))) menit, bus \(Int(ceil(ridingSeconds / 60))) menit."
    }

    public func validate() throws {
        try source.validate()
        if let connection {
            guard let ride, let egress, connection.bufferSeconds.isFinite,
                  (120 ... 1200).contains(connection.bufferSeconds), !connection.evidence.isEmpty,
                  connection.walk.from.latitude == ride.alight.latitude, connection.walk.from.longitude == ride.alight.longitude,
                  connection.walk.to.latitude == connection.ride.board.latitude, connection.walk.to.longitude == connection.ride.board.longitude,
                  connection.walk.seconds.isFinite, (0 ... 1200).contains(connection.walk.seconds) else {
                throw IntegrationError.invalid("Bukti perpindahan bus tidak valid.")
            }
            let firstExit = BuswayWalk(from: ride.alight.pin, to: ride.alight.pin, seconds: 0, distanceMeters: 0, provider: access.provider)
            let first = BuswayJourney(source: source, departure: departure, arrival: ride.alightAt, access: access, ride: ride, egress: firstExit)
            try first.validate()
            let nextDeparture = ride.alightAt.addingTimeInterval(connection.bufferSeconds)
            let second = BuswayJourney(source: source, departure: nextDeparture, arrival: arrival,
                                       access: connection.walk, ride: connection.ride, egress: egress)
            try second.validate()
            return
        }
        let walks = [access] + (egress.map { [$0] } ?? [])
        guard departure.timeIntervalSince1970.isFinite, arrival.timeIntervalSince1970.isFinite,
              seconds.isFinite, seconds >= 0, !source.id.isEmpty,
              walks.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 && $0.distanceMeters.isFinite && $0.distanceMeters >= 0
                      && IntegrationCatalog.contains($0.from) && IntegrationCatalog.contains($0.to)
                      && ["mapkit_walking", "apple_maps_rest_walking", "google_routes_walking", "valhalla_osm_walking", "synthetic_walking"].contains($0.provider) }) else {
            throw IntegrationError.invalid("Bukti jalan kaki/GTFS tidak valid.")
        }
        if let ride {
            guard let egress, ride.patternID.hasPrefix(ride.pattern.effectiveRouteID + "-"), ride.service.operates(on: ride.serviceDay),
                  ride.patternID == ride.pattern.id, ride.pattern.serviceID == ride.service.id,
                  ride.headsign == ride.pattern.headsign, ride.directionID == ride.pattern.directionID,
                  ["0", "1"].contains(ride.directionID), ride.pattern.frequencies.contains(ride.frequency),
                  ride.pattern.calls.contains(where: { $0.sequence == ride.boardSequence && $0.stopID == ride.board.id && $0.departureOffset == ride.boardOffset && $0.pickupAllowed != false }),
                  ride.pattern.calls.contains(where: { $0.sequence == ride.alightSequence && $0.stopID == ride.alight.id && $0.arrivalOffset == ride.alightOffset && $0.dropOffAllowed != false }),
                  TripClock.calendar.startOfDay(for: ride.serviceDay) == ride.serviceDay,
                  ride.frequency.start >= 0, ride.frequency.start < ride.frequency.end, ride.frequency.end <= 172800,
                  ride.boardSequence < ride.alightSequence, ride.board.id != ride.alight.id,
                  ride.boardOffset < ride.alightOffset, ride.frequency.exactTimes == 0,
                  ride.frequency.headway > 0,
                  access.to.latitude == ride.board.latitude, access.to.longitude == ride.board.longitude,
                  egress.from.latitude == ride.alight.latitude, egress.from.longitude == ride.alight.longitude,
                  access.seconds <= 1200, egress.seconds <= 1200,
                  abs(ridingSeconds - Double(ride.alightOffset - ride.boardOffset)) < 1.01,
                  abs(arrival.timeIntervalSince(ride.alightAt) - egress.seconds) < 1.01 else {
                throw IntegrationError.invalid("Halte, arah atau perhitungan durasi bus tidak valid.")
            }
            let start = ride.serviceDay.addingTimeInterval(Double(ride.frequency.start + ride.boardOffset))
            let end = ride.serviceDay.addingTimeInterval(Double(ride.frequency.end + ride.boardOffset))
            let expected = max(departure.addingTimeInterval(access.seconds), start)
                .addingTimeInterval(Double(ride.frequency.headway))
            guard ride.boardAt < end, abs(ride.boardAt.timeIntervalSince(expected)) < 1.01 else {
                throw IntegrationError.invalid("Buffer headway atau jam layanan bus tidak valid.")
            }
        } else {
            guard egress == nil, access.seconds <= 1200, abs(seconds - access.seconds) < 1.01 else {
                throw IntegrationError.invalid("Durasi berjalan penuh tidak konsisten.")
            }
        }
    }
}

public enum BuswayAssumptions {
    public static let notes = [
        "POC jaringan TJ Jakarta dengan rute langsung atau satu transfer ketika rute langsung tidak tersedia. Platform dicari sesuai arah dalam 800 m dan tiap komponen jalan kaki dibatasi 20 menit.",
        "Transfer memakai kandidat GTFS, walking tervalidasi dan buffer tambahan dua menit. Maksimal 64 kandidat per tahap dan 128 query walking per kalkulasi; hasil merupakan pencarian terbatas.",
        "GTFS static, exact_times=0. Buffer tunggu satu headway penuh setelah akses/awal layanan, ditambah waktu bus dari offset GTFS. Bukan prediksi kedatangan bus live.",
        "Calendar mingguan GTFS digunakan. Feed tidak menyediakan calendar_dates untuk pengecualian hari libur. Perubahan rute dan kondisi halte perlu diperiksa.",
        "Koordinat boarding GTFS dan walking MapKit belum membuktikan akses pintu masuk, penyeberangan, aksesibilitas atau kondisi lapangan.",
        "Durasi perjalanan mencakup jalan, buffer bus dan waktu di bus. Metrik waitingMinutes hanya menunggu jam kunjungan tempat.",
    ]
}
