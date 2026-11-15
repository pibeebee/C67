import Foundation
import Observation

struct NativeTripLogEvent: Codable, Identifiable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var at = Date()
    var sessionID: String
    var sequence: Int
    var operationID: String?
    var level: String
    var category: String
    var event: String
    var fields: [String: String]
}

struct NativeTripLogSnapshot: Sendable {
    var data: Data
    var recent: [NativeTripLogEvent]
    var fileCount: Int
    var invalidLines: Int
}

// All disk access stays off the main actor. Each event is appended and synchronized separately.
actor NativeTripLogWriter {
    let directory: URL
    private let sessionID: String
    private let maximumFiles: Int
    private let maximumBytes: Int
    private var file: URL?
    private var bytes = 0
    private var part = 0

    init(directory: URL, sessionID: String, maximumFiles: Int = 10, maximumBytes: Int = 2_000_000) {
        self.directory = directory
        self.sessionID = sessionID
        self.maximumFiles = max(1, maximumFiles)
        self.maximumBytes = max(1024, maximumBytes)
    }

    private func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("log-") }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
    }

    func append(_ input: NativeTripLogEvent) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directoryURL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directoryURL.setResourceValues(values)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var record = input
        record.fields = input.fields.sorted { $0.key < $1.key }.prefix(64).reduce(into: [:]) {
            result, field in
            let value =
                field.value.count > 16_384
                    ? String(field.value.prefix(16_384)) + " [truncated]" : field.value
            result[String(field.key.prefix(256))] = value
        }
        var data = try encoder.encode(record)
        // A pasted list or provider error must not create an unbounded log record.
        if data.count > min(131_072, maximumBytes / 2) {
            record.fields = [
                "truncated": "true",
                "preview": String(decoding: data.prefix(min(4096, maximumBytes / 8)), as: UTF8.self),
            ]
            data = try encoder.encode(record)
        }
        data.append(10)
        if file == nil || bytes + data.count > maximumBytes {
            part += 1
            let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
            let name = "log-\(stamp)-\(sessionID)-\(String(format: "%04d", part)).jsonl"
            let next = directory.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: next.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            file = next
            bytes = 0
            let stored = try files()
            for old in stored.prefix(max(0, stored.count - maximumFiles)) where old != next {
                try FileManager.default.removeItem(at: old)
            }
        }
        guard let file else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            bytes += data.count
        } catch {
            // Preserve any partial line; the next event starts a new file instead of appending to it.
            self.file = nil
            bytes = 0
            throw error
        }
    }

    func snapshot() throws -> NativeTripLogSnapshot {
        var data = Data()
        var recent: [NativeTripLogEvent] = []
        var invalid = 0
        let stored = try files()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in stored {
            let contents = try Data(contentsOf: file)
            data.append(contents)
            if !contents.isEmpty && contents.last != 10 { data.append(10) }
            for line in contents.split(separator: 10) where !line.isEmpty {
                do { recent.append(try decoder.decode(NativeTripLogEvent.self, from: Data(line))) } catch {
                    invalid += 1
                }
            }
            recent = Array(recent.suffix(80))
        }
        return .init(data: data, recent: recent, fileCount: stored.count, invalidLines: invalid)
    }
}

@MainActor @Observable final class NativeTripLogStore {
    static let shared = NativeTripLogStore()
    let sessionID = UUID().uuidString
    let directory: URL
    private(set) var storageError: String?
    private(set) var savedEvents = 0
    @ObservationIgnored private let writer: NativeTripLogWriter
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var sequence = 0

    init(directory: URL? = nil, maximumFiles: Int = 10, maximumBytes: Int = 2_000_000) {
        self.directory =
            directory
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("NativeTripLogs", isDirectory: true)
        writer = NativeTripLogWriter(
            directory: self.directory, sessionID: sessionID, maximumFiles: maximumFiles,
            maximumBytes: maximumBytes)
        record(
            "session.started", category: "app",
            fields: [
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? "unknown",
                "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "retention": "\(maximumFiles) files, \(maximumBytes) bytes/file; local only",
                "format": "C67-native-log-v1; JSON Lines",
            ])
    }

    func record(
        _ event: String, category: String, level: String = "info", operationID: String? = nil,
        fields: [String: String] = [:]
    ) {
        sequence += 1
        let entry = NativeTripLogEvent(
            sessionID: sessionID, sequence: sequence, operationID: operationID, level: level,
            category: category, event: event, fields: fields)
        let previous = pending
        pending = Task { [self] in
            await previous?.value
            do {
                try await writer.append(entry)
                savedEvents += 1
            } catch {
                // Visible to the UI. Do not recurse into the failing logger or interrupt planning.
                storageError = "Sebagian log gagal disimpan: \(error.localizedDescription)"
            }
        }
    }

    func recordJSON<Value: Encodable>(
        _ event: String, category: String, operationID: String? = nil, value: Value
    ) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            record(
                event, category: category, operationID: operationID,
                fields: ["json": String(decoding: data, as: UTF8.self)])
        } catch {
            record(
                "log.encoding_failed", category: "log", level: "error", operationID: operationID,
                fields: Self.errorFields(error))
        }
    }

    static func errorFields(_ error: Error) -> [String: String] {
        let root = error as NSError
        var fields = [
            "domain": root.domain, "code": String(root.code), "description": root.localizedDescription,
        ]
        var current = root
        for index in 0 ..< 4 {
            guard let next = current.userInfo[NSUnderlyingErrorKey] as? NSError, next !== current else {
                break
            }
            fields["underlying.\(index)"] = "\(next.domain) [\(next.code)] \(next.localizedDescription)"
            current = next
        }
        return fields
    }

    func flush() async { await pending?.value }

    func snapshot() async throws -> NativeTripLogSnapshot {
        await flush()
        return try await writer.snapshot()
    }
}
