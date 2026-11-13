import Foundation

@main struct NativeTripRoutingChecks {
    static func golden() -> TripRoutingProblem {
        let nodes = (0 ... 3).map {
            TripRoutingNode(
                id: "N\($0)", name: "Node \($0)", x: Double($0), y: 0, dwell: $0 == 0 ? 0 : 10, exposure: 1)
        }
        var arcs: [TripRoutingArc] = []
        for a in 0 ... 3 {
            for b in 0 ... 3 where a != b {
                arcs.append(.init(from: a, to: b, mode: "walking", seconds: 100))
            }
        }
        let costs = [
            "0:1": 1.0, "1:2": 1.0, "3:0": 1.0, "0:3": 2.0, "3:2": 1.0, "2:1": 1.0, "1:0": 2.0,
        ]
        for i in arcs.indices {
            if let cost = costs["\(arcs[i].from):\(arcs[i].to)"] { arcs[i].seconds = cost }
        }
        return .init(
            label: "Golden directed case", kind: "synthetic_static", nodes: nodes, targets: [1, 2, 3],
            origin: 0, end: 0, deadline: 1000, arcs: arcs, baselineOrders: [[1, 2, 3]])
    }

    static func main() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.count == 3, arguments[1] == "--emit-case" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(golden()).write(to: URL(fileURLWithPath: arguments[2]))
            return
        }
        if arguments.count == 4, arguments[1] == "--verify-result" {
            let problem = try JSONDecoder().decode(
                TripRoutingProblem.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
            let data = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
            let result = try TripRoutingImport.result(data, problem: problem, configuration: .init())
            precondition(result.best?.fullTour == true && result.best?.feasible == true)
            precondition(result.best!.travel >= 6 && result.best!.travel <= 103)
            print(
                "PASS: real OR-Tools output imported and independently evaluated, \(result.best!.travel) seconds"
            )
            return
        }
        let problem = golden()
        try problem.validate()
        let evaluator = TripRoutingEvaluator(problem)
        let baseline = evaluator.evaluate([1, 2, 3])
        precondition(
            baseline.travel == 103 && baseline.dwell == 30 && baseline.finish == 133 && baseline.fullTour)
        precondition(evaluator.evaluate([3, 2, 1]).travel == 6)
        print("PASS 1: directed cost, fixed dwell, final return and asymmetric golden optimum")

        var config = TripRoutingConfiguration(
            seed: 123, evaluationLimit: 10000, secondsLimit: 10, beamWidth: 8, iterations: 32)
        var solved: [TripRoutingResult] = []
        for method in TripRoutingAlgorithm.native {
            var search = TripRoutingSearch(problem: problem, configuration: config)
            let result = try search.solve(method)
            solved.append(result)
            precondition(result.best?.feasible == true && result.best?.fullTour == true)
            precondition(Set(result.best!.order) == Set(problem.targets))
            precondition(result.best!.travel <= baseline.travel)
        }
        precondition(solved.first { $0.algorithm == .exact }?.best?.travel == 6)
        precondition(solved.first { $0.algorithm == .exact }?.proof == "exhaustive_fixed_evaluator")
        print(
            "PASS 2: all seven native methods preserve visits; exhaustive reference finds known optimum")

        var windows = problem
        windows.nodes[1].opens = 50
        windows.nodes[1].closes = 80
        let timed = TripRoutingEvaluator(windows).evaluate([1, 2, 3])
        precondition(timed.waiting == 49 && timed.finish == 182 && timed.feasible)
        windows.nodes[1].closes = 55
        precondition(!TripRoutingEvaluator(windows).evaluate([1, 2, 3]).feasible)
        windows.deadline = 30
        precondition(!TripRoutingEvaluator(windows).evaluate([3, 2, 1]).feasible)
        print("PASS 3: opening wait, complete dwell before closing and day deadline enforced")

        var separateEnd = problem
        separateEnd.nodes.append(
            .init(id: "end", name: "Separate endpoint", x: 4, y: 0, dwell: 0, exposure: 1))
        separateEnd.end = 4
        for from in 0 ... 3 {
            separateEnd.arcs.append(.init(from: from, to: 4, mode: "walking", seconds: 5))
        }
        let ended = TripRoutingEvaluator(separateEnd).evaluate([1, 2, 3])
        precondition(ended.legs.last?.to == 4 && ended.travel == 107 && ended.fullTour)
        precondition(!evaluator.evaluate([1, 1, 3]).complete && !evaluator.evaluate([1, 2]).fullTour)
        print("PASS 4: distinct endpoint retained; dropped/duplicate visit rejected")

        var dynamic = problem
        dynamic.nodes[1].dwell = 60
        dynamic.arcs.removeAll { $0.from == 1 && $0.to == 2 }
        dynamic.arcs.append(.init(from: 1, to: 2, mode: "walking", seconds: 100, start: 0, end: 50))
        dynamic.arcs.append(.init(from: 1, to: 2, mode: "walking", seconds: 2, start: 50))
        let propagated = TripRoutingEvaluator(dynamic).evaluate([1, 2, 3])
        precondition(propagated.travel == 104 && propagated.legs[1].departure == 61)
        print("PASS 5: piecewise ETA uses propagated departure after travel/dwell")

        var missing = problem
        missing.arcs.removeAll { $0.to == 2 }
        var unknownSearch = TripRoutingSearch(problem: missing, configuration: config)
        let unknown = try unknownSearch.solve(.exact)
        precondition(
            unknown.termination == "data_incomplete" && unknown.proof == "not_proven"
                && unknown.best?.missing ?? 0 > 0)
        precondition(unknown.best?.feasible == false)
        print("PASS 6: unknown arcs never become zero duration or a false optimum/infeasibility proof")

        config.evaluationLimit = 1
        for method in [TripRoutingAlgorithm.exact, .local] {
            var limited = TripRoutingSearch(problem: problem, configuration: config)
            let result = try limited.solve(method)
            precondition(result.termination == "search_limit" && result.proof == "not_proven")
        }
        var large = TripRoutingSearch(
            problem: TripRoutingFixtures.make(count: 9), configuration: config)
        let skipped = try large.solve(.exact)
        precondition(skipped.proof == "unsupported_size")
        print("PASS 7: evaluation budget and unsupported exact size are explicitly distinguished")

        config.evaluationLimit = 10000
        var first = TripRoutingSearch(problem: problem, configuration: config)
        var second = TripRoutingSearch(problem: problem, configuration: config)
        let a = try first.solve(.alns)
        let b = try second.solve(.alns)
        precondition(a.best?.order == b.best?.order && a.evaluations == b.evaluations)
        print("PASS 8: seeded ALNS is repeatable when time limit does not bind")

        var weather = problem
        weather.weather = weather.nodes.indices.map {
            .init(node: $0, start: 0, end: 1000, chance: 0.2)
        }
        let wet = TripRoutingEvaluator(weather).evaluate([1, 2, 3])
        precondition(abs(wet.rain - 26.6) < 0.00001 && wet.unknownWeather == 0)
        weather.arcs.append(.init(from: 0, to: 1, mode: "transit", seconds: 0.5))
        let unknownWet = TripRoutingEvaluator(weather).evaluate([1, 2, 3])
        precondition(
            unknownWet.unknownWeather > 0
                && TripRoutingEvaluator(weather).weatherChoice([unknownWet]) == nil)
        print("PASS 9: rain scoring respects coverage; transit exposure stays unknown")

        let valid = TripRoutingExternalResult(
            schemaVersion: 1, problemID: problem.id, algorithm: "ortools_gls", order: [3, 2, 1],
            elapsed: 0.1, status: "solution", version: "fixture")
        let imported = try TripRoutingImport.result(
            JSONEncoder().encode(valid), problem: problem, configuration: config)
        precondition(imported.best?.travel == 6 && imported.proof == "not_proven")
        var wrong = valid
        wrong.problemID = "another-case"
        do {
            _ = try TripRoutingImport.result(
                JSONEncoder().encode(wrong), problem: problem, configuration: config)
            preconditionFailure("Wrong case accepted")
        } catch {}
        wrong = valid
        wrong.order = [1, 1, 2]
        do {
            _ = try TripRoutingImport.result(
                JSONEncoder().encode(wrong), problem: problem, configuration: config)
            preconditionFailure("Missing visit accepted")
        } catch {}
        print(
            "PASS 10: external import verifies case and visits, recomputes metrics, never trusts optimality"
        )

        let worker = TripRoutingWorker()
        let cancelled = Task { try await worker.solve(.exact, problem: problem, configuration: config) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancellation lost")
        } catch is CancellationError {}
        print("PASS 11: cancellation propagates from solver actor")
        var invalid = problem
        invalid.baselineOrders = [[99, 1, 2]]
        do {
            try invalid.validate()
            preconditionFailure("Malformed seed accepted")
        } catch {}
        print("PASS 12: malformed graph/seed rejected before search")
        var wideConfig = config
        wideConfig.evaluationLimit = 500
        wideConfig.secondsLimit = 0.5
        let wide = TripRoutingFixtures.make(count: 20, seed: 67)
        for algorithm in TripRoutingAlgorithm.native where algorithm != .exact {
            var search = TripRoutingSearch(problem: wide, configuration: wideConfig)
            let result = try search.solve(algorithm)
            precondition(result.best?.fullTour == true && result.best?.order.count == 20)
        }
        print("PASS 13: bounded native searches preserve all 20 stops")
        var sampleA = solved[0]
        var sampleB = solved[0]
        var failedSample = solved[0]
        sampleA.elapsed = 1
        sampleB.elapsed = 3
        failedSample.alternatives[0].complete = false
        let statistics = TripRoutingStatistics.make([sampleA, sampleB, failedSample])[0]
        precondition(
            statistics.runs == 3 && statistics.feasibleRuns == 2 && statistics.medianTravel == 103)
        precondition(statistics.minimumTravel == 103 && statistics.maximumTravel == 103)
        print("PASS 14: repeated-run statistics exclude incomplete tours from quality metrics")
        var coverageCase = problem
        coverageCase.arcs = problem.arcs.map {
            var arc = $0
            arc.seconds = nil
            arc.status = "directions_not_available"
            arc.mode = "transit"
            return arc
        }
        coverageCase.arcs.append(
            .init(
                from: 0, to: 1, mode: "walking", seconds: 3600,
                status: "excluded_by_walking_limit", note: "60 minutes exceeds 45-minute cap"))
        let beforeCoverage = coverageCase.coverage
        precondition(beforeCoverage.requiredPairs == 12 && beforeCoverage.availablePairs == 0)
        precondition(beforeCoverage.unsampledPairs == 0 && beforeCoverage.blockedPairs.count == 12)
        precondition(beforeCoverage.modes.first { $0.mode == "transit" }?.available == 0)
        coverageCase.arcs += problem.arcs.map {
            var arc = $0
            arc.mode = "automobile"
            return arc
        }
        let afterCoverage = coverageCase.coverage
        precondition(afterCoverage.availablePairs == 12 && afterCoverage.blockedPairs.isEmpty)
        for algorithm in TripRoutingAlgorithm.native {
            var search = TripRoutingSearch(problem: coverageCase, configuration: config)
            let result = try search.solve(algorithm)
            precondition(result.best?.feasible == true && result.best?.legs.count == 4)
            precondition(result.best?.legs.allSatisfy { $0.mode == "automobile" } == true)
        }
        coverageCase.arcs.removeAll { $0.from == 0 && $0.to == 1 }
        precondition(coverageCase.coverage.unsampledPairs == 1)
        precondition(coverageCase.coverage.blockedPairs[0].reasons[0].contains("not_sampled"))
        print(
            "PASS 15: coverage separates unavailable, excluded and unrequested; all solvers use real eligible car arcs"
        )
        var elapsedCase = problem
        elapsedCase.nodes[3].opens = 200
        let e = TripRoutingEvaluator(elapsedCase)
        let lessTravel = e.evaluate([3, 2, 1])
        let lessElapsed = e.evaluate([1, 2, 3])
        precondition(lessTravel.travel < lessElapsed.travel && lessTravel.finish > lessElapsed.finish)
        precondition(TripRoutingEvaluator.better(lessElapsed, lessTravel))
        var elapsedSearch = TripRoutingSearch(problem: elapsedCase, configuration: config)
        let elapsedResult = try elapsedSearch.solve(.hybrid)
        precondition(elapsedResult.best!.finish <= lessElapsed.finish)
        var impossibleFast = lessTravel
        impossibleFast.finish = 0
        impossibleFast.conflicts = ["closed"]
        precondition(TripRoutingEvaluator.better(lessElapsed, impossibleFast))
        print("PASS 16: elapsed objective includes opening wait; hard feasibility remains first")

        var carCase = problem
        carCase.targets = [1, 2]
        carCase.baselineOrders = [[1, 2]]
        carCase.nodes[1].dwell = 0
        carCase.nodes[2].dwell = 0
        carCase.arcs = []
        for a in 0 ... 2 {
            for b in 0 ... 2 where a != b {
                carCase.arcs.append(
                    .init(from: a, to: b, mode: "walking", seconds: a == 1 && b == 2 ? 1 : 100))
                carCase.arcs.append(
                    .init(
                        from: a, to: b, mode: "automobile",
                        seconds: (a == 0 && b == 1) || (a == 2 && b == 0) ? 1 : 100))
            }
        }
        carCase.privateCar = false
        let taxi = TripRoutingEvaluator(carCase).evaluate([1, 2])
        precondition(taxi.travel == 3 && Set(taxi.legs.map(\.mode)).count == 2)
        carCase.privateCar = true
        let car = TripRoutingEvaluator(carCase).evaluate([1, 2])
        precondition(car.travel == 102 && car.legs.allSatisfy { $0.mode == "automobile" })
        precondition(statistics.medianElapsed == 133 && statistics.minimumElapsed == 133)
        print(
            "PASS 17: private car cannot teleport between walking legs; elapsed statistics exclude partial tours"
        )
        var rainBudget = problem
        rainBudget.extraWeatherSeconds = 15
        var fastWet = baseline
        fastWet.finish = 200
        fastWet.travel = 10
        fastWet.waiting = 160
        fastWet.rain = 100
        fastWet.unknownWeather = 0
        var dry = evaluator.evaluate([3, 2, 1])
        dry.finish = 205
        dry.travel = 100
        dry.waiting = 75
        dry.rain = 0
        dry.unknownWeather = 0
        precondition(
            TripRoutingEvaluator(rainBudget).weatherChoice([fastWet, dry])?.order == dry.order)
        print(
            "PASS 18: weather tolerance uses elapsed trip budget even when driving duration increases")
        print("18 routing checks passed on macOS; no network or iOS runtime.")
    }
}
