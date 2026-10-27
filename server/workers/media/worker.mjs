import { validateImage } from './image.mjs';
import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
export class Worker {
  constructor(url, key) {
    this.url = new URL(url);
    if (!(this.url.protocol === 'https:' || ['localhost', '127.0.0.1'].includes(this.url.hostname))) throw new Error('HTTPS required');
    this.key = key;
  }
  async request(path, method = 'GET', body, type = 'application/json', allow404 = false) {
    const r = await fetch(new URL(path, this.url), { method, redirect: 'error', signal: AbortSignal.timeout(30000), headers: { apikey: this.key, Authorization: `Bearer ${this.key}`, 'Content-Type': type }, body: body === undefined ? undefined : type === 'application/json' ? JSON.stringify(body) : body });
    if (allow404 && r.status === 404) return null;
    if (!r.ok) throw new Error(`Worker HTTP ${r.status}`);
    return r;
  }
  async rpc(name, body = {}) { const r = await this.request(`/rest/v1/rpc/${name}`, 'POST', body); const t = await r.text(); return t ? JSON.parse(t) : null; }
  async remove(bucket, path) { await this.request(`/storage/v1/object/${bucket}`, 'DELETE', { prefixes: [path] }); }
  async once(uploadId = null) {
    const job = await this.rpc('claim_journal_job', { p_upload_id: uploadId });
    if (!job) return false;
    const raw = await this.request(`/storage/v1/object/authenticated/c67-journal-raw/${job.raw_path}`);
    // Bounded streaming prevents an unexpectedly large object from exhausting worker memory.
    const chunks = []; let size = 0;
    for await (const chunk of raw.body) { size += chunk.length; if (size > 5242880) { await this.rpc('finish_journal_job', { p_upload_id: job.upload_id, p_lease_id: job.lease_id, p_result: { failure_code: 'too_large' } }); return true; } chunks.push(chunk); }
    const result = await validateImage(Buffer.concat(chunks), job.content_type);
    if (!result.failure_code) {
      // Create-only write. A crash may have left this deterministic processed object behind.
      try { await this.request(`/storage/v1/object/c67-journal-ready/${job.ready_path}`, 'POST', result.bytes, 'image/jpeg'); }
      catch {
        const existing = await this.request(`/storage/v1/object/authenticated/c67-journal-ready/${job.ready_path}`);
        const prior = Buffer.from(await existing.arrayBuffer());
        if (!prior.equals(result.bytes)) throw new Error('Processed object mismatch');
      }
    }
    const { bytes, ...metadata } = result;
    await this.rpc('finish_journal_job', { p_upload_id: job.upload_id, p_lease_id: job.lease_id, p_result: metadata });
    await this.remove('c67-journal-raw', job.raw_path);
    return true;
  }
  async cleanup(allowedIds = null) {
    const allowed = job => allowedIds === null || allowedIds.includes(job.upload_id);
    for (const job of (await this.rpc('journal_raw_cleanup_candidates')).filter(allowed)) await this.remove('c67-journal-raw', job.raw_path);
    for (const job of (await this.rpc('journal_cleanup_candidates')).filter(allowed)) {
      await this.remove('c67-journal-raw', job.raw_path);
      await this.remove('c67-journal-ready', job.ready_path);
      await this.rpc('purge_journal_job', { p_upload_id: job.upload_id });
    }
  }
}
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const w = new Worker(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  if (process.argv.includes('--once')) { await w.once(); await w.cleanup(); }
  else for (;;) {
    try { await w.once(); await w.cleanup(); await writeFile('/tmp/c67-media-heartbeat', String(Date.now())); } catch { console.error('Media worker cycle failed; lease retained for retry'); }
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
}
