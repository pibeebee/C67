import Foundation
import CryptoKit

public enum PlanAudit {
    private static let bundledNetwork = Result { try BuswayFeed.network() }
    private static let bundledLegacy = Result { try BuswayFeed.load() }
    public static func validate(_ plan: IntegratedPlan) throws {
        guard plan.schemaVersion == 1, plan.prepared.request.id == plan.request.id,
              plan.prepared.request.revision == plan.request.revision,
              plan.quality.profile == plan.request.profile,
              plan.prepared.request == plan.request,
              plan.request.originPin.map({ $0 == plan.prepared.locations.first { $0.id == "origin" }?.selected }) ?? true,
              plan.prepared.selectedIDs.allSatisfy({ plan.request.includesArea(candidateID: $0) }),
              Set(plan.prepared.selectedIDs).count == plan.prepared.selectedIDs.count,
              (1 ... 6).contains(plan.prepared.selectedIDs.count),
              Set(plan.request.requiredCandidateIDs).isSubset(of: Set(plan.prepared.selectedIDs)),
              plan.travelMinutes.isFinite, plan.travelMinutes >= 0,
              plan.waitingMinutes.isFinite, plan.waitingMinutes >= 0,
              Set(plan.stops.map(\.id)).count == plan.stops.count,
              Set(plan.stops.map(\.venueID)).count == plan.stops.count,
              plan.stops.allSatisfy({ stop in
                  guard let candidate = plan.quality.catalog.candidates.first(where: { $0.id == stop.id }),
                        let timing = plan.timing.first(where: { $0.venue.id == stop.venueID }),
                        candidate.venueID == stop.venueID, stop.name == candidate.name, stop.area == candidate.scope,
                        !stop.sourceIDs.isEmpty,
                        Set(stop.sourceIDs) == Set(candidate.sourceIDs + timing.venue.sourceIDs)
                  else { return false }
                  return IntegrationCatalog.contains(stop.pin) && stop.arrival <= stop.visit && stop.visit < stop.leave
                      && abs(stop.leave.timeIntervalSince(stop.visit) - Double(stop.duration) * 60) < 0.01
                      && (stop.rainChance.map { $0.isFinite && (0 ... 1).contains($0) } ?? true)
              }) else { throw IntegrationError.invalid("Kontrak hasil tersimpan tidak valid.") }
        if plan.request.effectiveTransport == .transjakartaBRT {
            guard ["live_gtfs_estimate", "synthetic_replay"].contains(plan.evidenceMode) else {
                throw IntegrationError.invalid("Label bukti BRT tidak sesuai.")
            }
            for (index, leg) in plan.legs.enumerated() where leg.providerStatus == "available" {
                guard let journey = leg.busway, let seconds = leg.seconds, let arrival = leg.arrival,
                      (journey.ride == nil ? leg.mode == "walking" : leg.mode == "transit"),
                      abs(journey.departure.timeIntervalSince(leg.departure)) < 1.01,
                      abs(journey.arrival.timeIntervalSince(arrival)) < 1.01,
                      abs(journey.seconds - seconds) < 1.01 else {
                    throw IntegrationError.invalid("Bukti ruas BRT hilang atau durasinya berubah.")
                }
                try journey.validate()
                let sourceFeed = try (journey.source.id == bundledLegacy.get().source.id ? bundledLegacy : bundledNetwork).get()
                guard sourceFeed.source == journey.source,
                      journey.rides.allSatisfy({ ride in
                          sourceFeed.patterns.contains(ride.pattern)
                              && sourceFeed.stops.contains(ride.board) && sourceFeed.stops.contains(ride.alight)
                      }) else { throw IntegrationError.invalid("Bukti bus berbeda dari snapshot sumber.") }
                if let connection = journey.connection, let first = journey.ride {
                    guard sourceFeed.transfers?.contains(where: {
                        $0.fromStopID == first.alight.id && $0.toStopID == connection.ride.board.id
                            && $0.minimumSeconds == connection.bufferSeconds && $0.evidence == connection.evidence
                    }) == true else { throw IntegrationError.invalid("Bukti transfer berbeda dari snapshot sumber.") }
                }
                let expectedStart = index == 0 ? plan.prepared.locations.first { $0.id == "origin" }?.selected : (index - 1 < plan.stops.count ? plan.stops[index - 1].pin : nil)
                let expectedEnd = index < plan.stops.count ? plan.stops[index].pin : plan.prepared.locations.first { $0.id == "origin" }?.selected
                let end = journey.egress?.to ?? journey.access.to
                guard let expectedStart, let expectedEnd,
                      journey.access.from.latitude == expectedStart.latitude, journey.access.from.longitude == expectedStart.longitude,
                      end.latitude == expectedEnd.latitude, end.longitude == expectedEnd.longitude,
                      plan.evidenceMode == "synthetic_replay" || journey.walks.allSatisfy({ $0.provider == "mapkit_walking" }) else {
                    throw IntegrationError.invalid("Lokasi/sumber walking tidak sesuai ruas itinerary.")
                }
            }
        } else if plan.legs.contains(where: { $0.busway != nil }) {
            throw IntegrationError.invalid("Bukti BRT tidak sesuai pilihan moda.")
        }
        if plan.feasible {
            guard Set(plan.stops.map(\.id)) == Set(plan.prepared.selectedIDs),
                  let finish = plan.finish, finish <= plan.request.deadline,
                  plan.legs.count == plan.stops.count + 1,
                  plan.legs.allSatisfy({ $0.providerStatus == "available" && ($0.seconds ?? -1) >= 0 }),
                  plan.stops.allSatisfy({ stop in
                      guard let timing = plan.timing.first(where: { $0.venue.id == stop.venueID }) else { return false }
                      return VisitStartPolicy.earliest(arrival: stop.visit, tripDate: plan.request.departure,
                                                       ranges: timing.validStartRanges) == stop.visit
                  }) else { throw IntegrationError.invalid("Audit hasil layak gagal: tujuan, jam layanan, ETA atau deadline.") }
        }
    }
}

public struct SessionLoad: Sendable {
    public var session: IntegrationSession
    public var warnings: [String]
}

public actor TripStore {
    public let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                               in: .userDomainMask)[0].appendingPathComponent("C67TripIntegration-v1", isDirectory: true)
    }
    private struct Envelope: Codable {
        var schemaVersion = 1
        var payload: Data
        var sha256: String
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func canonicalRun(_ data: Data) throws -> Data {
        func normalize(_ value: Any, key: String = "") -> Any {
            if let dictionary = value as? [String: Any] {
                return dictionary.mapValues { $0 }.reduce(into: [String: Any]()) { output, pair in
                    output[pair.key] = normalize(pair.value, key: pair.key)
                }
            }
            if let values = value as? [String], ["must", "prefer", "avoid", "excludedIDs"].contains(key) { return values.sorted() }
            if let values = value as? [Any] { return values.map { normalize($0) } }
            return value
        }
        return try JSONSerialization.data(withJSONObject: normalize(JSONSerialization.jsonObject(with: data)), options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func validate(_ session: IntegrationSession) throws {
        guard session.schemaVersion == 1 else { throw IntegrationError.invalid("Versi sesi tidak didukung.") }
        if let accepted = session.accepted { try PlanAudit.validate(accepted); guard accepted.feasible else { throw IntegrationError.invalid("Jadwal diterima tidak layak.") } }
        if let proposal = session.proposal {
            try PlanAudit.validate(proposal)
            guard proposal.baseAcceptedID == session.accepted?.id else { throw IntegrationError.invalid("Usulan berasal dari versi lama.") }
        }
    }
    private func decode(_ file: URL) throws -> IntegrationSession {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 25_000_000 else { throw IntegrationError.invalid("File sesi melampaui batas 25 MB.") }
        let envelope = try IntegrationJSON.decoder().decode(Envelope.self, from: Data(contentsOf: file))
        guard envelope.schemaVersion == 1, hash(envelope.payload) == envelope.sha256 else { throw IntegrationError.invalid("Checksum sesi tidak sesuai.") }
        let session = try IntegrationJSON.decoder().decode(IntegrationSession.self, from: envelope.payload)
        try validate(session)
        return session
    }
    public func load() throws -> SessionLoad {
        let file = directory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .init(session: .init(), warnings: []) }
        do { return .init(session: try decode(file), warnings: []) }
        catch {
            let backup = directory.appendingPathComponent("session.previous.json")
            let quarantine = directory.appendingPathComponent("session.corrupt-\(UUID().uuidString).json")
            // Preserve the damaged artifact for diagnosis. Never overwrite it with an empty session.
            try FileManager.default.copyItem(at: file, to: quarantine)
            guard FileManager.default.fileExists(atPath: backup.path) else {
                throw IntegrationError.invalid("Sesi rusak, salinan diagnosis disimpan; tidak ada backup valid. \(error.localizedDescription)")
            }
            let restored = try decode(backup)
            try Data(contentsOf: backup).write(to: file, options: .atomic)
            return .init(session: restored, warnings: ["Sesi utama rusak; memulihkan versi sebelumnya. File rusak dipertahankan."])
        }
    }
    public func save(_ session: IntegrationSession) throws {
        try validate(session)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var archive: (URL, Data)?
        if let proposal = session.proposal {
            let history = directory.appendingPathComponent("runs", isDirectory: true)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            let path = history.appendingPathComponent("\(proposal.id).json")
            let bytes = try canonicalRun(IntegrationJSON.encoder().encode(proposal))
            if FileManager.default.fileExists(atPath: path.path) {
                guard try canonicalRun(Data(contentsOf: path)) == bytes else {
                    throw IntegrationError.invalid("Run ID telah dipakai untuk data berbeda; sesi tidak diubah.")
                }
            } else { archive = (path, bytes) }
        }
        let file = directory.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try decode(file) // Do not replace an unexamined corrupt primary.
            try Data(contentsOf: file).write(to: directory.appendingPathComponent("session.previous.json"), options: .atomic)
        }
        let payload = try IntegrationJSON.encoder().encode(session)
        let envelope = Envelope(payload: payload, sha256: hash(payload))
        if let archive { try archive.1.write(to: archive.0, options: .atomic) }
        try IntegrationJSON.encoder().encode(envelope).write(to: file, options: .atomic)
    }
    public func export(_ plan: IntegratedPlan) throws -> URL {
        try PlanAudit.validate(plan)
        let folder = directory.appendingPathComponent("exports/\(plan.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try IntegrationJSON.encoder().encode(plan).write(to: folder.appendingPathComponent("experiment.json"), options: .atomic)
        try PlanExplanation.markdown(plan).write(to: folder.appendingPathComponent("REPORT.md"), atomically: true, encoding: .utf8)
        if let raw = plan.rawRoutingReport { try raw.write(to: folder.appendingPathComponent("native-report.json"), options: .atomic) }
        if let log = plan.providerLog { try log.write(to: folder.appendingPathComponent("provider-log.jsonl"), options: .atomic) }
        return folder
    }
}

extension PlanExplanation {
    public static func markdown(_ plan: IntegratedPlan) -> String {
        let sources = plan.timing.flatMap(\.sources).map {
            "- [\($0.id): \($0.title)](\($0.url.absoluteString)); checked \($0.checkedAt.ISO8601Format())"
        } + plan.quality.catalog.sources.map {
            "- [\($0.id): \($0.title)](\($0.url.absoluteString)); checked \($0.checkedAt.ISO8601Format()); sha256 \($0.sha256)"
        }
        let stops = plan.stops.map {
            "- \($0.name) / \($0.area): arrival \(TripClock.label($0.arrival)); visit \(TripClock.label($0.visit))–\(TripClock.label($0.leave)); rain \($0.rainChance.map { String(format: "%.0f%%", $0 * 100) } ?? "unknown"); \($0.weatherProvider ?? "unknown provider")."
        }
        let journeys = plan.legs.compactMap(\.busway)
        let transport = plan.legs.flatMap { leg -> [String] in
            var details = ["- \(leg.from) → \(leg.to). \(TripClock.label(leg.departure)). \(leg.busway?.summary ?? leg.mode ?? "automobile")."]
            for ride in leg.busway?.rides ?? [] {
                details.append("- TJ \(ride.pattern.effectiveRouteID), \(ride.pattern.effectiveCategory), direction \(ride.headsign). Board \(ride.board.name) [\(ride.board.id)] at \(TripClock.label(ride.boardAt)). Alight \(ride.alight.name) [\(ride.alight.id)] at \(TripClock.label(ride.alightAt)).")
            }
            if let connection = leg.busway?.connection {
                details.append("- Transfer walking \(Int(connection.walk.seconds)) seconds, additional buffer \(Int(connection.bufferSeconds)) seconds. \(connection.evidence).")
            }
            return details
        }
        let busSources = journeys.map { journey in
            "- \(journey.source.publisher), [GTFS](\(journey.source.sourceURL)). [CC BY 4.0](\(journey.source.licenseURL)). [Attribution](\(journey.source.attributionURL)). Checked \(journey.source.checkedAt.ISO8601Format()). SHA256 \(journey.source.sourceSHA256). \(journey.source.modification)"
        }
        let metrics = plan.metrics.map { "- \($0.stage): \(String(format: "%.3f", $0.seconds)) s, \($0.requests) requests/group fetches." }
        let weather = plan.weather.map {
            "- \($0.provider): \($0.status), members \($0.memberIDs.joined(separator: ", ")); representative \($0.representative.name); metadata \($0.fetchedAt.ISO8601Format()); retrieved \($0.retrievedAt.ISO8601Format()); cache \($0.cached); \($0.credit?.legalURL.absoluteString ?? "no attribution"). Errors: \($0.errors.joined(separator: "; "))"
        }
        return (["# C67 Priority 3 run \(plan.id)", "", "Evidence: \(plan.evidenceMode). Status: \(plan.status). \(plan.summary)", "", "Origin: \(plan.request.originQuery)",
                 "Target areas: \((plan.request.targetAreas ?? []).isEmpty ? "All catalog areas" : plan.request.targetAreas!.map(\.label).joined(separator: ", "))",
                 "Required spots: \(plan.request.requiredCandidateIDs.joined(separator: ", "))", "", "## Schedule", ""]
                + stops + ["", "## Transport", ""] + transport + busSources + ["", "## Conflicts", ""] + plan.conflicts.map { "- " + $0 }
                + ["", "## Uncertainties", ""] + plan.uncertainties.map { "- " + $0 }
                + ["", "## Weather evidence", ""] + weather + ["", "## Metrics", ""] + metrics
                + ["", "## Sources", ""] + Array(Set(sources)).sorted()
                + ["", "No backend is required. This run alone does not establish user satisfaction, current venue availability or global optimality.", ""]).joined(separator: "\n")
    }
}
