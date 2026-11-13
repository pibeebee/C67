import Foundation
import PlannerContracts

@MainActor public final class LabWorker {
    public let store: JobStore
    public let runtime: LabRuntime
    public let mode: LabProviderMode
    public let snapshot: String
    public let directory: URL
    public let timeoutSeconds: Double
    private let apple: LabAppleREST?
    private let pinSnapshot: LabPinSnapshot?
    public let pinSnapshotHash: String
    public var providerCalls: Int { apple?.budget.calls ?? 0 }
    public var providerCells: Int { apple?.budget.cells ?? 0 }
    private var pump: Task<Void, Never>?
    private var operation: Task<LabOutcome, Error>?
    private var active: UUID?
    public init(store: JobStore, directory: URL, mode: LabProviderMode, timeoutSeconds: Double = 240,
                apple: LabAppleREST? = nil, pinSnapshot: LabPinSnapshot? = nil) throws {
        self.store = store; self.directory = directory; self.mode = mode; self.apple = apple
        if let pinSnapshot { try pinSnapshot.validate(now: .now) }
        self.pinSnapshot = pinSnapshot; pinSnapshotHash = try pinSnapshot.map { try LabJSON.hash($0) } ?? ""
        self.timeoutSeconds = timeoutSeconds; snapshot = try LabSnapshot.hash()
        runtime = try LabRuntime(embeddingDirectory: directory.appendingPathComponent("embeddings"))
        guard mode != .rest || apple != nil else { throw LabFailure.unavailable("REST configuration missing") }
    }
    public func submit(_ input: JobInput) throws -> LabJob {
        let value = try store.submit(input, snapshot: snapshot)
        start(); return value
    }
    public func cancel(_ id: UUID) throws -> LabJob {
        guard var job = try store.get(id) else { throw LabFailure.invalid("Unknown job") }
        if !job.state.terminal {
            job.state = .cancelled; job.completedAt = .now; job.progress = "cancelled"; try store.save(job)
            if active == id { operation?.cancel() }
        }
        return job
    }
    public func shutdown() {
        operation?.cancel(); pump?.cancel(); operation = nil; pump = nil
    }
    private func start() {
        guard pump == nil else { return }
        pump = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { pump = nil }
            do {
                while !Task.isCancelled, let job = try store.all().first(where: { $0.state == .queued }) {
                    await execute(job)
                }
            } catch { print("LAB_WORKER storage_failure") }
        }
    }
    private func progress(_ message: String, id: UUID) {
        guard var job = try? store.get(id), job.state == .running else { return }
        job.progress = String(message.prefix(500)); try? store.save(job)
    }
    private func execute(_ initial: LabJob) async {
        var job = initial; active = job.id
        defer { active = nil; operation = nil }
        do {
            job.state = .running; job.startedAt = .now; job.progress = "preference"; try store.save(job)
            let id = job.id; let input = job.input
            let directory = directory.appendingPathComponent("jobs/\(id)")
            let operation = Task { @MainActor [self] in
                var result = try await runtime.run(input.request, variant: input.variant, mode: mode,
                                                   now: mode == .replay ? LabMatrix.now : .now, directory: directory,
                                                   baseAcceptedID: input.baseAcceptedID,
                                                   eta: apple.map { LabRESTETA(apple: $0) },
                                                   search: pinSnapshot != nil ? try LabPinnedSearch(snapshot: pinSnapshot!) : apple.map { LabRESTSearch(apple: $0) }, weather: apple.map { LabRESTWeather(apple: $0) },
                                                   progress: { [weak self] message in self?.progress(message, id: id) })
                if pinSnapshot != nil { result.evidence += "_shared_real_pins" }
                return result
            }
            self.operation = operation
            let deadline = Task { @MainActor [self] in
                do { try await Task.sleep(for: .seconds(timeoutSeconds)) } catch { return }
                guard var job = try? store.get(id), job.state == .running else { return }
                job.state = .timedOut; job.completedAt = .now; job.error = "observation_limit_censored"
                try? store.save(job); operation.cancel()
            }
            defer { deadline.cancel() }
            let result = try await operation.value
            guard let latest = try store.get(id), latest.state == .running, !Task.isCancelled else { return }
            job = latest; job.result = result; job.state = .completed; job.progress = result.outcome
            job.completedAt = .now; try store.save(job)
        } catch {
            guard var latest = try? store.get(job.id), !latest.state.terminal else { return }
            latest.state = Task.isCancelled || error is CancellationError ? .cancelled : .failed
            latest.error = String(error.localizedDescription.prefix(1000)); latest.completedAt = .now
            try? store.save(latest)
        }
    }
}
