import Foundation

enum TripRoutingAlgorithm: String, Codable, CaseIterable, Identifiable, Sendable {
    case baseline, hybrid, local, insertion, beam, alns, exact, ortools
    var id: String { rawValue }
    var title: String {
        switch self {
        case .baseline: "Baseline geografis"
        case .hybrid: "Hybrid · durasi trip"
        case .local: "Multi-start + local search"
        case .insertion: "Cheapest insertion + local"
        case .beam: "Beam berbasis waktu"
        case .alns: "ALNS"
        case .exact: "Enumerasi urutan ≤8"
        case .ortools: "OR-Tools GLS · impor Mac"
        }
    }
    static var native: [Self] { allCases.filter { $0 != .ortools } }
}

struct TripRoutingNode: Codable, Sendable {
    var id: String
    var name: String
    var x: Double
    var y: Double
    var dwell: Double
    var opens: Double?
    var closes: Double?
    var exposure: Double?
}

struct TripRoutingArc: Codable, Sendable {
    var from: Int
    var to: Int
    var mode: String
    var seconds: Double?
    var start: Double = 0
    var end: Double = 172800
    var status = "available"
    var note: String? = nil
}

struct TripRoutingModeCoverage: Codable, Identifiable, Sendable {
    var mode: String
    var sampled: Int
    var available: Int
    var statuses: [String: Int]
    var id: String { mode }
}

struct TripRoutingPairCoverage: Codable, Identifiable, Sendable {
    var from: Int
    var to: Int
    var reasons: [String]
    var id: String { "\(from):\(to)" }
}

struct TripRoutingCoverage: Codable, Sendable {
    var requiredPairs: Int
    var availablePairs: Int
    var unsampledPairs: Int
    var modes: [TripRoutingModeCoverage]
    var blockedPairs: [TripRoutingPairCoverage]
}

struct TripRoutingWeather: Codable, Sendable {
    var node: Int
    var start: Double
    var end: Double
    var chance: Double
}

struct TripRoutingProblem: Codable, Sendable {
    var schemaVersion = 1
    var id = UUID().uuidString
    var label: String
    var kind: String
    var nodes: [TripRoutingNode]
    var targets: [Int]
    var origin: Int
    var end: Int
    var deadline: Double
    var arcs: [TripRoutingArc]
    var baselineOrders: [[Int]]
    var weather: [TripRoutingWeather] = []
    var extraWeatherSeconds: Double = 900
    var rainWeight: Double = 2
    var weatherSources: [String: String]? = nil
    var weatherAttribution: [String]? = nil
    var privateCar: Bool? = nil
    var objective: String? = "elapsed_v2"

    // Directed pairs needed for every possible ordering, excluding a stationary final leg.
    var coverage: TripRoutingCoverage {
        var pairs = Set<String>()
        var required: [(Int, Int)] = []
        func add(_ a: Int, _ b: Int) {
            if a != b && pairs.insert("\(a):\(b)").inserted { required.append((a, b)) }
        }
        for to in targets { add(origin, to) }
        for from in targets {
            for to in targets where from != to { add(from, to) }
            add(from, end)
        }
        let grouped = Dictionary(grouping: arcs, by: { "\($0.from):\($0.to)" })
        var blocked: [TripRoutingPairCoverage] = []
        var unsampled = 0
        for (from, to) in required {
            let options = grouped["\(from):\(to)"] ?? []
            if options.contains(where: {
                $0.status == "available" && $0.seconds != nil && $0.start <= 0 && $0.end > 0
            }) {
                continue
            }
            if options.isEmpty { unsampled += 1 }
            blocked.append(
                .init(
                    from: from, to: to,
                    reasons: options.isEmpty
                        ? ["not_sampled: batas request atau akuisisi dihentikan"]
                        : options.map { "\($0.mode): \($0.status)\($0.note.map { " · \($0)" } ?? "")" }))
        }
        var modes: [TripRoutingModeCoverage] = []
        for (mode, samples) in Dictionary(grouping: arcs, by: \.mode) {
            let sampled = Set(samples.map { "\($0.from):\($0.to)" }).count
            let available = samples.filter {
                $0.status == "available" && $0.seconds != nil && $0.start <= 0 && $0.end > 0
            }
            let availableCount = Set(available.map { "\($0.from):\($0.to)" }).count
            let statuses = Dictionary(grouping: samples, by: \.status).mapValues { $0.count }
            modes.append(
                .init(mode: mode, sampled: sampled, available: availableCount, statuses: statuses))
        }
        modes.sort { $0.mode < $1.mode }
        return .init(
            requiredPairs: required.count, availablePairs: required.count - blocked.count,
            unsampledPairs: unsampled, modes: modes, blockedPairs: blocked)
    }

    func validate() throws {
        guard schemaVersion == 1, (1 ... 20).contains(targets.count), nodes.count <= 22,
              nodes.indices.contains(origin), nodes.indices.contains(end), deadline.isFinite, deadline > 0,
              Set(nodes.map(\.id)).count == nodes.count, Set(targets).count == targets.count,
              targets.allSatisfy({ nodes.indices.contains($0) && $0 != origin && $0 != end })
        else { throw TripRoutingFailure.invalid("Struktur kasus routing tidak valid.") }
        guard baselineOrders.allSatisfy({ $0.count == targets.count && Set($0) == Set(targets) }) else {
            throw TripRoutingFailure.invalid("Seed urutan tidak sesuai tujuan.")
        }
        for node in nodes {
            guard node.x.isFinite, node.y.isFinite, node.dwell.isFinite, node.dwell >= 0,
                  node.opens.map({ $0.isFinite }) ?? true, node.closes.map({ $0.isFinite }) ?? true,
                  node.exposure.map({ $0.isFinite && (0 ... 1).contains($0) }) ?? true
            else { throw TripRoutingFailure.invalid("Parameter tempat tidak valid.") }
            if let opens = node.opens, let closes = node.closes, opens > closes {
                throw TripRoutingFailure.invalid("Jam buka/tutup tidak valid.")
            }
        }
        for arc in arcs {
            guard nodes.indices.contains(arc.from), nodes.indices.contains(arc.to),
                  arc.start.isFinite, arc.end.isFinite, arc.end > arc.start,
                  arc.seconds.map({ $0.isFinite && $0 >= 0 }) ?? true
            else { throw TripRoutingFailure.invalid("Data ETA tidak valid.") }
        }
        guard
            weather.allSatisfy({
                nodes.indices.contains($0.node) && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
                    && $0.chance.isFinite && (0 ... 1).contains($0.chance)
            }),
            extraWeatherSeconds.isFinite, extraWeatherSeconds >= 0, rainWeight.isFinite, rainWeight >= 0
        else { throw TripRoutingFailure.invalid("Data cuaca tidak valid.") }
    }
}

enum TripRoutingFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { text } else { nil } }
}

struct TripRoutingConfiguration: Codable, Sendable {
    var seed: UInt64 = 67
    var evaluationLimit = 100_000
    var secondsLimit = 3.0
    var beamWidth = 8
    var iterations = 150
}

struct TripRoutingLeg: Codable, Sendable {
    var from: Int
    var to: Int
    var mode: String
    var departure: Double
    var arrival: Double
    var visit: Double
    var leave: Double
}

struct TripRoutingEvaluation: Codable, Sendable {
    var order: [Int]
    var complete = false
    var fullTour = false
    var travel = 0.0
    var waiting = 0.0
    var dwell = 0.0
    var finish = 0.0
    var rain = 0.0
    var unknownWeather = 0.0
    var missing = 0
    var conflicts: [String] = []
    var legs: [TripRoutingLeg] = []
    var feasible: Bool { complete && conflicts.isEmpty }
    var rank: Int { !complete ? 2 : conflicts.isEmpty ? 0 : 1 }
    var score: Double {
        Double(rank) * 1e12 + Double(missing + conflicts.count) * 1e9 + finish + waiting * 1e-6
    }
}

struct TripRoutingResult: Codable, Identifiable, Sendable {
    var algorithm: TripRoutingAlgorithm
    var problemID: String
    var configuration: TripRoutingConfiguration
    var alternatives: [TripRoutingEvaluation]
    var evaluations: Int
    var elapsed: Double
    var termination: String
    var proof: String
    var note: String
    var id: String { "\(algorithm.rawValue)-\(configuration.seed)" }
    var best: TripRoutingEvaluation? { alternatives.first }
}

struct TripRoutingEvaluator: Sendable {
    let problem: TripRoutingProblem
    private let arcs: [String: [TripRoutingArc]]
    init(_ problem: TripRoutingProblem) {
        self.problem = problem
        arcs = Dictionary(grouping: problem.arcs, by: { "\($0.from):\($0.to)" })
    }

    static func better(_ a: TripRoutingEvaluation, _ b: TripRoutingEvaluation) -> Bool {
        if a.rank != b.rank { return a.rank < b.rank }
        if a.missing != b.missing { return a.missing < b.missing }
        if a.conflicts.count != b.conflicts.count { return a.conflicts.count < b.conflicts.count }
        if a.finish != b.finish { return a.finish < b.finish }
        if a.travel != b.travel { return a.travel < b.travel }
        if a.waiting != b.waiting { return a.waiting < b.waiting }
        return a.order.lexicographicallyPrecedes(b.order)
    }

    func evaluate(_ order: [Int], requireAll: Bool = true, closeRoute: Bool = true)
        -> TripRoutingEvaluation
    {
        if problem.privateCar == true {
            let variants = [false, true].map {
                evaluateOrder(order, requireAll: requireAll, closeRoute: closeRoute, automobileOnly: $0)
            }
            return variants.min(by: Self.better)!
        }
        return evaluateOrder(order, requireAll: requireAll, closeRoute: closeRoute, automobileOnly: nil)
    }

    private func evaluateOrder(_ order: [Int], requireAll: Bool, closeRoute: Bool, automobileOnly: Bool?) -> TripRoutingEvaluation {
        var result = TripRoutingEvaluation(order: order)
        guard Set(order).count == order.count, Set(order).isSubset(of: Set(problem.targets)),
              !requireAll || Set(order) == Set(problem.targets)
        else {
            result.conflicts = ["Tujuan hilang, berulang, atau tidak sesuai kasus."]
            return result
        }
        var from = problem.origin
        var cursor = 0.0
        let route = order + (closeRoute ? [problem.end] : [])
        for (index, to) in route.enumerated() {
            let arc: TripRoutingArc?
            if from == to {
                arc = .init(from: from, to: to, mode: "stationary", seconds: 0)
            } else {
                arc = arcs["\(from):\(to)"]?.filter {
                    $0.status == "available" && $0.seconds != nil && $0.start <= cursor && cursor < $0.end
                        && (automobileOnly == nil || ($0.mode == "automobile") == automobileOnly!)
                }.min {
                    $0.seconds == $1.seconds
                        ? ($0.mode == $1.mode
                            ? false : $0.mode == "walking" || ($1.mode != "walking" && $0.mode < $1.mode))
                        : $0.seconds! < $1.seconds!
                }
            }
            guard let arc, let seconds = arc.seconds else {
                result.missing += 1
                result.finish = cursor
                return result
            }
            let arrival = cursor + seconds
            let isEnd = closeRoute && index == order.count
            let node = problem.nodes[to]
            let visit = isEnd ? arrival : max(arrival, node.opens ?? arrival)
            let dwell = isEnd ? 0 : node.dwell
            let leave = visit + dwell
            if !isEnd, let closes = node.closes, leave > closes + 0.000001 {
                result.conflicts.append("\(node.name): melewati tutup.")
            }
            if leave > problem.deadline + 0.000001, !result.conflicts.contains("Melewati batas selesai.")
            {
                result.conflicts.append("Melewati batas selesai.")
            }
            result.travel += seconds
            result.waiting += visit - arrival
            result.dwell += dwell
            let visitWeather = exposure(
                node: to, start: arrival, end: leave, factor: isEnd ? 0 : node.exposure)
            let travelWeather = exposure(
                node: to, start: cursor, end: arrival,
                factor: arc.mode == "walking" ? 1 : arc.mode == "stationary" ? 0 : nil)
            result.rain += visitWeather.wet + travelWeather.wet
            result.unknownWeather += visitWeather.unknown + travelWeather.unknown
            result.legs.append(
                .init(
                    from: from, to: to, mode: arc.mode, departure: cursor, arrival: arrival, visit: visit,
                    leave: leave))
            cursor = leave
            from = to
        }
        result.finish = cursor
        result.complete = true
        result.fullTour = closeRoute && Set(order) == Set(problem.targets)
        return result
    }

    private func exposure(node: Int, start: Double, end: Double, factor: Double?) -> (
        wet: Double, unknown: Double
    ) {
        let duration = max(0, end - start)
        if duration == 0 || factor == 0 { return (0, 0) }
        guard let factor else { return (0, duration) }
        var known = 0.0
        var wet = 0.0
        for window in problem.weather where window.node == node {
            let overlap = max(0, min(end, window.end) - max(start, window.start))
            known += overlap
            wet += overlap * window.chance * factor
        }
        return (wet, max(0, duration - known))
    }

    func weatherChoice(_ pool: [TripRoutingEvaluation]) -> TripRoutingEvaluation? {
        guard let fastest = pool.filter({ $0.feasible && $0.fullTour }).min(by: Self.better) else {
            return nil
        }
        return pool.filter {
            $0.feasible && $0.fullTour && $0.unknownWeather < 0.000001
                && $0.travel <= fastest.travel + problem.extraWeatherSeconds
                && $0.finish <= fastest.finish + problem.extraWeatherSeconds
        }
        .min { $0.finish + $0.rain * problem.rainWeight < $1.finish + $1.rain * problem.rainWeight }
    }
}

struct TripRoutingRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
    mutating func shuffled(_ input: [Int]) -> [Int] {
        var result = input
        if result.count > 1 {
            for i in stride(from: result.count - 1, through: 1, by: -1) {
                result.swapAt(i, Int(next() % UInt64(i + 1)))
            }
        }
        return result
    }
}

// Pure CPU solver: network acquisition is outside the search budget and outside this type.
struct TripRoutingSearch {
    let evaluator: TripRoutingEvaluator
    let configuration: TripRoutingConfiguration
    private(set) var evaluations = 0
    private(set) var pool: [TripRoutingEvaluation] = []
    private(set) var sawMissing = false
    private var started = Date()
    private var stopped = false
    private var random: TripRoutingRandom

    init(problem: TripRoutingProblem, configuration: TripRoutingConfiguration) {
        evaluator = .init(problem)
        self.configuration = configuration
        random = .init(state: configuration.seed)
    }
    private var available: Bool {
        !Task.isCancelled && evaluations < configuration.evaluationLimit
            && Date().timeIntervalSince(started) < configuration.secondsLimit
    }
    private mutating func evaluate(_ order: [Int], all: Bool = true, close: Bool = true)
        -> TripRoutingEvaluation?
    {
        guard available else {
            stopped = true
            return nil
        }
        evaluations += 1
        let result = evaluator.evaluate(order, requireAll: all, closeRoute: close)
        sawMissing = sawMissing || result.missing > 0
        if all {
            if !pool.contains(where: { $0.order == order }) { pool.append(result) }
            pool.sort(by: TripRoutingEvaluator.better)
            if pool.count > 12 { pool.removeLast(pool.count - 12) }
        }
        return result
    }

    mutating func solve(_ algorithm: TripRoutingAlgorithm) throws -> TripRoutingResult {
        try evaluator.problem.validate()
        guard configuration.evaluationLimit > 0, configuration.secondsLimit.isFinite,
              configuration.secondsLimit > 0,
              (1 ... 64).contains(configuration.beamWidth), (1 ... 10000).contains(configuration.iterations)
        else { throw TripRoutingFailure.invalid("Batas pencarian tidak valid.") }
        started = Date()
        if algorithm == .ortools {
            return result(
                algorithm, proof: "external", note: "Ekspor kasus dan impor hasil helper OR-Tools Mac.")
        }
        if algorithm == .exact && evaluator.problem.targets.count > 8 {
            return result(
                algorithm, proof: "unsupported_size", note: "Enumerasi dibatasi maksimal 8 tujuan.")
        }
        let seeds =
            evaluator.problem.baselineOrders.isEmpty
                ? [evaluator.problem.targets] : evaluator.problem.baselineOrders
        for seed in seeds { _ = evaluate(seed) }
        switch algorithm {
        case .baseline: break
        case .hybrid:
            var starts = seeds + [repair([]), greedy()]
            starts.append(evaluator.problem.targets.sorted {
                (evaluator.problem.nodes[$0].opens ?? 0) < (evaluator.problem.nodes[$1].opens ?? 0)
            })
            for _ in 0 ..< 3 { starts.append(random.shuffled(evaluator.problem.targets)) }
            for start in starts where available { improve(start) }
        case .local:
            var starts = seeds + [evaluator.problem.targets, Array(evaluator.problem.targets.reversed())]
            starts.append(greedy())
            for _ in 0 ..< 3 { starts.append(random.shuffled(evaluator.problem.targets)) }
            for start in starts where available { improve(start) }
        case .insertion:
            let order = repair([])
            improve(order)
        case .beam: beam()
        case .alns: alns(seeds.first ?? evaluator.problem.targets)
        case .exact:
            enumerate([], remaining: evaluator.problem.targets)
        case .ortools: break
        }
        try Task.checkCancellation()
        let proof =
            algorithm == .exact && !stopped && !sawMissing ? "exhaustive_fixed_evaluator" : "not_proven"
        return result(
            algorithm, proof: proof,
            note:
            "Evaluator elapsed_v2 mengutamakan kelayakan lalu durasi trip termasuk tunggu/singgah. Mobil pribadi memakai satu strategi konsisten. Tidak mencari penundaan berangkat disengaja. Optimum enumerasi hanya untuk model yang sama."
        )
    }

    private func result(_ algorithm: TripRoutingAlgorithm, proof: String, note: String)
        -> TripRoutingResult
    {
        let termination: String
        if proof == "unsupported_size" {
            termination = "unsupported_size"
        } else if proof == "external" {
            termination = "awaiting_import"
        } else if stopped || (algorithm != .exact && !available) {
            termination = "search_limit"
        } else {
            termination = sawMissing ? "data_incomplete" : "completed"
        }
        return .init(
            algorithm: algorithm, problemID: evaluator.problem.id, configuration: configuration,
            alternatives: pool, evaluations: evaluations, elapsed: Date().timeIntervalSince(started),
            termination: termination, proof: proof, note: note)
    }

    private mutating func greedy() -> [Int] {
        var prefix: [Int] = []
        var remaining = evaluator.problem.targets
        while !remaining.isEmpty && available {
            var best: TripRoutingEvaluation?
            for node in remaining {
                guard let proposal = evaluate(prefix + [node], all: false, close: false) else { break }
                if best == nil || TripRoutingEvaluator.better(proposal, best!) { best = proposal }
            }
            guard let best else { break }
            prefix = best.order
            remaining.removeAll { prefix.contains($0) }
        }
        return prefix + remaining
    }

    private mutating func repair(_ retained: [Int]) -> [Int] {
        var order = retained
        var remaining = evaluator.problem.targets.filter { !retained.contains($0) }
        while !remaining.isEmpty && available {
            var best: TripRoutingEvaluation?
            for node in remaining {
                for position in 0 ... order.count {
                    var next = order
                    next.insert(node, at: position)
                    guard let candidate = evaluate(next, all: false) else { break }
                    if best == nil || TripRoutingEvaluator.better(candidate, best!) { best = candidate }
                }
            }
            guard let best else { break }
            order = best.order
            remaining.removeAll { order.contains($0) }
        }
        return order + remaining
    }

    private mutating func improve(_ initial: [Int]) {
        guard var current = evaluate(initial) else { return }
        for _ in 0 ..< 3 {
            var best = current
            for i in current.order.indices {
                for j in current.order.indices where i != j {
                    var swapped = current.order
                    swapped.swapAt(i, j)
                    if let candidate = evaluate(swapped), TripRoutingEvaluator.better(candidate, best) {
                        best = candidate
                    }
                    var moved = current.order
                    let node = moved.remove(at: i)
                    moved.insert(node, at: j)
                    if let candidate = evaluate(moved), TripRoutingEvaluator.better(candidate, best) {
                        best = candidate
                    }
                    if !available { return }
                }
            }
            if !TripRoutingEvaluator.better(best, current) { return }
            current = best
        }
    }

    private mutating func beam() {
        var states: [[Int]] = [[]]
        for _ in evaluator.problem.targets {
            var expanded: [TripRoutingEvaluation] = []
            for state in states {
                for node in evaluator.problem.targets where !state.contains(node) {
                    if let candidate = evaluate(state + [node], all: false, close: false) {
                        expanded.append(candidate)
                    }
                    if !available { break }
                }
                if !available { break }
            }
            expanded.sort(by: TripRoutingEvaluator.better)
            states = Array(expanded.prefix(configuration.beamWidth)).map(\.order)
            if !available || states.isEmpty { break }
        }
        for state in states where state.count == evaluator.problem.targets.count { _ = evaluate(state) }
    }

    private mutating func alns(_ initial: [Int]) {
        guard var current = evaluate(initial) else { return }
        var weights = [1.0, 1.0]
        for iteration in 0 ..< configuration.iterations where available {
            let draw = Double(random.next() % 1_000_000) / 1_000_000 * weights.reduce(0, +)
            let strategy = draw < weights[0] ? 0 : 1
            let count = min(current.order.count, max(2, current.order.count / 3))
            let removed: Set<Int>
            if strategy == 0 {
                removed = Set(random.shuffled(current.order).prefix(count))
            } else {
                let pivot = current.order[Int(random.next() % UInt64(current.order.count))]
                let node = evaluator.problem.nodes[pivot]
                removed = Set(
                    current.order.sorted {
                        let a = evaluator.problem.nodes[$0]
                        let b = evaluator.problem.nodes[$1]
                        return hypot(a.x - node.x, a.y - node.y) < hypot(b.x - node.x, b.y - node.y)
                    }.prefix(count))
            }
            let repaired = repair(current.order.filter { !removed.contains($0) })
            guard let next = evaluate(repaired) else { break }
            let improved = TripRoutingEvaluator.better(next, current)
            let temperature = max(1, 300 * (1 - Double(iteration) / Double(configuration.iterations)))
            let probability = exp(min(0, (current.score - next.score) / temperature))
            let accept = improved || Double(random.next() % 1_000_000) / 1_000_000 < probability
            weights[strategy] = weights[strategy] * 0.9 + (improved ? 5 : accept ? 1 : 0.1)
            if accept { current = next }
        }
    }

    private mutating func enumerate(_ prefix: [Int], remaining: [Int]) {
        guard available else {
            stopped = true
            return
        }
        if remaining.isEmpty {
            _ = evaluate(prefix)
            return
        }
        for node in remaining {
            enumerate(prefix + [node], remaining: remaining.filter { $0 != node })
            if stopped { return }
        }
    }
}

actor TripRoutingWorker {
    func solve(
        _ algorithm: TripRoutingAlgorithm, problem: TripRoutingProblem,
        configuration: TripRoutingConfiguration
    ) throws -> TripRoutingResult {
        var solver = TripRoutingSearch(problem: problem, configuration: configuration)
        return try solver.solve(algorithm)
    }
}

struct TripRoutingExternalResult: Codable {
    var schemaVersion: Int
    var problemID: String
    var algorithm: String
    var order: [Int]
    var elapsed: Double
    var status: String
    var version: String
}

enum TripRoutingImport {
    static func result(
        _ data: Data, problem: TripRoutingProblem, configuration: TripRoutingConfiguration
    ) throws -> TripRoutingResult {
        guard data.count <= 1_000_000 else {
            throw TripRoutingFailure.invalid("File hasil terlalu besar.")
        }
        let imported = try JSONDecoder().decode(TripRoutingExternalResult.self, from: data)
        guard imported.schemaVersion == 1, imported.problemID == problem.id,
              imported.algorithm == "ortools_gls", imported.elapsed.isFinite, imported.elapsed >= 0
        else { throw TripRoutingFailure.invalid("Hasil OR-Tools berasal dari kasus/format berbeda.") }
        if imported.order.isEmpty && imported.status != "solution"
            && imported.status != "static_projection"
        {
            return .init(
                algorithm: .ortools, problemID: problem.id, configuration: configuration, alternatives: [],
                evaluations: 0, elapsed: imported.elapsed, termination: imported.status,
                proof: "not_proven",
                note: "OR-Tools \(imported.version): tidak menemukan solusi. Ini bukan bukti infeasible.")
        }
        guard imported.order.count == problem.targets.count, Set(imported.order) == Set(problem.targets)
        else {
            throw TripRoutingFailure.invalid("Hasil OR-Tools menghilangkan atau menggandakan tujuan.")
        }
        let evaluated = TripRoutingEvaluator(problem).evaluate(imported.order)
        return .init(
            algorithm: .ortools, problemID: problem.id, configuration: configuration,
            alternatives: [evaluated], evaluations: 1, elapsed: imported.elapsed,
            termination: imported.status, proof: "not_proven",
            note:
            "OR-Tools \(imported.version). Metrik dihitung ulang oleh evaluator aplikasi. Solver Mac memakai proyeksi matriks pada waktu nol; tidak membuktikan optimum model dinamis. Parameter/seed helper terpisah dari pencarian native."
        )
    }
}

struct TripRoutingStatistics: Codable, Identifiable, Sendable {
    var problemID: String
    var algorithm: TripRoutingAlgorithm
    var runs: Int
    var feasibleRuns: Int
    var medianTravel: Double?
    var minimumTravel: Double?
    var maximumTravel: Double?
    var medianCPU: Double
    var medianElapsed: Double? = nil
    var minimumElapsed: Double? = nil
    var maximumElapsed: Double? = nil
    var id: String { "\(problemID)|\(algorithm.rawValue)" }

    static func make(_ results: [TripRoutingResult]) -> [Self] {
        func median(_ values: [Double]) -> Double? {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return nil }
            let middle = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        }
        let groups = Dictionary(grouping: results) { "\($0.problemID)|\($0.algorithm.rawValue)" }
        return groups.keys.sorted().compactMap { key in
            guard let runs = groups[key], let first = runs.first else { return nil }
            let travel = runs.compactMap { result -> Double? in
                guard let best = result.best, best.feasible && best.fullTour else { return nil }
                return best.travel
            }
            let elapsed = runs.compactMap { run -> Double? in
                guard let best = run.best, best.feasible && best.fullTour else { return nil }
                return best.finish
            }
            return Self(
                problemID: first.problemID, algorithm: first.algorithm, runs: runs.count,
                feasibleRuns: travel.count, medianTravel: median(travel), minimumTravel: travel.min(),
                maximumTravel: travel.max(), medianCPU: median(runs.map(\.elapsed)) ?? 0,
                medianElapsed: median(elapsed), minimumElapsed: elapsed.min(), maximumElapsed: elapsed.max())
        }
    }
}
