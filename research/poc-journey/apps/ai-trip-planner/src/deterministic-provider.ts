import { createHash } from "node:crypto";
import { Http } from "./http.ts";
import { duration, parseWeather } from "./data.ts";
import { object } from "./domain.ts";
import {
  openingInfo,
  unknownHours,
  type Forecast,
  type LocationInput,
  type PlaceMatch,
  type ResolvedLocation,
  type RouteOption,
  type RoutingInput,
  type RoutingProvider,
  type TravelMode,
} from "./deterministic-model.ts";

const id = (value: unknown) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex").slice(0, 16);
const normalize = (name: string) =>
  name
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]/gu, "");
const iso = (seconds: number) => new Date(seconds * 1000).toISOString();
const chunks = <T>(items: T[], size: number): T[][] =>
  Array.from({ length: Math.ceil(items.length / size) }, (_, i) =>
    items.slice(i * size, (i + 1) * size),
  );
const waypoint = (place: ResolvedLocation) => ({
  placeId: place.match!.placeId,
});
export const JAPAN_TRANSIT_LIMITATION =
  "Google Routes tidak mendukung mitra transit Jepang. https://developers.google.com/maps/faq#transit_directions_countries";

export async function mapLimited<T, R>(
  items: T[],
  worker: (value: T, index: number) => Promise<R>,
  concurrency = 3,
): Promise<R[]> {
  const result = new Array<R>(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        result[i] = await worker(items[i]!, i);
      }
    }),
  );
  return result;
}

export class GoogleRoutingProvider implements RoutingProvider {
  readonly evidence: {
    id: string;
    service: string;
    request: unknown;
    data: unknown;
    fetchedAt: string;
  }[] = [];
  readonly http: Http;
  readonly now: number;
  private apiKey: string;
  private maxRequests: number;
  private cache = new Map<string, Promise<unknown>>();
  private routeCache = new Map<string, Promise<RouteOption[]>>();
  constructor(
    apiKey: string,
    options: {
      fetcher?: typeof fetch;
      now?: number;
      maxRequests?: number;
    } = {},
  ) {
    this.apiKey = apiKey;
    this.now = options.now ?? Date.now();
    this.maxRequests = options.maxRequests ?? 200;
    this.http = new Http(
      options.fetcher ?? fetch,
      AbortSignal.timeout(15 * 60 * 1000),
    );
  }
  private async request(
    service: string,
    url: string,
    body: unknown,
    fields: string,
  ): Promise<unknown> {
    const key = JSON.stringify({ service, url, body, fields });
    if (!this.cache.has(key)) {
      this.cache.set(
        key,
        (async () => {
          if (this.evidence.length >= this.maxRequests)
            throw new Error("Provider request budget exhausted.");
          const record = {
            id: `provider:${id(key)}`,
            service,
            request: { url, body, fields },
            data: null as unknown,
            fetchedAt: new Date().toISOString(),
          };
          this.evidence.push(record);
          try {
            record.data = await this.http.json(service, url, {
              method: body === null ? "GET" : "POST",
              headers: {
                "Content-Type": "application/json",
                "X-Goog-Api-Key": this.apiKey,
                "X-Goog-FieldMask": fields,
              },
              ...(body === null ? {} : { body: JSON.stringify(body) }),
            });
            return record.data;
          } catch (error) {
            record.data = {
              error:
                error instanceof Error
                  ? error.message
                  : "Provider unavailable.",
            };
            throw error;
          }
        })(),
      );
    }
    return this.cache.get(key)!;
  }
  async resolve(
    location: LocationInput,
    input: RoutingInput,
  ): Promise<ResolvedLocation> {
    const result: ResolvedLocation = {
      ...location,
      status: "unavailable",
      match: null,
      alternatives: [],
      hours: unknownHours(),
      evidenceId: `place:${location.id}`,
      error: null,
    };
    try {
      const fields =
        "id,displayName,formattedAddress,location,types,businessStatus,regularOpeningHours,currentOpeningHours";
      const data = object(
        location.placeId
          ? await this.request(
              "Google Places Details",
              `https://places.googleapis.com/v1/places/${encodeURIComponent(location.placeId)}`,
              null,
              fields,
            )
          : await this.request(
              "Google Places Search",
              "https://places.googleapis.com/v1/places:searchText",
              {
                textQuery: location.query,
                pageSize: 3,
                languageCode: "en",
                regionCode: input.regionCode,
              },
              fields
                .split(",")
                .map((f) => `places.${f}`)
                .join(","),
            ),
        "Places response",
      );
      const places = location.placeId
        ? [data]
        : Array.isArray(data.places)
          ? data.places.map((p) => object(p, "place"))
          : [];
      const parsed = places.flatMap((p) => {
        const coord = p.location as Record<string, unknown> | undefined;
        const display = p.displayName as { text?: string } | undefined;
        if (
          typeof p.id !== "string" ||
          !coord ||
          typeof coord.latitude !== "number" ||
          typeof coord.longitude !== "number"
        )
          return [];
        return [
          {
            raw: p,
            match: {
              placeId: p.id,
              name: display?.text ?? location.name,
              address:
                typeof p.formattedAddress === "string"
                  ? p.formattedAddress
                  : "",
              latitude: coord.latitude,
              longitude: coord.longitude,
            } satisfies PlaceMatch,
          },
        ];
      });
      const unique = [
        ...new Map(parsed.map((p) => [p.match.placeId, p])).values(),
      ];
      result.alternatives = unique.map((p) => p.match);
      const names = new Set(
        [location.name, ...location.acceptedNames].map(normalize),
      );
      const exact = unique.filter((p) => names.has(normalize(p.match.name)));
      const selected =
        location.placeId || unique.length === 1
          ? unique[0]
          : exact.length === 1
            ? exact[0]
            : undefined;
      if (!selected) {
        result.status = unique.length > 1 ? "ambiguous" : "unavailable";
        result.error =
          unique.length > 1
            ? "Beberapa tempat cocok; pilih placeId. Tidak memilih kandidat pertama secara diam-diam."
            : "Lokasi tidak ditemukan.";
        return result;
      }
      result.match = selected.match;
      result.status = location.referenceNote ? "reference" : "resolved";
      const today = new Intl.DateTimeFormat("en-CA", {
        timeZone: input.timeZone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(this.now);
      result.hours = location.referenceNote
        ? {
            ...unknownHours(),
            note: "Jam tempat referensi tidak otomatis berlaku untuk aktivitas yang belum spesifik.",
          }
        : openingInfo(selected.raw, input, today);
    } catch (error) {
      result.error =
        error instanceof Error ? error.message : "Place lookup failed.";
    }
    return result;
  }
  private unsupported(
    from: ResolvedLocation,
    to: ResolvedLocation,
    mode: TravelMode,
    departureAt: number,
  ): RouteOption | null {
    return mode === "TRANSIT" && this.currentRegion === "JP"
      ? {
          id: `route:${id([from.id, to.id, mode, "unsupported"])}`,
          from: from.id,
          to: to.id,
          mode,
          status: "unsupported_region",
          durationSeconds: null,
          distanceMeters: null,
          walkingSeconds: null,
          departureAt,
          source: "capability",
          details: [],
          note: JAPAN_TRANSIT_LIMITATION,
        }
      : null;
  }
  private currentRegion = "";
  async matrix(
    locations: ResolvedLocation[],
    input: RoutingInput,
  ): Promise<RouteOption[]> {
    this.currentRegion = input.regionCode;
    const result: RouteOption[] = [];
    for (const mode of input.modes) {
      if (mode === "TRANSIT" && input.regionCode === "JP") {
        for (const from of locations)
          for (const to of locations)
            if (from.id !== to.id)
              result.push(this.unsupported(from, to, mode, input.startsAt)!);
        continue;
      }
      const batches = chunks(locations, 10).flatMap((origins) =>
        chunks(locations, 10).map((destinations) => ({
          origins,
          destinations,
        })),
      );
      const rows = await mapLimited(
        batches,
        async ({ origins, destinations }) => {
          const fallback = (
            from: ResolvedLocation,
            to: ResolvedLocation,
            status: RouteOption["status"],
            note: string,
          ): RouteOption => ({
            id: `matrix:${id([from.id, to.id, mode])}`,
            from: from.id,
            to: to.id,
            mode,
            status,
            durationSeconds: null,
            distanceMeters: null,
            walkingSeconds: null,
            departureAt: input.startsAt,
            source: "matrix_probe",
            details: [],
            note,
          });
          const pairs = origins.flatMap((from) =>
            destinations
              .filter((to) => to.id !== from.id)
              .map((to) => ({ from, to })),
          );
          try {
            const raw = await this.request(
              "Google Routes Matrix",
              "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix",
              {
                origins: origins.map((p) => ({ waypoint: waypoint(p) })),
                destinations: destinations.map((p) => ({
                  waypoint: waypoint(p),
                })),
                travelMode: mode,
                ...(mode === "TRANSIT"
                  ? { departureTime: iso(input.startsAt) }
                  : {}),
              },
              "originIndex,destinationIndex,status,condition,duration,distanceMeters,fallbackInfo",
            );
            if (!Array.isArray(raw))
              throw new Error("Invalid matrix response.");
            const indexed = new Map(
              raw.map((cell) => {
                const c = object(cell, "matrix cell");
                return [
                  `${c.originIndex ?? 0}:${c.destinationIndex ?? 0}`,
                  c,
                ] as const;
              }),
            );
            return pairs.map(({ from, to }) => {
              if (from.match!.placeId === to.match!.placeId)
                return {
                  ...fallback(
                    from,
                    to,
                    "ok",
                    "Titik Google yang sama; aktivitas tetap terpisah.",
                  ),
                  durationSeconds: 0,
                  distanceMeters: 0,
                  walkingSeconds: 0,
                  source: "same_place" as const,
                };
              const c = indexed.get(
                `${origins.indexOf(from)}:${destinations.indexOf(to)}`,
              );
              if (
                !c ||
                Number(
                  (c.status as { code?: number } | undefined)?.code ?? 0,
                ) !== 0
              )
                return fallback(
                  from,
                  to,
                  "provider_error",
                  "Matrix element unavailable; no zero-duration fallback.",
                );
              if (c.condition !== "ROUTE_EXISTS")
                return fallback(
                  from,
                  to,
                  "no_route",
                  "Query provider tidak menemukan rute; bukan bukti bahwa moda sebenarnya tidak tersedia.",
                );
              try {
                return {
                  ...fallback(
                    from,
                    to,
                    "ok",
                    "Probe pada jam berangkat trip; bukan jadwal final tiap ruas.",
                  ),
                  durationSeconds: duration(c.duration),
                  distanceMeters:
                    typeof c.distanceMeters === "number"
                      ? c.distanceMeters
                      : null,
                };
              } catch {
                return fallback(
                  from,
                  to,
                  "provider_error",
                  "Invalid matrix duration.",
                );
              }
            });
          } catch (error) {
            return pairs.map(({ from, to }) =>
              fallback(
                from,
                to,
                "provider_error",
                error instanceof Error ? error.message : "Matrix unavailable.",
              ),
            );
          }
        },
      );
      result.push(...rows.flat());
    }
    return result;
  }
  async routes(
    from: ResolvedLocation,
    to: ResolvedLocation,
    departureAt: number,
    input: RoutingInput,
  ): Promise<RouteOption[]> {
    this.currentRegion = input.regionCode;
    const output = await Promise.all(
      input.modes.map(async (mode) => {
        const unsupported = this.unsupported(from, to, mode, departureAt);
        if (unsupported) return [unsupported];
        const key = JSON.stringify([
          from.id,
          to.id,
          mode,
          mode === "TRANSIT" ? departureAt : null,
        ]);
        if (!this.routeCache.has(key))
          this.routeCache.set(
            key,
            this.routeRequest(from, to, mode, departureAt),
          );
        // Walking durations can be reused, but the actual departure belongs to this candidate.
        return (await this.routeCache.get(key)!).map((r) => ({
          ...r,
          departureAt,
        }));
      }),
    );
    return output.flat();
  }
  private async routeRequest(
    from: ResolvedLocation,
    to: ResolvedLocation,
    mode: TravelMode,
    departureAt: number,
  ): Promise<RouteOption[]> {
    const base: RouteOption = {
      id: `route:${id([from.id, to.id, mode, mode === "TRANSIT" ? departureAt : null])}`,
      from: from.id,
      to: to.id,
      mode,
      status: "no_route",
      durationSeconds: null,
      distanceMeters: null,
      walkingSeconds: null,
      departureAt,
      source: "departure_query",
      details: [],
      note: null,
    };
    if (from.match!.placeId === to.match!.placeId)
      return [
        {
          ...base,
          status: "ok",
          durationSeconds: 0,
          distanceMeters: 0,
          walkingSeconds: 0,
          source: "same_place",
          note: "Titik Google yang sama; aktivitas tetap terpisah. Periksa referenceNote jika lokasi hanya pendekatan area.",
        },
      ];
    try {
      const data = object(
        await this.request(
          "Google Routes Leg",
          "https://routes.googleapis.com/directions/v2:computeRoutes",
          {
            origin: waypoint(from),
            destination: waypoint(to),
            travelMode: mode,
            computeAlternativeRoutes: true,
            ...(mode === "TRANSIT" ? { departureTime: iso(departureAt) } : {}),
          },
          "routes.duration,routes.distanceMeters,routes.legs.steps.travelMode,routes.legs.steps.staticDuration,routes.legs.steps.transitDetails",
        ),
        "routes response",
      );
      if (!Array.isArray(data.routes) || data.routes.length === 0)
        return [{ ...base, note: "Query provider tidak menemukan rute." }];
      return data.routes.map((raw, index) => {
        const r = object(raw, "route");
        const steps = (Array.isArray(r.legs) ? r.legs : []).flatMap((leg) => {
          const l = object(leg, "leg");
          return Array.isArray(l.steps)
            ? l.steps.map((s) => object(s, "step"))
            : [];
        });
        const seconds = duration(r.duration);
        const walking = steps.filter((s) => s.travelMode === "WALK");
        const walkingSeconds =
          mode === "WALK"
            ? seconds
            : steps.length &&
                walking.every((s) => typeof s.staticDuration === "string")
              ? walking.reduce((sum, s) => sum + duration(s.staticDuration), 0)
              : null;
        return {
          ...base,
          id: `${base.id}:${index}`,
          status: "ok" as const,
          durationSeconds: seconds,
          distanceMeters:
            typeof r.distanceMeters === "number" ? r.distanceMeters : null,
          walkingSeconds,
          details: steps
            .filter((s) => s.transitDetails)
            .map((s) => s.transitDetails),
          note:
            mode === "TRANSIT"
              ? "Paparan hujan dihitung pada bagian berjalan; lokasi menunggu terlindung/tidak terlindung belum diketahui."
              : null,
        };
      });
    } catch (error) {
      return [
        {
          ...base,
          status: "provider_error",
          note:
            error instanceof Error ? error.message : "Route request failed.",
        },
      ];
    }
  }
  async forecasts(
    locations: ResolvedLocation[],
    input: RoutingInput,
  ): Promise<Forecast[]> {
    const today = new Intl.DateTimeFormat("en-CA", {
      timeZone: input.timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(this.now);
    const days = Math.round(
      (Date.parse(input.date) - Date.parse(today)) / 86400000,
    );
    if (days < 0 || days > 15)
      return locations.map((p) => ({
        locationId: p.id,
        status: "outside_forecast_horizon",
        hours: [],
        note: "Tanggal trip di luar horizon prakiraan 16 hari; tidak diganti cuaca simulasi.",
      }));
    return mapLimited(locations, async (place) => {
      const result: Forecast = {
        locationId: place.id,
        status: "unavailable",
        hours: [],
        note: null,
      };
      try {
        const query = new URLSearchParams({
          latitude: String(place.match!.latitude),
          longitude: String(place.match!.longitude),
          hourly: "precipitation_probability,temperature_2m,cloud_cover",
          start_date: input.date,
          end_date: input.date,
          timezone: input.timeZone,
          timeformat: "unixtime",
        });
        const url = `https://api.open-meteo.com/v1/forecast?${query}`;
        const raw = await this.http.json("Open-Meteo", url);
        this.evidence.push({
          id: `weather:${place.id}`,
          service: "Open-Meteo",
          request: { url },
          data: raw,
          fetchedAt: new Date().toISOString(),
        });
        const weather = parseWeather(raw, place.id, `weather:${place.id}`);
        result.hours = weather.hours.map((h) => ({
          at: h.at,
          rainProbability: h.rainProbability,
        }));
        result.status = result.hours.length ? "available" : "unavailable";
      } catch (error) {
        result.note =
          error instanceof Error ? error.message : "Forecast unavailable.";
      }
      return result;
    });
  }
}
