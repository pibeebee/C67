import {
  at,
  ensure,
  type Candidate,
  type Place,
  type Point,
  type Route,
  type Stop,
  type Trip,
  type Weather,
  type WeatherSummary,
} from "./domain.ts";
import { edge, type DataProvider } from "./data.ts";

export const WEIGHTS = {
  travel: 1,
  waiting: 0.25,
  missedPreferredWindow: 3,
  rainExposure: 2,
};
export const SHORTLIST_SIZE = 3;
type Lookup = (from: Point, to: Point, departure: number) => Promise<Route>;
export function permutations<T>(items: T[]): T[][] {
  return items.length < 2
    ? [items]
    : items.flatMap((item, index) =>
        permutations(items.filter((_, i) => i !== index)).map((rest) => [
          item,
          ...rest,
        ]),
      );
}
export function summarizeWeather(
  weather: Weather | undefined,
  start: number,
  end: number,
  exposure: Place["exposure"],
): WeatherSummary {
  const total = (end - start) / 60;
  let known = 0,
    rain = 0,
    temperature = 0,
    temperatureMinutes = 0,
    cloud = 0,
    cloudMinutes = 0;
  for (const hour of weather?.hours ?? []) {
    const minutes =
      Math.max(0, Math.min(end, hour.at + 3600) - Math.max(start, hour.at)) /
      60;
    if (hour.rainProbability !== null) {
      known += minutes;
      rain += minutes * hour.rainProbability;
    }
    if (hour.temperatureC !== null) {
      temperature += minutes * hour.temperatureC;
      temperatureMinutes += minutes;
    }
    if (hour.cloudCover !== null) {
      cloud += minutes * hour.cloudCover;
      cloudMinutes += minutes;
    }
  }
  const factor = exposure === "outdoor" ? 1 : exposure === "mixed" ? 0.5 : 0;
  return {
    rainProbability: known >= total - 0.001 ? rain / total : null,
    temperatureC:
      temperatureMinutes >= total - 0.001 ? temperature / total : null,
    cloudCover: cloudMinutes >= total - 0.001 ? cloud / total : null,
    rainExposureMinutes: (rain / 100) * factor,
    unknownMinutes: Math.max(0, total - known),
  };
}
function preferred(
  place: Place,
  trip: Trip,
  weather?: Weather,
): { start: number; end: number } | null {
  const window = place.preferredWindow;
  if (!window) return null;
  if (window.kind === "clock")
    return {
      start: at(trip.input.date, window.startTime),
      end: at(trip.input.date, window.endTime),
    };
  return weather?.sunset
    ? { start: weather.sunset - window.minutesBefore * 60, end: weather.sunset }
    : null;
}
export async function evaluate(
  trip: Trip,
  order: Place[],
  wait: boolean,
  lookup: Lookup,
  forecasts: Map<string, Weather>,
): Promise<Candidate> {
  let time = trip.startsAt;
  let from = trip.origin;
  const stops: Stop[] = [];
  const violations: string[] = [];
  for (const place of order) {
    const leg = await lookup(from, place, time);
    ensure(
      Number.isFinite(leg.durationSeconds) && leg.durationSeconds >= 0,
      "Invalid route duration.",
    );
    const arrivalAt = time + leg.durationSeconds;
    const weather = forecasts.get(place.id);
    const window = preferred(place, trip, weather);
    const opensAt = place.openingHours
      ? at(trip.input.date, place.openingHours.opensAt)
      : arrivalAt;
    const visitAt = Math.max(
      arrivalAt,
      opensAt,
      wait && window ? window.start : arrivalAt,
    );
    const leaveAt = visitAt + place.durationMinutes * 60;
    const warnings: string[] = [];
    if (
      place.openingHours &&
      leaveAt > at(trip.input.date, place.openingHours.closesAt)
    )
      violations.push(
        `${place.id}: visit extends beyond supplied closing time.`,
      );
    // Require at most 30 minutes of overlap; a soft preference never removes a destination.
    const overlap = window
      ? Math.max(
          0,
          Math.min(leaveAt, window.end) - Math.max(visitAt, window.start),
        ) / 60
      : 0;
    const desired = window
      ? Math.min(30, place.durationMinutes, (window.end - window.start) / 60)
      : 0;
    const missed = window
      ? Math.max(0, desired - overlap)
      : place.preferredWindow
        ? null
        : 0;
    if (missed === null)
      warnings.push(
        "Sunset-based preference cannot be evaluated because sunset is unavailable.",
      );
    else if (missed > 0)
      warnings.push(
        `Preferred-window overlap is short by ${Math.ceil(missed)} minutes; destination retained.`,
      );
    const summary = summarizeWeather(weather, visitAt, leaveAt, place.exposure);
    if (summary.unknownMinutes > 0)
      warnings.push(
        "Forecast coverage is incomplete. Weather penalty is a lower bound, not evidence of clear weather.",
      );
    if (weather?.warning) warnings.push(weather.warning);
    stops.push({
      placeId: place.id,
      name: place.name,
      leg,
      arrivalAt,
      visitAt,
      leaveAt,
      waitMinutes: (visitAt - arrivalAt) / 60,
      weather: summary,
      preferredWindow: window,
      preferredWindowMissMinutes: missed,
      evidenceIds: [
        `input:${place.id}`,
        leg.evidenceId,
        ...(weather ? [weather.evidenceId] : []),
      ],
      warnings,
    });
    time = leaveAt;
    from = place;
  }
  const overtimeMinutes = Math.max(0, (time - trip.finishBy) / 60);
  if (overtimeMinutes > 0)
    violations.push(
      `Finish time exceeded by ${Math.ceil(overtimeMinutes)} minutes. All remaining destinations are retained.`,
    );
  const travelMinutes = stops.reduce(
    (sum, s) => sum + s.leg.durationSeconds / 60,
    0,
  );
  const waitMinutes = stops.reduce((sum, s) => sum + s.waitMinutes, 0);
  const rainExposureMinutes = stops.reduce(
    (sum, s) => sum + s.weather.rainExposureMinutes,
    0,
  );
  const preferredWindowMissMinutes = stops.reduce(
    (sum, s) => sum + (s.preferredWindowMissMinutes ?? 0),
    0,
  );
  return {
    id: `${order.map((p) => p.id).join("/")}:${wait ? "wait" : "direct"}`,
    order: order.map((p) => p.id),
    waitForPreferredWindow: wait,
    stops,
    finishesAt: time,
    travelMinutes,
    waitMinutes,
    rainExposureMinutes,
    preferredWindowMissMinutes,
    unknownWeatherMinutes: stops.reduce(
      (sum, s) => sum + s.weather.unknownMinutes,
      0,
    ),
    overtimeMinutes,
    violations,
    feasible: violations.length === 0,
    score:
      Math.round(
        (travelMinutes * WEIGHTS.travel +
          waitMinutes * WEIGHTS.waiting +
          preferredWindowMissMinutes * WEIGHTS.missedPreferredWindow +
          rainExposureMinutes * WEIGHTS.rainExposure) *
          100,
      ) / 100,
  };
}
export function rank(a: Candidate, b: Candidate): number {
  return (
    Number(b.feasible) - Number(a.feasible) ||
    (a.feasible
      ? 0
      : a.violations.length - b.violations.length ||
        a.overtimeMinutes - b.overtimeMinutes) ||
    a.score - b.score ||
    a.id.localeCompare(b.id)
  );
}
export function assertPreserved(trip: Trip, candidate: Candidate): void {
  ensure(
    candidate.stops.map((s) => s.placeId).join(",") ===
      candidate.order.join(","),
    "Candidate stop sequence does not match its selected order.",
  );
  const expected = trip.places.map((p) => p.id).sort();
  ensure(
    candidate.order.length === expected.length &&
      [...candidate.order].sort().join(",") === expected.join(","),
    "Candidate changed the selected destinations.",
  );
  let time = trip.startsAt;
  let from = trip.origin.id;
  for (const stop of candidate.stops) {
    ensure(
      stop.leg.fromId === from &&
        stop.leg.toId === stop.placeId &&
        stop.leg.departureAt === time &&
        stop.arrivalAt === time + stop.leg.durationSeconds &&
        stop.visitAt >= stop.arrivalAt,
      "Candidate has inconsistent routing or time arithmetic.",
    );
    const place = trip.places.find((p) => p.id === stop.placeId)!;
    ensure(
      stop.leaveAt === stop.visitAt + place.durationMinutes * 60,
      "Candidate changed a visit duration.",
    );
    from = stop.placeId;
    time = stop.leaveAt;
  }
  ensure(
    candidate.stops.length === expected.length && time === candidate.finishesAt,
    "Candidate itinerary is incomplete.",
  );
}
export async function schedule(trip: Trip, provider: DataProvider) {
  const [matrix, forecasts] = await Promise.all([
    provider.matrix(trip),
    provider.weather(trip),
  ]);
  const initialLookup: Lookup = async (from, to, departure) => {
    const route = matrix.get(edge(from.id, to.id));
    ensure(route, `Route missing: ${from.id} -> ${to.id}.`);
    return { ...route, departureAt: departure };
  };
  const evaluated: Candidate[] = [];
  for (const order of permutations(trip.places))
    for (const wait of [false, true])
      evaluated.push(
        await evaluate(trip, order, wait, initialLookup, forecasts),
      );
  evaluated.sort(rank);
  const originalId = `${trip.places.map((p) => p.id).join("/")}:direct`;
  const original = evaluated.find((c) => c.id === originalId)!;
  const travelOnly = evaluated
    .filter((c) => !c.waitForPreferredWindow)
    .sort(
      (a, b) => a.travelMinutes - b.travelMinutes || a.id.localeCompare(b.id),
    )[0]!;
  const signatures = new Set<string>();
  const distinct = evaluated.filter((c) => {
    const signature = c.stops.map((s) => `${s.placeId}@${s.visitAt}`).join(",");
    if (signatures.has(signature)) return false;
    signatures.add(signature);
    return true;
  });
  const shortlist = new Map(
    distinct.slice(0, SHORTLIST_SIZE).map((c) => [c.id, c]),
  );
  shortlist.set(original.id, original);
  shortlist.set(travelOnly.id, travelOnly);
  const candidates: Candidate[] = [];
  // Each next leg is requested using the preceding visit's actual proposed departure.
  // Initial matrix values only shortlist candidates; they are never a final live timetable.
  for (const approximate of shortlist.values()) {
    const order = approximate.order.map((id) =>
      trip.places.find((p) => p.id === id)!,
    );
    const candidate = await evaluate(
      trip,
      order,
      approximate.waitForPreferredWindow,
      (from, to, departure) => provider.route(from, to, departure, trip),
      forecasts,
    );
    assertPreserved(trip, candidate);
    candidates.push(candidate);
  }
  return {
    candidates: candidates.sort(rank),
    baselineOriginal: candidates.find((c) => c.id === original.id)!,
    baselineTravelOnly: candidates.find((c) => c.id === travelOnly.id)!,
    initialCandidateCount: evaluated.length,
    forecasts,
  };
}
