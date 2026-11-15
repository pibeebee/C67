// Standalone experiment. No dependency on the iOS app, database, or shared service.
export type Mode = "live" | "fixture-ai" | "fixture";
export type Point = {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
};
export type Window =
  | { kind: "clock"; startTime: string; endTime: string }
  | { kind: "sunset"; minutesBefore: number };
export type Place = Point & {
  durationMinutes: number;
  exposure: "indoor" | "outdoor" | "mixed";
  context: string;
  openingHours?: { opensAt: string; closesAt: string };
  preferredWindow?: Window;
};
export type Input = {
  title: string;
  date: string;
  timeZone: "Asia/Jakarta";
  startTime: string;
  finishTime: string;
  mode: "DRIVE" | "WALK";
  preferences: string[];
  origin: Point;
  places: Place[];
};
export type Progress = {
  visitedIds: string[];
  fromId?: string;
  readyAt?: string;
};
export type Trip = {
  input: Input;
  origin: Point;
  places: Place[];
  visited: Place[];
  startsAt: number;
  finishBy: number;
};
export type Evidence = {
  id: string;
  source: string;
  synthetic: boolean;
  fetchedAt: string;
  data: unknown;
};
export type Route = {
  fromId: string;
  toId: string;
  departureAt: number;
  durationSeconds: number;
  distanceMeters: number;
  evidenceId: string;
};
export type WeatherHour = {
  at: number;
  rainProbability: number | null;
  temperatureC: number | null;
  cloudCover: number | null;
};
export type Weather = {
  placeId: string;
  hours: WeatherHour[];
  sunrise: number | null;
  sunset: number | null;
  evidenceId: string;
  warning?: string;
};
export type WeatherSummary = {
  rainProbability: number | null;
  temperatureC: number | null;
  cloudCover: number | null;
  rainExposureMinutes: number;
  unknownMinutes: number;
};
export type Stop = {
  placeId: string;
  name: string;
  leg: Route;
  arrivalAt: number;
  visitAt: number;
  leaveAt: number;
  waitMinutes: number;
  weather: WeatherSummary;
  preferredWindow: { start: number; end: number } | null;
  preferredWindowMissMinutes: number | null;
  evidenceIds: string[];
  warnings: string[];
};
export type Candidate = {
  id: string;
  order: string[];
  waitForPreferredWindow: boolean;
  stops: Stop[];
  finishesAt: number;
  travelMinutes: number;
  waitMinutes: number;
  rainExposureMinutes: number;
  preferredWindowMissMinutes: number;
  unknownWeatherMinutes: number;
  overtimeMinutes: number;
  violations: string[];
  feasible: boolean;
  score: number;
};
export type Decision = {
  candidateId: string;
  summary: string;
  rationale: { placeId: string; reason: string; evidenceIds: string[] }[];
  tradeoffs: string[];
  uncertainties: string[];
};
export type AIResult = {
  called: boolean;
  model: string | null;
  reasoningMode: "auto" | "off" | "on" | null;
  maxTokens: number | null;
  timeoutMs: number | null;
  contextLimit: number | null;
  responseId: string | null;
  usage: unknown;
  latencyMs: number;
  decision: Decision;
};

export class PocError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PocError";
  }
}
export function ensure(condition: unknown, message: string): asserts condition {
  if (!condition) throw new PocError(message);
}
export function object(value: unknown, label: string): Record<string, unknown> {
  ensure(
    typeof value === "object" && value !== null && !Array.isArray(value),
    `${label} must be an object.`,
  );
  return value as Record<string, unknown>;
}
export function text(value: unknown, label: string, max = 1000): string {
  ensure(
    typeof value === "string" && value.trim().length > 0 && value.length <= max,
    `${label} must be a nonempty string, maximum ${max} characters.`,
  );
  return value.trim();
}
export function finite(
  value: unknown,
  label: string,
  min: number,
  max: number,
): number {
  ensure(
    typeof value === "number" &&
      Number.isFinite(value) &&
      value >= min &&
      value <= max,
    `${label} must be between ${min} and ${max}.`,
  );
  return value;
}
export function clock(value: unknown, label: string): string {
  const result = text(value, label, 5);
  ensure(
    /^([01]\d|2[0-3]):[0-5]\d$/.test(result),
    `${label} must use HH:mm (WIB).`,
  );
  return result;
}
export function at(date: string, time: string): number {
  return Date.parse(`${date}T${time}:00+07:00`) / 1000;
}
export function iso(seconds: number): string {
  return new Date(seconds * 1000).toISOString();
}
export function wib(seconds: number): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Jakarta",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(seconds * 1000);
}
export function resolveDate(value: unknown, now = Date.now()): string {
  let date = text(value, "date", 10);
  if (date === "tomorrow")
    date = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Jakarta",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(now + 86400000);
  ensure(
    /^\d{4}-\d{2}-\d{2}$/.test(date),
    "date must use YYYY-MM-DD or tomorrow.",
  );
  const parsed = Date.parse(`${date}T00:00:00Z`);
  ensure(
    Number.isFinite(parsed) &&
      new Date(parsed).toISOString().slice(0, 10) === date,
    "date is not a valid calendar date.",
  );
  return date;
}
function point(value: unknown, label: string): Point {
  const p = object(value, label);
  const id = text(p.id, `${label}.id`, 30);
  ensure(
    /^[A-Za-z][A-Za-z0-9_-]*$/.test(id),
    `${label}.id must use letters, digits, underscores or hyphens.`,
  );
  return {
    id,
    name: text(p.name, `${label}.name`, 120),
    latitude: finite(p.latitude, `${label}.latitude`, -90, 90),
    longitude: finite(p.longitude, `${label}.longitude`, -180, 180),
  };
}
export function parseInput(value: unknown, dateOverride?: string): Input {
  const v = object(value, "input");
  const date = resolveDate(dateOverride ?? v.date);
  ensure(
    v.timeZone === "Asia/Jakarta",
    "This PoC supports Asia/Jakarta (WIB) only.",
  );
  const startTime = clock(v.startTime, "startTime");
  const finishTime = clock(v.finishTime, "finishTime");
  ensure(
    at(date, finishTime) > at(date, startTime),
    "finishTime must follow startTime on the same day.",
  );
  ensure(
    v.mode === "DRIVE" || v.mode === "WALK",
    "mode must be DRIVE or WALK. Transit/multimodal routing is outside this PoC.",
  );
  ensure(
    Array.isArray(v.preferences) && v.preferences.length <= 10,
    "preferences must be an array of at most 10 strings.",
  );
  ensure(
    Array.isArray(v.places) && v.places.length >= 1 && v.places.length <= 5,
    "Provide 1..5 selected destinations.",
  );
  const origin = point(v.origin, "origin");
  const places: Place[] = v.places.map((item, index) => {
    const label = `places[${index}]`;
    const p = object(item, label);
    ensure(
      ["indoor", "outdoor", "mixed"].includes(String(p.exposure)),
      `${label}.exposure must be indoor, outdoor or mixed.`,
    );
    const result: Place = {
      ...point(p, label),
      durationMinutes: finite(
        p.durationMinutes,
        `${label}.durationMinutes`,
        1,
        480,
      ),
      exposure: p.exposure as Place["exposure"],
      context: text(p.context, `${label}.context`, 1500),
    };
    if (p.openingHours !== undefined) {
      const hours = object(p.openingHours, `${label}.openingHours`);
      result.openingHours = {
        opensAt: clock(hours.opensAt, "opensAt"),
        closesAt: clock(hours.closesAt, "closesAt"),
      };
      ensure(
        result.openingHours.closesAt > result.openingHours.opensAt,
        "Opening hours must be on the same day, closing after opening.",
      );
    }
    if (p.preferredWindow !== undefined) {
      const window = object(p.preferredWindow, `${label}.preferredWindow`);
      if (window.kind === "clock") {
        const start = clock(window.startTime, "preferredWindow.startTime");
        const end = clock(window.endTime, "preferredWindow.endTime");
        ensure(end > start, "Preferred window must end after it starts.");
        result.preferredWindow = {
          kind: "clock",
          startTime: start,
          endTime: end,
        };
      } else {
        ensure(
          window.kind === "sunset",
          "preferredWindow.kind must be clock or sunset.",
        );
        result.preferredWindow = {
          kind: "sunset",
          minutesBefore: finite(window.minutesBefore, "minutesBefore", 1, 180),
        };
      }
    }
    return result;
  });
  ensure(
    new Set([origin.id, ...places.map((p) => p.id)]).size === places.length + 1,
    "Origin and destination IDs must be unique.",
  );
  return {
    title: text(v.title, "title", 160),
    date,
    timeZone: "Asia/Jakarta",
    startTime,
    finishTime,
    mode: v.mode,
    preferences: v.preferences.map((p, i) => text(p, `preferences[${i}]`, 500)),
    origin,
    places,
  };
}
export function prepareTrip(
  input: Input,
  progress: Progress = { visitedIds: [] },
): Trip {
  const ids = new Set(input.places.map((p) => p.id));
  ensure(
    new Set(progress.visitedIds).size === progress.visitedIds.length &&
      progress.visitedIds.every((id) => ids.has(id)),
    "Visited IDs must be unique selected destinations.",
  );
  ensure(
    Boolean(progress.fromId) === Boolean(progress.readyAt),
    "--from and --ready-at must be supplied together.",
  );
  ensure(
    progress.visitedIds.length === 0 || progress.fromId,
    "Replanning visited destinations requires --from and --ready-at.",
  );
  let origin = input.origin;
  let startsAt = at(input.date, input.startTime);
  if (progress.fromId) {
    const current = input.places.find((p) => p.id === progress.fromId);
    ensure(
      current && progress.visitedIds.includes(current.id),
      "--from must be a visited destination, including the current visit that ends at --ready-at.",
    );
    origin = current;
    startsAt = at(input.date, clock(progress.readyAt, "readyAt"));
    ensure(
      startsAt >= at(input.date, input.startTime),
      "readyAt must not precede the trip start.",
    );
  }
  const places = input.places.filter(
    (p) => !progress.visitedIds.includes(p.id),
  );
  ensure(
    places.length > 0,
    "All destinations have already been visited; no remaining itinerary to plan.",
  );
  ensure(
    startsAt < at(input.date, input.finishTime),
    "Departure must precede the finish time.",
  );
  return {
    input,
    origin,
    places,
    visited: input.places.filter((p) => progress.visitedIds.includes(p.id)),
    startsAt,
    finishBy: at(input.date, input.finishTime),
  };
}
