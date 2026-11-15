import Foundation

extension NativeTripDraft {
    var selectedRoutingAlgorithm: TripRoutingAlgorithm {
        TripRoutingAlgorithm(rawValue: routingAlgorithm ?? "hybrid") ?? .hybrid
    }
    var routingConfiguration: TripRoutingConfiguration {
        .init(
            seed: UInt64(max(0, routingSeed ?? 67)), evaluationLimit: routingEvaluationLimit ?? 100_000,
            secondsLimit: routingSecondsLimit ?? 3, beamWidth: routingBeamWidth ?? 8, iterations: 150)
    }
}

@MainActor enum NativeTripRoutingBridge {
    static func snapshot(
        _ draft: NativeTripDraft, services: NativeTripAppleServices,
        forecasts: [NativeTripForecast] = [], reserve: Int = 0, progress: (String) -> Void
    ) async throws -> TripRoutingProblem {
        try draft.validate()
        let points = draft.allPoints
        let indices = Dictionary(
            uniqueKeysWithValues: points.enumerated().map { ($0.element.id, $0.offset) })
        let stops = Dictionary(uniqueKeysWithValues: draft.stops.map { ($0.id, $0) })
        let nodes = points.map { point in
            let stop = stops[point.id]
            return TripRoutingNode(
                id: point.id, name: point.title, x: point.longitude!, y: point.latitude!,
                dwell: Double(stop?.dwell(defaultMinutes: draft.defaultDwell) ?? 0) * 60,
                opens: (stop?.role == .visit ? stop?.opening?.opensMinute : nil).map {
                    draft.clockDate(minutes: $0).timeIntervalSince(draft.departure)
                },
                closes: (stop?.role == .visit ? stop?.opening?.closesMinute : nil).map {
                    draft.clockDate(minutes: $0).timeIntervalSince(draft.departure)
                }, exposure: stop?.exposure.factor)
        }
        let origin = indices[draft.origin.id]!
        let end = indices[draft.endPoint.id]!
        let targets = draft.stops.map { indices[$0.id]! }
        var baseline = NativeTripEngine.orders(draft).map { $0.map { indices[$0.id]! } }
        let hasWindows = targets.contains { nodes[$0].opens != nil || nodes[$0].closes != nil }
        // Acquire an entire deadline-first seed before spreading the remaining budget over
        // neighbours. A partial matrix must still contain a coherent time-window candidate.
        let windowOrder = targets.sorted {
            let a = nodes[$0]
            let b = nodes[$1]
            if a.closes != b.closes { return (a.closes ?? .infinity) < (b.closes ?? .infinity) }
            if a.opens != b.opens { return (a.opens ?? 0) < (b.opens ?? 0) }
            return points[origin].distance(to: points[$0]) < points[origin].distance(to: points[$1])
        }
        if hasWindows, !baseline.contains(windowOrder) { baseline.append(windowOrder) }
        var pairs: [(Int, Int)] = []
        var seen = Set<String>()
        func add(_ a: Int, _ b: Int) {
            if a != b && seen.insert("\(a):\(b)").inserted { pairs.append((a, b)) }
        }
        let acquisitionOrders = hasWindows ? [windowOrder] + baseline : baseline
        for order in acquisitionOrders {
            let route = [origin] + order + [end]
            for (a, b) in zip(route, route.dropFirst()) { add(a, b) }
        }
        // After coherent time-window/baseline seeds, acquire nearby outgoing neighbours.
        // This samples useful edges at every location even when a full matrix exceeds budget.
        for from in [origin] + targets {
            let neighbours = targets.filter { $0 != from }.sorted {
                points[from].distance(to: points[$0]) < points[from].distance(to: points[$1])
            }
            for to in neighbours.prefix(3) { add(from, to) }
            if from != origin { add(from, end) }
        }
        for rank in 0 ..< targets.count {
            for from in [origin] + targets {
                let ordered = targets.filter { $0 != from }.sorted {
                    points[from].distance(to: points[$0]) < points[from].distance(to: points[$1])
                }
                if rank < ordered.count { add(from, ordered[rank]) }
            }
        }
        var arcs: [TripRoutingArc] = []
        for (index, pair) in pairs.enumerated() {
            try Task.checkCancellation()
            if !services.canRequestETA || services.remainingETARequests < reserve + draft.modes.count {
                break
            }
            progress("Snapshot ETA \(index + 1)/\(pairs.count) · \(services.directionRequests) request")
            let options = try await services.options(
                from: points[pair.0], to: points[pair.1], departure: draft.departure, draft: draft)
            for option in options {
                arcs.append(
                    .init(
                        from: pair.0, to: pair.1, mode: option.mode.rawValue,
                        seconds: option.seconds, status: option.status, note: option.note))
            }
        }
        // Recover intermittent non-transit failures once, without re-querying successful arcs,
        // bypassing walking limits, changing modes or consuming the live-validation reserve.
        let retryPairs = pairs.filter { pair in
            let options = arcs.filter { $0.from == pair.0 && $0.to == pair.1 }
            return !options.contains { $0.status == "available" && $0.seconds != nil }
                && options.contains { $0.mode != "transit" && $0.seconds == nil }
        }
        if !retryPairs.isEmpty, services.canRequestETA {
            progress("Menunggu sebelum mencoba ulang ETA yang belum tersedia")
            try await Task.sleep(for: .seconds(3))
        }
        for pair in retryPairs {
            try Task.checkCancellation()
            let retryCount = arcs.filter {
                $0.from == pair.0 && $0.to == pair.1 && $0.mode != "transit" && $0.seconds == nil
            }.count
            guard services.canRequestETA, services.remainingETARequests >= reserve + retryCount else {
                break
            }
            progress("Mencoba ulang ETA: \(points[pair.0].title) → \(points[pair.1].title)")
            services.event(
                "routing.snapshot_retry", category: "optimizer",
                fields: [
                    "from": points[pair.0].title, "to": points[pair.1].title,
                    "maximumAdditionalRequests": String(retryCount),
                ])
            let refreshed = try await services.options(
                from: points[pair.0], to: points[pair.1], departure: draft.departure, draft: draft,
                retryUnavailable: true)
            arcs.removeAll { $0.from == pair.0 && $0.to == pair.1 }
            arcs += refreshed.map {
                .init(
                    from: pair.0, to: pair.1, mode: $0.mode.rawValue, seconds: $0.seconds,
                    status: $0.status, note: $0.note)
            }
        }
        let weather = forecasts.flatMap { forecast -> [TripRoutingWeather] in
            guard let node = indices[forecast.pointID] else { return [] }
            return forecast.hours.map {
                .init(
                    node: node, start: $0.date.timeIntervalSince(draft.departure),
                    end: $0.date.addingTimeInterval(3600).timeIntervalSince(draft.departure),
                    chance: $0.rainChance)
            }
        }
        var result = TripRoutingProblem(
            label: "Snapshot MapKit · \(draft.clock(draft.departure))", kind: "mapkit_static_snapshot",
            nodes: nodes, targets: targets, origin: origin, end: end,
            deadline: draft.deadline.timeIntervalSince(draft.departure), arcs: arcs,
            baselineOrders: baseline, weather: weather,
            extraWeatherSeconds: Double(draft.extraWeatherMinutes) * 60, rainWeight: draft.rainWeight)
        result.weatherSources = Dictionary(
            forecasts.compactMap { forecast in forecast.provider.map { (forecast.pointID, $0.rawValue) }
            },
            uniquingKeysWith: { first, _ in first })
        if forecasts.contains(where: { $0.provider == .openMeteo }) {
            result.weatherAttribution = [NativeTripWeatherProvider.openMeteoCredit]
        }
        result.privateCar = draft.usesPrivateCar
        try result.validate()
        services.logs.recordJSON(
            "routing.coverage", category: "optimizer", operationID: services.operationID,
            value: result.coverage)
        services.event(
            "routing.snapshot", category: "optimizer",
            fields: [
                "problemID": result.id, "nodes": String(nodes.count),
                "sampledPairs": String(Set(arcs.map { "\($0.from):\($0.to)" }).count),
                "sampledArcs": String(arcs.count),
                "availableArcs": String(
                    arcs.filter { $0.status == "available" && $0.seconds != nil }.count),
                "requiredPairs": String(pairs.count), "requests": String(services.directionRequests),
                "kind": result.kind,
            ])
        return result
    }

    static func plan(
        _ draft: NativeTripDraft, services: NativeTripAppleServices, progress: (String) -> Void
    ) async throws -> NativeTripReport {
        try await NativeTripTimeAwarePlanner.plan(draft, services: services, progress: progress)
    }
}
