#if os(iOS)
    import SwiftUI
    import TripIntegration

    @main struct C67PerformanceApp: App {
        var body: some Scene { WindowGroup { BenchmarkView() } }
    }

    struct BenchmarkView: View {
        @State private var benchmark: PerformanceBenchmark
        init() {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let folder = documents.appendingPathComponent("C67Performance/\(UUID())")
            _benchmark = State(initialValue: try! PerformanceBenchmark(folder: folder))
        }
        var body: some View {
            NavigationStack {
                List {
                    Text("Benchmark only · isolated storage · real providers")
                    Text(benchmark.progress)
                    Text(benchmark.folder.lastPathComponent).font(.caption).textSelection(.enabled)
                    if !benchmark.complete { ProgressView() }
                    ForEach(benchmark.results, id: \.id) { row in
                        Text("\(row.id): \(row.seconds, specifier: "%.2f")s · \(row.observed) · \(row.passed ? "pass" : "FAIL")")
                    }
                }.navigationTitle("C67 · Performance")
            }.task {
                UIApplication.shared.isIdleTimerDisabled = true
                await benchmark.run()
                // Keep the screen on until evidence is retrieved and the normal app is restored.
            }
        }
    }
#else
    import Foundation
    import TripIntegration

    @main struct BenchmarkCLI {
        @MainActor static func main() async throws {
            guard CommandLine.arguments.count == 2 else { fatalError("Supply a fresh evidence directory") }
            let folder = URL(filePath: CommandLine.arguments[1])
            guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent("status.json").path) else {
                fatalError("Use a fresh evidence directory")
            }
            let benchmark = try PerformanceBenchmark(folder: folder, now: {
                TripClock.date("2026-11-06T00:00:00Z")
            })
            await benchmark.run()
            if !benchmark.complete || benchmark.results.count != 17 || benchmark.results.contains(where: { !$0.passed }) { exit(1) }
        }
    }
#endif
