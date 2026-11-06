import { ensure, object, resolveDate, type Weather } from "./domain.ts";
import { duration, parseWeather } from "./data.ts";
import { summarizeWeather } from "./scheduler.ts";
import { Http } from "./http.ts";

export type AuditEvent = {
  id: string;
  time: string;
  label: string;
  location: string;
  exposure: "indoor" | "outdoor" | "mixed" | "transit" | "unknown";
  optional?: boolean;
};
export type AuditLeg = {
  id: string;
  from: string;
  to: string;
  via?: string[];
  depart: string;
  arriveBy: string;
  mode: "WALK" | "TRANSIT";
  meaning:
    | "travel_only"
    | "activity_and_travel"
    | "station_to_station_proxy_for_home_arrival";
  eventIds: string[];
};
export type AuditFact = {
  id: string;
  kind: "seasonal_event" | "opening_hours" | "place_identity";
  eventIds: string[];
  name: string;
  url: string;
  note: string;
  startDate?: string;
  endDate?: string;
  opensAt?: string;
  closesAt?: string;
  checkedDate: string;
};
export type AuditInput = {
  title: string;
  date: string;
  timeZone: "Asia/Tokyo";
  source: string;
  areas: { id: string; name: string; latitude: number; longitude: number }[];
  locations: Record<
    string,
    { name: string; address: string | null; area: string; precision: string }
  >;
  events: AuditEvent[];
  legs: AuditLeg[];
  facts: AuditFact[];
};
export type CheckedLeg = AuditLeg & {
  evidenceId: string;
  status: "ok" | "unresolved_location" | "no_route" | "provider_error";
  plannedMinutes: number;
  estimatedMinutes: number | null;
  remainingMinutes: number | null;
  estimatedArrival: string | null;
  transitServices: unknown[];
  partialAddressMatch: boolean;
  error: string | null;
  providerResponse?: unknown;
};
export type AreaForecast = {
  areaId: string;
  evidenceId: string;
  weather: Weather;
  wind: { at: number; speedKmh: number | null; gustKmh: number | null }[];
  warning: string | null;
};
export type Finding = {
  id: string;
  severity: "conflict" | "unknown" | "note";
  eventIds: string[];
  evidenceIds: string[];
  message: string;
};
export type Snapshot = {
  collectedAt: string;
  input: AuditInput;
  legs: CheckedLeg[];
  forecasts: AreaForecast[];
  findings: Finding[];
  httpCalls: Record<string, number>;
};

export function jstAt(date: string, time: string): number {
  return Date.parse(`${date}T${time}:00+09:00`) / 1000;
}
export function jstStamp(seconds: number): string {
  return new Date((seconds + 9 * 3600) * 1000)
    .toISOString()
    .replace("Z", "+09:00");
}
export function parseAuditInput(raw: unknown): AuditInput {
  const v = object(raw, "itinerary");
  ensure(
    v.timeZone === "Asia/Tokyo",
    "Ordered Japan audit requires Asia/Tokyo.",
  );
  ensure(
    typeof v.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v.date),
    "Audit date must be explicit YYYY-MM-DD.",
  );
  resolveDate(v.date);
  ensure(
    Array.isArray(v.events) && v.events.length >= 2 && v.events.length <= 80,
    "Provide 2..80 ordered events.",
  );
  ensure(
    Array.isArray(v.legs) && Array.isArray(v.areas) && Array.isArray(v.facts),
    "Audit legs, areas and facts must be arrays.",
  );
  const locations = object(v.locations, "locations");
  const events = v.events as AuditEvent[];
  const ids = new Set<string>();
  let previous = -Infinity;
  for (const event of events) {
    ensure(
      typeof event.id === "string" && !ids.has(event.id),
      "Event IDs must be unique.",
    );
    ids.add(event.id);
    ensure(
      /^([01]\d|2[0-3]):[0-5]\d$/.test(event.time),
      "Event times must use HH:mm JST.",
    );
    const at = jstAt(v.date, event.time);
    ensure(at > previous, "Event times must increase on the same date.");
    previous = at;
    ensure(
      typeof event.label === "string" &&
        event.label.length > 0 &&
        event.label.length <= 500,
      "Invalid event label.",
    );
    ensure(
      event.location in locations,
      "Event references an unknown location.",
    );
    ensure(
      ["indoor", "outdoor", "mixed", "transit", "unknown"].includes(
        event.exposure,
      ),
      "Invalid event exposure.",
    );
  }
  const areaIds = new Set((v.areas as AuditInput["areas"]).map((a) => a.id));
  for (const area of v.areas as AuditInput["areas"])
    ensure(
      Number.isFinite(area.latitude) &&
        Math.abs(area.latitude) <= 90 &&
        Number.isFinite(area.longitude) &&
        Math.abs(area.longitude) <= 180,
      "Invalid regional forecast coordinates.",
    );
  for (const loc of Object.values(locations)) {
    const place = object(loc, "location");
    ensure(
      typeof place.name === "string" &&
        (place.address === null || typeof place.address === "string") &&
        areaIds.has(String(place.area)),
      "Invalid location or area reference.",
    );
  }
  const legIds = new Set<string>();
  for (const leg of v.legs as AuditLeg[]) {
    ensure(!legIds.has(leg.id), "Leg IDs must be unique.");
    legIds.add(leg.id);
    ensure(
      leg.from in locations &&
        leg.to in locations &&
        (leg.via ?? []).every((id) => id in locations),
      "Unknown route location.",
    );
    ensure(
      ["WALK", "TRANSIT"].includes(leg.mode),
      "Audit routes support WALK and TRANSIT.",
    );
    ensure(
      leg.mode !== "TRANSIT" || !leg.via?.length,
      "Transit cannot have intermediate waypoints.",
    );
    ensure(
      /^([01]\d|2[0-3]):[0-5]\d$/.test(leg.depart) &&
        /^([01]\d|2[0-3]):[0-5]\d$/.test(leg.arriveBy) &&
        jstAt(v.date, leg.arriveBy) > jstAt(v.date, leg.depart),
      "Invalid leg window.",
    );
    ensure(
      leg.eventIds.every((id) => ids.has(id)),
      "Unknown event reference on route.",
    );
  }
  for (const fact of v.facts as AuditFact[])
    ensure(
      /^https:\/\//.test(fact.url) && fact.eventIds.every((id) => ids.has(id)),
      "Invalid fact source or event reference.",
    );
  return raw as AuditInput;
}

export async function checkLeg(
  input: AuditInput,
  leg: AuditLeg,
  http: Http,
): Promise<CheckedLeg> {
  const plannedMinutes =
    (jstAt(input.date, leg.arriveBy) - jstAt(input.date, leg.depart)) / 60;
  const result: CheckedLeg = {
    ...leg,
    evidenceId: `route:${leg.id}`,
    status: "unresolved_location",
    plannedMinutes,
    estimatedMinutes: null,
    remainingMinutes: null,
    estimatedArrival: null,
    transitServices: [],
    partialAddressMatch: false,
    error: null,
  };
  const points = [leg.from, ...(leg.via ?? []), leg.to].map(
    (id) => input.locations[id]!,
  );
  if (points.some((p) => !p.address)) {
    result.error =
      "Exact apartment/restaurant location was not supplied; no route was invented.";
    return result;
  }
  try {
    const raw = object(
      await http.json(
        "Google audit route",
        "https://routes.googleapis.com/directions/v2:computeRoutes",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": process.env.GOOGLE_MAPS_API_KEY?.trim() ?? "",
            "X-Goog-FieldMask":
              "routes.duration,routes.distanceMeters,routes.legs.steps.travelMode,routes.legs.steps.transitDetails,geocodingResults",
          },
          body: JSON.stringify({
            origin: { address: points[0]!.address },
            destination: { address: points.at(-1)!.address },
            ...(leg.via?.length
              ? {
                  intermediates: points
                    .slice(1, -1)
                    .map((p) => ({ address: p.address })),
                }
              : {}),
            travelMode: leg.mode,
            departureTime: jstStamp(jstAt(input.date, leg.depart)),
            ...(leg.mode === "TRANSIT"
              ? {
                  transitPreferences: {
                    allowedTravelModes: ["TRAIN", "SUBWAY", "LIGHT_RAIL"],
                  },
                }
              : {}),
          }),
        },
      ),
      "Google route",
    );
    result.providerResponse = raw;
    if (!Array.isArray(raw.routes) || !raw.routes.length) {
      result.status = "no_route";
      result.error =
        "Provider returned no route. This is not evidence that the real journey is impossible.";
      return result;
    }
    const route = object(raw.routes[0], "Google route");
    const seconds = duration(route.duration);
    result.status = "ok";
    result.estimatedMinutes = seconds / 60;
    result.remainingMinutes = plannedMinutes - seconds / 60;
    result.estimatedArrival = jstStamp(jstAt(input.date, leg.depart) + seconds);
    if (Array.isArray(route.legs))
      for (const routeLeg of route.legs) {
        const steps = object(routeLeg, "route leg").steps;
        if (Array.isArray(steps))
          for (const step of steps) {
            const s = object(step, "route step");
            if (s.travelMode === "TRANSIT" && s.transitDetails)
              result.transitServices.push(s.transitDetails);
          }
      }
    const geocoding =
      raw.geocodingResults && typeof raw.geocodingResults === "object"
        ? object(raw.geocodingResults, "geocoding")
        : {};
    result.partialAddressMatch = JSON.stringify(geocoding).includes(
      '"partialMatch":true',
    );
    return result;
  } catch (error) {
    result.status = "provider_error";
    result.error =
      error instanceof Error ? error.message : "Route request failed.";
    return result;
  }
}
async function forecast(
  input: AuditInput,
  area: AuditInput["areas"][number],
  http: Http,
): Promise<AreaForecast> {
  const evidenceId = `weather:${area.id}`;
  try {
    const params = new URLSearchParams({
      latitude: String(area.latitude),
      longitude: String(area.longitude),
      hourly:
        "temperature_2m,precipitation_probability,cloud_cover,wind_speed_10m,wind_gusts_10m",
      daily: "sunrise,sunset",
      timezone: input.timeZone,
      timeformat: "unixtime",
      start_date: input.date,
      end_date: input.date,
      wind_speed_unit: "kmh",
    });
    const raw = object(
      await http.json(
        "Open-Meteo audit",
        `https://api.open-meteo.com/v1/forecast?${params}`,
      ),
      "forecast",
    );
    const weather = parseWeather(raw, area.id, evidenceId);
    const hourly = object(raw.hourly, "forecast hours");
    const speeds = Array.isArray(hourly.wind_speed_10m)
      ? hourly.wind_speed_10m
      : [];
    const gusts = Array.isArray(hourly.wind_gusts_10m)
      ? hourly.wind_gusts_10m
      : [];
    const nullable = (v: unknown) =>
      typeof v === "number" && Number.isFinite(v) ? v : null;
    return {
      areaId: area.id,
      evidenceId,
      weather,
      wind: weather.hours.map((h, i) => ({
        at: h.at,
        speedKmh: nullable(speeds[i]),
        gustKmh: nullable(gusts[i]),
      })),
      warning: null,
    };
  } catch {
    return {
      areaId: area.id,
      evidenceId,
      weather: {
        placeId: area.id,
        evidenceId,
        hours: [],
        sunrise: null,
        sunset: null,
      },
      wind: [],
      warning:
        "Forecast unavailable; no clear-weather or sunset claim can be verified.",
    };
  }
}
export function eventSlots(input: AuditInput, forecasts: AreaForecast[]) {
  return input.events.map((event, index) => {
    const start = jstAt(input.date, event.time);
    const next = input.events[index + 1];
    const end = next ? jstAt(input.date, next.time) : start;
    const area = input.locations[event.location]!.area;
    const weather = forecasts.find((f) => f.areaId === area)?.weather;
    const summary =
      next && ["outdoor", "mixed", "indoor"].includes(event.exposure)
        ? summarizeWeather(
            weather,
            start,
            end,
            event.exposure as "outdoor" | "mixed" | "indoor",
          )
        : null;
    return {
      ...event,
      evidenceId: `input:${event.id}`,
      startsAt: jstStamp(start),
      endsAt: jstStamp(end),
      slotMinutes: (end - start) / 60,
      forecastArea: area,
      regionalForecast: summary,
      sunset: weather?.sunset ? jstStamp(weather.sunset) : null,
      afterSunset: weather?.sunset ? start >= weather.sunset : null,
    };
  });
}
export function deriveFindings(
  input: AuditInput,
  legs: CheckedLeg[],
  forecasts: AreaForecast[],
): Finding[] {
  const findings: Finding[] = [];
  for (const leg of legs) {
    if (leg.status !== "ok")
      findings.push({
        id: `check:${leg.id}`,
        severity: "unknown",
        eventIds: leg.eventIds,
        evidenceIds: [leg.evidenceId],
        message: `${leg.id}: ${leg.error} Original ${leg.plannedMinutes}-minute allocation is unverified.`,
      });
    else if (leg.remainingMinutes! < 0)
      findings.push({
        id: `check:${leg.id}`,
        severity: "conflict",
        eventIds: leg.eventIds,
        evidenceIds: [leg.evidenceId],
        message: `${leg.id}: provider travel estimate ${leg.estimatedMinutes!.toFixed(1)} minutes exceeds the ${leg.plannedMinutes}-minute slot by ${(-leg.remainingMinutes!).toFixed(1)} minutes.`,
      });
    else if (leg.meaning === "activity_and_travel")
      findings.push({
        id: `check:${leg.id}`,
        severity: "note",
        eventIds: leg.eventIds,
        evidenceIds: [leg.evidenceId],
        message: `${leg.id}: ${leg.remainingMinutes!.toFixed(1)} minutes remain for the activity within this shared activity-and-travel slot, before queues/breaks.`,
      });
    if (leg.meaning === "station_to_station_proxy_for_home_arrival")
      findings.push({
        id: `check:home`,
        severity: "unknown",
        eventIds: leg.eventIds,
        evidenceIds: [leg.evidenceId, "input:E24"],
        message:
          "Final route ends at Funabashi Station, while 22:00 refers to the apartment. Apartment transfer time is unknown and has not been included.",
      });
  }
  for (const fact of input.facts) {
    if (
      fact.kind === "seasonal_event" &&
      fact.startDate &&
      fact.endDate &&
      (input.date < fact.startDate || input.date > fact.endDate)
    )
      findings.push({
        id: `check:${fact.id}`,
        severity: "conflict",
        eventIds: fact.eventIds,
        evidenceIds: [fact.id],
        message: `If illumination means ${fact.name}, it is outside the published ${fact.startDate} to ${fact.endDate} season. The user's intended illumination is unspecified; ordinary lighting availability remains unknown.`,
      });
    if (fact.kind === "opening_hours" && fact.opensAt && fact.closesAt) {
      const event = input.events.find((e) => fact.eventIds.includes(e.id))!;
      findings.push({
        id: `check:${fact.id}`,
        severity:
          event.time >= fact.opensAt && event.time < fact.closesAt
            ? "note"
            : "conflict",
        eventIds: fact.eventIds,
        evidenceIds: [fact.id, `input:${event.id}`],
        message: `${fact.name}: planned ${event.time} JST; published general hours ${fact.opensAt}–${fact.closesAt}. Date-specific closures have not been independently confirmed.`,
      });
    }
  }
  for (const slot of eventSlots(input, forecasts)) {
    if (slot.id === "E18" && slot.afterSunset)
      findings.push({
        id: "check:sea-candle-sunset",
        severity: "note",
        eventIds: ["E18"],
        evidenceIds: [`input:E18`, `weather:${slot.forecastArea}`],
        message: `Sea Candle arrival ${slot.startsAt} is after the supplied sunset ${slot.sunset}; this does not rule out night views or establish a seasonal event.`,
      });
    if (
      slot.exposure === "outdoor" &&
      slot.regionalForecast?.rainProbability !== null &&
      slot.regionalForecast?.rainProbability !== undefined &&
      slot.regionalForecast.rainProbability >= 60
    )
      findings.push({
        id: `check:rain:${slot.id}`,
        severity: "note",
        eventIds: [slot.id],
        evidenceIds: [`input:${slot.id}`, `weather:${slot.forecastArea}`],
        message: `Regional mean forecast rain probability during this slot is ${slot.regionalForecast.rainProbability.toFixed(1)}%. This is a regional forecast, not a guarantee or predicted rain duration.`,
      });
  }
  return findings;
}
export async function collectAudit(
  input: AuditInput,
  http: Http,
): Promise<Snapshot> {
  const legs: CheckedLeg[] = [];
  for (let i = 0; i < input.legs.length; i += 3)
    legs.push(
      ...(await Promise.all(
        input.legs.slice(i, i + 3).map((leg) => checkLeg(input, leg, http)),
      )),
    );
  const forecasts: AreaForecast[] = [];
  for (let i = 0; i < input.areas.length; i += 3)
    forecasts.push(
      ...(await Promise.all(
        input.areas.slice(i, i + 3).map((area) => forecast(input, area, http)),
      )),
    );
  return {
    collectedAt: new Date().toISOString(),
    input,
    legs,
    forecasts,
    findings: deriveFindings(input, legs, forecasts),
    httpCalls: http.calls,
  };
}
