# Pocket reasonable ordering and legacy visit research

New native itineraries call authenticated `POST /v1/order` and poll
`GET /v1/order/jobs/{requestID}`. The server requests **untimed** activity ordering
from Luna: every selected place stays in the answer, with no catalog, geographic
gate, six-place cap, hours research or ETA prerequisite. Optional WeatherKit
forecasts and Astral 3.2 light windows are supplied as context. Unknown estimates
stay null. Exact IDs, manual order, estimates and context references are validated.
No model-generated numeric weather/light facts are displayed as source data.

An experimental `POCKET_AUTH_MODE=authenticated` validates each bearer token using
the configured HTTPS Supabase Auth `/auth/v1/user` endpoint and binds ordering and
visit jobs to its verified user ID. Configure `SUPABASE_URL` and the publishable
`SUPABASE_CLIENT_KEY`; never use a service-role key. The previous `legacy` mode
remains the local default and legacy jobs remain scoped to it. The iOS `pocket-auth`
mode is implemented locally with Sign in with Apple, token refresh and account-specific
storage. Production configuration, server deployment and end-to-end physical-device
verification are still required. Do not deploy solely from these local changes.

Ordering uses one provider attempt. Polls and identical submissions read the same
persisted job. Failed/interrupted jobs never restart automatically; the traveller
must explicitly retry with a new request ID. Original commands, results and private
context/answer snapshots stay in the protected data directory. Do not publish
these private records or log authorization headers.

The current supported ordering transport is native `responses` with completed
Luna/max metadata. The older alias chat transport remains for legacy operations.
Provider metadata establishes the reported identity, not upstream implementation.
WeatherKit REST is preferred when `APPLE_TEAM_ID`, `APPLE_WEATHER_SERVICE_ID`,
`APPLE_WEATHER_KEY_ID`, and `APPLE_WEATHER_PRIVATE_KEY` are configured. Keep the
key server-side; encode line breaks in the environment value as `\n`. If WeatherKit
or its attribution is unavailable, ordering falls back to Open-Meteo. Weather
failures do not block an order. Solar calculations do not prove
viewpoint access, visibility or arrival feasibility. See [integration](../../docs/guides/pocket-engine-integration.md).

## Legacy timed planning

The maintained service researches the traveller's selected place IDs, names, pins, available addresses and websites at request time. It does not serve or initialize a venue catalog. It is separate from Supabase and the earlier Node planner. Legacy timed trips keep Apple ETA and schedule validation; all Pocket personal trips remain on device.

`POST /v1/visits/resolve` accepts an authenticated asynchronous research job. Poll `GET /v1/visits/jobs/{jobID}`. Identical request IDs resume their job; changed selections must use a new ID. Jobs and full source snapshots are stored in the private data directory. A completed research job may contain unresolved places; completed research does not establish every visit's feasibility.

Luna transport uses streamed content and requires the provider’s actual completed response and expected model alias. Transient transport failures retry the same model once; interrupted output is rejected.

The server asks Luna for focused search queries, searches through DDGS, retrieves actual pages, follows branch visitor/contact links and uses Playwright for rendered content where necessary. Search snippets are not operating-hour evidence. Luna extracts atomic claims with source IDs and exact supporting quotations. A separate Luna review may reject claims. Unknown or conflicting hours/access remain unresolved. A further search attempt targets missing evidence. Luna suggests visit duration and soft visit timing separately from operator-imposed rules. `POST /v1/advice/visits` selects an immutable, locally validated schedule and supplies its reasoning. The app revalidates the selected option. No substitute model or invented hours are used after a failure.

## Local setup

Create a Python 3.12 virtual environment, install `requirements.txt`, and run `python -m playwright install chromium`. Copy `.env.example` into ignored `.env`, supply a random read token of at least 24 characters and the provider key (or its private env-file pointer). Never put the provider key in the app. Then run from the repo root:

```sh
python server/pocket/src/server.py --env-file server/pocket/.env --data-dir .local/visit-resolution
```

Default bind is `127.0.0.1:8792`. The current default transport is `POCKET_LLM_PROTOCOL=responses`; it requires a completed native response with reported Luna model and reasoning effort `max`. `chat-completions` retains the earlier tested alias transport. The current ordering acceptance is recorded separately from historical research/advice acceptance. `POCKET_HOST`, `POCKET_PORT`, and optional `C67_BROWSER` override the bind and local Chromium executable. Set the app's Pocket settings URL and read token. Release connections require trusted HTTPS. No provider key is sent to the iPhone.

The Docker recipe packages this maintained resolver and the existing provider credential helper, with no catalog resources. `docker compose -f server/pocket/compose.yml up -d --build` is a deployment action, separate from local source/test work. Put a trusted HTTPS proxy in front, permit health plus the ordering/job and legacy research/advice routes, permit JSON bodies up to 200 KB, and allow over 310 seconds for synchronous schedule advice. Ordering/research jobs poll independently of generation/crawl duration. Do not log Authorization or request bodies. The crawler checks robots policies and rejects private network URLs/redirects; sites may still block access. No free crawler guarantees access to every source.

## Verification

```sh
python -m unittest discover -s server/pocket/tests -v
```

These tests use synthetic sources and model responses to check exact-quote rejection, independent review, unknown branch identity, reservation conditions, model/truncation rejection, source extraction, private-address rejection, job retries and authenticated HTTP without a catalog route. Ordering tests also cover complete selection preservation, unknown duration, optional weather failure, invalid sources, manual-order constraints and no regeneration on duplicate/terminal requests. Actual web/Luna and native UI acceptance are recorded in [the runtime task](../../docs/tasks/pocket-runtime-visit-resolution.md). Container, shared-server and TestFlight acceptance are separate.

### Account deletion

In authenticated mode, `POST /v1/account/deletion` verifies the traveller through Supabase Auth. Apple accounts confirm with a fresh native authorization code. The server exchanges it with Apple, checks the Apple subject against the account's linked identity, and revokes the Apple token before accepting the request. Codes and tokens are not saved by the endpoint. The client saves its private random receipt before submitting so a lost response or restart can check the same request.

To enable the endpoint in an environment:

1. Apply the account-deletion cleanup migration to that environment and deploy the matching Pocket service and ingress.
2. Set the server-only `SUPABASE_SERVICE_ROLE_KEY` and Sign in with Apple variables in the [example environment](.env.example). The Apple client ID for the native code exchange is the app's bundle identifier. The Sign in with Apple signing key is separate from the WeatherKit configuration.
3. Exercise the full flow against an isolated test account before enabling it for testers.

The worker removes owner-scoped Pocket jobs and snapshots, then clears associated Storage objects and deletes the Supabase Auth user. Foreign keys remove related database records. Interrupted work is retried. Earlier visit-research snapshots are included when their job records reference them. Older flat files from interrupted research with no persisted reference have no trustworthy ownership link and require separate retention cleanup. The app removes account data from the device that confirms completion.
