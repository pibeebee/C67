import Foundation
import PreferenceLearning

public struct QualityPipeline: Sendable {
    public let embedding: any PreferenceEmbedding
    public init(embedding: any PreferenceEmbedding = E5Embedding()) { self.embedding = embedding }
    public static func decisions(
        profile: QualityProfile, catalog: QualityCatalog,
        now: Date = .now
    ) throws -> [QualityDecision] {
        try catalog.validate()
        try profile.validate(catalog: catalog)
        guard now.timeIntervalSince1970.isFinite else {
            throw PreferenceError.invalid("Jam tidak valid.")
        }
        let sources = Dictionary(uniqueKeysWithValues: catalog.sources.map { ($0.id, $0) })
        let today = Self.date(now)
        return catalog.candidates.map { candidate in
            var reasons: [String] = []
            var unknown: [QualityFeature] = []
            var state = "eligible"
            if profile.excludedIDs.contains(candidate.id) || profile.likedID == candidate.id {
                return .init(
                    candidate: candidate, state: "excluded", reasons: ["Identitas sudah dipilih/ditolak."],
                    unknown: [])
            }
            if let reason = candidate.blockedReason {
                return .init(candidate: candidate, state: "blocked", reasons: [reason], unknown: [])
            }
            if let end = candidate.validThrough, today > end {
                return .init(
                    candidate: candidate, state: "blocked",
                    reasons: ["Sumber program berakhir \(end); keberlanjutan belum diverifikasi."],
                    unknown: [])
            }
            if candidate.sourceIDs.contains(where: {
                guard let source = sources[$0] else { return true }
                return source.checkedAt > now.addingTimeInterval(300)
                    || now.timeIntervalSince(source.checkedAt) >= 7 * 86400
            }) {
                return .init(
                    candidate: candidate, state: "needs_check",
                    reasons: ["Sumber perlu diperiksa ulang; tidak masuk ranking terverifikasi."], unknown: []
                )
            }
            for feature in profile.must.sorted(by: { $0.rawValue < $1.rawValue }) {
                switch candidate.value(feature) {
                case .yes: reasons.append("Wajib didukung: \(feature.label).")
                case .no:
                    state = "excluded"
                    reasons.append("Tidak memenuhi: \(feature.label).")
                case .unknown, .conflict: unknown.append(feature)
                }
            }
            for feature in profile.avoid.sorted(by: { $0.rawValue < $1.rawValue }) {
                switch candidate.value(feature) {
                case .no:
                    reasons.append(
                        "Avoid didukung: \(feature.label) tidak diperbolehkan/tidak ada pada area ini.")
                case .yes:
                    state = "excluded"
                    reasons.append("Bertentangan dengan avoid: \(feature.label).")
                case .unknown, .conflict: unknown.append(feature)
                }
            }
            if state != "excluded" && !unknown.isEmpty { state = "needs_check" }
            return .init(candidate: candidate, state: state, reasons: reasons, unknown: unknown)
        }
    }
    public func run(
        profile: QualityProfile, catalog: QualityCatalog, useEmbedding: Bool = true,
        now: Date = .now, progress: @escaping @Sendable (String) async -> Void = { _ in }
    ) async throws -> QualityRun {
        let began = Date()
        let decisions = try Self.decisions(profile: profile, catalog: catalog, now: now)
        try Task.checkCancellation()
        var value = QualityRun(
            catalog: catalog, profile: profile, decisions: decisions,
            category: [], semantic: [], combined: [], status: "category_only",
            warnings: [
                "Fakta merupakan publikasi bersumber, belum inspeksi lokasi atau jaminan kapasitas.",
                "Kebutuhan wajib/avoid memakai area yang sama; unknown tidak dianggap cocok.",
                "Skor adalah urutan relatif, bukan probabilitas kepuasan pribadi.",
            ], elapsedSeconds: 0)
        value.createdAt = now
        if !profile.direction.isEmpty && !profile.directionConfirmed {
            value.status = "preference_review_required"
            value.warnings.append(
                "Arahan belum dikonfirmasi. Pilih syarat terstruktur; negasi/koreksi tidak ditebak model.")
            return value
        }
        let eligible = decisions.filter { $0.state == "eligible" }
        let soft = profile.softFeatures
        value.category = eligible.map { decision in
            let matched = soft.filter { decision.candidate.value($0) == .yes }.sorted {
                $0.rawValue < $1.rawValue
            }
            return QualityRow(
                candidateID: decision.id,
                categoryScore: soft.isEmpty ? 0 : Double(matched.count) / Double(soft.count),
                supportedPreferences: matched)
        }.sorted {
            $0.categoryScore == $1.categoryScore ? $0.id < $1.id : $0.categoryScore > $1.categoryScore
        }
        if eligible.isEmpty {
            value.status = "no_verified_match"
        } else if !profile.hasSignal {
            value.status = "general_not_personalized"
        } else if profile.must.isEmpty && !soft.isEmpty
            && value.category.allSatisfy({ $0.supportedPreferences.isEmpty })
        {
            value.status = "no_supported_preference"
            value.warnings.append(
                "Belum ada kandidat dengan bukti untuk aspek yang disukai. Daftar kategori hanya alternatif umum, bukan kecocokan personal."
            )
        } else if useEmbedding {
            do {
                value.embedding = try await embedding.metadata()
                let query = try await embedding.encode(profile.query, query: true)
                var rows: [QualityRow] = []
                for decision in eligible {
                    try Task.checkCancellation()
                    await progress("Mencocokkan \(decision.candidate.name)")
                    let vector = try await embedding.encode(decision.candidate.passage, query: false)
                    let cosine = try PreferenceRanker.cosine(query, vector)
                    var row = value.category.first { $0.id == decision.id }!
                    row.semanticScore = cosine
                    row.combinedScore = 0.6 * row.categoryScore + 0.4 * ((cosine + 1) / 2)
                    rows.append(row)
                }
                try Task.checkCancellation()
                value.semantic = rows.sorted {
                    $0.semanticScore == $1.semanticScore
                        ? $0.id < $1.id : $0.semanticScore! > $1.semanticScore!
                }
                value.combined = rows.sorted {
                    $0.combinedScore == $1.combinedScore
                        ? $0.id < $1.id : $0.combinedScore! > $1.combinedScore!
                }
                value.status = "comparison_completed"
            } catch is CancellationError { throw CancellationError() } catch {
                value.embedding = nil
                value.semantic = []
                value.combined = []
                value.status = "category_fallback"
                value.warnings.append("Embeddings gagal: \(error.localizedDescription)")
            }
        }
        value.elapsedSeconds = Date().timeIntervalSince(began)
        try Self.validate(value)
        return value
    }
    public static func validate(_ run: QualityRun) throws {
        try run.catalog.validate()
        try run.profile.validate(catalog: run.catalog)
        let eligible = Set(
            try decisions(profile: run.profile, catalog: run.catalog, now: run.createdAt)
                .filter { $0.state == "eligible" }.map(\.id))
        guard run.schemaVersion == 1,
              ["quality-v1-category0.6-semantic0.4", "quality-v2-category0.6-semantic0.4"].contains(
                  run.policy),
              run.elapsedSeconds.isFinite, run.elapsedSeconds >= 0,
              [run.category, run.semantic, run.combined].allSatisfy({ rows in
                  Set(rows.map(\.id)).count == rows.count && Set(rows.map(\.id)).isSubset(of: eligible)
                      && rows.allSatisfy { row in
                          row.categoryScore.isFinite && (0 ... 1).contains(row.categoryScore)
                              && (row.semanticScore.map { $0.isFinite && (-1 ... 1).contains($0) } ?? true)
                              && (row.combinedScore.map { $0.isFinite && (0 ... 1).contains($0) } ?? true)
                      }
              })
        else { throw PreferenceError.invalid("Hasil ranking tidak sesuai kandidat terverifikasi.") }
    }
    public static func date(_ date: Date) -> String {
        let format = DateFormatter()
        format.timeZone = TimeZone(identifier: "Asia/Jakarta")
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }
}

public actor QualityStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func saveProfile(_ profile: QualityProfile, catalog: QualityCatalog) throws {
        try profile.validate(catalog: catalog)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder().encode(profile).write(
            to: directory.appendingPathComponent("current.profile"), options: .atomic)
    }
    public func profile(catalog: QualityCatalog) throws -> QualityProfile {
        let url = directory.appendingPathComponent("current.profile")
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let result = try JSONDecoder().decode(QualityProfile.self, from: Data(contentsOf: url))
        try result.validate(catalog: catalog)
        return result
    }
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
    public func save(_ run: QualityRun) throws {
        try Task.checkCancellation()
        try QualityPipeline.validate(run)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder().encode(run)
        let url = directory.appendingPathComponent("\(run.id).json")
        if FileManager.default.fileExists(atPath: url.path), try Data(contentsOf: url) != data {
            throw PreferenceError.invalid("ID eksperimen sudah dipakai.")
        }
        try data.write(to: url, options: .atomic)
    }
    public func history() throws -> (runs: [QualityRun], unreadable: Int) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], 0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var results: [QualityRun] = []
        var unreadable = 0
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            do {
                let value = try decoder.decode(QualityRun.self, from: Data(contentsOf: url))
                try QualityPipeline.validate(value)
                guard url.deletingPathExtension().lastPathComponent == value.id.uuidString else {
                    throw PreferenceError.invalid("Identitas berkas berbeda.")
                }
                results.append(value)
            } catch { unreadable += 1 }
        }
        return (results.sorted { $0.createdAt > $1.createdAt }, unreadable)
    }
    public func export(_ run: QualityRun) throws -> URL {
        try QualityPipeline.validate(run)
        let folder = directory.appendingPathComponent("Exports/\(run.id)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder().encode(run).write(to: folder.appendingPathComponent("run.json"), options: .atomic)
        try Data(run.markdown.utf8).write(
            to: folder.appendingPathComponent("REPORT.md"), options: .atomic)
        return folder
    }
}
extension QualityRun {
    public var markdown: String {
        func ranking(_ title: String, rows: [QualityRow]) -> String {
            title + "\n\n"
                + rows.prefix(3).map { row in
                    let candidate = catalog.candidates.first { $0.id == row.id }!
                    return "- \(candidate.name) / \(candidate.scope) — \(row.id)"
                }.joined(separator: "\n")
        }
        return """
        # Kecocokan preferensi — \(id)

        \(createdAt.ISO8601Format()); \(policy); \(status).
        Input edits \(inputChanges), corrections \(userCorrections), follow-up questions \(followupQuestions).
        These are local interaction counters, not observed reduction in user burden.

        \(ranking("## Category", rows: category))

        \(ranking("## Embeddings", rows: semantic))

        \(ranking("## Combined", rows: combined))

        ## Limits

        \(warnings.map { "- " + $0 }.joined(separator: "\n"))

        ## Sources

        \(catalog.sources.map { "- [\($0.title)](\($0.url)); checked \($0.checkedAt.ISO8601Format())" }.joined(separator: "\n"))
        """
    }
}
