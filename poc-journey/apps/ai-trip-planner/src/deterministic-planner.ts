import { ensure } from "./domain.ts";
import { mapLimited } from "./deterministic-provider.ts";
import {
  type Forecast,
  type OpeningInfo,
  type ResolvedLocation,
  type RouteOption,
  type RoutingInput,
  type RoutingProvider,
} from "./deterministic-model.ts";

export type WetEstimate = {
  expectedWetMinutes: number;
  unknownMinutes: number;
};
export function wetMinutes(
  forecast: Forecast | undefined,
  start: number,
  end: number,
  factor: number | null,
): WetEstimate {
  const total = Math.max(0, end - start) / 60;
  if (factor === 0 || total === 0)
    return { expectedWetMinutes: 0, unknownMinutes: 0 };
  if (factor === null) return { expectedWetMinutes: 0, unknownMinutes: total };
  let known = 0,
    wet = 0;
  for (const hour of forecast?.hours ?? []) {
    const minutes =
      Math.max(0, Math.min(end, hour.at + 3600) - Math.max(start, hour.at)) /
      60;
    if (hour.rainProbability !== null) {
      known += minutes;
      wet += ((minutes * hour.rainProbability) / 100) * factor;
    }
  }
  return {
    expectedWetMinutes: wet,
    unknownMinutes: Math.max(0, total - known),
  };
}
export function visitSlot(
  hours: OpeningInfo,
  arrival: number,
  dwellMinutes: number,
  transfer: boolean,
): { start: number; conflict: boolean } {
  if (transfer || hours.status === "unknown")
    return { start: arrival, conflict: false };
  const slot = hours.windows.find(
    (w) => Math.max(arrival, w.start) + dwellMinutes * 60 <= w.end,
  );
  return slot
    ? { start: Math.max(arrival, slot.start), conflict: false }
    : { start: arrival, conflict: true };
}
const exposure = (place: ResolvedLocation) =>
  place.exposure === "indoor"
    ? 0
    : place.exposure === "outdoor"
      ? 1
      : place.exposure === "mixed"
        ? 0.5
        : null;
const edge = (from: string, to: string) => `${from}->${to}`;
type BeamState = {
  order: number[];
  mask: number;
  from: string;
  time: number;
  travel: number;
  waiting: number;
  wet: number;
  conflicts: number;
};
export type SearchResult = {
  orders: string[][];
  expanded: number;
  retainedWidth: number;
  method: string;
};

// A bounded beam search explores directed routes and opening windows, not n! permutations.
// Matrix probes are estimates for search only. Every shortlisted leg is queried at its propagated departure.
export function searchOrders(
  input: RoutingInput,
  places: ResolvedLocation[],
  matrix: RouteOption[],
  forecasts: Forecast[],
): SearchResult {
  const edges = new Map<string, RouteOption[]>();
  for (const r of matrix)
    if (r.status === "ok" && r.durationSeconds !== null) {
      const key = edge(r.from, r.to);
      edges.set(key, [...(edges.get(key) ?? []), r]);
    }
  const weather = new Map(forecasts.map((f) => [f.locationId, f]));
  const weatherAvailable = forecasts.some((f) => f.status === "available");
  const orders: string[][] = [];
  let expanded = 0;
  for (const weight of weatherAvailable
    ? [0, input.weatherPolicy.rainWeight]
    : [0]) {
    let states: BeamState[] = [
      {
        order: [],
        mask: 0,
        from: input.origin.id,
        time: input.startsAt,
        travel: 0,
        waiting: 0,
        wet: 0,
        conflicts: 0,
      },
    ];
    const score = (state: BeamState, final = false) => {
      const tail = edges.get(edge(state.from, input.returnTo.id));
      const returnSeconds = tail?.length
        ? Math.min(...tail.map((r) => r.durationSeconds!))
        : state.from === input.returnTo.id
          ? 0
          : Infinity;
      return {
        conflicts:
          state.conflicts +
          (final && state.time + returnSeconds > input.endsAt ? 1 : 0),
        cost: state.travel + returnSeconds / 60 + state.wet * weight,
      };
    };
    const compare = (a: BeamState, b: BeamState, final = false) => {
      const x = score(a, final),
        y = score(b, final);
      return (
        x.conflicts - y.conflicts ||
        x.cost - y.cost ||
        a.waiting - b.waiting ||
        a.order
          .map((i) => places[i]!.id)
          .join(",")
          .localeCompare(b.order.map((i) => places[i]!.id).join(","))
      );
    };
    for (let depth = 0; depth < places.length && states.length; depth++) {
      const next: BeamState[] = [];
      for (const state of states)
        for (const [i, place] of places.entries()) {
          if (state.mask & (1 << i)) continue;
          const options = edges.get(edge(state.from, place.id));
          if (!options?.length) continue;
          const choices = options.map((option) => {
            const arrival = state.time + option.durationSeconds!;
            const moveWet = wetMinutes(
              weather.get(place.id),
              state.time,
              arrival,
              option.mode === "WALK" ? 1 : null,
            );
            const slot = visitSlot(
              place.hours,
              arrival,
              place.dwellMinutes,
              place.role === "transfer",
            );
            const leave = slot.start + place.dwellMinutes * 60;
            const visitWet = wetMinutes(
              weather.get(place.id),
              slot.start,
              leave,
              exposure(place),
            );
            return {
              order: [...state.order, i],
              mask: state.mask | (1 << i),
              from: place.id,
              time: leave,
              travel: state.travel + option.durationSeconds! / 60,
              waiting: state.waiting + (slot.start - arrival) / 60,
              wet:
                state.wet +
                moveWet.expectedWetMinutes +
                visitWet.expectedWetMinutes,
              conflicts: state.conflicts + Number(slot.conflict),
            };
          });
          expanded += choices.length;
          choices.sort((a, b) => compare(a, b));
          next.push(...choices.slice(0, 1));
        }
      next.sort((a, b) => compare(a, b, depth === places.length - 1));
      states = next.slice(0, input.search.beamWidth);
    }
    for (const state of states.slice(0, input.search.shortlist)) {
      if (
        state.order.length !== places.length ||
        !edges.has(edge(state.from, input.returnTo.id))
      )
        continue;
      orders.push(state.order.map((i) => places[i]!.id));
    }
  }
  return {
    orders: [...new Map(orders.map((o) => [o.join(","), o])).values()],
    expanded,
    retainedWidth: input.search.beamWidth,
    method:
      "bounded_beam_search_then_departure_queries; no global-optimality guarantee",
  };
}

export type ScheduledStop = {
  placeId: string;
  name: string;
  from: string;
  departureAt: number;
  arrivalAt: number | null;
  visitAt: number | null;
  leaveAt: number | null;
  dwellMinutes: number;
  dwellSource: ResolvedLocation["dwellSource"];
  waitMinutes: number;
  chosen: RouteOption | null;
  options: RouteOption[];
  warnings: string[];
};
export type RoutingCandidate = {
  id: string;
  policy: "fastest" | "weather";
  order: string[];
  stops: ScheduledStop[];
  complete: boolean;
  unvisitedIds: string[];
  finishesAt: number | null;
  travelMinutes: number;
  dwellMinutes: number;
  waitMinutes: number;
  expectedWetMinutes: number;
  unknownWeatherMinutes: number;
  conflicts: string[];
  conditional: string[];
  feasible: boolean;
};
export async function evaluateOrder(
  input: RoutingInput,
  order: ResolvedLocation[],
  origin: ResolvedLocation,
  returnTo: ResolvedLocation,
  provider: RoutingProvider,
  forecasts: Forecast[],
  policy: RoutingCandidate["policy"],
): Promise<RoutingCandidate> {
  const result: RoutingCandidate = {
    id: `${order.map((p) => p.id).join("/")}:${policy}`,
    policy,
    order: order.map((p) => p.id),
    stops: [],
    complete: false,
    unvisitedIds: order.map((p) => p.id),
    finishesAt: null,
    travelMinutes: 0,
    dwellMinutes: 0,
    waitMinutes: 0,
    expectedWetMinutes: 0,
    unknownWeatherMinutes: 0,
    conflicts: [],
    conditional: [],
    feasible: false,
  };
  const weather = new Map(forecasts.map((f) => [f.locationId, f]));
  let cursor = input.startsAt,
    from = origin;
  const targets = [
    ...order,
    {
      ...returnTo,
      role: "transfer" as const,
      dwellMinutes: 0,
      dwellSource: "transfer" as const,
    },
  ];
  for (const [index, place] of targets.entries()) {
    const options = await provider.routes(from, place, cursor, input);
    const usable = options.filter(
      (r) =>
        r.status === "ok" &&
        r.durationSeconds !== null &&
        Number.isFinite(r.durationSeconds) &&
        r.durationSeconds >= 0,
    );
    const optionCost = (r: RouteOption) => {
      const seconds = r.durationSeconds!;
      const wet = wetMinutes(
        weather.get(place.id),
        cursor,
        cursor + seconds,
        1,
      );
      const outdoor = r.walkingSeconds;
      return (
        seconds / 60 +
        (policy === "weather" && wet.unknownMinutes === 0 && outdoor !== null
          ? wet.expectedWetMinutes *
            Math.min(1, outdoor / Math.max(1, seconds)) *
            input.weatherPolicy.rainWeight
          : 0)
      );
    };
    usable.sort(
      (a, b) =>
        optionCost(a) - optionCost(b) ||
        a.durationSeconds! - b.durationSeconds! ||
        a.id.localeCompare(b.id),
    );
    const chosen = usable[0] ?? null;
    const stop: ScheduledStop = {
      placeId: place.id,
      name: place.name,
      from: from.id,
      departureAt: cursor,
      arrivalAt: null,
      visitAt: null,
      leaveAt: null,
      dwellMinutes: place.dwellMinutes,
      dwellSource: place.dwellSource,
      waitMinutes: 0,
      chosen,
      options,
      warnings: [],
    };
    result.stops.push(stop);
    if (!chosen) {
      result.conflicts.push(`ROUTE_UNAVAILABLE:${from.id}->${place.id}`);
      return result;
    }
    ensure(
      chosen.from === from.id &&
        chosen.to === place.id &&
        chosen.departureAt === cursor,
      "Provider returned a route for another leg/departure.",
    );
    const arrival = cursor + chosen.durationSeconds!;
    const slot = visitSlot(
      place.hours,
      arrival,
      place.dwellMinutes,
      place.role === "transfer",
    );
    const leave = slot.start + place.dwellMinutes * 60;
    stop.arrivalAt = arrival;
    stop.visitAt = slot.start;
    stop.leaveAt = leave;
    stop.waitMinutes = (slot.start - arrival) / 60;
    if (slot.conflict) result.conflicts.push(`OPENING_WINDOW:${place.id}`);
    if (place.status === "reference")
      result.conditional.push(
        `APPROXIMATE_LOCATION:${place.id}: ${place.referenceNote}`,
      );
    if (
      place.role === "visit" &&
      ["unknown", "regular"].includes(place.hours.status)
    ) {
      const warning = `${place.id}: ${place.hours.note}`;
      stop.warnings.push(warning);
      result.conditional.push(warning);
    }
    if (options.some((o) => o.status === "unsupported_region"))
      stop.warnings.push(
        "TRANSIT tidak tersedia melalui provider pada region ini; WALK bukan pengganti yang otomatis layak.",
      );
    const moveWet = wetMinutes(
      weather.get(place.id),
      cursor,
      arrival,
      chosen.walkingSeconds === null
        ? null
        : Math.min(
            1,
            chosen.walkingSeconds / Math.max(1, chosen.durationSeconds!),
          ),
    );
    const visitWet = wetMinutes(
      weather.get(place.id),
      slot.start,
      leave,
      exposure(place),
    );
    const waitingWet = wetMinutes(
      weather.get(place.id),
      arrival,
      slot.start,
      exposure(place),
    );
    result.expectedWetMinutes +=
      moveWet.expectedWetMinutes +
      visitWet.expectedWetMinutes +
      waitingWet.expectedWetMinutes;
    result.unknownWeatherMinutes +=
      moveWet.unknownMinutes +
      visitWet.unknownMinutes +
      waitingWet.unknownMinutes;
    result.travelMinutes += chosen.durationSeconds! / 60;
    result.dwellMinutes += place.dwellMinutes;
    result.waitMinutes += stop.waitMinutes;
    cursor = leave;
    from = place;
    if (index < order.length)
      result.unvisitedIds = result.unvisitedIds.filter((id) => id !== place.id);
  }
  result.complete = true;
  result.finishesAt = cursor;
  if (cursor > input.endsAt)
    result.conflicts.push(
      `FINISH_LIMIT: lewat ${Math.ceil((cursor - input.endsAt) / 60)} menit`,
    );
  if (result.unknownWeatherMinutes > 0)
    result.conditional.push(
      "Prakiraan/paparan cuaca tidak lengkap; tidak dianggap cerah.",
    );
  result.feasible = result.conflicts.length === 0;
  ensure(
    result.unvisitedIds.length === 0 &&
      result.stops.at(-1)!.placeId === input.returnTo.id,
    "Incomplete candidate or missing return leg.",
  );
  ensure(
    Math.abs(
      (cursor - input.startsAt) / 60 -
        result.travelMinutes -
        result.dwellMinutes -
        result.waitMinutes,
    ) < 0.001,
    "Timeline arithmetic is inconsistent.",
  );
  return result;
}

export function selectCandidates(
  input: RoutingInput,
  candidates: RoutingCandidate[],
) {
  const complete = candidates.filter((c) => c.complete);
  complete.sort(
    (a, b) =>
      Number(b.feasible) - Number(a.feasible) ||
      a.conflicts.length - b.conflicts.length ||
      a.travelMinutes - b.travelMinutes ||
      a.waitMinutes - b.waitMinutes ||
      a.id.localeCompare(b.id),
  );
  const fastest = complete[0] ?? null;
  const weatherChoices = fastest?.feasible
    ? complete.filter(
        (c) =>
          c.feasible &&
          c.unknownWeatherMinutes < 0.001 &&
          c.travelMinutes <=
            fastest.travelMinutes + input.weatherPolicy.maxExtraMinutes &&
          c.finishesAt! <=
            fastest.finishesAt! + input.weatherPolicy.maxExtraMinutes * 60,
      )
    : [];
  weatherChoices.sort(
    (a, b) =>
      a.travelMinutes +
        a.expectedWetMinutes * input.weatherPolicy.rainWeight -
        (b.travelMinutes +
          b.expectedWetMinutes * input.weatherPolicy.rainWeight) ||
      a.id.localeCompare(b.id),
  );
  return { fastest, weatherAdjusted: weatherChoices[0] ?? null };
}

export async function planWithoutAI(
  input: RoutingInput,
  provider: RoutingProvider,
  progress: (phase: string) => Promise<void> = async () => {},
) {
  await progress("resolving_places");
  const inputLocations = [
    ...new Map(
      [input.origin, ...input.places, input.returnTo].map((p) => [p.id, p]),
    ).values(),
  ];
  const locations = await mapLimited(inputLocations, (p) =>
    provider.resolve(p, input),
  );
  const unresolved = locations.filter((p) => !p.match);
  const empty = {
    schemaVersion: 4,
    engine: "deterministic",
    aiCalls: 0,
    input,
    locations,
    forecasts: [] as Forecast[],
    matrix: [] as RouteOption[],
    search: null as SearchResult | null,
    candidates: [] as RoutingCandidate[],
    fastest: null as RoutingCandidate | null,
    weatherAdjusted: null as RoutingCandidate | null,
    weatherReason: "Belum dievaluasi.",
    status: "needs_location_selection",
  };
  if (unresolved.length)
    return { ...empty, unresolvedIds: unresolved.map((p) => p.id) };
  const byId = new Map(locations.map((p) => [p.id, p]));
  await progress("collecting_matrix_and_weather");
  const [matrix, forecasts] = await Promise.all([
    provider.matrix(locations, input),
    provider.forecasts(locations, input),
  ]);
  await progress("searching_orders");
  const search = searchOrders(
    input,
    input.places.map((p) => byId.get(p.id)!),
    matrix,
    forecasts,
  );
  const candidates: RoutingCandidate[] = [];
  const weatherAvailable = forecasts.some((f) => f.status === "available");
  await progress("checking_candidates_at_actual_departures");
  // Sequential candidates share caches; dependent legs are always queried in order.
  for (const ids of search.orders)
    for (const policy of weatherAvailable
      ? (["fastest", "weather"] as const)
      : (["fastest"] as const))
      candidates.push(
        await evaluateOrder(
          input,
          ids.map((id) => byId.get(id)!),
          byId.get(input.origin.id)!,
          byId.get(input.returnTo.id)!,
          provider,
          forecasts,
          policy,
        ),
      );
  const selected = selectCandidates(input, candidates);
  const status = !selected.fastest
    ? "insufficient_route_data"
    : !selected.fastest.feasible
      ? "no_feasible_candidate"
      : selected.fastest.conditional.length
        ? "conditional_plan"
        : "plan_available";
  return {
    ...empty,
    status,
    locations,
    matrix,
    forecasts,
    search,
    candidates,
    ...selected,
    weatherReason: selected.weatherAdjusted
      ? "Skor = menit perpindahan + bobot × menit paparan hujan berbobot probabilitas; bukan tambahan ETA akibat hujan. Batas tambahan waktu adalah parameter eksperimen."
      : !weatherAvailable
        ? "Prakiraan cuaca belum tersedia; rekomendasi cuaca ditunda."
        : !selected.fastest?.feasible
          ? "Belum ada kandidat yang memenuhi batas trip; rekomendasi cuaca ditunda."
          : "Cakupan cuaca/paparan kandidat belum lengkap atau tidak memenuhi batas tambahan waktu.",
    unresolvedIds: [] as string[],
  };
}
