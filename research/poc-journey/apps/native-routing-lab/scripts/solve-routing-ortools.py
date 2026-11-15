#!/usr/bin/env python3
"""Offline OR-Tools reference: case JSON from the iOS app -> result JSON for import."""
import argparse
import json
import math
from pathlib import Path
import time


def load_case(path):
    if path.stat().st_size > 10_000_000:
        raise ValueError("Case exceeds 10 MB")
    problem = json.loads(path.read_text(), parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    nodes, targets = problem["nodes"], problem["targets"]
    if problem.get("schemaVersion") != 1 or not 1 <= len(targets) <= 20 or len(nodes) > 22:
        raise ValueError("Unsupported case schema/size")
    origin, end = problem["origin"], problem["end"]
    def index(value):
        return type(value) is int and 0 <= value < len(nodes)
    if not index(origin) or not index(end) or len(set(targets)) != len(targets) or not all(index(i) and i not in (origin, end) for i in targets):
        raise ValueError("Invalid targets or endpoints")
    if set(targets) | {origin, end} != set(range(len(nodes))):
        raise ValueError("All nodes must represent a target or endpoint")
    if len({n["id"] for n in nodes}) != len(nodes):
        raise ValueError("Duplicate node IDs")
    for node in nodes:
        if not math.isfinite(node["dwell"]) or node["dwell"] < 0:
            raise ValueError("Invalid dwell")
        for key in ("opens", "closes"):
            if node.get(key) is not None and not math.isfinite(node[key]):
                raise ValueError("Invalid time window")
    if not math.isfinite(problem["deadline"]) or problem["deadline"] <= 0:
        raise ValueError("Invalid deadline")
    for arc in problem["arcs"]:
        if not index(arc["from"]) or not index(arc["to"]):
            raise ValueError("Invalid arc")
        if arc.get("seconds") is not None and (not math.isfinite(arc["seconds"]) or arc["seconds"] < 0):
            raise ValueError("Invalid duration")
    return problem


def solve_static(problem, seconds):
    import ortools
    from ortools.constraint_solver import pywrapcp, routing_enums_pb2
    started = time.perf_counter()
    nodes = problem["nodes"]
    count = len(nodes)
    unknown = 10**9
    matrix = [[0 if i == j else unknown for j in range(count)] for i in range(count)]
    dynamic = False
    for arc in problem["arcs"]:
        dynamic |= arc.get("start", 0) != 0 or arc.get("end", 172800) < problem["deadline"]
        if arc.get("status") == "available" and arc.get("seconds") is not None and arc.get("start", 0) <= 0 < arc.get("end", 172800):
            i, j = arc["from"], arc["to"]
            matrix[i][j] = min(matrix[i][j], math.ceil(arc["seconds"]))
    manager = pywrapcp.RoutingIndexManager(count, 1, [problem["origin"]], [problem["end"]])
    routing = pywrapcp.RoutingModel(manager)
    # Start is fixed at zero. Minimise end-start including waiting and dwell,
    # rather than adding a travel objective that ignores opening-hour waits.
    zero_cost = routing.RegisterTransitCallback(lambda a, b: 0)
    routing.SetArcCostEvaluatorOfAllVehicles(zero_cost)
    def duration(a, b):
        source = manager.IndexToNode(a)
        return matrix[source][manager.IndexToNode(b)] + (0 if source == problem["origin"] else math.ceil(nodes[source]["dwell"]))
    time_callback = routing.RegisterTransitCallback(duration)
    deadline = math.floor(problem["deadline"])
    routing.AddDimension(time_callback, deadline, deadline, True, "Time")
    dimension = routing.GetDimensionOrDie("Time")
    dimension.SetSpanCostCoefficientForAllVehicles(1)
    invalid_window = False
    for node in problem["targets"]:
        lower = max(0, math.ceil(nodes[node].get("opens") or 0))
        closes = nodes[node].get("closes")
        upper = deadline if closes is None else min(deadline, math.floor(closes - nodes[node]["dwell"]))
        if upper < lower:
            invalid_window = True
            break
        dimension.CumulVar(manager.NodeToIndex(node)).SetRange(lower, upper)
    dimension.CumulVar(routing.End(0)).SetRange(0, deadline)
    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PARALLEL_CHEAPEST_INSERTION
    params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.FromMilliseconds(round(seconds * 1000))
    solution = None if invalid_window else routing.SolveWithParameters(params)
    order = []
    if solution:
        current = solution.Value(routing.NextVar(routing.Start(0)))
        while not routing.IsEnd(current):
            order.append(manager.IndexToNode(current))
            current = solution.Value(routing.NextVar(current))
        if len(order) != len(problem["targets"]) or set(order) != set(problem["targets"]):
            raise ValueError("Solver did not preserve mandatory visits")
    return {
        "schemaVersion": 1, "problemID": problem["id"], "algorithm": "ortools_gls",
        "order": order, "elapsed": time.perf_counter() - started,
        "status": ("static_projection" if dynamic else "solution") if solution else "no_solution_found",
        "version": ortools.__version__, "timeLimitSeconds": seconds,
        "objective": "elapsed_v2", "modelFinish": solution.Value(dimension.CumulVar(routing.End(0))) if solution else None,
        "note": "Integer-second static projection at t=0, minimising elapsed trip time. Re-evaluate in iOS. No global optimality claim; no solution is not proof of infeasibility.",
    }


def solve(problem, seconds):
    if not problem.get("privateCar"):
        return solve_static(problem, seconds)
    started = time.perf_counter()
    variants = []
    for automobile_only in (True, False):
        variant = dict(problem, privateCar=False, arcs=[a for a in problem["arcs"] if (a["mode"] == "automobile") == automobile_only])
        result = solve_static(variant, seconds / 2)
        result["carStrategy"] = "all_automobile" if automobile_only else "no_automobile"
        variants.append(result)
    result = min(variants, key=lambda r: (not bool(r["order"]), r["modelFinish"] if r["modelFinish"] is not None else math.inf))
    result["elapsed"] = time.perf_counter() - started
    result["timeLimitSeconds"] = seconds
    result["note"] += " Private car compares two consistent whole-trip strategies, with half the search budget each; park-and-walk is not modelled."
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", default=3.0, type=float)
    args = parser.parse_args()
    if not math.isfinite(args.seconds) or not 0.1 <= args.seconds <= 60:
        parser.error("--seconds must be between 0.1 and 60")
    if args.case.resolve() == args.output.resolve():
        parser.error("Output must differ from the input case")
    result = solve(load_case(args.case), args.seconds)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    temporary.replace(args.output)
    print(f"{result['status']}; OR-Tools {result['version']}; {len(result['order'])} visits; {args.output}")


if __name__ == "__main__":
    main()
