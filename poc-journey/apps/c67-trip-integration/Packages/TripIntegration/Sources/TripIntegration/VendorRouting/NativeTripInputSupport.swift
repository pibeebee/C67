import CoreLocation
import Foundation

enum NativeTripLocationSelection {
    static func automaticMatch(
        _ matches: [NativeTripMatch], point: NativeTripPoint, context: String,
        requireExactName: Bool = false
    ) -> NativeTripMatch? {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let exact = matches.filter { normalized($0.name) == normalized(point.title) }
        guard let match = matches.count == 1 ? matches.first : exact.count == 1 ? exact.first : nil
        else {
            return nil
        }
        if requireExactName {
            // A nearby street or another branch is not proof of the requested venue.
            let names = [point.title, point.query] + (point.queryAliases ?? [])
            guard matches.count == 1, names.contains(where: { normalized($0) == normalized(match.name) })
            else {
                return nil
            }
        }
        if let region = point.searchRegion {
            let distance = CLLocation(latitude: region.latitude, longitude: region.longitude).distance(
                from: CLLocation(latitude: match.latitude, longitude: match.longitude))
            return distance <= region.radiusMeters ? match : nil
        }
        // A unique or exact name is not sufficient: "Kota Tua" also exists in Sumatra.
        let area = context.split(separator: ",").first.map { normalized(String($0)) } ?? ""
        guard !area.isEmpty, normalized(match.address).contains(area) else { return nil }
        return match
    }
}

enum NativeTripListInput {
    static let maximumStops = 20

    static func names(from text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.replacingOccurrences(
                of: #"^(?:[0-9]+[.)]\s+|[-*•]\s+)"#, with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
    }

    static func searchQuery(name: String, context: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !context.isEmpty,
              name.range(of: context, options: [.caseInsensitive, .diacriticInsensitive]) == nil
        else { return name }
        return "\(name), \(context)"
    }

    static func stops(from names: [String], existingCount: Int) throws -> [NativeTripStop] {
        guard !names.isEmpty else { throw NativeTripError.message("Isi setidaknya satu nama tempat.") }
        guard existingCount + names.count <= maximumStops else {
            throw NativeTripError.message(
                "Maksimum \(maximumStops) tujuan. Tersisa \(max(0, maximumStops - existingCount)) tempat; daftar belum ditambahkan."
            )
        }
        return names.map { name in
            NativeTripStop(point: .init(id: UUID().uuidString, title: name, query: name))
        }
    }
}

extension NativeTripDraft {
    var locationWarnings: [String] {
        let points = allPoints.filter { $0.coordinate != nil }
        guard points.count > 1 else { return [] }
        return points.compactMap { point in
            let nearest = points.filter { $0.id != point.id }.map { point.distance(to: $0) }.min()!
            guard nearest > 200_000 else { return nil }
            return
                "Periksa pin \(point.title): \(point.address ?? point.resolvedName ?? "alamat belum tersedia"). Titik terdekat dalam rencana berjarak sekitar \(Int(nearest / 1000)) km."
        }
    }

    static func jakarta(now: Date = Date()) -> Self {
        var value = Self.empty(now: now, timeZone: TimeZone(identifier: "Asia/Jakarta")!)
        value.configureJakarta()
        return value
    }

    mutating func configureJakarta() {
        changeTimeZone(to: "Asia/Jakarta")
        planningArea = "jakarta"
        searchContext = NativeTripJakarta.context
        walking = false
        transit = false
        automobile = true
        carUse = NativeTripCarUse.onDemand.rawValue
        routingAlgorithm = "hybrid"
        routingAdaptive = true
        routingRequestLimit = 512
        origin.searchRegion = NativeTripJakarta.region
        end.searchRegion = NativeTripJakarta.region
        for index in stops.indices { stops[index].point.searchRegion = NativeTripJakarta.region }
    }

    static func jakartaFivePlaces(now: Date = Date()) -> Self {
        var value = Self.jakarta(now: now)
        let day = value.calendar.date(byAdding: .day, value: 1, to: now)!
        value.departure = value.calendar.startOfDay(for: day).addingTimeInterval(8 * 3600)
        value.finishBy = value.calendar.startOfDay(for: day).addingTimeInterval(18 * 3600)
        value.origin = .init(
            id: "origin", title: "Stasiun Sudirman", query: "Stasiun Sudirman",
            latitude: -6.2023912, longitude: 106.8234359, resolvedName: "Stasiun Sudirman",
            address: "Jalan Kendal No. 1, Jakarta Pusat", searchRegion: NativeTripJakarta.region,
            selectionSource: "Pin dari log pengguna 4 November 2026; periksa sebelum perjalanan")
        let places: [(String, String, Double, Double)] = [
            ("monas", "Monas", -6.1753936, 106.827186),
            ("kotatua", "Kota Tua", -6.1347997, 106.8130414),
            ("glodok", "Jalan Pasar Glodok Selatan", -6.1434347, 106.815066),
            ("ashta", "Ashta", -6.229714, 106.807101),
            ("blokm", "Blok M Square", -6.2445743, 106.8006164),
        ]
        value.stops = places.map { id, name, latitude, longitude in
            .init(
                point: .init(
                    id: id, title: name, query: name, latitude: latitude,
                    longitude: longitude, resolvedName: name,
                    address: "Jakarta; pin dari log 4 November 2026",
                    searchRegion: NativeTripJakarta.region,
                    selectionSource: "Pin dari log pengguna 4 November 2026; periksa sebelum perjalanan"))
        }
        return value
    }

    static func empty(now: Date = Date(), timeZone: TimeZone = .current) -> Self {
        Self(
            departure: now, timeZoneID: timeZone.identifier,
            origin: .init(id: "origin", title: "Titik awal", query: ""),
            end: .init(id: "end", title: "Titik akhir", query: ""), stops: [])
    }

    func searchQuery(for point: NativeTripPoint, using alternative: String? = nil) -> String {
        NativeTripListInput.searchQuery(
            name: alternative ?? point.query,
            context: isJakartaProfile ? NativeTripJakarta.context : searchContext)
    }

    mutating func appendPlaces(_ text: String) throws {
        let additions = try NativeTripListInput.stops(
            from: NativeTripListInput.names(from: text), existingCount: stops.count)
        stops.append(
            contentsOf: additions.map { stop in
                var value = stop
                if isJakartaProfile { value.point.searchRegion = NativeTripJakarta.region }
                return value
            })
    }

    mutating func changeTimeZone(to identifier: String) {
        guard let zone = TimeZone(identifier: identifier) else { return }
        let wallClock = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: departure)
        let deadlineClock = finishBy.map {
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        var next = Calendar(identifier: .gregorian)
        next.timeZone = zone
        timeZoneID = identifier
        if let date = next.date(from: wallClock) { departure = date }
        if let deadlineClock { finishBy = next.date(from: deadlineClock) }
    }
}

/// Native launch must not depend on opening the historical group-trip database.
enum NativeTripLaunchRouting {
    static func usesNativePlanner(arguments: [String]) -> Bool {
        if arguments.contains("--native-itinerary") { return true }
        let legacyEntryFlags = [
            "--legacy-poc", "--diary-demo", "--diary-ui-testing", "--ui-testing", "--demo-preview",
        ]
        return !legacyEntryFlags.contains(where: arguments.contains)
    }
}
