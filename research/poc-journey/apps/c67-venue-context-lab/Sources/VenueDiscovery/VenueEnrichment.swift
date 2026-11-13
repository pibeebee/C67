import Darwin
import Foundation
import PlaceContextEngine

@MainActor public final class VenueEnrichment {
    private struct Discovery: Codable {
        var checkedAt: Date
        var urls: [URL]
    }
    private struct State: Codable {
        var facts: [String: [VenueField: VenueFact]] = [:]
        var pages: [String: SourcePage] = [:]
        var lastFailure: [String: Date] = [:]
        var reservedCredits = 0
        var reports: [String: VenueResearchReport]?
        var sourceCooldowns: [String: Date]?
        var discoveries: [String: Discovery]?
    }

    private let file: URL
    private let lockFile: Int32
    private let firecrawl: FirecrawlClient?
    private let playwright: PlaywrightCollector?
    private let extractor: GiovancExtractor?
    private let discovery: FirecrawlClient?
    private let cap: Int
    private var state: State
    private var queue: [OpenVenue] = []
    private var queued = Set<String>()
    private var worker: Task<Void, Never>?
    private var suspended = false
    private var lastError: String?
    private var pagesRead = 0
    private var excerptsSelected = 0
    private var extractions = 0

    public init(directory: URL, environment: [String: String]) throws {
        let stateFile = directory.appendingPathComponent("venue-evidence-v1.json")
        file = stateFile
        let lock = directory.appendingPathComponent("venue-evidence.lock")
        let fd = open(lock.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard fd >= 0 else { throw EnrichmentFailure(message: "Penyimpanan bukti tidak dapat dikunci.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw EnrichmentFailure(message: "Server Venue Context lain masih memakai folder bukti ini.")
        }
        do {
            state = FileManager.default.fileExists(atPath: stateFile.path)
                ? try ContextJSON.decoder().decode(State.self, from: Data(contentsOf: stateFile)) : State()
            guard let limit = Int(environment["VENUE_FIRECRAWL_CREDIT_CAP"] ?? "150"), (1 ... 10_000).contains(limit) else {
                throw EnrichmentFailure(message: "Batas kredit Firecrawl tidak valid.")
            }
            cap = limit
            if environment["VENUE_ENRICHMENT_ENABLED"] == "1" {
                guard let giovancKey = environment["GIOVANC_API_KEY"], !giovancKey.isEmpty else {
                    throw EnrichmentFailure(message: "Isi kredensial luna-provider.example sebelum mengaktifkan pencarian bukti.")
                }
                let http = EnrichmentHTTP()
                switch environment["VENUE_WEB_PROVIDER"] ?? "playwright" {
                case "firecrawl":
                    guard let key = environment["FIRECRAWL_API_KEY"], !key.isEmpty else {
                        throw EnrichmentFailure(message: "Isi kredensial Firecrawl terlebih dahulu.")
                    }
                    firecrawl = FirecrawlClient(key: key, http: http)
                    playwright = nil
                case "playwright":
                    firecrawl = nil
                    playwright = try PlaywrightCollector(environment: environment)
                default:
                    throw EnrichmentFailure(message: "VENUE_WEB_PROVIDER harus firecrawl atau playwright.")
                }
                let discoveryMode = environment["VENUE_URL_DISCOVERY"] ?? "none"
                guard ["none", "firecrawl"].contains(discoveryMode) else {
                    throw EnrichmentFailure(message: "VENUE_URL_DISCOVERY harus none atau firecrawl.")
                }
                if discoveryMode == "firecrawl", playwright != nil, environment["VENUE_RESEARCH_OFFLINE"] != "1" {
                    guard let key = environment["FIRECRAWL_API_KEY"], !key.isEmpty else {
                        throw EnrichmentFailure(message: "Pencarian URL Firecrawl memerlukan API key.")
                    }
                    discovery = FirecrawlClient(key: key, http: http)
                } else { discovery = nil }
                guard let modelTimeout = Double(environment["GIOVANC_TIMEOUT_SECONDS"] ?? "90"), (15 ... 180).contains(modelTimeout) else {
                    throw EnrichmentFailure(message: "GIOVANC_TIMEOUT_SECONDS harus 15...180.")
                }
                extractor = GiovancExtractor(key: giovancKey, model: environment["GIOVANC_MODEL"] ?? "cx/gpt-6-luna(max)",
                                             http: EnrichmentHTTP(timeout: modelTimeout))
            } else {
                firecrawl = nil
                playwright = nil
                extractor = nil
                discovery = nil
            }
            lockFile = fd
        } catch {
            close(fd)
            throw error
        }
    }

    deinit { close(lockFile) }

    public static func checkFirecrawl(environment: [String: String]) async throws -> Int {
        guard let key = environment["FIRECRAWL_API_KEY"], !key.isEmpty else {
            throw EnrichmentFailure(message: "FIRECRAWL_API_KEY belum diatur.")
        }
        return try await FirecrawlClient(key: key, http: EnrichmentHTTP()).remainingCredits()
    }

    public func status() -> [String: String] {
        let facts = state.facts.values.flatMap { $0.values }.filter { $0.fresh(at: Date()) }
        return ["enabled": String(extractor != nil), "suspended": String(suspended),
                "webProvider": playwright != nil ? "playwright" : (firecrawl != nil ? "firecrawl" : "disabled"),
                "urlDiscovery": discovery != nil ? "firecrawl" : "none",
                "pagesRead": String(pagesRead), "excerptsSelected": String(excerptsSelected), "extractions": String(extractions),
                "pending": String(queued.count), "reservedCredits": String(state.reservedCredits), "creditCap": String(cap),
                "freshSupportedFacts": String(facts.filter { $0.status == "supported" }.count),
                "freshUnknownFacts": String(facts.filter { $0.status == "unknown" }.count),
                "lastError": lastError ?? ""]
    }

    public func diagnostics() -> [VenueResearchReport] {
        (state.reports ?? [:]).values.sorted { $0.venueID < $1.venueID }
    }

    public func facts(for id: String, now: Date = .now) -> [VenueField: VenueFact] {
        (state.facts[id] ?? [:]).filter { $0.value.fresh(at: now) }
    }

    @discardableResult public func enqueue(_ venue: OpenVenue, now: Date = .now) -> Bool {
        guard extractor != nil, !suspended, queued.count < 100, !queued.contains(venue.id),
              (firecrawl == nil && discovery == nil) || state.reservedCredits + 4 <= cap, missing(for: venue.id, now: now).count > 0,
              state.lastFailure[venue.id].map({ now.timeIntervalSince($0) >= 3600 }) ?? true else { return false }
        queue.append(venue)
        queued.insert(venue.id)
        if worker == nil {
            worker = Task { await self.drain() }
        }
        return true
    }

    public func shutdown() async {
        let task = worker
        task?.cancel()
        await task?.value
    }

    private func missing(for id: String, now: Date) -> [VenueField] {
        let current = facts(for: id, now: now)
        return VenueField.allCases.filter { current[$0] == nil }
    }

    private func persist(_ next: State) throws {
        try ContextJSON.encoder().encode(next).write(to: file, options: .atomic)
        state = next
    }

    private func reserve(_ credits: Int) throws {
        guard state.reservedCredits + credits <= cap else {
            suspended = true
            throw EnrichmentFailure(message: "Batas kredit pilot tercapai.")
        }
        var next = state
        next.reservedCredits += credits
        try persist(next)
    }

    private func drain() async {
        defer { queue.removeAll(); queued.removeAll(); worker = nil }
        guard let extractor else { return }
        while !queue.isEmpty && !Task.isCancelled && !suspended {
            let venue = queue.removeFirst()
            do {
                try await research(venue, extractor: extractor)
            } catch is CancellationError {
                return
            } catch {
                var next = state
                next.lastFailure[venue.id] = Date()
                lastError = error.localizedDescription
                do { try persist(next) }
                catch { suspended = true; lastError = "Penyimpanan bukti gagal. Pengayaan dihentikan." }
                if ["HTTP 401", "HTTP 402", "HTTP 403", "HTTP 429"].contains(where: { lastError?.contains($0) == true }) {
                    suspended = true
                }
            }
            queued.remove(venue.id)
        }
    }

    private func research(_ venue: OpenVenue, extractor: GiovancExtractor) async throws {
        var report = VenueResearchReport(venueID: venue.id, startedAt: Date(), stage: "collecting")
        do {
            try await research(venue, extractor: extractor, report: &report)
            report.completedAt = Date()
            var next = state
            next.reports = next.reports ?? [:]
            next.reports?[venue.id] = report
            try persist(next)
        } catch {
            report.completedAt = Date()
            report.error = error.localizedDescription
            report.stage += "_failed"
            var next = state
            next.reports = next.reports ?? [:]
            next.reports?[venue.id] = report
            try persist(next)
            throw error
        }
    }

    private func research(_ venue: OpenVenue, extractor: GiovancExtractor, report: inout VenueResearchReport) async throws {
        let fields = missing(for: venue.id, now: .now)
        guard !fields.isEmpty else { report.stage = "cache_hit"; return }
        let pages: [SourcePage]
        if let playwright {
            var seen = Set<URL>()
            let reusable = state.pages.values.filter { seen.insert($0.url).inserted }
            var discovered: [URL] = []
            if let discovery {
                if let cached = state.discoveries?[venue.id], Date().timeIntervalSince(cached.checkedAt) < 30 * 86400 {
                    discovered = cached.urls
                    report.searchCacheHit = true
                } else {
                    do {
                        guard try await discovery.remainingCredits() >= 2 else { throw EnrichmentFailure(message: "Saldo pencarian URL tidak cukup.") }
                        try reserve(2)
                        discovered = try await discovery.search(venue, fields: fields)
                        var next = state
                        next.discoveries = next.discoveries ?? [:]
                        next.discoveries?[venue.id] = .init(checkedAt: Date(), urls: discovered)
                        try persist(next)
                        report.searchCacheHit = false
                    } catch {
                        report.searchError = error.localizedDescription
                        throw error
                    }
                }
                report.searchURLs = discovered
            }
            let blocked = (state.sourceCooldowns ?? [:]).filter { $0.value > Date() }.map(\.key)
            let collection = try await playwright.collect(for: venue, cached: reusable, blockedHosts: blocked, discovered: discovered)
            var cooldownState = state
            cooldownState.sourceCooldowns = (cooldownState.sourceCooldowns ?? [:]).filter { $0.value > Date() }
            for attempt in collection.attempts where [403, 429].contains(attempt.status) {
                if let host = attempt.url.host?.lowercased() {
                    let normalized = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                    cooldownState.sourceCooldowns?[normalized] = Date().addingTimeInterval(3600)
                }
            }
            try persist(cooldownState)
            report.pageAttempts = collection.attempts
            report.discoveredURLs = collection.discoveredURLs
            report.cachedPages = collection.cachedPages
            pages = collection.pages
            if pages.isEmpty && !collection.attempts.isEmpty {
                throw EnrichmentFailure(message: "Semua halaman gagal dibaca; lihat pageAttempts untuk status dan penyebab.")
            }
            if !pages.isEmpty {
                var next = state
                next.pages = next.pages.filter { Date().timeIntervalSince($0.value.fetchedAt) < 30 * 86400 }
                for page in pages { next.pages[page.url.absoluteString] = page }
                // Also retain seed aliases after redirects, so a cached page is not fetched again.
                for attempt in collection.attempts where attempt.reason == "read" {
                    if let resolved = attempt.resolvedURL, let page = pages.first(where: { $0.url == resolved }) {
                        next.pages[attempt.url.absoluteString] = page
                    }
                }
                try persist(next)
            }
        } else if let firecrawl {
            pages = try await firecrawlPages(venue, fields: fields, firecrawl: firecrawl)
        } else { return }
        report.pageURLs = pages.map(\.url)
        pagesRead += pages.count
        var seenExcerpts = Set<String>()
        let excerpts = pages.compactMap { Self.excerpt($0, venue: venue) }.filter { seenExcerpts.insert($0.text).inserted }
        report.excerpts = excerpts.count
        excerptsSelected += excerpts.count
        var resolved: [VenueField: VenueFact] = [:]
        if fields.contains(.hours), let fact = pages.compactMap({ StructuredVenueEvidence.hours(in: $0, venue: venue) }).first {
            resolved[.hours] = fact
            report.fields.append(.init(field: .hours, outcome: "supported", reason: "structured_hours", proposed: nil))
            // A subsequent model failure must not discard independently parsed evidence.
            var next = state
            next.facts[venue.id, default: [:]][.hours] = fact
            try persist(next)
        }
        let requested = fields.filter { resolved[$0] == nil }
        var claims: [GiovancExtractor.Claim] = []
        if !excerpts.isEmpty && !requested.isEmpty {
            report.stage = "extracting"
            for attempt in 1 ... 3 {
                try Task.checkCancellation()
                report.modelAttempts = attempt
                var active = state
                active.reports = active.reports ?? [:]
                active.reports?[venue.id] = report
                try persist(active)
                do {
                    claims = try await extractor.extract(venue, fields: requested, pages: excerpts)
                    extractions += 1
                    break
                } catch {
                    report.modelErrors.append(error.localizedDescription)
                    let message = error.localizedDescription
                    let retryable = (error as NSError).domain == NSURLErrorDomain ||
                        ["HTTP 408", "HTTP 429", "HTTP 500", "HTTP 502", "HTTP 503", "HTTP 504", "Keluaran ekstraksi", "Format respons"].contains { message.contains($0) }
                    guard attempt < 3, retryable else { throw error }
                    try await Task.sleep(for: .seconds(attempt))
                }
            }
        }
        report.stage = "validating"
        var next = state
        let now = Date()
        for field in requested {
            let claim = claims.first { $0.field == field }
            let assessment = claim.map { Self.assess($0, venue: venue, pages: excerpts, now: now) }
            let fact = assessment?.fact ?? VenueFact.unknown(field, at: now)
            next.facts[venue.id, default: [:]][field] = fact
            let reason = assessment?.reason ?? (pages.isEmpty ? "no_approved_source" : excerpts.isEmpty ? "branch_not_found_in_pages" : "no_claim")
            report.fields.append(.init(field: field, outcome: fact.status, reason: reason, proposed: claim))
        }
        next.lastFailure.removeValue(forKey: venue.id)
        try persist(next)
        report.stage = "completed"
    }

    private func firecrawlPages(_ venue: OpenVenue, fields: [VenueField], firecrawl: FirecrawlClient) async throws -> [SourcePage] {
        let remaining = try await firecrawl.remainingCredits()
        guard remaining >= 4 else {
            suspended = true
            throw EnrichmentFailure(message: "Saldo Firecrawl kurang dari batas aman satu pencarian.")
        }
        try reserve(2)
        let search = try await firecrawl.search(venue, fields: fields)
        let known = (venue.operatorURLs ?? []).filter { FirecrawlClient.allowed($0, for: venue) }
        let found = Array(search.prefix(1)) + known + Array(search.dropFirst())
        var pages: [SourcePage] = []
        var visited = Set<URL>()
        for url in found where visited.insert(url).inserted {
            try Task.checkCancellation()
            if let cached = state.pages[url.absoluteString], Date().timeIntervalSince(cached.fetchedAt) < 30 * 86400 {
                pages.append(cached)
            } else {
                try reserve(1)
                if let page = try await firecrawl.scrape(url, venue: venue) {
                    var next = state
                    next.pages = next.pages.filter { Date().timeIntervalSince($0.value.fetchedAt) < 30 * 86400 }
                    next.pages[url.absoluteString] = page
                    next.pages[page.url.absoluteString] = page
                    try persist(next)
                    pages.append(page)
                }
            }
            if visited.count == 2 { break }
        }
        return pages
    }

    nonisolated static func excerpt(_ page: SourcePage, venue: OpenVenue) -> SourcePage? {
        let names = ((venue.branchAliases ?? ([venue.name] + venue.aliases)) + StructuredVenueEvidence.branchAnchors(for: venue))
            .map(OpenVenue.normalized).filter { $0.count >= 5 }
        if page.text.contains("[Bagian terpisah]") {
            let sections = page.text.components(separatedBy: "[Bagian terpisah]").filter { section in
                let text = OpenVenue.normalized(section)
                return names.contains { text.contains($0) }
            }
            guard !sections.isEmpty else { return nil }
            return .init(url: page.url, text: String(sections.joined(separator: "\n[Bagian terpisah]\n").prefix(12_000)),
                         fetchedAt: page.fetchedAt)
        }
        let semantic = (page.blocks ?? []).filter { block in
            let text = OpenVenue.normalized(block.text)
            return names.contains { text.contains($0) }
        }
        // Article blocks are already selected from the original article body (including SSR data).
        // Other blocks remain separate so facts cannot be assembled across branch cards.
        if !semantic.isEmpty {
            let text = semantic.map(\.text).joined(separator: "\n\n[Bagian terpisah]\n\n")
            return .init(url: page.url, text: String(text.prefix(24_000)), fetchedAt: page.fetchedAt, blocks: semantic)
        }
        let lines = page.text.components(separatedBy: .newlines)
        if page.url.host == "onefifteenthcoffee.squarespace.com" {
            let anchors = StructuredVenueEvidence.branchAnchors(for: venue)
            if let start = lines.firstIndex(where: { anchors.contains(OpenVenue.normalized($0)) }) {
                var end = min(lines.count, start + 25)
                var blanks = 0
                for index in (start + 1) ..< end {
                    blanks = lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? blanks + 1 : 0
                    if blanks >= 3 { end = index - 2; break }
                }
                return .init(url: page.url, text: lines[start ..< end].joined(separator: "\n"), fetchedAt: page.fetchedAt)
            }
        }
        var selected = IndexSet()
        for (i, line) in lines.enumerated() where names.contains(where: { OpenVenue.normalized(line).contains($0) }) {
            let isLocator = ["www.periplus.com", "periplus.com"].contains(page.url.host ?? "") && page.url.path.hasSuffix("Store-Locator")
            selected.insert(integersIn: (isLocator ? i : max(0, i - 3)) ..< min(lines.count, i + (isLocator ? 6 : 20)))
            if selected.count >= 60 { break }
        }
        guard !selected.isEmpty else { return nil }
        var sections: [String] = []
        for range in selected.rangeView {
            sections.append(lines[range].joined(separator: "\n"))
        }
        return .init(url: page.url, text: String(sections.joined(separator: "\n\n[Bagian terpisah]\n\n").prefix(12_000)),
                     fetchedAt: page.fetchedAt)
    }

    nonisolated static func assess(_ claim: GiovancExtractor.Claim, venue: OpenVenue, pages: [SourcePage], now: Date) -> (fact: VenueFact?, reason: String) {
        guard ["supported", "contradicted"].contains(claim.status) else { return (nil, "model_unknown") }
        guard let number = claim.page, pages.indices.contains(number - 1) else { return (nil, "invalid_page_reference") }
        guard let branchQuote = claim.branchQuote, let quote = claim.quote,
              (5 ... 700).contains(branchQuote.count), (8 ... 1000).contains(quote.count), (2 ... 280).contains(claim.value.count)
        else { return (nil, "invalid_quote_shape") }
        let page = pages[number - 1]
        func folded(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let blocks = page.text.components(separatedBy: "[Bagian terpisah]")
        let matchingBlocks = blocks.filter { block in
            let text = folded(block)
            return text.contains(folded(branchQuote)) && text.contains(folded(quote))
        }
        guard !matchingBlocks.isEmpty else { return (nil, "quote_not_in_same_source_block") }
        guard StructuredVenueEvidence.identityMatches(branchQuote, venue: venue, source: page.url) else { return (nil, "branch_identity_not_proven") }
        let closeEvidence = matchingBlocks.contains { block in
            let text = folded(block)
            guard let place = text.range(of: folded(branchQuote)), let fact = text.range(of: folded(quote)) else { return false }
            return abs(text.distance(from: place.lowerBound, to: fact.lowerBound)) <= 700
        }
        let articleScope = (page.blocks ?? []).contains { block in
            guard block.kind == "article" else { return false }
            let normalized = OpenVenue.normalized(block.title ?? page.url.lastPathComponent)
            let specificNames = ([venue.name] + (venue.branchAliases ?? [])).map(OpenVenue.normalized).filter { $0.count >= 10 }
            let text = folded(block.text)
            return specificNames.contains { normalized.contains($0) } &&
                text.contains(folded(branchQuote)) && text.contains(folded(quote))
        }
        guard closeEvidence || articleScope else { return (nil, "fact_too_far_from_branch") }
        if let valid = claim.validThrough {
            guard ContextClock.day(valid) != nil, valid >= ContextClock.label(now), quote.contains(valid) else { return (nil, "invalid_or_expired_validity") }
        }
        let hours: [VenueHours]?
        if claim.field == .hours {
            guard claim.status == "supported", let rows = claim.hours, VenueHours.supported(rows, quote: quote) else { return (nil, "hours_not_bound_to_cited_days_and_times") }
            hours = rows
        } else {
            guard claim.hours == nil else { return (nil, "hours_on_non_hours_field") }
            hours = nil
            if claim.field == .access && claim.status == "supported" {
                let access = " " + OpenVenue.normalized(quote) + " "
                let negative = [" tidak untuk umum ", " khusus anggota ", " khusus mahasiswa ", " members only ",
                                " not open to the public ", " dilarang masuk ", " private event "]
                let positive = [" terbuka untuk umum ", " open to the public ", " pengunjung dapat ", " pengunjung wajib ",
                                " visitors can ", " visitors must ", " tiket masuk ", " admission ticket "]
                guard positive.contains(where: { access.contains($0) }), !negative.contains(where: { access.contains($0) }) else { return (nil, "public_access_not_explicit") }
            }
        }
        let capturedSource = (page.blocks ?? []).first { block in
            let text = folded(block.text)
            return block.sourceURL != nil && text.contains(folded(branchQuote)) && text.contains(folded(quote))
        }?.sourceURL
        if let capturedSource, !FirecrawlClient.allowed(capturedSource, for: venue) { return (nil, "unapproved_captured_source") }
        return (.init(field: claim.field, status: claim.status, value: claim.value, checkedAt: page.fetchedAt,
                      source: capturedSource ?? page.url, quote: quote, branchQuote: branchQuote, hours: hours, validThrough: claim.validThrough), "accepted_cited_claim")
    }
}
