import Foundation

extension TimingRun {
    /// Structural validation preserves old dated runs; it never refreshes their facts or re-ranks them.
    public func validate() throws {
        let success = ["regular_hours_options", "context_ranked"]
        let stopped = [
            "needs_recheck", "suspended", "hours_unknown", "closed_regular",
            "no_window", "context_unknown", "context_unavailable",
        ]
        guard schemaVersion == 1, ["visit-time-v1", "visit-time-v2"].contains(policyVersion),
              success.contains(status) || stopped.contains(status),
              createdAt.isValidTimingTimestamp,
              elapsedSeconds.isFinite, elapsedSeconds >= 0, !routingPerformed,
              request.venueID == venue.id, (15 ... 360).contains(request.durationMinutes),
              request.durationMinutes % 15 == 0, request.available.start >= 0,
              request.available.end <= 1440, request.available.start < request.available.end
        else { throw TimingError.invalid("Kontrak hasil eksperimen tidak valid.") }
        try TimingCatalog(schemaVersion: 1, id: catalogID, sources: sources, venues: [venue]).validate()
        let day = try VenueClock.day(request.date, timeZone: venue.timeZone)
        let cal = try VenueClock.calendar(venue.timeZone)
        let weekday = (cal.component(.weekday, from: day) + 5) % 7 + 1
        let schedule = venue.schedule.first { $0.weekday == weekday }
        guard options.count <= 3, Set(options.map(\.id)).count == options.count,
              success.contains(status) ? !options.isEmpty : options.isEmpty
        else { throw TimingError.invalid("Status/jumlah opsi hasil tidak konsisten.") }
        for option in options {
            guard option.start.isValidTimingTimestamp,
                  option.end.isValidTimingTimestamp, option.start < option.end,
                  abs(option.end.timeIntervalSince(option.start) - Double(request.durationMinutes * 60))
                  < 0.001,
                  option.maxRainChance.map({ $0.isFinite && (0 ... 1).contains($0) }) ?? true,
                  option.maxTemperatureC.map(\.isFinite) ?? true
            else { throw TimingError.invalid("Waktu atau pengukuran opsi tidak valid.") }
            let start = option.start.timeIntervalSince(day) / 60
            let end = option.end.timeIntervalSince(day) / 60
            guard start >= Double(request.available.start), end <= Double(request.available.end),
                  start.truncatingRemainder(dividingBy: 15) == 0,
                  let schedule,
                  schedule.sessions.contains(where: { Double($0.start) <= start && end <= Double($0.end) }),
                  schedule.lastEntry.map({ start <= Double($0) }) ?? true,
                  !schedule.entryPauses.contains(where: {
                      Double($0.start) <= start && start < Double($0.end)
                  })
            else { throw TimingError.invalid("Opsi melanggar aturan waktu tersimpan.") }
        }
        for range in validStartRanges {
            guard range.start >= request.available.start, range.start <= range.end,
                  range.end <= request.available.end - request.durationMinutes,
                  range.start % 15 == 0, range.end % 15 == 0
            else { throw TimingError.invalid("Rentang mulai hasil tidak valid.") }
        }
        guard
            zip(validStartRanges, validStartRanges.dropFirst()).allSatisfy({
                $0.0.end < $0.1.start
            })
        else { throw TimingError.invalid("Rentang mulai hasil tumpang tindih/tidak berurutan.") }
        if let weather = environment {
            guard weather.venueID == venue.id, weather.date == request.date,
                  weather.fetchedAt.isValidTimingTimestamp,
                  weather.validUntil.isValidTimingTimestamp,
                  weather.validUntil > weather.fetchedAt,
                  (-6.45 ... -6.05).contains(weather.latitude), (106.65 ... 107).contains(weather.longitude),
                  weather.sunrise.map(\.isValidTimingTimestamp) ?? true,
                  weather.sunset.map(\.isValidTimingTimestamp) ?? true,
                  weather.hours.allSatisfy({
                      $0.start.isValidTimingTimestamp
                          && ($0.rainChance.map { $0.isFinite && (0 ... 1).contains($0) } ?? true)
                          && ($0.temperatureC.map(\.isFinite) ?? true)
                  })
            else { throw TimingError.invalid("Konteks hasil tersimpan tidak valid.") }
        }
    }
}
