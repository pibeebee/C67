import Foundation
import PreferenceQuality
import VisitTiming

@MainActor public final class IntegrationPipeline {
    public let catalog: IntegrationCatalog
    private let quality: QualityPipeline
    private let search: any TripPlaceSearching
    public let weather: TripWeatherCoordinator
    private let logDirectory: URL
    private var routing: NativeTripAppleServices?
    var labFast = false
    var labSelective = false
    var labBulk = false
    var labIsREST = false
    var labBatch: (@MainActor ([LabETAQuery]) async throws -> [LabETAValue])?
    // Test-only explicit injection; no synthetic defaults in the app's normal entry point.
    var replayETA: (@MainActor (NativeTripPoint, NativeTripPoint, NativeTripMode, Date) async throws -> NativeTripETA)?
    public init(catalog: IntegrationCatalog, quality: QualityPipeline = .init(),
                search: any TripPlaceSearching = MapKitTripSearch(),
                weather: TripWeatherCoordinator = .init(), logDirectory: URL? = nil) {
        self.catalog = catalog; self.quality = quality; self.search = search; self.weather = weather
        self.logDirectory = logDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                                     in: .userDomainMask)[0].appendingPathComponent("C67TripIntegration-v1/ProviderLogs")
    }
    public func cancel() { search.cancel(); routing?.cancel() }

    public func recommend(_ request: TripRequest, now: Date = .now,
                          progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> RecommendationReview {
        try request.validate(catalog: catalog, now: now)
        let result = try await quality.run(profile: request.profile, catalog: catalog.quality,
                                           useEmbedding: request.useEmbedding, now: now, progress: progress)
        try Task.checkCancellation()
        let ranked = result.combined.isEmpty ? result.category : result.combined
        let ordered = request.requiredCandidateIDs + ranked.map(\.id).filter { !request.requiredCandidateIDs.contains($0) }
        let ids = ordered + result.decisions.map(\.id).filter { !ordered.contains($0) }
        var suggestions: [PlaceSuggestion] = []
        var usedVenues = Set<String>()
        var recommended = 0
        for id in ids {
            guard let candidate = catalog.candidate(id), let decision = result.decisions.first(where: { $0.id == id }) else { continue }
            var issues = decision.state == "eligible" ? [] : decision.reasons + ["Status fakta: \(decision.state)."]
            let timing = try catalog.timingRun(candidateID: id, request: request, now: now)
            if timing == nil { issues.append("Jam layanan bersumber belum tersedia untuk venue ini.") }
            if let timing, timing.validStartRanges.isEmpty { issues += ["Waktu kunjung belum layak: \(timing.status)."] + timing.warnings }
            if result.status == "preference_review_required" { issues.append("Konfirmasi arahan melalui preferensi terstruktur dahulu.") }
            let canPropose = issues.isEmpty && !usedVenues.contains(candidate.venueID) && recommended < request.desiredCount
            if canPropose { usedVenues.insert(candidate.venueID); recommended += 1 }
            suggestions.append(.init(id: id, venueID: candidate.venueID, name: candidate.name,
                                     area: candidate.scope, reasons: decision.reasons + (ranked.first { $0.id == id }?.supportedPreferences.map { "Disukai dan bersumber: \($0.label)." } ?? []),
                                     issues: issues, sourceIDs: candidate.sourceIDs, timing: timing,
                                     required: request.requiredCandidateIDs.contains(id), recommended: canPropose))
        }
        // Keep blocked/unknown candidates inspectable, but never silently replace required selections.
        let missingRequired = request.requiredCandidateIDs.filter { id in !suggestions.contains { $0.id == id } }
        guard missingRequired.isEmpty else { throw IntegrationError.invalid("Tujuan wajib hilang dari hasil preferensi: \(missingRequired).") }
        return .init(request: request, quality: result, suggestions: suggestions,
                     warnings: result.warnings + [
                         "Katalog lokal terbatas; MapKit memverifikasi lokasi, bukan sumber preferensi/jam layanan.",
                         "Tanpa tujuan utama, semua tempat yang Anda pilih tetap setara dan dipertahankan.",
                         "Waktu pilihan P1 adalah saran per tempat; optimasi rute tidak menjamin seluruh saran tercapai.",
                     ])
    }

    public func prepare(_ review: RecommendationReview, selectedIDs: [String], now: Date = .now,
                        progress: (String) -> Void = { _ in }) async throws -> PreparedTrip {
        let began = Date()
        try review.request.validate(catalog: catalog, now: now)
        guard (1 ... 6).contains(selectedIDs.count), Set(selectedIDs).count == selectedIDs.count,
              Set(review.request.requiredCandidateIDs).isSubset(of: Set(selectedIDs)) else {
            throw IntegrationError.invalid("Pilih 1–6 tempat; seluruh tujuan wajib harus dipertahankan.")
        }
        let selected = try selectedIDs.map { id in
            guard let item = review.suggestions.first(where: { $0.id == id }), item.selectable else {
                throw IntegrationError.invalid("Tujuan \(id) belum memenuhi fakta/waktu. Perbaiki input atau sumber; tujuan tidak dihapus otomatis.")
            }
            return item
        }
        guard Set(selected.map(\.venueID)).count == selected.count else {
            throw IntegrationError.invalid("Pilih satu area per venue untuk itinerary ini.")
        }
        var locations: [LocationReview] = []
        var requests = 0
        let definitions = [("origin", review.request.originQuery, ["bundaran", "hi"], Optional<String>.none)]
            + selected.map { item in
                let candidate = catalog.candidate(item.id)!
                let branch: String? = item.venueID == "cikini" ? "cikini" : item.venueID == "bdt" ? "tebet" : nil
                return (item.id, candidate.mapQuery, candidate.matchWords, branch)
            }
        for (id, query, words, branch) in definitions {
            try Task.checkCancellation()
            progress("Mencari lokasi: \(query)")
            requests += 1
            do {
                let results = try await search.search(query: query)
                try Task.checkCancellation()
                locations.append(PlaceIdentityPolicy.review(id: id, query: query, words: words, branch: branch, results: results))
            } catch {
                try Task.checkCancellation()
                if (error as? URLError)?.code == .cancelled { throw CancellationError() }
                locations.append(.init(id: id, query: query, candidates: [], selected: nil,
                                       issue: "MapKit: \(ProviderDiagnostics.message(error))"))
            }
        }
        return .init(request: review.request, selectedIDs: selectedIDs, locations: locations,
                     searchRequests: requests, searchSeconds: Date().timeIntervalSince(began))
    }

    public func plan(_ prepared: PreparedTrip, review: RecommendationReview,
                     baseAcceptedID: UUID?, now: Date = .now, progress: (String) -> Void = { _ in }) async throws -> IntegratedPlan {
        let began = Date()
        let request = prepared.request
        try request.validate(catalog: catalog, now: now)
        guard request == review.request,
              prepared.ready, prepared.locations.count == prepared.selectedIDs.count + 1,
              Set(prepared.locations.map(\.id)) == Set(["origin"] + prepared.selectedIDs),
              Set(request.requiredCandidateIDs).isSubset(of: Set(prepared.selectedIDs)),
              (1 ... 6).contains(prepared.selectedIDs.count),
              Set(prepared.selectedIDs).count == prepared.selectedIDs.count,
              prepared.locations.allSatisfy({ location in
                  guard let pin = location.selected else { return false }
                  return location.candidates.contains(pin) && IntegrationCatalog.contains(pin)
              }) else { throw IntegrationError.invalid("Lokasi belum dikonfirmasi atau input telah berubah.") }
        let selectedCandidates = try prepared.selectedIDs.map { id in
            guard let candidate = catalog.candidate(id), review.suggestions.first(where: { $0.id == id })?.selectable == true else {
                throw IntegrationError.invalid("Kandidat tidak cocok dengan review saat ini.")
            }
            return candidate
        }
        guard Set(selectedCandidates.map(\.venueID)).count == selectedCandidates.count else {
            throw IntegrationError.invalid("Duplikat venue pada itinerary.")
        }
        // Recheck evidence at planning time, including source expiry during a long-running screen.
        let decisions = try QualityPipeline.decisions(profile: request.profile, catalog: catalog.quality, now: now)
        guard prepared.selectedIDs.allSatisfy({ id in decisions.first { $0.id == id }?.state == "eligible" }) else {
            throw IntegrationError.invalid("Bukti preferensi berubah/kedaluwarsa. Buat rekomendasi ulang.")
        }
        progress("Mengambil cuaca untuk tanggal dan rentang trip")
        weather.resetMetrics()
        let weatherBegan = Date()
        let forecasts = try await weather.fetch(prepared.locations, request: request, now: now)
        try Task.checkCancellation()
        let weatherSeconds = Date().timeIntervalSince(weatherBegan)
        var timing: [TimingRun] = []
        for candidate in selectedCandidates {
            let environment = try environment(for: candidate.id, venueID: candidate.venueID,
                                              forecasts: forecasts, request: request)
            guard let run = try catalog.timingRun(candidateID: candidate.id, request: request,
                                                  environment: environment, now: now), !run.validStartRanges.isEmpty else {
                throw IntegrationError.invalid("Jam layanan \(candidate.name) belum mempunyai waktu mulai valid. Semua pilihan dipertahankan untuk koreksi.")
            }
            timing.append(run)
        }
        let logs = NativeTripLogStore(directory: logDirectory, maximumFiles: 3, maximumBytes: 500_000)
        let services = NativeTripAppleServices(logs: logs, requestLimit: 512)
        services.integrationETA = replayETA
        if labBulk { services.labBatch = labBatch }
        services.integrationForecasts = prepared.locations.map { location in
            let value = forecasts.first { $0.memberIDs.contains(location.id) }
            let valid = value.map { $0.complete && $0.expiresAt > now } ?? false
            return NativeTripForecast(pointID: location.id,
                                      hours: valid ? value!.hours.map { .init(date: $0.start, rainChance: $0.rainChance, temperatureC: $0.temperatureC) } : [],
                                      status: valid ? "available" : "unavailable", note: value?.errors.joined(separator: "\n") ?? "Cuaca belum tersedia.",
                                      fetchedAt: value?.fetchedAt, provider: value.flatMap { NativeTripWeatherProvider(rawValue: $0.provider) },
                                      retrievedAt: value?.retrievedAt)
        }
        let ranges = Dictionary(uniqueKeysWithValues: zip(selectedCandidates, timing).map { ($0.0.id, $0.1.validStartRanges) })
        services.integrationVisitStart = { id, arrival in
            VisitStartPolicy.earliest(arrival: arrival, tripDate: request.departure, ranges: ranges[id] ?? [])
        }
        routing = services
        defer { routing = nil }
        func point(_ id: String) -> NativeTripPoint {
            let location = prepared.locations.first { $0.id == id }!
            let pin = location.selected!
            return .init(id: id, title: pin.name, query: location.query, latitude: pin.latitude, longitude: pin.longitude,
                         resolvedName: pin.name, address: pin.address, searchRegion: NativeTripJakarta.region,
                         selectionSource: location.manualConfirmation ? "MapKit · dikonfirmasi pengguna" : "MapKit · satu kecocokan nama/cabang")
        }
        var draft = NativeTripDraft.jakarta(now: request.departure)
        draft.departure = request.departure; draft.finishBy = request.deadline
        draft.origin = point("origin"); draft.end = draft.origin; draft.returnsToOrigin = true
        draft.defaultDwell = request.defaultDuration
        draft.stops = selectedCandidates.map { candidate in
            let run = timing.first { $0.venue.id == candidate.venueID }!
            let day = run.venue.schedule.first { $0.weekday == ((TripClock.calendar.component(.weekday, from: request.departure) + 5) % 7 + 1) }
            return .init(point: point(candidate.id), role: .visit, dwellOverride: request.duration(candidate.venueID),
                         exposure: NativeTripExposure(rawValue: run.venue.exposure) ?? .unknown,
                         opening: .init(opensMinute: day?.sessions.map(\.start).min(), closesMinute: day?.sessions.map(\.end).max(),
                                        serviceDate: TripClock.day(request.departure), timeZoneID: "Asia/Jakarta",
                                        sourceNote: run.sources.map { "\($0.id): \($0.url.absoluteString)" }.joined(separator: "; ")))
        }
        let routeBegan = Date()
        var report: NativeTripReport
        if labSelective { report = try await LabSelectivePlanner.plan(draft, services: services, progress: progress) }
        else if labFast { report = try await LabFastPlanner.plan(draft, services: services, progress: progress) }
        else { report = try await NativeTripTimeAwarePlanner.plan(draft, services: services, progress: progress) }
        try Task.checkCancellation()
        let routeSeconds = Date().timeIntervalSince(routeBegan)
        // Weather choice is already constrained to feasible provider-validated candidates and <=15m extra.
        let completionNow = now.addingTimeInterval(Date().timeIntervalSince(began))
        let weatherStillFresh = forecasts.allSatisfy { !$0.complete || $0.expiresAt > completionNow }
        let chosen = (weatherStillFresh ? report.weatherChoice : nil) ?? report.fastest
            ?? report.candidates.sorted(by: NativeTripCandidate.better).first
        if replayETA != nil && !labIsREST { report.simulationKind = "P3 explicit synthetic replay; not live provider evidence" }
        if let credit = forecasts.first(where: { $0.provider == "weatherkit" && $0.complete })?.credit,
           let light = credit.markLightURL, let dark = credit.markDarkURL {
            report.storedWeatherCredit = .init(serviceName: credit.name, legalPageURL: credit.legalURL,
                                               combinedMarkLightURL: light, combinedMarkDarkURL: dark)
        }
        var stops: [PlannedStop] = []
        for leg in chosen?.legs ?? [] where !leg.isReturn {
            guard let candidate = catalog.candidate(leg.to.id), let arrival = leg.arrival,
                  let visit = leg.visit, let leave = leg.leave,
                  let pin = prepared.locations.first(where: { $0.id == candidate.id })?.selected else { continue }
            let run = timing.first { $0.venue.id == candidate.venueID }!
            let weather = forecasts.first { $0.memberIDs.contains(candidate.id) }
            let usable = weather.map { $0.complete && $0.expiresAt > completionNow } ?? false
            stops.append(.init(id: candidate.id, venueID: candidate.venueID, name: candidate.name,
                               area: candidate.scope, pin: pin, arrival: arrival, visit: visit, leave: leave,
                               duration: request.duration(candidate.venueID), sourceIDs: candidate.sourceIDs + run.venue.sourceIDs,
                               weatherProvider: usable ? weather?.provider : nil,
                               rainChance: usable ? WeatherPolicy.rain(weather!.hours, start: visit, end: leave) : nil,
                               recommendedWindows: run.options, notes: leg.notes + run.warnings))
        }
        var conflicts = chosen?.conflicts ?? ["Tidak ada kandidat rute lengkap."]
        if request.departure < completionNow && (replayETA == nil || labIsREST) {
            conflicts.append("Waktu berangkat sudah berlalu saat proses selesai; pilih waktu baru dan hitung ulang.")
        }
        if Set(stops.map(\.id)) != Set(prepared.selectedIDs) { conflicts.append("Tidak semua tujuan pilihan berhasil dijadwalkan; tidak ada penghapusan otomatis.") }
        for stop in stops {
            let allowed = ranges[stop.id] ?? []
            if VisitStartPolicy.earliest(arrival: stop.visit, tripDate: request.departure, ranges: allowed) != stop.visit {
                conflicts.append("Waktu mulai \(stop.name) tidak lolos audit jam layanan.")
            }
        }
        if let finish = chosen?.finish, finish > request.deadline { conflicts.append("Tiba kembali melewati deadline.") }
        var uncertainties = (chosen?.uncertainties ?? []) + forecasts.flatMap(\.errors)
        if !weatherStillFresh { uncertainties.append("Cuaca kedaluwarsa saat routing; pilihan cepat digunakan, konteks cuaca perlu diperbarui.") }
        if forecasts.contains(where: { !$0.complete }) { uncertainties.append("Sebagian/seluruh cuaca belum diketahui. Rute layak tidak membuktikan WeatherKit berhasil.") }
        if stops.contains(where: { $0.rainChance == nil }) { uncertainties.append("Ada interval kunjungan tanpa cakupan cuaca lengkap; tidak dianggap 0% hujan.") }
        uncertainties += ["Parkir, antrean, kapasitas, tiket, hari libur dan penutupan mendadak belum dijamin.",
                          "Pencarian dibatasi; hasil hybrid adaptif bukan bukti optimum global.",
                          "Perubahan durasi +30 menit menghitung ulang seluruh draf sebelum perjalanan, bukan pelacakan trip aktif."]
        let feasible = chosen?.feasible == true && conflicts.isEmpty
        let legs = (chosen?.legs ?? []).map { leg in
            PlannedLeg(id: leg.id, from: leg.from.title, to: leg.to.title, departure: leg.departure,
                       arrival: leg.arrival, seconds: leg.chosen?.seconds, providerStatus: leg.chosen?.status ?? "unavailable")
        }
        var value = IntegratedPlan(createdAt: now, request: request, prepared: prepared, quality: review.quality,
                                   stops: stops, legs: legs, timing: timing, weather: forecasts, status: feasible ? "ready" : "conflicted",
                                   conflicts: Array(Set(conflicts)).sorted(), uncertainties: Array(Set(uncertainties)).sorted(),
                                   finish: chosen?.finish, travelMinutes: chosen?.travelMinutes ?? 0, waitingMinutes: chosen?.waitingMinutes ?? 0,
                                   metrics: [.init(stage: "preferences", seconds: review.quality.elapsedSeconds, requests: 0),
                                             .init(stage: "mapkit_search", seconds: prepared.searchSeconds, requests: prepared.searchRequests),
                                             .init(stage: "weather_groups", seconds: weatherSeconds, requests: weather.requests),
                                             .init(stage: "mapkit_eta", seconds: routeSeconds, requests: report.requests),
                                             .init(stage: "plan_total_excluding_review_search", seconds: Date().timeIntervalSince(began), requests: 0)],
                                   summary: "", rawRoutingReport: try IntegrationJSON.encoder().encode(report), baseAcceptedID: baseAcceptedID)
        value.evidenceMode = labIsREST ? "live_rest" : replayETA == nil ? "live" : "synthetic_replay"
        do { value.providerLog = try await logs.snapshot().data }
        catch { value.uncertainties.append("Log provider tidak lengkap: \(error.localizedDescription)") }
        try Task.checkCancellation()
        try PlanAudit.validate(value)
        value.summary = PlanExplanation.text(value)
        return value
    }

    private func environment(for id: String, venueID: String, forecasts: [WeatherEvidence],
                             request: TripRequest) throws -> TimingEnvironment? {
        guard let value = forecasts.first(where: { $0.memberIDs.contains(id) }), value.complete,
              let credit = value.credit else { return nil }
        struct Payload: Encodable {
            var provider: String; var fetchedAt: Date; var validUntil: Date; var date: String; var venueID: String
            var latitude: Double; var longitude: Double; var locationName: String; var locationSource: String
            var hours: [TimingHour]; var sunrise: Date?; var sunset: Date?
            var attributionURL: URL; var attribution: String; var errors: [String]
        }
        // Keep the provider timestamp: P1 can reject older metadata instead of relabeling it as fresh.
        let payload = Payload(provider: value.provider, fetchedAt: value.fetchedAt, validUntil: value.expiresAt,
                              date: TripClock.day(request.departure), venueID: venueID, latitude: value.representative.latitude,
                              longitude: value.representative.longitude, locationName: value.representative.name,
                              locationSource: "MapKit representative, maximum group radius 3 km; not exact venue weather",
                              hours: value.hours.map { .init(start: $0.start, rainChance: $0.rainChance, temperatureC: $0.temperatureC) },
                              sunrise: value.sunrise, sunset: value.sunset, attributionURL: credit.legalURL,
                              attribution: credit.name, errors: value.errors)
        return try IntegrationJSON.decoder().decode(TimingEnvironment.self, from: IntegrationJSON.encoder().encode(payload))
    }
}

public enum PlanExplanation {
    public static func text(_ plan: IntegratedPlan) -> String {
        let sequence = plan.stops.map(\.name).joined(separator: " → ")
        let finish = plan.finish.map(TripClock.label) ?? "unknown"
        let weather = Set(plan.weather.filter(\.complete).map(\.provider)).sorted().joined(separator: ", ")
        return "\(plan.feasible ? "Reviewable draft" : "Unresolved draft"): \(sequence). "
            + "Travel \(String(format: "%.1f", plan.travelMinutes)) min; waiting \(String(format: "%.1f", plan.waitingMinutes)) min. "
            + "Return to Bundaran HI: \(finish). Deadline: \(TripClock.label(plan.request.deadline)). "
            + "All \(plan.prepared.selectedIDs.count) selected places have equal priority. "
            + "\(plan.conflicts.count) conflicts; \(plan.uncertainties.count) uncertainty notes. "
            + "Weather source: \(weather.isEmpty ? "unknown" : weather). "
            + "Published visiting windows are suggestions, not a claim that this route achieves every preferred window."
    }
}
