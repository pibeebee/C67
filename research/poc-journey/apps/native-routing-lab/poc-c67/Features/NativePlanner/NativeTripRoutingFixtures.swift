import Foundation

enum TripRoutingFixtures {
    static func make(count: Int = 8, dynamic: Bool = false, seed: UInt64 = 67) -> TripRoutingProblem {
        let count = min(20, max(1, count))
        let nodes: [TripRoutingNode] = (0 ... count).map { i -> TripRoutingNode in
            let name = i == 0 ? "Awal / akhir sintetis" : "Tempat sintetis \(i)"
            let dwell: Double = i == 0 ? 0 : 1800
            return TripRoutingNode(
                id: "synthetic-\(i)", name: name,
                x: Double(i % 4), y: Double(i / 4), dwell: dwell, opens: nil, closes: nil,
                exposure: 1)
        }
        var rng = TripRoutingRandom(state: seed)
        var arcs: [TripRoutingArc] = []
        for from in nodes.indices {
            for to in nodes.indices where from != to {
                let base = 180 + Double(rng.next() % 1400)
                if dynamic {
                    arcs.append(
                        .init(from: from, to: to, mode: "walking", seconds: base, start: 0, end: 7200))
                    arcs.append(
                        .init(
                            from: from, to: to, mode: "walking", seconds: 180 + Double(rng.next() % 1400),
                            start: 7200))
                } else {
                    arcs.append(.init(from: from, to: to, mode: "walking", seconds: base))
                }
            }
        }
        let targets = Array(1 ... count)
        let weather: [TripRoutingWeather] = nodes.indices.map { node in
            TripRoutingWeather(node: node, start: 0, end: 172800, chance: Double(node % 4) * 0.2)
        }
        var result = TripRoutingProblem(
            label: dynamic ? "Sintetis · ETA berubah pada +120 menit" : "Sintetis · waktu statis berarah",
            kind: dynamic ? "synthetic_piecewise" : "synthetic_static", nodes: nodes, targets: targets,
            origin: 0, end: 0, deadline: 17 * 3600, arcs: arcs, baselineOrders: [],
            weather: weather)
        result.baselineOrders = geographicalOrders(result)
        return result
    }

    static func geographicalOrders(_ problem: TripRoutingProblem) -> [[Int]] {
        func distance(_ a: Int, _ b: Int) -> Double {
            hypot(problem.nodes[a].x - problem.nodes[b].x, problem.nodes[a].y - problem.nodes[b].y)
        }
        var remaining = problem.targets
        var order: [Int] = []
        var current = problem.origin
        while !remaining.isEmpty {
            remaining.sort {
                distance(current, $0) == distance(current, $1)
                    ? $0 < $1 : distance(current, $0) < distance(current, $1)
            }
            current = remaining.removeFirst()
            order.append(current)
        }
        func length(_ value: [Int]) -> Double {
            let route = [problem.origin] + value + [problem.end]
            return zip(route, route.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
        }
        func improve(_ seed: [Int]) -> [Int] {
            var value = seed
            if value.count > 2 {
                for _ in 0 ..< 2 {
                    for i in 0 ..< (value.count - 1) {
                        for j in (i + 1) ..< value.count {
                            var next = value
                            next.replaceSubrange(i ... j, with: value[i ... j].reversed())
                            if length(next) + 0.000001 < length(value) { value = next }
                        }
                    }
                }
            }
            return value
        }
        let first = improve(order)
        let second = improve(Array(first.reversed()))
        return first == second ? [first] : [first, second]
    }
}
