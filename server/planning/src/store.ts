import {
  Failure,
  iso,
  requireUUID,
  seconds,
  uuid,
  validateRequest,
  type Event,
  type Input,
  type Job,
  type PersonalTrip,
  type Request,
  type Result,
} from './domain.ts';

export interface Store {
  request(token: string, input: Request): Promise<Job>;
  job(token: string, id: string): Promise<Job>;
  apply(
    token: string,
    id: string,
    requestID: string,
    expectedRevision: number | null,
  ): Promise<PersonalTrip>;
  event(token: string, id: string, event: Event): Promise<PersonalTrip>;
  trips(token: string): Promise<PersonalTrip[]>;
  claim(): Promise<Job | null>;
  finish(job: Job, result: Result | null, error: string | null): Promise<void>;
  renew(job: Job): Promise<void>;
}

export function canonical(value: any): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object')
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
      .join(',')}}`;
  return JSON.stringify(value);
}

function inputIdentity(value: Input): string {
  return canonical({
    ...value,
    starts_at: Date.parse(value.starts_at),
    finish_by: Date.parse(value.finish_by),
    first_place_id: value.first_place_id?.toLowerCase() ?? null,
    places: value.places.map((place) => ({
      ...place,
      id: place.id.toLowerCase(),
      website: place.website ?? null,
      preferred_after: place.preferred_after ? Date.parse(place.preferred_after) : null,
      preferred_before: place.preferred_before ? Date.parse(place.preferred_before) : null,
    })),
  });
}

export class MemoryStore implements Store {
  private jobs = new Map<string, Job>();
  private plans = new Map<string, PersonalTrip>();
  private owners = new Map<string, string>();
  private receipts = new Map<string, { input: string; value: unknown }>();
  private appliedJobs = new Map<string, PersonalTrip>();
  private now: () => number;
  constructor(now = () => Date.now()) {
    this.now = now;
  }
  private actor(token: string) {
    requireUUID(token);
    return token;
  }
  private copy<T>(value: T): T {
    return structuredClone(value);
  }
  private publicJob(job: Job): Job {
    const value = this.copy(job);
    delete value.owner_id;
    delete value.lease_token;
    return value;
  }
  private owner(actor: string, id: string) {
    if (this.owners.get(id) !== actor) throw new Failure('NOT_FOUND', 404);
  }
  private receipt<T>(actor: string, request: string, input: unknown, action: () => T): T {
    requireUUID(request);
    const key = `${actor}:${request}`;
    const fingerprint = canonical(input);
    const previous = this.receipts.get(key);
    if (previous) {
      if (previous.input !== fingerprint) throw new Failure('REQUEST_CONFLICT', 409);
      return this.copy(previous.value) as T;
    }
    const value = action();
    this.receipts.set(key, { input: fingerprint, value: this.copy(value) });
    return this.copy(value);
  }
  async request(token: string, request: Request) {
    const actor = this.actor(token);
    validateRequest(request);
    return this.receipt(actor, request.request_id, { operation: 'request', ...request }, () => {
      let input = this.copy(request.input);
      if (request.purpose === 'replan') {
        this.owner(actor, request.trip_id!);
        const trip = this.plans.get(request.trip_id!)!;
        if (trip.revision !== request.base_revision || trip.status === 'completed')
          throw new Failure('REVISION_CONFLICT', 409);
        if (inputIdentity(input) !== inputIdentity(trip.input))
          throw new Failure('INPUT_CONFLICT', 409);
        input = this.remaining(trip, request.current_origin);
      }
      const job: Job = {
        id: uuid(),
        status: 'queued',
        purpose: request.purpose,
        input,
        trip_id: request.trip_id ?? null,
        base_revision: request.base_revision ?? null,
        result: null,
        error_code: null,
        created_at: iso(this.now()),
        owner_id: actor,
      };
      this.jobs.set(job.id, job);
      this.owners.set(job.id, actor);
      return this.publicJob(job);
    });
  }
  private remaining(trip: PersonalTrip, currentOrigin?: Input['origin'] | null): Input {
    if (trip.status !== 'active') return this.copy(trip.input);
    const remaining = trip.plan.stops.filter((stop) => !trip.completed_stop_ids.includes(stop.id));
    if (!remaining.length || this.now() >= Date.parse(trip.input.finish_by))
      throw new Failure('NO_REMAINING_TIME', 409);
    const first = remaining[0];
    const input = this.copy(trip.input);
    const atCurrentStop = trip.current_stop_id === first.id;
    const lastVisited = [...trip.plan.stops]
      .reverse()
      .find((stop) => trip.completed_stop_ids.includes(stop.id));
    input.starts_at = iso(this.now());
    input.origin = atCurrentStop
      ? first.location
      : (currentOrigin ?? lastVisited?.location ?? input.origin);
    input.first_place_id = atCurrentStop ? first.id : null;
    input.places = remaining.map((stop) => ({
      ...input.places.find((place) => place.id === stop.id)!,
      visit_seconds:
        atCurrentStop && stop.id === first.id
          ? Math.max(0, Math.ceil((Date.parse(first.departure_at) - this.now()) / 1000))
          : stop.visit_seconds,
    }));
    return input;
  }
  async job(token: string, id: string) {
    const actor = this.actor(token);
    this.owner(actor, id);
    return this.publicJob(this.jobs.get(id)!);
  }
  async apply(token: string, id: string, requestID: string, expectedRevision: number | null) {
    const actor = this.actor(token);
    this.owner(actor, id);
    return this.receipt(actor, requestID, { operation: 'apply', id, expectedRevision }, () => {
      const job = this.jobs.get(id)!;
      const proposal = job.result?.proposal;
      if (expectedRevision !== job.base_revision) throw new Failure('REVISION_CONFLICT', 409);
      const prior = this.appliedJobs.get(id);
      if (prior) return this.copy(prior);
      if (job.status !== 'succeeded' || !proposal?.feasible || job.purpose === 'suggest')
        throw new Failure('PROPOSAL_NOT_APPLICABLE', 409);
      if (this.now() - Date.parse(job.created_at) > 900000)
        throw new Failure('PROPOSAL_EXPIRED', 409);
      let trip: PersonalTrip;
      if (job.trip_id) {
        this.owner(actor, job.trip_id);
        trip = this.plans.get(job.trip_id)!;
        if (
          trip.revision !== expectedRevision ||
          trip.revision !== job.base_revision ||
          trip.status === 'completed'
        )
          throw new Failure('REVISION_CONFLICT', 409);
        const visited = trip.plan.stops.filter((stop) => trip.completed_stop_ids.includes(stop.id));
        trip.plan = { ...this.copy(proposal), stops: [...visited, ...proposal.stops] };
        trip.revision += 1;
      } else {
        if (expectedRevision !== null) throw new Failure('REVISION_CONFLICT', 409);
        // Applying one proposal twice under different request IDs still creates only one trip.
        trip = {
          id: uuid(),
          title: job.input.title,
          revision: 1,
          status: 'planned',
          input: this.copy(job.input),
          plan: this.copy(proposal),
          completed_stop_ids: [],
          current_stop_id: null,
          current_arrived_at: null,
          synthetic: true,
          created_at: iso(this.now()),
        };
        this.plans.set(trip.id, trip);
        this.owners.set(trip.id, actor);
      }
      this.appliedJobs.set(id, this.copy(trip));
      return trip;
    });
  }
  async event(token: string, id: string, event: Event) {
    const actor = this.actor(token);
    this.owner(actor, id);
    return this.receipt(actor, event.request_id, { operation: 'event', id, event }, () => {
      const trip = this.plans.get(id)!;
      if (trip.revision !== event.expected_revision || trip.status === 'completed')
        throw new Failure('REVISION_CONFLICT', 409);
      const next = trip.plan.stops.find((stop) => !trip.completed_stop_ids.includes(stop.id));
      if (event.kind === 'start' && trip.status === 'planned') trip.status = 'active';
      else if (
        event.kind === 'arrive' &&
        trip.status === 'active' &&
        !trip.current_stop_id &&
        next &&
        next.id === event.stop_id
      ) {
        trip.current_stop_id = next.id;
        trip.current_arrived_at = iso(this.now());
        next.departure_at = iso(this.now() + next.visit_seconds * 1000);
      } else if (
        event.kind === 'complete_stop' &&
        trip.status === 'active' &&
        next &&
        next.id === event.stop_id &&
        trip.current_stop_id === next.id
      ) {
        trip.completed_stop_ids.push(next.id);
        trip.current_stop_id = null;
        trip.current_arrived_at = null;
        if (trip.completed_stop_ids.length === trip.plan.stops.length) trip.status = 'completed';
      } else if (
        event.kind === 'extend_stay' &&
        trip.status === 'active' &&
        next &&
        next.id === event.stop_id &&
        trip.current_stop_id === next.id &&
        Number.isInteger(event.extra_seconds) &&
        Number(event.extra_seconds) > 0 &&
        Number(event.extra_seconds) <= 7200
      ) {
        next.departure_at = iso(
          Math.max(this.now(), Date.parse(next.departure_at)) + Number(event.extra_seconds) * 1000,
        );
      } else throw new Failure('INVALID_EVENT', 400);
      trip.revision += 1;
      return trip;
    });
  }
  async trips(token: string) {
    const actor = this.actor(token);
    return this.copy(
      [...this.plans.values()]
        .filter((trip) => this.owners.get(trip.id) === actor)
        .sort((a, b) => b.created_at.localeCompare(a.created_at)),
    );
  }
  async claim() {
    const job = [...this.jobs.values()].find((value) => value.status === 'queued');
    if (!job) return null;
    job.status = 'running';
    job.lease_token = uuid();
    return this.copy(job);
  }
  async renew(_job: Job) {}
  async finish(job: Job, result: Result | null, error: string | null) {
    const stored = this.jobs.get(job.id);
    if (!stored || stored.lease_token !== job.lease_token) throw new Failure('LEASE_CONFLICT', 409);
    stored.result = this.copy(result);
    stored.error_code = error;
    stored.status = error ? 'failed' : 'succeeded';
  }
}

export class SupabaseStore implements Store {
  url: string;
  key: string;
  serviceKey: string;
  constructor(url: string, key: string, serviceKey: string) {
    const parsed = new URL(url);
    if (
      (parsed.protocol !== 'https:' &&
        !(
          parsed.protocol === 'http:' &&
          ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname)
        )) ||
      parsed.username ||
      parsed.password ||
      parsed.search ||
      parsed.hash ||
      (parsed.pathname !== '/' && parsed.pathname !== '')
    )
      throw new Failure('INVALID_CONFIGURATION', 503);
    if (!key || !serviceKey) throw new Failure('INVALID_CONFIGURATION', 503);
    this.url = parsed.origin;
    this.key = key;
    this.serviceKey = serviceKey;
  }
  private async rpc(name: string, token: string, body: unknown, worker = false): Promise<any> {
    const response = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(20000),
      headers: {
        apikey: worker ? this.serviceKey : this.key,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!response.ok)
      throw new Failure(
        response.status === 409
          ? 'REVISION_CONFLICT'
          : response.status === 404
            ? 'NOT_FOUND'
            : response.status === 401
              ? 'AUTHENTICATION_REQUIRED'
              : response.status === 429
                ? 'RATE_LIMITED'
                : 'PLANNING_UNAVAILABLE',
        response.status >= 500 ? 503 : response.status,
      );
    return response.json();
  }
  request(token: string, input: Request) {
    return this.rpc('request_planning_job', token, { p_request: input });
  }
  job(token: string, id: string) {
    return this.rpc('get_planning_job', token, { p_job_id: id });
  }
  apply(token: string, id: string, requestID: string, expectedRevision: number | null) {
    return this.rpc('apply_planning_proposal', token, {
      p_job_id: id,
      p_request_id: requestID,
      p_expected_revision: expectedRevision,
    });
  }
  event(token: string, id: string, event: Event) {
    return this.rpc('record_planning_event', token, { p_trip_id: id, p_event: event });
  }
  trips(token: string) {
    return this.rpc('list_personal_planning_trips', token, {});
  }
  claim() {
    return this.rpc('claim_planning_job', this.serviceKey, {}, true);
  }
  finish(job: Job, result: Result | null, error: string | null) {
    return this.rpc(
      'finish_planning_job',
      this.serviceKey,
      { p_job_id: job.id, p_lease_token: job.lease_token, p_result: result, p_error_code: error },
      true,
    );
  }
  renew(job: Job) {
    return this.rpc(
      'renew_planning_job',
      this.serviceKey,
      { p_job_id: job.id, p_lease_token: job.lease_token },
      true,
    );
  }
}
