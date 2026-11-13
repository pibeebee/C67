import { jstAt, jstStamp } from "./audit.ts";
import {
  RouteEvidenceStore,
  type RouteEvidence,
  type ForecastEvidence,
} from "./planning-data.ts";
import type {
  DayProposal,
  DayRow,
  PlaceContext,
  UntimedInput,
} from "./untimed.ts";

export type PlanningIssue = {
  code: string;
  severity: "conflict" | "unknown" | "advisory";
  rowIndex: number | null;
  message: string;
  evidenceIds: string[];
  repairableByScheduling: boolean;
};
export type ScheduledRow = {
  rowIndex: number;
  proposed: DayRow;
  startsAt: string;
  endsAt: string;
  allocatedMinutes: number;
  durationSource:
    | "ai_visit_proposal"
    | "ai_unverified_transfer"
    | "provider_plus_system_buffer"
    | "ai_buffer"
    | "source_opening_wait";
  routeId: string | null;
  routeStatus: RouteEvidence["status"] | null;
  providerTravelMinutes: number | null;
  systemBufferMinutes: number;
  note: string;
};
export type Simulation = {
  rows: ScheduledRow[];
  issues: PlanningIssue[];
  changes: { rowIndex: number; addedMinutes: number; reason: string }[];
  startsAt: string;
  endsAt: string;
  repairRecommended: boolean;
  status: "conflicts" | "needs_information" | "ready_for_review";
  verifiedTravelFeasibility: false;
};
export async function simulateDay(
  input: UntimedInput,
  context: PlaceContext,
  proposal: DayProposal,
  routes: RouteEvidenceStore,
  forecasts: ForecastEvidence[],
  buffers: { walking: number; transit: number },
  control?: { unknownFloors: Map<string, number>; typedBuffers: boolean },
): Promise<Simulation> {
  const rows: ScheduledRow[] = [],
    issues: PlanningIssue[] = [],
    changes: Simulation["changes"] = [];
  let cursor = jstAt(input.date, proposal.rows[0]!.start);
  const startsAt = jstStamp(cursor);
  let previousMoveBuffer = 0;
  for (const [rowIndex, row] of proposal.rows.entries()) {
    const proposedMinutes =
      (jstAt(input.date, row.end) - jstAt(input.date, row.start)) / 60;
    let allocatedMinutes = proposedMinutes,
      route: RouteEvidence | null = null,
      systemBufferMinutes = 0;
    let durationSource: ScheduledRow["durationSource"] =
      row.kind === "visit"
        ? "ai_visit_proposal"
        : row.kind === "wait"
          ? "ai_buffer"
          : "ai_unverified_transfer";
    let note =
      row.kind === "visit"
        ? "Durasi kunjungan diusulkan AI; jam di tabel dihitung kode."
        : row.kind === "wait"
          ? "Buffer dari proposal AI; alasan naratif AI tidak dianggap fakta operasional."
          : "Alokasi perpindahan AI belum terverifikasi.";
    if (
      row.kind === "wait" &&
      control?.typedBuffers &&
      row.waitPurpose === "transfer_buffer" &&
      previousMoveBuffer > 0
    ) {
      const credit = Math.min(allocatedMinutes, previousMoveBuffer);
      allocatedMinutes -= credit;
      changes.push({
        rowIndex,
        addedMinutes: -credit,
        reason:
          "Credit transfer buffer already owned by the preceding movement; do not count it twice.",
      });
      note = `Buffer AI dikurangi ${credit} menit karena sudah berada dalam alokasi perpindahan.`;
      if (allocatedMinutes === 0) {
        previousMoveBuffer = 0;
        continue;
      }
    }
    previousMoveBuffer = 0;
    if (
      control &&
      row.kind === "wait" &&
      ["opening", "event"].includes(String(row.waitPurpose))
    ) {
      const sources = context.facts.filter(
        (f) =>
          f.kind === "opening_hours" &&
          f.opensAt &&
          f.activityIds.some((id) =>
            input.activities.some(
              (a) => a.id === id && a.locationId === row.from,
            ),
          ),
      );
      if (
        sources.length &&
        sources.every((f) => cursor >= jstAt(input.date, f.opensAt!))
      ) {
        issues.push({
          code: "UNSUPPORTED_OPENING_WAIT",
          severity: "conflict",
          rowIndex,
          message:
            "Wait is labeled as awaiting opening/event start, but all supplied opening times at this location have already passed. Relabel a genuine queue/break or repair the reasoning.",
          evidenceIds: sources.map((f) => f.id),
          repairableByScheduling: true,
        });
      }
    }
    if (row.kind === "visit") {
      const hours = context.facts.filter(
        (f) =>
          f.kind === "opening_hours" &&
          f.activityIds.includes(row.activityId!) &&
          f.opensAt &&
          f.closesAt,
      );
      const opens = hours.length
        ? Math.max(...hours.map((f) => jstAt(input.date, f.opensAt!)))
        : null;
      const closes = hours.length
        ? Math.min(...hours.map((f) => jstAt(input.date, f.closesAt!)))
        : null;
      if (opens !== null && cursor < opens) {
        const wait = (opens - cursor) / 60;
        rows.push({
          rowIndex,
          proposed: row,
          startsAt: jstStamp(cursor),
          endsAt: jstStamp(opens),
          allocatedMinutes: wait,
          durationSource: "source_opening_wait",
          routeId: null,
          routeStatus: null,
          providerTravelMinutes: null,
          systemBufferMinutes: 0,
          note: `Menunggu sampai batas buka dari sumber ${hours.map((f) => f.id).join(", ")}; terpisah dari waktu kunjungan.`,
        });
        changes.push({
          rowIndex,
          addedMinutes: wait,
          reason: "Wait until supplied opening/event start time.",
        });
        cursor = opens;
      }
      if (closes !== null && cursor + allocatedMinutes * 60 > closes)
        issues.push({
          code: "VISIT_OUTSIDE_HOURS",
          severity: "conflict",
          rowIndex,
          message: `Visit ends ${jstStamp(cursor + allocatedMinutes * 60)}, beyond supplied close ${jstStamp(closes)}. Duration was not silently shortened.`,
          evidenceIds: hours.map((f) => f.id),
          repairableByScheduling: true,
        });
      for (const fact of context.facts.filter(
        (f) =>
          f.kind === "seasonal_event" &&
          f.activityIds.includes(row.activityId!) &&
          f.startDate &&
          f.endDate,
      ))
        if (input.date < fact.startDate! || input.date > fact.endDate!)
          issues.push({
            code: "EVENT_OUTSIDE_SEASON",
            severity: "conflict",
            rowIndex,
            message: `${fact.name} does not cover ${input.date}; changing clock times cannot resolve this date conflict.`,
            evidenceIds: [fact.id],
            repairableByScheduling: false,
          });
      if (!hours.length)
        issues.push({
          code: "OPENING_HOURS_UNCONFIRMED",
          severity: "unknown",
          rowIndex,
          message:
            "No applicable opening-hours constraint was supplied for this activity; availability was not inferred.",
          evidenceIds: [],
          repairableByScheduling: false,
        });
    }
    if (row.kind === "move") {
      route = await routes.query(
        row.from,
        row.to,
        row.mode as "WALK" | "TRANSIT",
        jstStamp(cursor),
      );
      if (route.status === "ok") {
        systemBufferMinutes =
          row.mode === "WALK" ? buffers.walking : buffers.transit;
        const required =
          Math.ceil(route.estimatedMinutes!) + systemBufferMinutes;
        allocatedMinutes = Math.max(proposedMinutes, required);
        durationSource = "provider_plus_system_buffer";
        note = `Estimasi provider ${route.estimatedMinutes!.toFixed(1)} menit + buffer sistem ${systemBufferMinutes} menit; buffer merupakan asumsi yang dapat dikonfigurasi.`;
        if (allocatedMinutes > proposedMinutes)
          changes.push({
            rowIndex,
            addedMinutes: allocatedMinutes - proposedMinutes,
            reason:
              "Provider travel estimate plus minimum system buffer exceeded AI allocation.",
          });
        if (route.partialAddressMatch)
          issues.push({
            code: "PARTIAL_PLACE_MATCH",
            severity: "unknown",
            rowIndex,
            message:
              "Provider matched an approximate location; exact target needs confirmation.",
            evidenceIds: [route.id],
            repairableByScheduling: false,
          });
      } else {
        if (control) {
          const key = `${row.mode}:${row.from}->${row.to}`;
          const floor = control.unknownFloors.get(key) ?? proposedMinutes;
          control.unknownFloors.set(key, Math.max(floor, proposedMinutes));
          if (proposedMinutes < floor) {
            allocatedMinutes = floor;
            changes.push({
              rowIndex,
              addedMinutes: floor - proposedMinutes,
              reason:
                "Unknown transfer allocation cannot be reduced without new provider evidence.",
            });
            issues.push({
              code: "UNSUPPORTED_TRAVEL_REDUCTION",
              severity: "conflict",
              rowIndex,
              message: `AI reduced unknown travel from ${floor} to ${proposedMinutes} minutes without a new provider estimate; original floor was retained.`,
              evidenceIds: [route.id],
              repairableByScheduling: true,
            });
          }
        }
        issues.push({
          code:
            route.status === "unresolved_location"
              ? "MISSING_LOCATION"
              : "ROUTE_UNVERIFIED",
          severity: "unknown",
          rowIndex,
          message:
            route.error ??
            "Travel estimate unavailable; the AI allocation remains an assumption.",
          evidenceIds: [route.id],
          repairableByScheduling: false,
        });
      }
      previousMoveBuffer = systemBufferMinutes;
    }
    const end = cursor + allocatedMinutes * 60;
    rows.push({
      rowIndex,
      proposed: row,
      startsAt: jstStamp(cursor),
      endsAt: jstStamp(end),
      allocatedMinutes,
      durationSource,
      routeId: route?.id ?? null,
      routeStatus: route?.status ?? null,
      providerTravelMinutes: route?.estimatedMinutes ?? null,
      systemBufferMinutes,
      note,
    });
    if (row.kind === "visit") {
      const area = context.locations[row.to]!.area;
      const weather = forecasts.find((f) => f.areaId === area);
      if (weather?.status === "available") {
        const hours = weather.hours.filter(
          (h) =>
            Date.parse(h.at) / 1000 < end &&
            Date.parse(h.at) / 1000 + 3600 > cursor,
        );
        const wet = hours.filter(
          (h) => h.rainProbability !== null && h.rainProbability >= 60,
        );
        if (wet.length)
          issues.push({
            code: "REGIONAL_RAIN_RISK",
            severity: "advisory",
            rowIndex,
            message:
              "One or more overlapping regional forecast hours have rain probability >=60%; exposure and preferences still need review. This does not predict rainfall duration.",
            evidenceIds: [weather.id],
            repairableByScheduling: false,
          });
      }
    }
    cursor = end;
  }
  const endsAt = jstStamp(cursor);
  if (endsAt.slice(0, 10) !== input.date)
    issues.push({
      code: "RETURN_AFTER_TRIP_DATE",
      severity: "conflict",
      rowIndex: null,
      message: `Propagated return ${endsAt} is outside the requested one-day trip; no destination was removed or clock clamped.`,
      evidenceIds: [],
      repairableByScheduling: true,
    });
  for (const f of forecasts)
    if (f.status !== "available")
      issues.push({
        code: "FORECAST_UNAVAILABLE",
        severity: "unknown",
        rowIndex: null,
        message: `${f.areaId}: ${f.error}`,
        evidenceIds: [f.id],
        repairableByScheduling: false,
      });
    else if (
      !f.sunrise ||
      !f.sunset ||
      f.hours.some((h) => h.rainProbability === null)
    )
      issues.push({
        code: "PARTIAL_FORECAST",
        severity: "unknown",
        rowIndex: null,
        message: `${f.areaId}: some solar/rain forecast fields are missing; available is not equivalent to complete.`,
        evidenceIds: [f.id],
        repairableByScheduling: false,
      });
  const conflict = issues.some((i) => i.severity === "conflict"),
    unknown = issues.some((i) => i.severity === "unknown");
  return {
    rows,
    issues,
    changes,
    startsAt,
    endsAt,
    repairRecommended:
      changes.length > 0 || issues.some((i) => i.repairableByScheduling),
    status: conflict
      ? "conflicts"
      : unknown
        ? "needs_information"
        : "ready_for_review",
    verifiedTravelFeasibility: false,
  };
}
