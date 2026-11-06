import {
  at,
  ensure,
  finite,
  iso,
  object,
  type Evidence,
  type Point,
  type Route,
  type Trip,
  type Weather,
  type WeatherHour,
} from "./domain.ts";
import { Http } from "./http.ts";

export type Matrix = Map<string, Route>;
export type DataProvider = {
  evidence: Evidence[];
  matrix(trip: Trip): Promise<Matrix>;
  route(from: Point, to: Point, departure: number, trip: Trip): Promise<Route>;
  weather(trip: Trip): Promise<Map<string, Weather>>;
};
export const edge = (from: string, to: string) => `${from}/${to}`;
const waypoint = (p: Point) => ({
  location: { latLng: { latitude: p.latitude, longitude: p.longitude } },
});
export function duration(value: unknown): number {
  ensure(
    typeof value === "string" && /^\d+(\.\d{1,9})?s$/.test(value),
    "Google Routes returned an invalid duration.",
  );
  return Math.ceil(
    finite(Number(value.slice(0, -1)), "route duration seconds", 0, 172800),
  );
}
function nullable(value: unknown, min: number, max: number): number | null {
  return typeof value === "number" &&
    Number.isFinite(value) &&
    value >= min &&
    value <= max
    ? value
    : null;
}
export function parseWeather(
  raw: unknown,
  placeId: string,
  evidenceId: string,
): Weather {
  const data = object(raw, "Open-Meteo response");
  const hourly = object(data.hourly, "Open-Meteo hourly");
  ensure(
    Array.isArray(hourly.time),
    "Open-Meteo hourly time must be an array.",
  );
  const array = (key: string) =>
    Array.isArray(hourly[key]) ? (hourly[key] as unknown[]) : [];
  const rain = array("precipitation_probability");
  const temperatures = array("temperature_2m");
  const clouds = array("cloud_cover");
  const hours: WeatherHour[] = [];
  let previous = -Infinity;
  for (const [i, time] of hourly.time.entries()) {
    const stamp = finite(time, "weather timestamp", 0, 1e11);
    ensure(
      stamp >= previous + 3600,
      "Weather hourly intervals must be unique, ascending and nonoverlapping.",
    );
    previous = stamp;
    hours.push({
      at: stamp,
      rainProbability: nullable(rain[i], 0, 100),
      temperatureC: nullable(temperatures[i], -100, 80),
      cloudCover: nullable(clouds[i], 0, 100),
    });
  }
  const daily =
    data.daily && typeof data.daily === "object"
      ? object(data.daily, "Open-Meteo daily")
      : {};
  const sun = (key: string) =>
    nullable(Array.isArray(daily[key]) ? daily[key][0] : null, 1, 1e11);
  return {
    placeId,
    hours,
    sunrise: sun("sunrise"),
    sunset: sun("sunset"),
    evidenceId,
  };
}

export class LiveData implements DataProvider {
  evidence: Evidence[] = [];
  private cache = new Map<string, Route>();
  private apiKey: string;
  private http: Http;
  constructor(apiKey: string, http: Http) {
    this.apiKey = apiKey;
    this.http = http;
  }

  private record(id: string, source: string, data: unknown): string {
    this.evidence.push({
      id,
      source,
      synthetic: false,
      fetchedAt: new Date().toISOString(),
      data,
    });
    return id;
  }
  private routing(trip: Trip, departure: number) {
    return {
      travelMode: trip.input.mode,
      departureTime: iso(departure),
      ...(trip.input.mode === "DRIVE"
        ? { routingPreference: "TRAFFIC_AWARE" }
        : {}),
    };
  }
  async matrix(trip: Trip): Promise<Matrix> {
    const origins = [trip.origin, ...trip.places];
    const result = await this.http.json(
      "Google Routes matrix",
      "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": this.apiKey,
          "X-Goog-FieldMask":
            "originIndex,destinationIndex,status,condition,duration,distanceMeters,fallbackInfo",
        },
        body: JSON.stringify({
          origins: origins.map((p) => ({ waypoint: waypoint(p) })),
          destinations: trip.places.map((p) => ({ waypoint: waypoint(p) })),
          ...this.routing(trip, trip.startsAt),
        }),
      },
    );
    return this.parseMatrix(result, trip, origins);
  }
  parseMatrix(raw: unknown, trip: Trip, origins: Point[]): Matrix {
    ensure(Array.isArray(raw), "Google Routes matrix must be an array.");
    const routes: Matrix = new Map();
    for (const value of raw) {
      const cell = object(value, "matrix element");
      // Protobuf JSON may omit scalar fields whose value is zero.
      const oi = finite(
        cell.originIndex ?? 0,
        "originIndex",
        0,
        origins.length - 1,
      );
      const di = finite(
        cell.destinationIndex ?? 0,
        "destinationIndex",
        0,
        trip.places.length - 1,
      );
      ensure(
        Number.isInteger(oi) && Number.isInteger(di),
        "Matrix indices must be integers.",
      );
      const from = origins[oi]!;
      const to = trip.places[di]!;
      if (from.id === to.id) continue;
      const status =
        cell.status === undefined ? {} : object(cell.status, "matrix status");
      ensure(
        (status.code ?? 0) === 0 && cell.condition === "ROUTE_EXISTS",
        `No usable Google route for ${from.id} -> ${to.id}; the destination was not removed.`,
      );
      const key = edge(from.id, to.id);
      ensure(
        !routes.has(key),
        "Google Routes returned duplicate matrix elements.",
      );
      const route: Route = {
        fromId: from.id,
        toId: to.id,
        departureAt: trip.startsAt,
        durationSeconds: duration(cell.duration),
        distanceMeters: finite(
          cell.distanceMeters ?? 0,
          "distanceMeters",
          0,
          2e7,
        ),
        evidenceId: `matrix:${key}`,
      };
      this.record(route.evidenceId, "Google Routes computeRouteMatrix", {
        ...route,
        trafficRequested: trip.input.mode === "DRIVE",
        fallbackInfo: cell.fallbackInfo ?? null,
      });
      routes.set(key, route);
    }
    for (const from of origins)
      for (const to of trip.places)
        if (from.id !== to.id)
          ensure(
            routes.has(edge(from.id, to.id)),
            `Google Routes omitted ${from.id} -> ${to.id}.`,
          );
    return routes;
  }
  async route(
    from: Point,
    to: Point,
    departure: number,
    trip: Trip,
  ): Promise<Route> {
    const key = `${edge(from.id, to.id)}@${departure}`;
    const cached = this.cache.get(key);
    if (cached) return cached;
    const raw = object(
      await this.http.json(
        "Google Routes leg",
        "https://routes.googleapis.com/directions/v2:computeRoutes",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": this.apiKey,
            "X-Goog-FieldMask":
              "routes.duration,routes.distanceMeters,fallbackInfo",
          },
          body: JSON.stringify({
            origin: waypoint(from),
            destination: waypoint(to),
            ...this.routing(trip, departure),
          }),
        },
      ),
      "Google route response",
    );
    ensure(
      Array.isArray(raw.routes) && raw.routes.length > 0,
      `No Google route for ${from.id} -> ${to.id}.`,
    );
    const r = object(raw.routes[0], "Google route");
    const route: Route = {
      fromId: from.id,
      toId: to.id,
      departureAt: departure,
      durationSeconds: duration(r.duration),
      distanceMeters: finite(r.distanceMeters ?? 0, "distanceMeters", 0, 2e7),
      evidenceId: `route:${key}`,
    };
    this.record(route.evidenceId, "Google Routes computeRoutes", {
      ...route,
      trafficRequested: trip.input.mode === "DRIVE",
      fallbackInfo: raw.fallbackInfo ?? null,
    });
    this.cache.set(key, route);
    return route;
  }
  async weather(trip: Trip): Promise<Map<string, Weather>> {
    const results = new Map<string, Weather>();
    for (let i = 0; i < trip.places.length; i += 3) {
      await Promise.all(
        trip.places.slice(i, i + 3).map(async (place) => {
          const id = `weather:${place.id}`;
          const params = new URLSearchParams({
            latitude: String(place.latitude),
            longitude: String(place.longitude),
            hourly: "temperature_2m,precipitation_probability,cloud_cover",
            daily: "sunrise,sunset",
            timezone: "Asia/Jakarta",
            timeformat: "unixtime",
            start_date: trip.input.date,
            end_date: trip.input.date,
          });
          let weather: Weather;
          try {
            weather = parseWeather(
              await this.http.json(
                "Open-Meteo",
                `https://api.open-meteo.com/v1/forecast?${params}`,
              ),
              place.id,
              id,
            );
          } catch {
            weather = {
              placeId: place.id,
              hours: [],
              sunrise: null,
              sunset: null,
              evidenceId: id,
              warning:
                "Weather unavailable or invalid; rain and sunset must be treated as unknown.",
            };
          }
          this.record(id, "Open-Meteo (weather model forecast)", {
            ...weather,
            requestedDate: trip.input.date,
            latitude: place.latitude,
            longitude: place.longitude,
            attribution: "https://open-meteo.com/",
          });
          results.set(place.id, weather);
        }),
      );
    }
    return results;
  }
}

export type Fixture = {
  label: string;
  minutes: Record<string, Record<string, number>>;
  kilometers: Record<string, Record<string, number>>;
  sunrise: string;
  sunset: string;
  rain: {
    placeId: string;
    startHour: number;
    endHour: number;
    probability: number;
  }[];
};
export class FixtureData implements DataProvider {
  evidence: Evidence[] = [];
  private fixture: Fixture;
  constructor(fixture: Fixture) {
    this.fixture = fixture;
  }
  async route(from: Point, to: Point, departure: number): Promise<Route> {
    const minutes = this.fixture.minutes[from.id]?.[to.id];
    const km = this.fixture.kilometers[from.id]?.[to.id];
    ensure(
      minutes !== undefined && km !== undefined,
      "Fixture supports only its declared IDs (example: A/B/C/D). Use live mode for other destinations.",
    );
    const route = {
      fromId: from.id,
      toId: to.id,
      departureAt: departure,
      durationSeconds: finite(minutes, "fixture minutes", 0, 2880) * 60,
      distanceMeters: finite(km, "fixture km", 0, 20000) * 1000,
      evidenceId: `fixture-route:${edge(from.id, to.id)}@${departure}`,
    };
    if (!this.evidence.some((e) => e.id === route.evidenceId))
      this.evidence.push({
        id: route.evidenceId,
        source: this.fixture.label,
        synthetic: true,
        fetchedAt: new Date().toISOString(),
        data: route,
      });
    return route;
  }
  async matrix(trip: Trip): Promise<Matrix> {
    const result: Matrix = new Map();
    for (const from of [trip.origin, ...trip.places])
      for (const to of trip.places)
        if (from.id !== to.id)
          result.set(
            edge(from.id, to.id),
            await this.route(from, to, trip.startsAt),
          );
    return result;
  }
  async weather(trip: Trip): Promise<Map<string, Weather>> {
    return new Map(
      trip.places.map((place) => {
        const weather: Weather = {
          placeId: place.id,
          evidenceId: `weather:${place.id}`,
          sunrise: at(trip.input.date, this.fixture.sunrise),
          sunset: at(trip.input.date, this.fixture.sunset),
          hours: Array.from({ length: 24 }, (_, h) => ({
            at: at(trip.input.date, `${String(h).padStart(2, "0")}:00`),
            rainProbability:
              this.fixture.rain.find(
                (r) =>
                  r.placeId === place.id && h >= r.startHour && h < r.endHour,
              )?.probability ?? 10,
            temperatureC: 29,
            cloudCover: 40,
          })),
        };
        this.evidence.push({
          id: weather.evidenceId,
          source: `${this.fixture.label} — synthetic forecast`,
          synthetic: true,
          fetchedAt: new Date().toISOString(),
          data: weather,
        });
        return [place.id, weather];
      }),
    );
  }
}
