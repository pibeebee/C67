import { Failure, iso, seconds, type Input, type Leg, type Stop } from './domain.ts';

export type Candidate = {
  id: string;
  stops: Stop[];
  finishes_at: string;
  feasible: boolean;
  score: number;
  warnings: string[];
};
export type Route = {
  duration_seconds: number;
  distance_meters: number | null;
  evidence_id: string;
};
export type RouteLookup = (from: string, to: string, departure: string) => Promise<Route>;

function permutations<T>(items: T[]): T[][] {
  if (items.length < 2) return [items];
  return items.flatMap((item, index) =>
    permutations(items.filter((_, i) => index !== i)).map((rest) => [item, ...rest]),
  );
}

export function evaluate(
  input: Input,
  order: string[],
  routes: Map<string, Route>,
  weatherWarnings: Map<string, string[]> = new Map(),
): Candidate {
  let at = seconds(input.starts_at);
  let from = 'origin';
  let penalty = 0;
  const stops: Stop[] = [];
  const warnings: string[] = [];
  for (const id of order) {
    const place = input.places.find((p) => p.id === id);
    const route = routes.get(`${from}:${id}`);
    if (!place || !route || !Number.isFinite(route.duration_seconds) || route.duration_seconds < 0)
      throw new Failure('ROUTE_UNAVAILABLE', 503);
    const travel = Math.ceil(route.duration_seconds);
    at += travel;
    const notes = [...(weatherWarnings.get(id) ?? [])];
    if (place.preferred_after && at < seconds(place.preferred_after)) {
      penalty += seconds(place.preferred_after) - at;
      notes.push('Arrival precedes your preferred experience window.');
    }
    if (place.preferred_before && at > seconds(place.preferred_before)) {
      penalty += at - seconds(place.preferred_before);
      notes.push('Your preferred experience window may be missed; the destination is retained.');
    }
    stops.push({
      id,
      name: place.name,
      location: place.location,
      arrival_at: iso(at * 1000),
      departure_at: iso((at + place.visit_seconds) * 1000),
      visit_seconds: place.visit_seconds,
      travel_seconds: travel,
      warnings: notes,
    });
    at += place.visit_seconds;
    from = id;
  }
  const feasible = at <= seconds(input.finish_by);
  if (!feasible)
    warnings.push(
      `Selected visits exceed the finish-by time by ${Math.ceil((at - seconds(input.finish_by)) / 60)} minutes. No destinations were removed.`,
    );
  return {
    id: order.join('/'),
    stops,
    finishes_at: iso(at * 1000),
    feasible,
    score: (feasible ? 0 : 1e9) + penalty * 4 + at - seconds(input.starts_at),
    warnings,
  };
}

export async function schedule(
  input: Input,
  lookup: RouteLookup,
  weatherWarnings = new Map<string, string[]>(),
  proposedOrders: string[][] = [],
) {
  const routes = new Map<string, Route>();
  const ids = input.places.map((p) => p.id);
  const origins = ['origin', ...ids];
  const tasks: (() => Promise<void>)[] = [];
  for (const from of origins)
    for (const to of ids)
      if (from !== to)
        tasks.push(async () => {
          routes.set(`${from}:${to}`, await lookup(from, to, input.starts_at));
        });
  // Bound provider concurrency. The maximum six-stop matrix has 36 edges.
  for (let index = 0; index < tasks.length; index += 4)
    await Promise.all(tasks.slice(index, index + 4).map((task) => task()));
  const orders = permutations(ids).filter(
    (order) => !input.first_place_id || order[0] === input.first_place_id,
  );
  const evaluated = orders
    .map((order) => evaluate(input, order, routes, weatherWarnings))
    .sort((a, b) => a.score - b.score);
  const shortlist = evaluated.slice(0, 3);
  for (const order of proposedOrders.slice(0, 3)) {
    const match = evaluated.find((candidate) => candidate.id === order.join('/'));
    if (match && !shortlist.some((item) => item.id === match.id)) shortlist.push(match);
  }
  const refined: Candidate[] = [];
  for (const candidate of shortlist) {
    const exact = new Map<string, Route>();
    let at = input.starts_at;
    let from = 'origin';
    for (const stop of candidate.stops) {
      const route = await lookup(from, stop.id, at);
      exact.set(`${from}:${stop.id}`, route);
      at = iso((seconds(at) + Math.ceil(route.duration_seconds) + stop.visit_seconds) * 1000);
      from = stop.id;
    }
    refined.push(
      evaluate(
        input,
        candidate.stops.map((stop) => stop.id),
        exact,
        weatherWarnings,
      ),
    );
  }
  return refined.sort((a, b) => a.score - b.score);
}
