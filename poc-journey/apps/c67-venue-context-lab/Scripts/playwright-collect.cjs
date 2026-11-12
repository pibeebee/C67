const { chromium } = require('playwright');
const fs = require('node:fs');

const host = (url) => url.hostname.toLowerCase().replace(/^www\./, '');
const normalize = (text) => text.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const assetHosts = new Set(['cdn.jsdelivr.net', 'cdnjs.cloudflare.com', 'code.jquery.com', 'unpkg.com']);
function isAllowed(url, allowed) {
  return url.protocol === 'https:' && !url.username && !url.password && !url.port && allowed.has(host(url));
}
function canonical(value, base) {
  try {
    const url = new URL(value, base);
    url.hash = '';
    return url;
  } catch { return null; }
}

// Executed in the page. Text always comes from the source; identity hints only select blocks.
function extractDocument(hints) {
  const norm = (text) => text.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const names = hints.names.map(norm).filter((x) => x.length >= 5);
  const matches = (text) => names.some((name) => norm(text).includes(name));
  const blocks = [];
  const add = (kind, text, title) => {
    text = (text || '').trim();
    if (text && !blocks.some((b) => b.text === text)) blocks.push({ kind, text: text.slice(0, 16000), ...(title ? { title } : {}) });
  };
  for (const element of document.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      const root = JSON.parse(element.textContent);
      const visit = (value, depth = 0) => {
        if (!value || typeof value !== 'object' || depth > 8) return;
        if (Array.isArray(value)) return value.slice(0, 100).forEach((x) => visit(x, depth + 1));
        const text = JSON.stringify(value);
        if (value.name && (value.address || value.geo || value.openingHours || value.openingHoursSpecification) && matches(text)) {
          add('jsonld', text);
        }
        if (value['@graph']) visit(value['@graph'], depth + 1);
        for (const key of ['department', 'location', 'subOrganization']) if (value[key]) visit(value[key], depth + 1);
      };
      visit(root);
    } catch { /* Invalid source metadata is not evidence. */ }
  }
  const next = document.getElementById('__NEXT_DATA__');
  if (next && location.hostname === 'smartcity.jakarta.go.id') {
    try {
      const article = JSON.parse(next.textContent).props.pageProps.detailArticle;
      if (article?.description) {
        const parsed = new DOMParser().parseFromString(article.description, 'text/html');
        parsed.querySelectorAll('script,style,noscript').forEach((tag) => tag.remove());
        const lines = [...parsed.body.querySelectorAll('h1,h2,h3,h4,p,li,tr')].map((tag) => tag.textContent.trim()).filter(Boolean);
        const title = article.title || article.judul || document.querySelector('h1')?.innerText || document.title;
        add('article', [title, lines.join('\n') || parsed.body.textContent].filter(Boolean).join('\n'), title);
      }
    } catch { /* Fall through to visible content. */ }
  }
  const candidates = [...document.querySelectorAll('tr,li,section,article,[itemtype*="LocalBusiness"],.store-item,.store,.location,.branch,[class*="store-card"]')]
    .map((element) => ({ element, text: element.innerText?.trim() || '' }))
    .filter(({ text }) => text.length >= 30 && text.length <= 4000 && matches(text));
  for (const item of candidates.filter((item) => !candidates.some((other) => other !== item && item.element.contains(other.element)))) {
    add('branch', item.text);
  }
  const main = document.querySelector('main') || document.querySelector('[role="main"]') || document.body;
  return {
    text: main?.innerText?.trim().slice(0, 90000) || '', blocks: blocks.slice(0, 24),
    links: [...document.querySelectorAll('a[href]')].slice(0, 2500).map((a) => ({ url: a.href, text: a.innerText.trim().slice(0, 160) }))
  };
}

function rankLinks(links, input, allowed, visited) {
  const names = input.names.map(normalize).filter((x) => x.length >= 5);
  const tokens = (input.branchTokens || []).map(normalize).filter((x) => x.length >= 4);
  const selected = new Map();
  for (const link of links) {
    const url = canonical(link.url);
    if (!url || !isAllowed(url, allowed) || visited.has(url.href) || /\.(pdf|jpg|png|zip|mp4)$/i.test(url.pathname)) continue;
    if (/logout|signout|checkout|add-to-cart|wp-admin/i.test(url.href)) continue;
    const text = normalize(link.text + ' ' + url.pathname.replace(/%20/g, ' '));
    let score = names.some((n) => text.includes(n)) ? 20 : 0;
    score += tokens.filter((t) => text.includes(t)).length * 4;
    if (/\b(store|stores|locator|location|locations|cabang|outlet|contact|kontak|visit|kunjungan|hours|operasional|library|perpustakaan|fasilitas|facility|facilities|ticket|tiket|about|tentang)\b/.test(text)) score += 5;
    if (score === 5 && input.brandTokens && !input.brandTokens.some((token) => host(url).replace(/[^a-z0-9]/g, '').includes(token))) continue;
    if (score > 0) selected.set(url.href, { url: url.href, score });
  }
  return [...selected.values()].sort((a, b) => b.score - a.score || a.url.localeCompare(b.url));
}

async function readPage(browser, url, input, allowed, attempts) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    const started = Date.now();
    const context = await browser.newContext({ locale: 'id-ID', serviceWorkers: 'block', acceptDownloads: false });
    let retry = false;
    try {
      await context.route('**/*', (route) => {
        const request = route.request();
        const target = canonical(request.url());
        const resource = request.resourceType();
        const approvedAsset = target && target.protocol === 'https:' && !target.port && !target.username && !target.password && assetHosts.has(host(target)) && ['script', 'stylesheet'].includes(resource);
        return target && request.method() === 'GET' && (isAllowed(target, allowed) || approvedAsset) &&
          ['document', 'script', 'xhr', 'fetch', 'stylesheet'].includes(resource) ? route.continue() : route.abort();
      });
      await context.routeWebSocket('**/*', (socket) => socket.close());
      const page = await context.newPage();
      const network = [];
      const responseTasks = [];
      page.on('response', (response) => {
        const source = canonical(response.url());
        if (!source || !isAllowed(source, allowed) || !response.ok() || !/json/i.test(response.headers()['content-type'] || '') ||
          !/store|location|branch|outlet|library/i.test(source.pathname) || network.length >= 4) return;
        responseTasks.push((async () => {
          try { const text = await response.text(); if (text.length <= 250000) network.push({ url: source.href, data: JSON.parse(text) }); } catch { /* Ignore unreadable payloads. */ }
        })());
      });
      const response = await page.goto(url.href, { waitUntil: 'domcontentloaded', timeout: 16000 });
      const resolved = canonical(page.url());
      const status = response?.status() || 0;
      if (!response || !response.ok() || !resolved || !isAllowed(resolved, allowed)) {
        const reason = !resolved || !isAllowed(resolved, allowed) ? 'redirect_not_approved' : `http_${status}`;
        attempts.push({ url: url.href, resolvedURL: resolved?.href, attempt, status, reason, durationSeconds: (Date.now() - started) / 1000 });
        retry = [0, 408, 500, 502, 503, 504].includes(status);
      } else {
        if (resolved.hostname === 'smartcity.jakarta.go.id') {
          await page.locator('#__NEXT_DATA__').waitFor({ state: 'attached', timeout: 5000 }).catch(() => {});
        } else {
          await page.waitForFunction(() => (document.querySelector('main') || document.body)?.innerText?.trim().length > 200, undefined, { timeout: 2500 }).catch(() => {});
        }
        const extracted = await page.evaluate(extractDocument, { names: input.names });
        await Promise.allSettled(responseTasks);
        for (const payload of network) {
          const walk = (value, depth = 0) => {
            if (!value || typeof value !== 'object' || depth > 7 || extracted.blocks.length >= 30) return;
            if (Array.isArray(value)) return value.slice(0, 300).forEach((v) => walk(v, depth + 1));
            const text = JSON.stringify(value);
            if (text.length <= 16000 && input.names.some((n) => normalize(text).includes(normalize(n))) &&
              Object.keys(value).some((k) => /name|title|address/i.test(k))) {
              extracted.blocks.push({ kind: 'network', text, sourceURL: payload.url });
            } else Object.values(value).forEach((v) => walk(v, depth + 1));
          };
          walk(payload.data);
        }
        const reason = extracted.text || extracted.blocks.length ? 'read' : 'empty_content';
        attempts.push({ url: url.href, resolvedURL: resolved.href, attempt, status, reason, durationSeconds: (Date.now() - started) / 1000 });
        if (reason === 'read') return { requestedURL: url.href, url: resolved.href, status, ...extracted };
      }
    } catch (error) {
      attempts.push({ url: url.href, attempt, status: 0, reason: error.name === 'TimeoutError' ? 'timeout' : 'network_error', durationSeconds: (Date.now() - started) / 1000 });
      retry = true;
    } finally { await context.close(); }
    if (!retry || attempt === 2) break;
    await new Promise((resolve) => setTimeout(resolve, 350 * attempt));
  }
  return null;
}

async function collect(input) {
  const allowed = new Set(input.hosts);
  const budget = Math.max(1, Math.min(input.maxPages || 5, 8));
  const started = Date.now();
  const visited = new Set();
  const blockedHosts = new Set(input.blockedHosts || []);
  const pages = [];
  const attempts = [];
  const cache = new Map((input.cachedPages || []).flatMap((p) => [p.url, ...(p.aliases || [])].map((url) => [url, p])));
  const seeds = [...input.urls];
  // A root page is useful for discovering a replacement for a stale deep link.
  for (const value of input.urls) {
    const url = canonical(value);
    if (url && url.pathname !== '/') seeds.push(url.origin + '/');
  }
  const queue = [...new Set(seeds)].map((url) => ({ url }));
  if (!queue.length || !allowed.size) return { pages, attempts, discoveredURLs: [] };
  const browser = await chromium.launch({ headless: true, chromiumSandbox: true });
  const discoveredURLs = new Set();
  try {
    while (queue.length && visited.size < budget && Date.now() - started < 105000) {
      const item = queue.shift();
      const url = canonical(item.url);
      if (!url || !isAllowed(url, allowed) || visited.has(url.href)) continue;
      visited.add(url.href);
      const cached = cache.get(url.href);
      if (!cached && blockedHosts.has(host(url))) {
        attempts.push({ url: url.href, attempt: 0, status: 0, reason: 'host_cooldown', durationSeconds: 0 });
        continue;
      }
      const row = cached ? { ...cached, status: 200, requestedURL: url.href, fromCache: true } : await readPage(browser, url, input, allowed, attempts);
      if (!row) {
        if (attempts.some((a) => host(new URL(a.url)) === host(url) && [403, 429].includes(a.status))) blockedHosts.add(host(url));
        continue;
      }
      pages.push(row);
      const ranked = rankLinks(row.links || [], input, allowed, visited);
      for (const link of ranked) discoveredURLs.add(link.url);
      // Keep the second supplied source before new links; then prefer relevant links over roots.
      const unvisitedSeed = input.urls.find((seed) => !visited.has(seed));
      queue.sort((a, b) => (a.url === unvisitedSeed ? -1 : b.url === unvisitedSeed ? 1 : 0));
      const insertAt = queue[0]?.url === unvisitedSeed ? 1 : 0;
      queue.splice(insertAt, 0, ...ranked.slice(0, 4));
    }
  } finally { await browser.close(); }
  return { pages, attempts, discoveredURLs: [...discoveredURLs].slice(0, 100) };
}

if (require.main === module) {
  const watchdog = setTimeout(() => { process.stderr.write('Collection deadline exceeded\n'); process.exit(1); }, 150000);
  collect(JSON.parse(fs.readFileSync(0, 'utf8'))).then((output) => process.stdout.write(JSON.stringify(output)))
    .catch(() => { process.stderr.write('Playwright collection failed\n'); process.exitCode = 1; })
    .finally(() => clearTimeout(watchdog));
}
module.exports = { canonical, isAllowed, rankLinks, extractDocument };
