import Foundation

struct PlaywrightCollector: Sendable {
    private struct Input: Encodable {
        var urls: [URL]
        var hosts: [String]
        var names: [String]
        var brandTokens: [String]
        var blockedHosts: [String]
        var branchTokens: [String]
        var maxPages: Int
        var cachedPages: [CachedPage]
    }
    private struct CachedPage: Encodable {
        var url: URL
        var text: String
        var blocks: [EvidenceBlock]?
        var links: [SourceLink]?
        var aliases: [URL]?
    }
    private struct Output: Decodable {
        struct Page: Decodable {
            var requestedURL: URL
            var url: URL
            var status: Int
            var text: String
            var blocks: [EvidenceBlock]?
            var links: [SourceLink]?
            var fromCache: Bool?
        }
        var pages: [Page]
        var attempts: [PageAttempt]
        var discoveredURLs: [URL]
    }
    struct Collection: Sendable {
        var pages: [SourcePage]
        var attempts: [PageAttempt]
        var discoveredURLs: [URL]
        var cachedPages: Int
    }

    let script: URL
    let node: URL
    let browserEnvironment: [String: String]
    let maxPages: Int
    let replayManifest: [String: [URL]]?

    init(environment: [String: String]) throws {
        script = URL(fileURLWithPath: environment["VENUE_PLAYWRIGHT_SCRIPT"] ?? "Scripts/playwright-collect.cjs")
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            throw EnrichmentFailure(message: "Skrip Playwright belum tersedia.")
        }
        node = URL(fileURLWithPath: environment["VENUE_NODE_PATH"] ?? "/usr/bin/env")
        guard let limit = Int(environment["VENUE_PLAYWRIGHT_MAX_PAGES"] ?? "5"), (1 ... 8).contains(limit) else {
            throw EnrichmentFailure(message: "Batas halaman Playwright harus 1...8.")
        }
        maxPages = limit
        if environment["VENUE_RESEARCH_OFFLINE"] == "1" {
            guard let manifest = environment["VENUE_REPLAY_MANIFEST"] else {
                throw EnrichmentFailure(message: "Mode replay memerlukan manifest URL per cabang.")
            }
            replayManifest = try JSONDecoder().decode([String: [URL]].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
        } else { replayManifest = nil }
        browserEnvironment = environment.filter {
            ["PATH", "HOME", "TMPDIR", "NODE_PATH", "PLAYWRIGHT_BROWSERS_PATH"].contains($0.key)
        }
    }

    func collect(for venue: OpenVenue, cached: [SourcePage], blockedHosts: [String] = [], discovered: [URL] = []) async throws -> Collection {
        if let replayManifest {
            let urls = replayManifest[venue.id] ?? []
            let pages = urls.compactMap { url in
                cached.first { $0.url == url && FirecrawlClient.allowed(url, for: venue) && Date().timeIntervalSince($0.fetchedAt) < 30 * 86400 }
            }
            let attempts: [PageAttempt] = pages.isEmpty && !(venue.operatorURLs ?? []).isEmpty
                ? [.init(url: venue.operatorURLs![0], attempt: 0, status: 0, reason: "offline_source_unavailable", durationSeconds: 0)] : []
            return .init(pages: pages, attempts: attempts, discoveredURLs: [], cachedPages: pages.count)
        }
        let known = (venue.operatorURLs?.isEmpty == false ? venue.operatorURLs : nil)
            ?? venue.operatorHosts.compactMap { URL(string: "https://" + $0 + "/") }
        let seeds = Array(discovered.prefix(1)) + known + Array(discovered.dropFirst())
        let allowed = seeds.filter { FirecrawlClient.allowed($0, for: venue) }
        guard !allowed.isEmpty else { return .init(pages: [], attempts: [], discoveredURLs: [], cachedPages: 0) }
        let hosts = Set(venue.operatorHosts + allowed.compactMap(\.host)).map {
            $0.lowercased().hasPrefix("www.") ? String($0.lowercased().dropFirst(4)) : $0.lowercased()
        }
        let reusable = cached.filter { FirecrawlClient.allowed($0.url, for: venue) && Date().timeIntervalSince($0.fetchedAt) < 30 * 86400 }
        let names = (venue.branchAliases ?? ([venue.name] + venue.aliases)) + StructuredVenueEvidence.branchAnchors(for: venue)
        let input = try JSONEncoder().encode(Input(urls: Array(allowed.prefix(2)), hosts: Array(Set(hosts)).sorted(),
                                                   names: names, brandTokens: OpenVenue.normalized(venue.name).split(separator: " ").map(String.init).filter {
                                                       $0.count >= 5 && !["coffee", "library", "museum", "perpustakaan", "jakarta", "selatan", "shopping", "indonesia"].contains($0)
                                                   }, blockedHosts: blockedHosts, branchTokens: OpenVenue.normalized(venue.branch).split(separator: " ").map(String.init), maxPages: maxPages,
                                                   cachedPages: reusable.prefix(40).map { .init(url: $0.url, text: $0.text, blocks: $0.blocks, links: $0.links, aliases: $0.aliases) }))
        let data = try await Task.detached(priority: .utility) { try run(input: input) }.value
        let output = try JSONDecoder().decode(Output.self, from: data)
        let pages = output.pages.compactMap { row -> SourcePage? in
            guard (200 ..< 300).contains(row.status), FirecrawlClient.allowed(row.url, for: venue),
                  !row.text.isEmpty || !(row.blocks ?? []).isEmpty else { return nil }
            let fetchedAt = row.fromCache == true ? reusable.first(where: { $0.url == row.url })?.fetchedAt : nil
            return SourcePage(url: row.url, text: row.text, fetchedAt: fetchedAt ?? Date(), blocks: row.blocks, links: row.links, aliases: Array(Set([row.requestedURL, row.url] + (reusable.first(where: { $0.url == row.url })?.aliases ?? []))))
        }
        return .init(pages: pages, attempts: output.attempts, discoveredURLs: output.discoveredURLs,
                     cachedPages: output.pages.filter { $0.fromCache == true }.count)
    }

    private func run(input: Data) throws -> Data {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = node
        process.arguments = (node.path == "/usr/bin/env" ? ["node"] : []) + [script.path]
        process.environment = browserEnvironment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 4 * 1024 * 1024 else {
            throw EnrichmentFailure(message: "Playwright gagal atau melewati batas waktu/ukuran. Periksa Node dan Chromium.")
        }
        return data
    }
}
