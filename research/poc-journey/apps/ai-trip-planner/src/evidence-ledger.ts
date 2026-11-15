import { createHash } from "node:crypto";
import { ensure, object, text, resolveDate } from "./domain.ts";
import {
  groundedClaim,
  numericText,
  type ResearchClaim,
} from "./research-agent.ts";
import type { BrowserPage } from "./research-browser.ts";
import type { UntimedInput, PlaceContext } from "./untimed.ts";
import type { ForecastEvidence, RouteEvidence } from "./planning-data.ts";

export type Applicability = {
  kind:
    | "general"
    | "daily"
    | "weekdays"
    | "weekends"
    | "date_range"
    | "specific_date"
    | "unknown";
  weekdays: number[];
  validFrom: string | null;
  validThrough: string | null;
  exceptionNote: string;
};
export type ScopedClaim = ResearchClaim & {
  applicability: Applicability;
  applies: "yes" | "conditional" | "no" | "unknown";
};
export type Requirement = {
  id: string;
  kind: "identity" | "hours" | "event" | "transit" | "forecast";
  subject: string;
  critical: boolean;
  status:
    | "provided"
    | "supported"
    | "conditional"
    | "missing"
    | "unavailable"
    | "conflicting"
    | "deferred";
  evidenceIds: string[];
  message: string;
};
export const edgeKey = (from: string, to: string, mode: string) =>
  `${mode}:${from}->${to}`;
const digest = (v: unknown) =>
  createHash("sha256").update(JSON.stringify(v)).digest("hex");
export class EvidenceLedger {
  readonly claims: ScopedClaim[] = [];
  readonly rejected: { message: string; sourceId: string | null }[] = [];
  readonly unavailable: {
    requirementId: string;
    reason: string;
    evidenceIds: string[];
  }[] = [];
  constructor(input: UntimedInput, context: PlaceContext) {
    this.input = input;
    this.originalContext = context;
  }
  private proposedTransit: { from: string; to: string }[] = [];
  setProposedTransit(pairs: { from: string; to: string }[]) {
    this.proposedTransit = pairs;
  }
  readonly input: UntimedInput;
  readonly originalContext: PlaceContext;
  register(raw: unknown, pages: BrowserPage[]) {
    const v = object(raw, "scoped claim");
    let claimInput = this.input;
    if (
      v.kind === "travel_duration" &&
      this.input.requiredTransit.length === 0
    ) {
      const pair = [v.from, v.to];
      ensure(
        pair.every(
          (id) =>
            typeof id === "string" &&
            Object.hasOwn(this.originalContext.locations, id) &&
            (this.input.activities.some((a) => a.locationId === id) ||
              id === this.input.origin ||
              id === this.input.returnTo) &&
            /station|stasiun|駅/i.test(
              this.originalContext.locations[String(id)]!.name,
            ),
        ),
        "Travel-duration claim endpoints must be selected station/origin/return IDs.",
      );
      claimInput = {
        ...this.input,
        requiredTransit: [{ from: String(v.from), to: String(v.to) }],
      };
    }
    const claim = groundedClaim(v, pages, claimInput, 8000);
    ensure(
      claim.kind === "travel_duration" || claim.activityIds.length > 0,
      "A place claim must map to a requested activity.",
    );
    const a = object(v.applicability, "applicability");
    ensure(
      [
        "general",
        "daily",
        "weekdays",
        "weekends",
        "date_range",
        "specific_date",
        "unknown",
      ].includes(String(a.kind)),
      "Invalid applicability kind.",
    );
    ensure(
      Array.isArray(a.weekdays) &&
        a.weekdays.every(
          (x) =>
            typeof x === "number" && Number.isInteger(x) && x >= 0 && x <= 6,
        ),
      "Invalid weekdays.",
    );
    const quote = numericText(claim.quote),
      day = new Date(`${this.input.date}T12:00:00+09:00`).getUTCDay();
    let applies: ScopedClaim["applies"] = "unknown";
    const validFrom =
        a.validFrom === null ? null : text(a.validFrom, "validFrom", 10),
      validThrough =
        a.validThrough === null
          ? null
          : text(a.validThrough, "validThrough", 10);
    if (a.kind === "date_range" || a.kind === "specific_date") {
      ensure(
        validFrom &&
          validThrough &&
          /^\d{4}-\d{2}-\d{2}$/.test(validFrom) &&
          /^\d{4}-\d{2}-\d{2}$/.test(validThrough) &&
          validFrom <= validThrough &&
          quote.includes(validFrom) &&
          quote.includes(validThrough),
        "Applicability dates must be quoted; a range need not spell out the trip date.",
      );
      resolveDate(validFrom);
      resolveDate(validThrough);
      if (a.kind === "specific_date")
        ensure(
          validFrom === validThrough,
          "A specific-date rule must quote one date.",
        );
      applies =
        this.input.date >= validFrom && this.input.date <= validThrough
          ? "yes"
          : "no";
    } else if (a.kind === "weekdays" || a.kind === "weekends") {
      const expected = a.kind === "weekdays" ? [1, 2, 3, 4, 5] : [0, 6];
      ensure(
        (a.kind === "weekdays"
          ? /平日|weekdays?|Monday.*Friday/i
          : /土日|weekends?|Saturday.*Sunday/i
        ).test(quote),
        "Weekday classification must be present in the quotation.",
      );
      ensure(
        JSON.stringify([...a.weekdays].sort()) ===
          JSON.stringify(expected.sort()),
        "Weekday list does not match the quoted category.",
      );
      // Holiday exceptions cannot be determined from a weekly rule alone.
      applies = expected.includes(day) ? "conditional" : "no";
    } else if (a.kind === "daily") {
      ensure(
        /毎日|daily|every day|年中無休/i.test(quote),
        "Daily applicability must be stated in the quote.",
      );
      applies = "conditional";
    } else if (a.kind === "general") applies = "conditional";
    if (claim.kind === "seasonal_event")
      applies =
        this.input.date >= claim.startDate! && this.input.date <= claim.endDate!
          ? "yes"
          : "no";
    const scoped: ScopedClaim = {
      ...claim,
      id: `claim:${digest({ claim, a }).slice(0, 20)}`,
      applicability: {
        kind: a.kind as Applicability["kind"],
        weekdays: a.weekdays as number[],
        validFrom,
        validThrough,
        exceptionNote: text(a.exceptionNote, "exceptionNote", 1500),
      },
      applies,
    };
    const same = this.claims.find((c) => c.id === scoped.id);
    if (same) return same;
    this.claims.push(scoped);
    return scoped;
  }
  context(): PlaceContext {
    const c = structuredClone(this.originalContext);
    for (const claim of this.claims) {
      if (claim.applicability.kind === "unknown") continue;
      if (
        claim.kind !== "seasonal_event" &&
        claim.applies !== "yes" &&
        claim.applies !== "conditional"
      )
        continue;
      if (!["opening_hours", "seasonal_event"].includes(claim.kind)) continue;
      c.facts.push({
        id: claim.id,
        kind: claim.kind,
        activityIds: claim.activityIds,
        name: claim.name,
        url: claim.url,
        note: `Quote-grounded AI extraction; scope ${claim.applicability.kind}; applicability ${claim.applies}; exceptions: ${claim.applicability.exceptionNote}. ${claim.note}`,
        ...(claim.opensAt
          ? { opensAt: claim.opensAt, closesAt: claim.closesAt! }
          : {}),
        ...(claim.startDate
          ? { startDate: claim.startDate, endDate: claim.endDate! }
          : {}),
      });
    }
    return c;
  }
  requirements(
    routes: RouteEvidence[],
    forecasts: ForecastEvidence[],
  ): Requirement[] {
    const requirements: Requirement[] = [];
    for (const a of this.input.activities) {
      const place = this.originalContext.locations[a.locationId]!;
      requirements.push({
        id: `identity:${a.id}`,
        kind: "identity",
        subject: a.id,
        critical:
          !place.address ||
          [
            "unknown",
            "station_area",
            "beach_area",
            "street_reference_point",
          ].includes(place.precision),
        status: !place.address
          ? "missing"
          : place.precision === "named_place"
            ? "provided"
            : "conditional",
        evidenceIds: [`input:${a.id}`],
        message: `Input location precision: ${place.precision}; no automatic replacement of the selected place.`,
      });
      const hours = this.claims.filter(
        (c) =>
          c.kind === "opening_hours" &&
          c.activityIds.includes(a.id) &&
          ["yes", "conditional"].includes(c.applies),
      );
      const original = this.originalContext.facts.filter(
        (f) => f.kind === "opening_hours" && f.activityIds.includes(a.id),
      );
      const windows = [
        ...new Set(hours.map((h) => `${h.opensAt}-${h.closesAt}`)),
      ];
      const sourceConflict =
        windows.length > 1 ||
        hours.some((h) =>
          original.some(
            (f) => f.opensAt !== h.opensAt || f.closesAt !== h.closesAt,
          ),
        );
      const publicArea = [
        "beach_area",
        "park_area",
        "bridge_area",
        "street_area",
      ].includes(place.precision);
      requirements.push({
        id: `hours:${a.id}`,
        kind: "hours",
        subject: a.id,
        critical: !publicArea,
        status: sourceConflict
          ? "conflicting"
          : hours.some((h) => h.applies === "yes")
            ? "supported"
            : hours.length || original.length
              ? "conditional"
              : "missing",
        evidenceIds: [...hours.map((h) => h.id), ...original.map((f) => f.id)],
        message: sourceConflict
          ? "Source opening windows disagree; retain both and request resolution."
          : "General hours may inform planning; date-specific closures, shop/restaurant identity and exceptions still require confirmation.",
      });
    }
    for (const a of this.input.activities) {
      const original = this.originalContext.facts.filter(
        (f) => f.kind === "seasonal_event" && f.activityIds.includes(a.id),
      );
      const sourced = this.claims.filter(
        (c) => c.kind === "seasonal_event" && c.activityIds.includes(a.id),
      );
      if (!original.length && !sourced.length) continue;
      const explicitlyNamed = sourced.some((c) =>
        a.label.toLocaleLowerCase().includes(c.name.toLocaleLowerCase()),
      );
      requirements.push({
        id: `event:${a.id}`,
        kind: "event",
        subject: a.id,
        critical: true,
        status: sourced.some((c) => c.applies === "no")
          ? "conflicting"
          : sourced.length && explicitlyNamed
            ? "supported"
            : original.length || sourced.length
              ? "conditional"
              : "missing",
        evidenceIds: [
          ...original.map((f) => f.id),
          ...sourced.map((c) => c.id),
        ],
        message:
          "Check the event's exact identity and published season. Mapping generic illumination to a named event is a system interpretation until confirmed.",
      });
    }
    for (const pair of [
      ...new Map(
        [...this.input.requiredTransit, ...this.proposedTransit].map((p) => [
          `${p.from}->${p.to}`,
          p,
        ]),
      ).values(),
    ]) {
      const matching = routes.filter(
        (r) => r.from === pair.from && r.to === pair.to && r.mode === "TRANSIT",
      );
      const known = matching.filter(
        (r) => r.status === "ok" && !r.partialAddressMatch,
      );
      requirements.push({
        id: `transit:${pair.from}->${pair.to}`,
        kind: "transit",
        subject: edgeKey(pair.from, pair.to, "TRANSIT"),
        critical: true,
        status: known.length
          ? "supported"
          : matching.length
            ? "unavailable"
            : "missing",
        evidenceIds: matching.map((r) => r.id),
        message: known.length
          ? "Provider estimate exists; final-departure simulation still determines coverage."
          : "No provider route estimate yet. A generic quoted duration cannot certify a dated train service.",
      });
    }
    for (const area of this.originalContext.areas) {
      const f = forecasts.find((f) => f.areaId === area.id);
      requirements.push({
        id: `forecast:${area.id}`,
        kind: "forecast",
        subject: area.id,
        critical: false,
        status:
          f?.status === "outside_forecast_horizon"
            ? "deferred"
            : f?.status === "available"
              ? f.hours.some((h) => h.rainProbability === null) ||
                !f.sunrise ||
                !f.sunset
                ? "conditional"
                : "supported"
              : "unavailable",
        evidenceIds: f ? [f.id] : [],
        message:
          f?.status === "outside_forecast_horizon"
            ? "Future forecast is not obtainable now; do not repeatedly search for invented weather."
            : "Regional forecast evidence, not guaranteed conditions at a venue.",
      });
    }
    return requirements;
  }
  snapshot(routes: RouteEvidence[], forecasts: ForecastEvidence[]) {
    return {
      requirements: this.requirements(routes, forecasts),
      claims: this.claims,
      rejected: this.rejected,
      unavailable: this.unavailable,
    };
  }
  evidenceIds(
    routes: RouteEvidence[],
    forecasts: ForecastEvidence[],
    pages: BrowserPage[],
  ) {
    return new Set([
      ...this.input.activities.map((a) => `input:${a.id}`),
      ...this.originalContext.facts.map((f) => f.id),
      ...this.claims.map((c) => c.id),
      ...routes.map((r) => r.id),
      ...forecasts.map((f) => f.id),
      ...pages.map((p) => p.id),
    ]);
  }
}
