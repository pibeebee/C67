import { ensure, object, resolveDate } from "./domain.ts";
import type { PlaceContext } from "./untimed.ts";

export function parsePlaceContext(
  raw: unknown,
): PlaceContext & { research?: unknown } {
  const c = object(raw, "place context");
  const locations = object(c.locations, "context locations");
  ensure(
    Array.isArray(c.areas) &&
      c.areas.length > 0 &&
      c.areas.length <= 12 &&
      Array.isArray(c.facts) &&
      c.facts.length <= 60 &&
      Array.isArray(c.walkingPairs) &&
      c.walkingPairs.length <= 30,
    "Context collection bounds exceeded.",
  );
  const areas = new Set<string>();
  for (const rawArea of c.areas) {
    const a = object(rawArea, "area");
    ensure(
      typeof a.id === "string" &&
        !areas.has(a.id) &&
        typeof a.latitude === "number" &&
        Math.abs(a.latitude) <= 90 &&
        typeof a.longitude === "number" &&
        Math.abs(a.longitude) <= 180,
      "Invalid forecast sampling area.",
    );
    areas.add(a.id);
  }
  ensure(
    Object.keys(locations).length > 0 && Object.keys(locations).length <= 60,
    "Provide 1..60 named/area locations.",
  );
  for (const rawPlace of Object.values(locations)) {
    const p = object(rawPlace, "location");
    ensure(
      typeof p.name === "string" &&
        p.name.length <= 500 &&
        (p.address === null ||
          (typeof p.address === "string" &&
            p.address.length > 0 &&
            p.address.length <= 1000)) &&
        areas.has(String(p.area)),
      "Invalid context location.",
    );
  }
  for (const pair of c.walkingPairs)
    ensure(
      Array.isArray(pair) &&
        pair.length === 2 &&
        pair.every((p) => typeof p === "string" && Object.hasOwn(locations, p)),
      "Unknown walking pair.",
    );
  const ids = new Set<string>();
  for (const rawFact of c.facts) {
    const f = object(rawFact, "source fact");
    ensure(
      typeof f.id === "string" &&
        !ids.has(f.id) &&
        typeof f.name === "string" &&
        typeof f.url === "string" &&
        new URL(f.url).protocol === "https:" &&
        Array.isArray(f.activityIds) &&
        f.activityIds.every((x) => typeof x === "string") &&
        typeof f.note === "string",
      "Invalid source fact.",
    );
    ids.add(f.id);
    if (f.kind === "seasonal_event") {
      ensure(
        typeof f.startDate === "string" &&
          typeof f.endDate === "string" &&
          /^\d{4}-\d{2}-\d{2}$/.test(f.startDate) &&
          /^\d{4}-\d{2}-\d{2}$/.test(f.endDate) &&
          f.startDate <= f.endDate,
        "Invalid seasonal source dates.",
      );
      resolveDate(f.startDate);
      resolveDate(f.endDate);
    }
    if (f.kind === "opening_hours")
      ensure(
        typeof f.opensAt === "string" &&
          typeof f.closesAt === "string" &&
          /^([01]\d|2[0-3]):[0-5]\d$/.test(f.opensAt) &&
          /^([01]\d|2[0-3]):[0-5]\d$/.test(f.closesAt) &&
          f.opensAt < f.closesAt,
        "Only a valid single same-day source opening window is supported.",
      );
  }
  ensure(
    Array.isArray(c.limitations) &&
      c.limitations.every((x) => typeof x === "string"),
    "Context limitations must be strings.",
  );
  return raw as PlaceContext & { research?: unknown };
}
