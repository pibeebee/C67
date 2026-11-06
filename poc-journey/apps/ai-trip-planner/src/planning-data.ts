import { createHash } from "node:crypto";
import { ensure, object } from "./domain.ts";
import { duration, parseWeather } from "./data.ts";
import { jstAt, jstStamp } from "./audit.ts";
import { Http } from "./http.ts";
import {
  forecastAvailability,
  type PlaceContext,
  type UntimedInput,
} from "./untimed.ts";

export type RouteEvidence = {
  id: string;
  from: string;
  to: string;
  mode: "WALK" | "TRANSIT";
  departureAt: string | null;
  fetchedAt: string;
  status:
    | "ok"
    | "no_route"
    | "unresolved_location"
    | "provider_error"
    | "budget_exhausted";
  estimatedMinutes: number | null;
  distanceMeters: number | null;
  partialAddressMatch: boolean;
  transitDetails: unknown[];
  error: string | null;
};
export class RouteEvidenceStore {
  readonly evidence: RouteEvidence[] = [];
  private cache = new Map<string, Promise<RouteEvidence>>();
  readonly http = new Http(fetch, AbortSignal.timeout(15 * 60 * 1000));
  readonly context: PlaceContext;
  private key: string;
  readonly maxRequests: number;
  constructor(context: PlaceContext, key: string, maxRequests = 90) {
    this.context = context;
    this.key = key;
    this.maxRequests = maxRequests;
  }
  query(
    from: string,
    to: string,
    mode: "WALK" | "TRANSIT",
    departureAt: string | null,
  ): Promise<RouteEvidence> {
    const cacheKey = JSON.stringify({
      from,
      to,
      mode,
      departureAt: mode === "TRANSIT" ? departureAt : null,
    });
    if (!this.cache.has(cacheKey))
      this.cache.set(
        cacheKey,
        this.request(from, to, mode, departureAt, cacheKey),
      );
    return this.cache.get(cacheKey)!;
  }
  seed(evidence: RouteEvidence[]) {
    for (const e of evidence) {
      const key = JSON.stringify({
        from: e.from,
        to: e.to,
        mode: e.mode,
        departureAt: e.mode === "TRANSIT" ? e.departureAt : null,
      });
      this.evidence.push(e);
      this.cache.set(key, Promise.resolve(e));
    }
  }
  private async request(
    from: string,
    to: string,
    mode: "WALK" | "TRANSIT",
    departureAt: string | null,
    key: string,
  ) {
    const result: RouteEvidence = {
      id: `route:${createHash("sha256").update(key).digest("hex").slice(0, 16)}`,
      from,
      to,
      mode,
      departureAt: mode === "TRANSIT" ? departureAt : null,
      fetchedAt: new Date().toISOString(),
      status: "unresolved_location",
      estimatedMinutes: null,
      distanceMeters: null,
      partialAddressMatch: false,
      transitDetails: [],
      error: null,
    };
    this.evidence.push(result);
    const origin = this.context.locations[from],
      destination = this.context.locations[to];
    if (!origin?.address || !destination?.address) {
      result.error =
        "A selected location is not precise enough for routing; no restaurant or station was substituted.";
      return result;
    }
    if ((this.http.calls["Google planning route"] ?? 0) >= this.maxRequests) {
      result.status = "budget_exhausted";
      result.error = "Run route request budget exhausted.";
      return result;
    }
    try {
      ensure(
        mode !== "TRANSIT" ||
          (departureAt !== null && Number.isFinite(Date.parse(departureAt))),
        "Transit requires an explicit proposed/system-probe departure.",
      );
      const raw = object(
        await this.http.json(
          "Google planning route",
          "https://routes.googleapis.com/directions/v2:computeRoutes",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Goog-Api-Key": this.key,
              "X-Goog-FieldMask":
                "routes.duration,routes.distanceMeters,routes.legs.steps.transitDetails,geocodingResults",
            },
            body: JSON.stringify({
              origin: { address: origin.address },
              destination: { address: destination.address },
              travelMode: mode,
              ...(mode === "TRANSIT"
                ? {
                    departureTime: departureAt,
                    transitPreferences: {
                      allowedTravelModes: ["TRAIN", "SUBWAY", "LIGHT_RAIL"],
                    },
                  }
                : {}),
            }),
          },
        ),
        "route response",
      );
      if (!Array.isArray(raw.routes) || raw.routes.length === 0) {
        result.status = "no_route";
        result.error =
          "This provider query returned no route; actual transport availability remains unknown.";
        return result;
      }
      const route = object(raw.routes[0], "route");
      result.estimatedMinutes = duration(route.duration) / 60;
      result.distanceMeters =
        typeof route.distanceMeters === "number" ? route.distanceMeters : null;
      result.partialAddressMatch = JSON.stringify(
        raw.geocodingResults ?? {},
      ).includes('"partialMatch":true');
      if (Array.isArray(route.legs))
        for (const leg of route.legs) {
          const steps = object(leg, "route leg").steps;
          if (Array.isArray(steps))
            for (const step of steps) {
              const s = object(step, "route step");
              if (s.transitDetails)
                result.transitDetails.push(s.transitDetails);
            }
        }
      result.status = "ok";
    } catch {
      result.status = "provider_error";
      result.error =
        "Google route request failed; no travel duration was invented.";
    }
    return result;
  }
}
export type ForecastEvidence = {
  id: string;
  areaId: string;
  fetchedAt: string;
  status: "available" | "outside_forecast_horizon" | "unavailable";
  hours: {
    at: string;
    temperatureC: number | null;
    rainProbability: number | null;
    cloudCover: number | null;
  }[];
  sunrise: string | null;
  sunset: string | null;
  error: string | null;
};
export async function collectForecasts(
  input: UntimedInput,
  context: PlaceContext,
  http: Http,
): Promise<ForecastEvidence[]> {
  const availability = forecastAvailability(input.date);
  const results: ForecastEvidence[] = [];
  for (let i = 0; i < context.areas.length; i += 3)
    results.push(
      ...(await Promise.all(
        context.areas.slice(i, i + 3).map(async (area) => {
          const result: ForecastEvidence = {
            id: `weather:${area.id}`,
            areaId: area.id,
            fetchedAt: new Date().toISOString(),
            status: "unavailable",
            hours: [],
            sunrise: null,
            sunset: null,
            error: null,
          };
          if (availability.status === "outside_forecast_horizon") {
            result.status = "outside_forecast_horizon";
            result.error =
              "Trip date is outside the forecast horizon. Weather and solar times were not fabricated.";
            return result;
          }
          try {
            const params = new URLSearchParams({
              latitude: String(area.latitude),
              longitude: String(area.longitude),
              hourly: "temperature_2m,precipitation_probability,cloud_cover",
              daily: "sunrise,sunset",
              timezone: input.timeZone,
              timeformat: "unixtime",
              start_date: input.date,
              end_date: input.date,
            });
            const raw = await http.json(
              "Open-Meteo planning forecast",
              `https://api.open-meteo.com/v1/forecast?${params}`,
            );
            const weather = parseWeather(raw, area.id, result.id);
            result.hours = weather.hours.map((h) => ({
              ...h,
              at: jstStamp(h.at),
            }));
            result.sunrise = weather.sunrise ? jstStamp(weather.sunrise) : null;
            result.sunset = weather.sunset ? jstStamp(weather.sunset) : null;
            ensure(
              result.hours.length > 0 &&
                result.hours.every((h) => h.at.slice(0, 10) === input.date),
              "Forecast response did not cover the requested local date.",
            );
            result.status = "available";
          } catch {
            result.error =
              "Forecast request failed or did not cover the requested date; unknown is not zero-percent rain.";
          }
          return result;
        }),
      )),
    );
  return results;
}
export async function collectInitialRoutes(
  input: UntimedInput,
  context: PlaceContext,
  routes: RouteEvidenceStore,
) {
  const requested = [
    ...context.walkingPairs.map(([from, to]) => ({
      from,
      to,
      mode: "WALK" as const,
      departureAt: null,
    })),
    ...input.requiredTransit.map((p) => ({
      ...p,
      mode: "TRANSIT" as const,
      departureAt: jstStamp(jstAt(input.date, "12:00")),
    })),
  ];
  const evidence: RouteEvidence[] = [];
  for (let i = 0; i < requested.length; i += 3)
    evidence.push(
      ...(await Promise.all(
        requested
          .slice(i, i + 3)
          .map((p) => routes.query(p.from, p.to, p.mode, p.departureAt)),
      )),
    );
  return {
    evidence,
    probeTimeSource:
      "TRANSIT noon probe is a system sampling assumption, not the user's departure time or a confirmed itinerary. Final routes are queried again at propagated departures.",
  };
}
