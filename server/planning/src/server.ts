import { createServer, type IncomingMessage } from 'node:http';
import { Failure, requireUUID, validateRequest } from './domain.ts';
import { plan } from './engine.ts';
import { type Providers } from './providers.ts';
import { type Store } from './store.ts';

async function body(request: IncomingMessage) {
  let bytes = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > 65536) throw new Failure('INPUT_TOO_LARGE', 413);
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch {
    throw new Failure('INVALID_JSON');
  }
}

export function createAPI(store: Store, providers: Providers) {
  return createServer(async (request, response) => {
    const send = (status: number, data: unknown) => {
      response.writeHead(status, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
      });
      response.end(JSON.stringify(data));
    };
    try {
      if (request.method === 'GET' && request.url === '/health') {
        send(200, { status: 'ok', synthetic: providers.synthetic });
        return;
      }
      const authorization = request.headers.authorization;
      if (!authorization?.startsWith('Bearer ') || authorization.length > 16384)
        throw new Failure('AUTHENTICATION_REQUIRED', 401);
      const token = authorization.slice(7);
      const path = new URL(request.url!, 'http://localhost').pathname;
      if (request.method === 'POST' && path === '/v1/planning/jobs') {
        const input = await body(request);
        validateRequest(input);
        send(202, await store.request(token, input));
      } else if (request.method === 'GET' && /^\/v1\/planning\/jobs\/[^/]+$/.test(path)) {
        const id = path.split('/').at(-1)!;
        requireUUID(id);
        send(200, await store.job(token, id));
      } else if (request.method === 'GET' && path === '/v1/planning/trips') {
        send(200, await store.trips(token));
      } else if (
        request.method === 'POST' &&
        /^\/v1\/planning\/proposals\/[^/]+\/apply$/.test(path)
      ) {
        const id = path.split('/').at(-2)!;
        requireUUID(id);
        const input = await body(request);
        requireUUID(input.request_id);
        if (
          input.expected_revision !== null &&
          (!Number.isSafeInteger(input.expected_revision) || input.expected_revision < 1)
        )
          throw new Failure('INVALID_REVISION');
        send(200, await store.apply(token, id, input.request_id, input.expected_revision));
      } else if (request.method === 'POST' && /^\/v1\/planning\/trips\/[^/]+\/events$/.test(path)) {
        const id = path.split('/').at(-2)!;
        requireUUID(id);
        const input = await body(request);
        requireUUID(input.request_id);
        if (
          !Number.isSafeInteger(input.expected_revision) ||
          input.expected_revision < 1 ||
          !['start', 'arrive', 'complete_stop', 'extend_stay'].includes(input.kind)
        )
          throw new Failure('INVALID_EVENT');
        send(200, await store.event(token, id, input));
      } else throw new Failure('NOT_FOUND', 404);
    } catch (error) {
      const failure = error instanceof Failure ? error : new Failure('PLANNING_UNAVAILABLE', 503);
      send(failure.status, {
        error: { code: failure.code, retryable: failure.status >= 500 || failure.status === 429 },
      });
    }
  });
}

export async function workOnce(store: Store, providers: Providers) {
  const job = await store.claim();
  if (!job) return false;
  let leaseFailed = false;
  const controller = new AbortController();
  const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(540000)]);
  const timer = setInterval(() => {
    store.renew(job).catch(() => {
      leaseFailed = true;
      controller.abort();
    });
  }, 30000);
  timer.unref();
  try {
    const result = await plan(job.input, providers, job.purpose, signal);
    signal.throwIfAborted();
    if (leaseFailed) throw new Failure('LEASE_CONFLICT', 409);
    await store.finish(job, result, null);
  } catch (error) {
    await store.finish(
      job,
      null,
      leaseFailed
        ? 'LEASE_CONFLICT'
        : signal.aborted
          ? 'JOB_EXPIRED'
          : error instanceof Failure
            ? error.code
            : 'PROVIDER_UNAVAILABLE',
    );
  } finally {
    clearInterval(timer);
  }
  return true;
}
