import Foundation

@main struct NativeTripLogChecks {
    @MainActor static func main() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.count == 3, arguments[1] == "--seed" {
            let store = NativeTripLogStore(directory: URL(fileURLWithPath: arguments[2]))
            store.record(
                "persisted.fixture", category: "check",
                fields: ["query": "Test place", "operation": "cross-process"])
            await store.flush()
            precondition(store.storageError == nil)
            return
        }
        if arguments.count == 3, arguments[1] == "--read" {
            let store = NativeTripLogStore(directory: URL(fileURLWithPath: arguments[2]))
            let snapshot = try await store.snapshot()
            precondition(
                snapshot.recent.contains {
                    $0.event == "persisted.fixture" && $0.fields["operation"] == "cross-process"
                })
            print("PASS 9: log written by a terminated process is readable in a separate process")
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c67-log-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let normal = root.appendingPathComponent("normal")
        let first = NativeTripLogStore(directory: normal)
        first.record(
            "search.requested", category: "mapkit", operationID: "lookup-1",
            fields: ["query": "Cafe\n東京", "coordinate": "-6.17,106.82"])
        let one = try await first.snapshot()
        precondition(first.storageError == nil && first.savedEvents == 2 && one.fileCount == 1)
        precondition(one.invalidLines == 0 && one.recent.last?.fields["query"] == "Cafe\n東京")
        precondition(one.data.split(separator: 10).count == 2)
        print(
            "PASS 1: automatic append, synchronize, valid JSON Lines and Unicode/newline preservation")

        for i in 0 ..< 25 { first.record("ordered", category: "check", fields: ["index": String(i)]) }
        let ordered = try await first.snapshot()
        precondition(ordered.recent.map(\.sequence) == Array(1 ... 27))
        precondition(ordered.recent.last?.fields["index"] == "24")
        print("PASS 2: queued events retain order; snapshot waits for pending writes")

        let second = NativeTripLogStore(directory: normal)
        let restarted = try await second.snapshot()
        precondition(
            restarted.fileCount == 2
                && restarted.recent.contains {
                    $0.sessionID == first.sessionID && $0.operationID == "lookup-1"
                })
        precondition(restarted.recent.last?.sessionID == second.sessionID)
        print("PASS 3: a new store/session reopens earlier on-disk logs")

        second.record(
            "oversized", category: "check",
            fields: Dictionary(
                uniqueKeysWithValues: (0 ..< 64).map { ("field\($0)", String(repeating: "A", count: 6000)) }))
        let oversized = try await second.snapshot()
        precondition(
            oversized.recent.last?.fields["truncated"] == "true" && oversized.invalidLines == 0)
        print("PASS 4: oversized record is bounded and explicitly marked, without invalid JSON")

        let rotating = root.appendingPathComponent("rotation")
        let bounded = NativeTripLogStore(directory: rotating, maximumFiles: 3, maximumBytes: 1024)
        for i in 0 ..< 25 {
            bounded.record(
                "rotation.\(i)", category: "check", fields: ["payload": String(repeating: "R", count: 900)])
        }
        let rotated = try await bounded.snapshot()
        let files = try FileManager.default.contentsOfDirectory(
            at: rotating, includingPropertiesForKeys: [.fileSizeKey])
        precondition(rotated.fileCount == 3 && rotated.recent.last?.event == "rotation.24")
        for file in files {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!
            precondition(size <= 1024)
        }
        print("PASS 5: rotation keeps latest files within count/size limits")

        let firstFile = try FileManager.default.contentsOfDirectory(
            at: normal, includingPropertiesForKeys: nil
        ).first!
        let handle = try FileHandle(forWritingTo: firstFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{partial-record".utf8))
        try handle.close()
        let damaged = try await second.snapshot()
        precondition(
            damaged.invalidLines == 1
                && String(decoding: damaged.data, as: UTF8.self).contains("{partial-record"))
        print(
            "PASS 6: damaged lines are reported and preserved in raw export, without hiding valid events")

        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blocked)
        let failed = NativeTripLogStore(directory: blocked)
        failed.record("must-not-crash", category: "check")
        await failed.flush()
        precondition(failed.storageError != nil && failed.savedEvents == 0)
        print("PASS 7: storage failures are surfaced without crashing or reporting successful writes")

        let underlying = NSError(
            domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "Timed out"])
        let error = NSError(
            domain: "MKErrorDomain", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
        let fields = NativeTripLogStore.errorFields(error)
        precondition(
            fields["domain"] == "MKErrorDomain" && fields["code"] == "1"
                && fields["underlying.0"]?.contains("-1001") == true)
        print("PASS 8: error domain/code and underlying failure retained for debugging")
        print("8 persistent-log checks passed on macOS; no network, iOS tests or Simulator.")
    }
}
