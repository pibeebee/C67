import { createAPI, workOnce } from './server.ts';
import { LiveProviders, SyntheticProviders } from './providers.ts';
import { MemoryStore, SupabaseStore } from './store.ts';

const mock = process.env.PLANNING_DATA_MODE === 'mock';
if (!mock && process.env.PLANNING_DATA_MODE !== 'live')
  throw new Error('Set PLANNING_DATA_MODE=mock or live explicitly.');
const store = mock
  ? new MemoryStore()
  : new SupabaseStore(
      process.env.SUPABASE_URL ?? '',
      process.env.SUPABASE_CLIENT_KEY ?? '',
      process.env.SUPABASE_SERVICE_ROLE_KEY ?? '',
    );
const providers = mock ? new SyntheticProviders() : new LiveProviders(process.env);
const server = createAPI(store, providers);
const port = Number(process.env.PORT ?? '8788');
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
server.listen(port, mock ? '127.0.0.1' : (process.env.HOST ?? '127.0.0.1'), () =>
  console.log(
    JSON.stringify({
      event: 'planning_started',
      port,
      mode: mock ? 'synthetic-memory-only' : 'live',
    }),
  ),
);
let running = false;
const timer = setInterval(async () => {
  if (running) return;
  running = true;
  try {
    await workOnce(store, providers);
  } catch {
    console.error(JSON.stringify({ event: 'planning_worker_error' }));
  } finally {
    running = false;
  }
}, 1000);
function stop() {
  clearInterval(timer);
  server.close();
}
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
