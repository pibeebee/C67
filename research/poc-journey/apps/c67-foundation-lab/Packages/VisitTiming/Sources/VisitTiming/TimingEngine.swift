import Foundation

public struct VisitTimingEngine: Sendable {
    public init() {}
    public func evaluate(
        _ input: TimingRequest, catalog: TimingCatalog,
        environment: TimingEnvironment? = nil, now: Date = .now
    ) throws -> TimingRun {
        guard now.isValidTimingTimestamp else {
            throw TimingError.invalid("Jam evaluasi tidak valid.")
        }
        try catalog.validate()
        guard let venue = catalog.venues.first(where: { $0.id == input.venueID }),
              (15 ... 360).contains(input.durationMinutes), input.durationMinutes % 15 == 0,
              input.available.start >= 0, input.available.end <= 1440,
              input.available.start < input.available.end
        else { throw TimingError.invalid("Tempat, rentang atau durasi tidak valid.") }
        let cal = try VenueClock.calendar(venue.timeZone)
        let day = try VenueClock.day(input.date, timeZone: venue.timeZone)
        let sources = catalog.sources.filter { venue.sourceIDs.contains($0.id) }
        let sanitized = Self.sanitizedEnvironment(environment, venue: venue, date: input.date, now: now)
        let weather = sanitized.value
        var run = TimingRun(
            createdAt: now, catalogID: catalog.id, request: input, venue: venue,
            sources: sources, environment: weather, status: "unknown", options: [],
            validStartRanges: [],
            warnings: [
                "Durasi \(input.durationMinutes) menit adalah asumsi perencanaan yang dapat diubah, bukan fakta durasi venue.",
                "Jadwal reguler belum memverifikasi kapasitas, tiket, hari libur atau perubahan mendadak.",
            ] + sanitized.warnings)
        func stopped(_ status: String, _ message: String) -> TimingRun {
            var result = run
            result.status = status
            result.warnings.append(message)
            return result
        }
        // Snapshot facts may not establish historical opening or far-future availability.
        guard sources.allSatisfy({ $0.checkedAt <= now.addingTimeInterval(300) }),
              sources.allSatisfy({ now.timeIntervalSince($0.checkedAt) <= 7 * 86400 }),
              sources.allSatisfy({
                  day >= cal.startOfDay(for: $0.checkedAt)
                      && day < cal.startOfDay(for: $0.checkedAt).addingTimeInterval(8 * 86400)
              })
        else {
            return stopped(
                "needs_recheck",
                "Snapshot fakta di luar batas pemeriksaan tujuh hari; periksa sumber terbaru.")
        }
        if day < cal.startOfDay(for: now) {
            return stopped(
                "no_window", "Tanggal rencana sudah berlalu; gunakan hasil tersimpan untuk riwayat.")
        }
        if venue.suspended {
            return stopped("suspended", venue.notice ?? "Pengumuman penutupan perlu diperiksa kembali.")
        }
        let weekday = (cal.component(.weekday, from: day) + 5) % 7 + 1
        guard let schedule = venue.schedule.first(where: { $0.weekday == weekday }) else {
            return stopped(
                "hours_unknown", "Jam untuk hari ini tidak dipublikasikan pada sumber yang dipakai.")
        }
        guard !schedule.sessions.isEmpty else {
            return stopped("closed_regular", "Hari tutup menurut jadwal reguler yang dipublikasikan.")
        }
        func absolute(_ minute: Int) -> Date { day.addingTimeInterval(Double(minute * 60)) }
        var starts: [Int] = []
        let today = VenueClock.dateString(now, timeZone: venue.timeZone)
        for session in schedule.sessions.sorted(by: { $0.start < $1.start }) {
            let first = max(session.start, input.available.start)
            let last = min(session.end, input.available.end) - input.durationMinutes
            guard first <= last else { continue }
            for minute in stride(from: ((first + 14) / 15) * 15, through: last, by: 15) {
                if let limit = schedule.lastEntry, minute > limit { continue }
                if schedule.entryPauses.contains(where: { minute >= $0.start && minute < $0.end }) {
                    continue
                }
                if input.date == today,
                   absolute(minute) < now
                {
                    continue
                }
                starts.append(minute)
            }
        }
        guard !starts.isEmpty else {
            return stopped(
                "no_window",
                "Tidak ada waktu mulai yang memenuhi rentang, durasi, aturan masuk dan sesi layanan.")
        }
        for minute in starts {
            if let previous = run.validStartRanges.last, previous.end + 15 == minute {
                run.validStartRanges[run.validStartRanges.count - 1].end = minute
            } else {
                run.validStartRanges.append(.init(minute, minute))
            }
        }
        if input.goal != .openingOnly && venue.exposure != "outdoor" {
            return stopped(
                "context_unknown",
                "Konteks aktivitas luar ruang belum bersumber untuk tempat ini; gunakan jam layanan.")
        }
        var options: [(minute: Int, score: Double, value: VisitOption)] = []
        for minute in starts {
            let start = absolute(minute)
            let end = absolute(minute + input.durationMinutes)
            let coverage = Self.weatherCoverage(weather, start: start, end: end)
            var score = Double(minute)
            var reason =
                "Memenuhi jadwal reguler dan aturan masuk; belum ada dasar untuk menyebutnya waktu terbaik."
            switch input.goal {
            case .openingOnly: break
            case .lowerRain:
                guard let rain = coverage.rain else { continue }
                score = rain
                reason =
                    "Diurutkan menurut peluang hujan maksimum sepanjang kunjungan; tanpa jaminan bebas hujan."
            case .daylight:
                guard let sunrise = weather?.sunrise, let sunset = weather?.sunset,
                      VenueClock.dateString(sunrise, timeZone: venue.timeZone) == input.date,
                      VenueClock.dateString(sunset, timeZone: venue.timeZone) == input.date,
                      start >= sunrise, end <= sunset
                else { continue }
                reason =
                    "Seluruh durasi berada di antara sunrise dan sunset provider; kondisi terang di lokasi tidak dijamin."
            case .nearSunset:
                guard let sunset = weather?.sunset,
                      VenueClock.dateString(sunset, timeZone: venue.timeZone) == input.date,
                      start >= sunset.addingTimeInterval(-3600), start <= sunset
                else { continue }
                score = abs(end.timeIntervalSince(sunset))
                reason =
                    "Mulai dalam satu jam menjelang sunset; kedekatan akhir kunjungan dengan sunset adalah aturan aplikasi."
            }
            options.append(
                (
                    minute, score,
                    .init(
                        start: start, end: end, maxRainChance: coverage.rain,
                        maxTemperatureC: coverage.temperature, reason: reason)
                ))
        }
        if options.isEmpty {
            return stopped(
                input.goal == .openingOnly ? "no_window" : "context_unavailable",
                "Tidak ada slot yang dapat mendukung tujuan waktu ini dengan data yang tersedia; jam layanan tetap terlihat."
            )
        }
        options.sort { $0.score == $1.score ? $0.minute < $1.minute : $0.score < $1.score }
        // Show separated alternatives; preserve all allowed start ranges for inspection.
        var selected: [VisitOption] = []
        for option in options {
            if selected.allSatisfy({ abs($0.start.timeIntervalSince(option.value.start)) >= 3600 }) {
                selected.append(option.value)
            }
            if selected.count == 3 { break }
        }
        run.options = selected
        run.status = input.goal == .openingOnly ? "regular_hours_options" : "context_ranked"
        if input.goal == .nearSunset {
            run.warnings.append(
                "Sunset bukan jaminan golden hour, pandangan matahari atau izin fotografi; belum ada fakta tersebut."
            )
        }
        if input.goal != .openingOnly {
            run.warnings.append(
                "Prakiraan adalah perkiraan titik MapKit, bukan pengukuran mikrocuaca di venue.")
        }
        return run
    }

    static func weatherCoverage(_ value: TimingEnvironment?, start: Date, end: Date)
        -> (rain: Double?, temperature: Double?)
    {
        guard let value, start.isValidTimingTimestamp,
              end.isValidTimingTimestamp, start < end,
              value.hours.allSatisfy({ $0.start.isValidTimingTimestamp })
        else { return (nil, nil) }
        let hours = value.hours.sorted { $0.start < $1.start }
        guard
            zip(hours, hours.dropFirst()).allSatisfy({
                $0.0.start.addingTimeInterval(3600) <= $0.1.start
            })
        else { return (nil, nil) }
        var cursor = start
        var rain: [Double] = []
        var temperature: [Double] = []
        while cursor < end {
            guard
                let hour = hours.first(where: {
                    $0.start <= cursor && cursor < $0.start.addingTimeInterval(3600)
                }), let chance = hour.rainChance, chance.isFinite, (0 ... 1).contains(chance)
            else { return (nil, nil) }
            rain.append(chance)
            if let t = hour.temperatureC, t.isFinite { temperature.append(t) }
            cursor = min(end, hour.start.addingTimeInterval(3600))
        }
        return (rain.max(), temperature.count == rain.count ? temperature.max() : nil)
    }

    /// Validate the common envelope before any early venue/date return, then isolate bad components.
    static func sanitizedEnvironment(
        _ input: TimingEnvironment?, venue: VenueFacts,
        date: String, now: Date
    ) -> (value: TimingEnvironment?, warnings: [String]) {
        guard var value = input else { return (nil, []) }
        let invalid =
            "Prakiraan kedaluwarsa/tidak sesuai tempat, tanggal atau koordinat; tidak dipakai sebagai konteks."
        guard value.fetchedAt.isValidTimingTimestamp,
              value.validUntil.isValidTimingTimestamp,
              value.venueID == venue.id, value.date == date,
              value.fetchedAt <= now.addingTimeInterval(300),
              value.validUntil > value.fetchedAt, value.validUntil > now,
              now.timeIntervalSince(value.fetchedAt) < 900,
              (-6.45 ... -6.05).contains(value.latitude), (106.65 ... 107.0).contains(value.longitude),
              !value.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.attributionURL.scheme?.lowercased() == "https",
              value.attributionURL.host?.isEmpty == false
        else { return (nil, [invalid]) }
        value.validUntil = min(value.validUntil, value.fetchedAt.addingTimeInterval(900))
        var warnings: [String] = []
        if value.hours.contains(where: { !$0.start.isValidTimingTimestamp }) {
            value.hours = []
            warnings.append("Timestamp prakiraan per jam tidak valid; komponen per jam tidak digunakan.")
        } else {
            value.hours.sort { $0.start < $1.start }
            if !zip(value.hours, value.hours.dropFirst()).allSatisfy({
                $0.0.start.addingTimeInterval(3600) <= $0.1.start
            }) {
                value.hours = []
                warnings.append(
                    "Interval prakiraan duplikat/tumpang tindih; komponen per jam tidak digunakan.")
            }
        }
        for index in value.hours.indices {
            if let rain = value.hours[index].rainChance, !rain.isFinite || !(0 ... 1).contains(rain) {
                value.hours[index].rainChance = nil
                warnings.append("Nilai peluang hujan tidak valid diperlakukan sebagai belum diketahui.")
            }
            if let temperature = value.hours[index].temperatureC, !temperature.isFinite {
                value.hours[index].temperatureC = nil
                warnings.append("Suhu tidak valid diperlakukan sebagai belum diketahui.")
            }
        }
        func validSolar(_ event: Date?) -> Date? {
            guard let event, event.isValidTimingTimestamp,
                  VenueClock.dateString(event, timeZone: venue.timeZone) == date
            else { return nil }
            return event
        }
        value.sunrise = validSolar(value.sunrise)
        value.sunset = validSolar(value.sunset)
        if let rise = value.sunrise, let set = value.sunset, rise >= set {
            value.sunrise = nil
            value.sunset = nil
            warnings.append("Urutan sunrise/sunset bertentangan; komponen matahari tidak digunakan.")
        }
        // De-duplicate diagnostics without depending on Set ordering.
        var seen = Set<String>()
        return (value, warnings.filter { seen.insert($0).inserted })
    }
}

extension TimingRun {
    public var markdown: String {
        let sourceLines = sources.map {
            "- [\($0.title)](\($0.url.absoluteString)); diperiksa \($0.checkedAt.ISO8601Format()); \($0.method)"
        }.joined(separator: "\n")
        let optionLines = options.map {
            "- \(VenueClock.label($0.start))–\(VenueClock.label($0.end)) WIB: \($0.reason)"
        }.joined(separator: "\n")
        return """
        # Waktu Kunjung — \(venue.name)

        Run: \(id). Tanggal: \(request.date), \(venue.timeZone). Status: \(status).
        Policy: \(policyVersion). Durasi asumsi: \(request.durationMinutes) menit.
        Tujuan: \(request.goal.label). Routing: tidak dilakukan.

        \(optionLines.isEmpty ? "Belum ada usulan waktu." : optionLines)

        ## Batas dan ketidakpastian

        \(warnings.map { "- " + $0 }.joined(separator: "\n"))
        \(venue.unknowns.map { "- Belum diketahui: " + $0 }.joined(separator: "\n"))

        ## Sumber fakta

        \(sourceLines)

        Prakiraan: \(environment?.provider ?? "tidak dipakai").
        \(environment?.attribution ?? "")
        """
    }
}

public actor TimingStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(_ run: TimingRun) throws {
        let data = try checkedData(run)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(
            to: directory.appendingPathComponent("\(run.id).json"), options: .atomic)
    }
    public func history() throws -> (runs: [TimingRun], unreadable: Int) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], 0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var runs: [TimingRun] = []
        var unreadable = 0
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            do {
                let run = try decoder.decode(TimingRun.self, from: Data(contentsOf: url))
                try run.validate()
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == run.id else {
                    throw TimingError.invalid("Identitas berkas riwayat tidak sesuai.")
                }
                runs.append(run)
            } catch {
                unreadable += 1
            }
        }
        return (runs.sorted { $0.createdAt > $1.createdAt }, unreadable)
    }
    public func export(_ run: TimingRun) throws -> URL {
        let data = try checkedData(run)
        let folder = directory.appendingPathComponent("Exports/\(run.id)")
        let jsonURL = folder.appendingPathComponent("run.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            try requireSameRun(at: jsonURL, data: data)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: jsonURL, options: .atomic)
        try Data(run.markdown.utf8).write(
            to: folder.appendingPathComponent("REPORT.md"), options: .atomic)
        return folder
    }
    private func checkedData(_ run: TimingRun) throws -> Data {
        try run.validate()
        let data = try encoder().encode(run)
        let existing = directory.appendingPathComponent("\(run.id).json")
        if FileManager.default.fileExists(atPath: existing.path) {
            try requireSameRun(at: existing, data: data)
        }
        return data
    }
    private func requireSameRun(at path: URL, data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let previous = try decoder.decode(TimingRun.self, from: Data(contentsOf: path))
        try previous.validate()
        guard try encoder().encode(previous) == data else {
            throw TimingError.invalid(
                "ID eksperimen sudah dipakai hasil berbeda; berkas lama dipertahankan.")
        }
    }
    private func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys, .prettyPrinted]
        return value
    }
}
