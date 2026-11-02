import { randomUUID } from 'node:crypto';

export type Point = { latitude: number; longitude: number };
export type Place = {
  id: string;
  name: string;
  location: Point;
  visit_seconds: number;
  website?: string | null;
  preferred_after?: string | null;
  preferred_before?: string | null;
};
export type Input = {
  title: string;
  origin: Point;
  places: Place[];
  preferences: string;
  starts_at: string;
  finish_by: string;
  time_zone: string;
  mode: 'walking' | 'automobile';
  first_place_id?: string | null;
};
export type Evidence = {
  id: string;
  label: string;
  url: string | null;
  attribution_logo_url?: string | null;
  checked_at: string;
  kind: 'route' | 'weather' | 'place';
  summary: string;
  synthetic: boolean;
};
export type Leg = {
  from_id: string;
  to_id: string;
  duration_seconds: number;
  distance_meters: number | null;
  departure_at: string;
  evidence_id: string;
};
export type Stop = {
  id: string;
  name: string;
  location: Point;
  arrival_at: string;
  departure_at: string;
  visit_seconds: number;
  travel_seconds: number;
  warnings: string[];
};
export type Proposal = {
  id: string;
  input: Input;
  stops: Stop[];
  finishes_at: string;
  feasible: boolean;
  explanation: string;
  warnings: string[];
  evidence: Evidence[];
  synthetic: boolean;
};
export type Result = {
  proposal: Proposal | null;
  candidates: Place[];
  warnings: string[];
  synthetic: boolean;
};
export type Request = {
  request_id: string;
  purpose: 'plan' | 'suggest' | 'replan';
  input: Input;
  trip_id?: string | null;
  base_revision?: number | null;
  current_origin?: Point | null;
};
export type Job = {
  id: string;
  status: 'queued' | 'running' | 'succeeded' | 'failed';
  purpose: Request['purpose'];
  input: Input;
  trip_id: string | null;
  base_revision: number | null;
  result: Result | null;
  error_code: string | null;
  created_at: string;
  lease_token?: string;
  owner_id?: string;
};
export type PersonalTrip = {
  id: string;
  title: string;
  revision: number;
  status: 'planned' | 'active' | 'completed';
  input: Input;
  plan: Proposal;
  completed_stop_ids: string[];
  current_stop_id: string | null;
  current_arrived_at: string | null;
  synthetic: boolean;
  created_at: string;
};
export type Event = {
  request_id: string;
  expected_revision: number;
  kind: 'start' | 'arrive' | 'complete_stop' | 'extend_stay';
  stop_id?: string | null;
  extra_seconds?: number | null;
};
export class Failure extends Error {
  code: string;
  status: number;
  constructor(code: string, status = 400) {
    super(code);
    this.code = code;
    this.status = status;
  }
}
export const uuid = () => randomUUID();
export const iso = (value: number) => new Date(value).toISOString();
export const seconds = (value: string) => Date.parse(value) / 1000;
export function requireUUID(value: unknown): asserts value is string {
  if (
    typeof value !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  )
    throw new Failure('INVALID_ID');
}
export function validatePoint(value: Point) {
  if (
    !value ||
    !Number.isFinite(value.latitude) ||
    !Number.isFinite(value.longitude) ||
    Math.abs(value.latitude) > 90 ||
    Math.abs(value.longitude) > 180
  )
    throw new Failure('INVALID_LOCATION');
}
export function validateInput(input: Input) {
  if (
    !input ||
    typeof input.title !== 'string' ||
    !input.title.trim() ||
    input.title.length > 120 ||
    typeof input.preferences !== 'string' ||
    input.preferences.length > 2000
  )
    throw new Failure('INVALID_INPUT');
  validatePoint(input.origin);
  if (!Array.isArray(input.places) || input.places.length < 1 || input.places.length > 6)
    throw new Failure('PLACE_LIMIT');
  const ids = new Set<string>();
  for (const place of input.places) {
    if (!place || typeof place !== 'object') throw new Failure('INVALID_PLACE');
    requireUUID(place.id);
    validatePoint(place.location);
    if (
      ids.has(place.id.toLowerCase()) ||
      typeof place.name !== 'string' ||
      !place.name.trim() ||
      place.name.length > 200 ||
      !Number.isInteger(place.visit_seconds) ||
      place.visit_seconds < 0 ||
      place.visit_seconds > 86400
    )
      throw new Failure('INVALID_PLACE');
    if (place.website != null && (typeof place.website !== 'string' || place.website.length > 2048))
      throw new Failure('INVALID_PLACE');
    for (const time of [place.preferred_after, place.preferred_before])
      if (time != null && !validInstant(time)) throw new Failure('INVALID_WINDOW');
    if (
      place.preferred_after &&
      place.preferred_before &&
      seconds(place.preferred_after) > seconds(place.preferred_before)
    )
      throw new Failure('INVALID_WINDOW');
    ids.add(place.id.toLowerCase());
  }
  if (input.first_place_id != null) {
    requireUUID(input.first_place_id);
    if (!ids.has(input.first_place_id.toLowerCase())) throw new Failure('INVALID_PLACE');
  }
  if (
    !['walking', 'automobile'].includes(input.mode) ||
    !validInstant(input.starts_at) ||
    !validInstant(input.finish_by)
  )
    throw new Failure('INVALID_TIME');
  const duration = seconds(input.finish_by) - seconds(input.starts_at);
  if (!(duration > 0 && duration <= 86400)) throw new Failure('INVALID_TIME');
  if (typeof input.time_zone !== 'string' || !input.time_zone || input.time_zone.length > 100)
    throw new Failure('INVALID_TIME_ZONE');
  try {
    new Intl.DateTimeFormat('en', { timeZone: input.time_zone }).format();
  } catch {
    throw new Failure('INVALID_TIME_ZONE');
  }
}
export function validInstant(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    /T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value))
  );
}
export function validateRequest(request: Request) {
  requireUUID(request?.request_id);
  validateInput(request.input);
  if (!['plan', 'suggest', 'replan'].includes(request.purpose))
    throw new Failure('INVALID_PURPOSE');
  if (request.purpose === 'replan') {
    requireUUID(request.trip_id);
    if (!Number.isSafeInteger(request.base_revision) || Number(request.base_revision) < 1)
      throw new Failure('INVALID_REVISION');
    if (request.current_origin) validatePoint(request.current_origin);
  } else if (request.trip_id || request.base_revision || request.current_origin)
    throw new Failure('INVALID_INPUT');
}

export function assertProposal(proposal: Proposal, input: Input) {
  const selected = input.places.map((place) => place.id).sort();
  if (
    !proposal ||
    JSON.stringify(proposal.stops.map((stop) => stop.id).sort()) !== JSON.stringify(selected)
  )
    throw new Failure('INVALID_MODEL_OUTPUT', 502);
  let prior = seconds(input.starts_at);
  for (const stop of proposal.stops) {
    const place = input.places.find((p) => p.id === stop.id)!;
    if (
      !Number.isInteger(stop.travel_seconds) ||
      stop.travel_seconds < 0 ||
      stop.visit_seconds !== place.visit_seconds ||
      seconds(stop.arrival_at) !== prior + stop.travel_seconds ||
      seconds(stop.departure_at) !== seconds(stop.arrival_at) + stop.visit_seconds
    )
      throw new Failure('INVALID_SCHEDULE', 502);
    prior = seconds(stop.departure_at);
  }
  if (
    seconds(proposal.finishes_at) !== prior ||
    proposal.feasible !== prior <= seconds(input.finish_by)
  )
    throw new Failure('INVALID_SCHEDULE', 502);
}
