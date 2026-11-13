import Foundation

@MainActor enum NativeTripEngine {
    // Coordinates generate candidates only. Actual MapKit travel time selects the result.
    // This bounded heuristic does not claim a globally shortest, time-dependent route.
    static func orders(_ draft: NativeTripDraft) -> [[NativeTripStop]] {
        var remaining = draft.stops
        var greedy: [NativeTripStop] = []
        var from = draft.origin
        while !remaining.isEmpty {
            remaining.sort { a, b in
                let x = from.distance(to: a.point)
                let y = from.distance(to: b.point)
                return x == y ? a.id < b.id : x < y
            }
            let next = remaining.removeFirst()
            greedy.append(next)
            from = next.point
        }
        func length(_ order: [NativeTripStop]) -> Double {
            var current = draft.origin
            var meters = 0.0
            for stop in order {
                meters += current.distance(to: stop.point)
                current = stop.point
            }
            return meters + current.distance(to: draft.endPoint)
        }
        func polished(_ seed: [NativeTripStop]) -> [NativeTripStop] {
            var value = seed
            guard value.count > 2 else { return value }
            for _ in 0 ..< 2 {
                var improved = false
                for i in 0 ..< (value.count - 1) {
                    for j in (i + 1) ..< value.count {
                        var next = value
                        next.replaceSubrange(i ... j, with: value[i ... j].reversed())
                        if length(next) + 1 < length(value) {
                            value = next
                            improved = true
                        }
                    }
                }
                if !improved { break }
            }
            return value
        }
        let first = polished(greedy)
        let seeds = [first, polished(Array(first.reversed()))]
        var signatures = Set<String>()
        return seeds.filter { signatures.insert($0.map(\.id).joined(separator: ",")).inserted }
    }

    private static func rain(_ forecast: NativeTripForecast?, start: Date, end: Date, factor: Double?)
        -> (wet: Double, unknown: Double, chance: Double?)
    {
        let total = max(0, end.timeIntervalSince(start)) / 60
        if total == 0 || factor == 0 { return (0, 0, nil) }
        guard let factor else { return (0, total, nil) }
        var known = 0.0
        var expected = 0.0
        for hour in forecast?.hours ?? [] {
            let overlap =
                max(
                    0, min(end, hour.date.addingTimeInterval(3600)).timeIntervalSince(max(start, hour.date)))
                / 60
            guard hour.rainChance.isFinite, (0 ... 1).contains(hour.rainChance) else { continue }
            known += overlap
            expected += overlap * hour.rainChance
        }
        return (
            expected * factor, max(0, total - known), known >= total - 0.001 ? expected / total : nil
        )
    }

    static func evaluate(
        _ order: [NativeTripStop], draft: NativeTripDraft, services: NativeTripAppleServices,
        forecasts: [NativeTripForecast], progress: (String) -> Void
    ) async throws -> NativeTripCandidate {
        if draft.usesPrivateCar {
            var variants: [NativeTripCandidate] = []
            var car = draft
            car.carUse = NativeTripCarUse.onDemand.rawValue
            car.walking = false; car.transit = false
            variants.append(try await evaluate(order, draft: car, services: services, forecasts: forecasts, progress: progress))
            if draft.walking || draft.transit {
                var noCar = draft
                noCar.automobile = false
                variants.append(try await evaluate(order, draft: noCar, services: services, forecasts: forecasts, progress: progress))
            }
            var best = variants.min(by: NativeTripCandidate.better)!
            best.uncertainties.append("Mobil pribadi memakai mobil untuk seluruh ruas atau tanpa mobil. Parkir lalu berjalan kaki dalam subtrip belum dimodelkan.")
            return best
        }
        var result = NativeTripCandidate(
            id: order.map(\.id).joined(separator: "/"), order: order.map(\.id))
        let weather = Dictionary(
            forecasts.map { ($0.pointID, $0) }, uniquingKeysWith: { first, _ in first })
        var cursor = draft.departure
        var from = draft.origin
        var targets = order
        targets.append(NativeTripStop(point: draft.endPoint, role: .transfer))
        for (index, stop) in targets.enumerated() {
            try Task.checkCancellation()
            progress("Ruas \(index + 1)/\(targets.count): \(from.title) → \(stop.point.title)")
            let options = try await services.options(
                from: from, to: stop.point, departure: cursor, draft: draft)
            let chosen = options.filter(\.usable).sorted { a, b in
                if a.seconds == b.seconds { return a.mode == .walking && b.mode != .walking }
                return a.seconds! < b.seconds!
            }.first
            let dwell = stop.dwell(defaultMinutes: draft.defaultDwell)
            var leg = NativeTripLeg(
                id: "\(result.id):\(index)", from: from, to: stop.point, departure: cursor,
                dwellMinutes: dwell,
                dwellSource: stop.role == .transfer
                    ? "transfer" : stop.dwellOverride == nil ? "default" : "pengguna",
                isReturn: index == order.count, chosen: chosen, options: options, notes: [])
            guard let chosen, let seconds = chosen.seconds else {
                leg.notes.append(
                    "Tidak ada moda terpilih yang dapat dipakai pada ruas ini. Periksa lokasi, ketersediaan layanan, batas berjalan, atau aktifkan pilihan mobil di Pengaturan bila sesuai perjalanan Anda."
                )
                result.legs.append(leg)
                result.conflicts.append(
                    "Data transportasi belum cukup: \(from.title) → \(stop.point.title).")
                return result
            }
            let arrival = cursor.addingTimeInterval(seconds)
            var visit = arrival
            if stop.role == .visit, let opening = stop.opening {
                if let opens = opening.opensMinute {
                    visit = max(arrival, draft.clockDate(minutes: opens))
                }
                if let closes = opening.closesMinute,
                   visit.addingTimeInterval(Double(dwell) * 60) > draft.clockDate(minutes: closes)
                {
                    result.conflicts.append("\(stop.point.title): melewati jam tutup yang dimasukkan.")
                }
                leg.notes.append("\(opening.summary). Input manual untuk tanggal trip, zona \(draft.timeZoneID).")
                if let note = opening.sourceNote, !note.isEmpty {
                    leg.notes.append("Catatan sumber jam operasional: \(note)")
                }
                if opening.opensMinute == nil {
                    result.uncertainties.append("Jam buka \(stop.point.title) belum diisi.")
                }
                if opening.closesMinute == nil {
                    result.uncertainties.append("Jam tutup \(stop.point.title) belum diisi.")
                }
            } else if stop.role == .visit {
                leg.notes.append(
                    "Jam operasional belum diisi; tempat ini belum dipastikan dapat dikunjungi pada waktu kedatangan."
                )
                result.uncertainties.append("Jam operasional \(stop.point.title) belum diisi.")
            }
            let leave = visit.addingTimeInterval(Double(dwell) * 60)
            if stop.point.selectionSource == "Pin manual pengguna" {
                let note =
                    "\(stop.point.title): koordinat dipilih pengguna; kecocokan nama belum diverifikasi oleh pencarian MapKit."
                leg.notes.append(note)
                result.uncertainties.append(note)
            }
            leg.arrival = arrival
            leg.visit = visit
            leg.leave = leave
            if let reference = stop.point.referenceNote {
                leg.notes.append(reference)
                result.uncertainties.append(reference)
            }
            let visitRain = rain(
                weather[stop.point.id], start: arrival, end: leave, factor: stop.exposure.factor)
            leg.rainChance = visitRain.chance
            leg.weatherProvider = weather[stop.point.id]?.provider
            let travelRain = rain(
                weather[stop.point.id], start: cursor, end: arrival,
                factor: chosen.mode == .walking ? 1 : nil)
            result.rainExposureMinutes += visitRain.wet + travelRain.wet
            result.unknownWeatherMinutes += visitRain.unknown + travelRain.unknown
            if chosen.mode == .transit {
                leg.notes.append(
                    "ETA transit tersedia; detail berjalan/menunggu dan paparan cuaca saat transfer belum tersedia."
                )
                result.uncertainties.append("Detail dan paparan cuaca transit belum diketahui.")
            }
            if chosen.mode == .automobile {
                leg.notes.append(chosen.note)
                result.uncertainties.append(
                    "Waktu parkir, akses kendaraan dan paparan di luar mobil belum diketahui.")
            }
            result.travelMinutes += seconds / 60
            result.dwellMinutes += dwell
            result.waitingMinutes += visit.timeIntervalSince(arrival) / 60
            result.legs.append(leg)
            cursor = leave
            from = stop.point
            if cursor > draft.endOfDay {
                result.conflicts.append(
                    "Melewati batas trip satu hari. Sisa tujuan tetap ada pada input; jadwal tidak dipangkas agar muat."
                )
                return result
            }
        }
        result.finish = cursor
        result.complete = true
        let seen = result.legs.filter { !$0.isReturn }.map { $0.to.id }
        guard seen.count == draft.stops.count, Set(seen) == Set(draft.stops.map(\.id)),
              result.legs.last?.to.id == draft.endPoint.id
        else {
            throw NativeTripError.message("Kandidat tidak mempertahankan semua tujuan atau ruas kembali.")
        }
        let computed = result.travelMinutes + Double(result.dwellMinutes) + result.waitingMinutes
        guard abs(cursor.timeIntervalSince(draft.departure) / 60 - computed) < 0.01 else {
            throw NativeTripError.message("Perhitungan waktu kandidat tidak konsisten.")
        }
        return result
    }

    static func plan(
        _ draft: NativeTripDraft, services: NativeTripAppleServices, progress: (String) -> Void
    ) async throws -> NativeTripReport {
        try draft.validate()
        if draft.selectedRoutingAlgorithm != .baseline {
            return try await NativeTripRoutingBridge.plan(draft, services: services, progress: progress)
        }
        services.resetRun()
        let forecasts = try await services.forecasts(
            points: draft.allPoints, draft: draft, progress: progress)
        try Task.checkCancellation()
        progress("Menyusun kandidat urutan")
        let alternatives = orders(draft)
        services.event(
            "plan.candidates", category: "planner",
            fields: [
                "orders": alternatives.map { $0.map(\.id).joined(separator: " → ") }.joined(
                    separator: " | ")
            ])
        var candidates: [NativeTripCandidate] = []
        for (index, order) in alternatives.enumerated() {
            try Task.checkCancellation()
            await Task.yield()
            candidates.append(
                try await evaluate(order, draft: draft, services: services, forecasts: forecasts) {
                    progress("Kandidat \(index + 1)/\(alternatives.count) · \($0)")
                })
        }
        for candidate in candidates {
            services.event(
                "plan.candidate_result", category: "planner",
                fields: [
                    "order": candidate.order.joined(separator: " → "), "complete": String(candidate.complete),
                    "feasible": String(candidate.feasible), "travelMinutes": String(candidate.travelMinutes),
                    "rainExposureMinutes": String(candidate.rainExposureMinutes),
                    "unknownWeatherMinutes": String(candidate.unknownWeatherMinutes),
                    "finish": candidate.finish?.ISO8601Format() ?? "unknown",
                    "conflicts": candidate.conflicts.joined(separator: " | "),
                    "uncertainties": candidate.uncertainties.joined(separator: " | "),
                ])
        }
        let complete = candidates.filter(\.complete).sorted {
            NativeTripCandidate.better($0, $1)
        }
        let fastest = complete.first
        let weatherCandidates = complete.filter { candidate in
            guard let fastest, fastest.feasible else { return false }
            return candidate.feasible && candidate.unknownWeatherMinutes < 0.001
                && candidate.travelMinutes <= fastest.travelMinutes + Double(draft.extraWeatherMinutes)
                && candidate.finish!
                <= fastest.finish!.addingTimeInterval(Double(draft.extraWeatherMinutes * 60))
        }
        let weatherChoice = weatherCandidates.min { a, b in
            a.elapsedMinutes + a.rainExposureMinutes * draft.rainWeight < b.elapsedMinutes + b
                .rainExposureMinutes * draft.rainWeight
        }
        let weatherNote =
            weatherChoice == nil
                ? "Rekomendasi cuaca ditunda: prakiraan, paparan transit, atau kandidat layak belum lengkap. Prakiraan per tempat yang tersedia tetap dapat dilihat."
                : "Pilihan cuaca membandingkan menit perjalanan dan perkiraan paparan hujan. Bobot dan batas tambahan waktu adalah asumsi PoC, bukan tambahan ETA akibat hujan."
        services.event(
            "plan.weather_decision", category: "planner",
            fields: [
                "fastest": fastest?.id ?? "none", "weatherChoice": weatherChoice?.id ?? "none",
                "note": weatherNote,
            ])
        return .init(
            draft: draft, candidates: candidates, fastest: fastest, weatherChoice: weatherChoice,
            forecasts: forecasts, requests: services.directionRequests, weatherNote: weatherNote)
    }
}
