import { ensure, object, resolveDate, text, finite } from "./domain.ts";

export type TravelMode = "WALK" | "TRANSIT";
export type Exposure = "indoor" | "outdoor" | "mixed" | "unknown";
export type LocationInput = {
  id: string;
  name: string;
  query: string;
  placeId?: string;
  acceptedNames: string[];
  role: "visit" | "transfer";
  dwellMinutes: number;
  dwellSource: "user" | "default" | "transfer";
  exposure: Exposure;
  referenceNote: string | null;
};
export type RoutingInput = {
  title: string;
  date: string;
  timeZone: "Asia/Tokyo" | "Asia/Jakarta";
  startTime: string;
  finishBy: string;
  finishSource: "user" | "end_of_day";
  startsAt: number;
  endsAt: number;
  regionCode: string;
  origin: LocationInput;
  returnTo: LocationInput;
  places: LocationInput[];
  modes: TravelMode[];
  defaultDwellMinutes: number;
  weatherPolicy: { rainWeight: number; maxExtraMinutes: number };
  search: { beamWidth: number; shortlist: number };
};
export type OpeningWindow = { start: number; end: number };
export type OpeningInfo = {
  status: "date_specific" | "regular" | "unknown" | "closed";
  windows: OpeningWindow[];
  note: string;
};
export type PlaceMatch = {
  placeId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
};
export type ResolvedLocation = LocationInput & {
  status: "resolved" | "reference" | "ambiguous" | "unavailable";
  match: PlaceMatch | null;
  alternatives: PlaceMatch[];
  hours: OpeningInfo;
  evidenceId: string;
  error: string | null;
};
export type RouteOption = {
  id: string;
  from: string;
  to: string;
  mode: TravelMode;
  status:
    | "ok"
    | "no_route"
    | "unsupported_region"
    | "provider_error"
    | "budget_exhausted";
  durationSeconds: number | null;
  distanceMeters: number | null;
  walkingSeconds: number | null;
  departureAt: number;
  source: "matrix_probe" | "departure_query" | "same_place" | "capability";
  details: unknown[];
  note: string | null;
};
export type Forecast = {
  locationId: string;
  status: "available" | "outside_forecast_horizon" | "unavailable";
  hours: { at: number; rainProbability: number | null }[];
  note: string | null;
};
export interface RoutingProvider {
  resolve(
    location: LocationInput,
    input: RoutingInput,
  ): Promise<ResolvedLocation>;
  matrix(
    locations: ResolvedLocation[],
    input: RoutingInput,
  ): Promise<RouteOption[]>;
  routes(
    from: ResolvedLocation,
    to: ResolvedLocation,
    departureAt: number,
    input: RoutingInput,
  ): Promise<RouteOption[]>;
  forecasts(
    locations: ResolvedLocation[],
    input: RoutingInput,
  ): Promise<Forecast[]>;
}

const offsets = { "Asia/Tokyo": "+09:00", "Asia/Jakarta": "+07:00" } as const;
export const timestamp = (
  date: string,
  clock: string,
  zone: RoutingInput["timeZone"],
) => Date.parse(`${date}T${clock}:00${offsets[zone]}`) / 1000;
export function localClock(at: number, zone: RoutingInput["timeZone"]): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: zone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(at * 1000);
}
export const unknownHours = (): OpeningInfo => ({
  status: "unknown",
  windows: [],
  note: "Jam operasional tidak tersedia; tidak dianggap buka 24 jam.",
});

export function parseRoutingInput(raw: unknown): RoutingInput {
  const v = object(raw, "routing input");
  const date = resolveDate(v.date);
  ensure(
    v.timeZone === "Asia/Tokyo" || v.timeZone === "Asia/Jakarta",
    "Use Asia/Tokyo or Asia/Jakarta.",
  );
  const timeZone = v.timeZone;
  const clock = (value: unknown, label: string) => {
    const valueText = text(value, label, 5);
    ensure(
      /^([01]\d|2[0-3]):[0-5]\d$/.test(valueText),
      `${label} must use HH:mm.`,
    );
    return valueText;
  };
  const startTime = clock(v.startTime, "startTime");
  const finishBy =
    v.finishBy === undefined ? "23:59" : clock(v.finishBy, "finishBy");
  const defaultDwellMinutes = finite(
    v.defaultDwellMinutes ?? 30,
    "defaultDwellMinutes",
    1,
    480,
  );
  const location = (rawPlace: unknown, transfer = false): LocationInput => {
    const p = object(rawPlace, "location");
    const id = text(p.id, "location.id", 80);
    ensure(/^[A-Za-z][A-Za-z0-9_-]*$/.test(id), "Invalid location ID.");
    const role = p.role ?? (transfer ? "transfer" : "visit");
    ensure(
      role === "visit" || role === "transfer",
      "role must be visit or transfer; a station name alone does not determine its role.",
    );
    const exposure = p.exposure ?? "unknown";
    ensure(
      ["indoor", "outdoor", "mixed", "unknown"].includes(String(exposure)),
      "Invalid exposure.",
    );
    const dwellMinutes =
      role === "transfer"
        ? 0
        : finite(p.dwellMinutes ?? defaultDwellMinutes, "dwellMinutes", 1, 480);
    ensure(
      role !== "transfer" ||
        p.dwellMinutes === undefined ||
        p.dwellMinutes === 0,
      "A transfer has no extra visit duration; use role visit for sightseeing at a station.",
    );
    ensure(
      p.acceptedNames === undefined ||
        (Array.isArray(p.acceptedNames) &&
          p.acceptedNames.every((x) => typeof x === "string" && x.trim())),
      "Invalid acceptedNames.",
    );
    const query = text(p.query, "query", 400);
    return {
      id,
      name: text(p.name ?? query, "name", 200),
      query,
      ...(p.placeId ? { placeId: text(p.placeId, "placeId", 250) } : {}),
      acceptedNames: (p.acceptedNames as string[] | undefined) ?? [],
      role,
      exposure: exposure as Exposure,
      dwellMinutes,
      dwellSource:
        role === "transfer"
          ? "transfer"
          : p.dwellMinutes === undefined
            ? "default"
            : "user",
      referenceNote:
        p.referenceNote === undefined
          ? null
          : text(p.referenceNote, "referenceNote", 1000),
    };
  };
  const origin = location(v.origin, true);
  const returnTo =
    v.returnTo === undefined ? origin : location(v.returnTo, true);
  ensure(
    Array.isArray(v.places) && v.places.length > 0 && v.places.length <= 20,
    "Provide 1..20 destinations.",
  );
  const places = v.places.map((p) => location(p));
  ensure(
    new Set(places.map((p) => p.id)).size === places.length &&
      places.every((p) => p.id !== origin.id && p.id !== returnTo.id),
    "Destination IDs must be unique and distinct from endpoints.",
  );
  ensure(
    origin.id !== returnTo.id || origin.query === returnTo.query,
    "The same endpoint ID cannot identify two different places.",
  );
  const modes = v.modes ?? ["WALK", "TRANSIT"];
  ensure(
    Array.isArray(modes) &&
      modes.length > 0 &&
      modes.every((m) => m === "WALK" || m === "TRANSIT") &&
      new Set(modes).size === modes.length,
    "Supported modes: WALK and TRANSIT.",
  );
  const weather = object(v.weatherPolicy ?? {}, "weatherPolicy"),
    search = object(v.search ?? {}, "search");
  const startsAt = timestamp(date, startTime, timeZone),
    endsAt = timestamp(date, finishBy, timeZone);
  ensure(
    endsAt > startsAt,
    "finishBy must follow startTime within the trip date.",
  );
  const regionCode = text(v.regionCode, "regionCode", 2).toUpperCase();
  ensure(/^[A-Z]{2}$/.test(regionCode), "Use a two-letter regionCode.");
  const beamWidth = finite(search.beamWidth ?? 128, "beamWidth", 1, 512),
    shortlist = finite(search.shortlist ?? 4, "shortlist", 1, 8);
  ensure(
    Number.isInteger(beamWidth) && Number.isInteger(shortlist),
    "Search sizes must be integers.",
  );
  return {
    title: text(v.title ?? "Itinerary tanpa AI", "title", 200),
    date,
    timeZone,
    startTime,
    finishBy,
    finishSource: v.finishBy === undefined ? "end_of_day" : "user",
    startsAt,
    endsAt,
    regionCode,
    origin,
    returnTo,
    places,
    modes,
    defaultDwellMinutes,
    weatherPolicy: {
      rainWeight: finite(weather.rainWeight ?? 2, "rainWeight", 0, 20),
      maxExtraMinutes: finite(
        weather.maxExtraMinutes ?? 15,
        "maxExtraMinutes",
        0,
        120,
      ),
    },
    search: { beamWidth, shortlist },
  };
}

// Weekly periods are intersected with the requested local date, including overnight periods.
// Current hours are used only inside their seven-day coverage, never for an arbitrary future date.
export function openingInfo(
  raw: Record<string, unknown>,
  input: RoutingInput,
  today: string,
): OpeningInfo {
  if (
    ["CLOSED_PERMANENTLY", "CLOSED_TEMPORARILY"].includes(
      String(raw.businessStatus),
    )
  )
    return { status: "closed", windows: [], note: String(raw.businessStatus) };
  const days = Math.round(
    (Date.parse(input.date) - Date.parse(today)) / 86400000,
  );
  const current = days >= 0 && days < 7 && raw.currentOpeningHours;
  const hours = current || raw.regularOpeningHours;
  if (
    !hours ||
    typeof hours !== "object" ||
    !Array.isArray((hours as Record<string, unknown>).periods)
  )
    return unknownHours();
  const periods = (hours as { periods: unknown[] }).periods;
  const base = timestamp(input.date, "00:00", input.timeZone);
  const weekday = new Date(`${input.date}T12:00:00Z`).getUTCDay();
  const windows: OpeningWindow[] = [];
  const pointMinutes = (
    point: Record<string, unknown>,
    shift: number,
  ): number | null => {
    if (point.date && typeof point.date === "object") {
      const d = point.date as Record<string, number>;
      const actual = Date.UTC(d.year!, d.month! - 1, d.day!);
      if (!Number.isFinite(actual)) return null;
      return (
        (actual - Date.parse(input.date)) / 60000 +
        Number(point.hour ?? 0) * 60 +
        Number(point.minute ?? 0)
      );
    }
    if (typeof point.day !== "number") return null;
    return (
      (point.day - weekday + shift * 7) * 1440 +
      Number(point.hour ?? 0) * 60 +
      Number(point.minute ?? 0)
    );
  };
  for (const p of periods) {
    if (!p || typeof p !== "object") continue;
    const { open, close } = p as {
      open?: Record<string, unknown>;
      close?: Record<string, unknown>;
    };
    if (!open) continue;
    if (
      !close &&
      open.day === 0 &&
      Number(open.hour ?? 0) === 0 &&
      Number(open.minute ?? 0) === 0
    ) {
      windows.push({ start: base, end: base + 86400 });
      continue;
    }
    if (!close) continue;
    for (const shift of [-1, 0, 1]) {
      const start = pointMinutes(open, shift),
        rawEnd = pointMinutes(close, shift);
      if (start === null || rawEnd === null) continue;
      const end = rawEnd <= start ? rawEnd + 7 * 1440 : rawEnd;
      const clippedStart = Math.max(0, start),
        clippedEnd = Math.min(1440, end);
      if (clippedEnd > clippedStart)
        windows.push({
          start: base + clippedStart * 60,
          end: base + clippedEnd * 60,
        });
      if (open.date) break;
    }
  }
  return {
    status: current ? "date_specific" : "regular",
    windows: [
      ...new Map(windows.map((w) => [`${w.start}:${w.end}`, w])).values(),
    ].sort((a, b) => a.start - b.start),
    note: current
      ? "Jam khusus dalam cakupan tujuh hari provider."
      : "Jadwal reguler; pengecualian tanggal trip belum dikonfirmasi.",
  };
}
