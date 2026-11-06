import { chromium, type Browser, type BrowserContext } from "playwright";
import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { createHash } from "node:crypto";
import { ensure, object, text } from "./domain.ts";
import type { PlaceContext } from "./untimed.ts";

export type ResearchConfig = {
  allowedHosts: string[];
  seedUrls: string[];
  queries: string[];
  maxPages: number;
  maxSearches: number;
  maxRounds: number;
  timeoutMs: number;
  maxPageChars: number;
};
export type BrowserPage = {
  id: string;
  requestedUrl: string;
  url: string;
  title: string;
  retrievedAt: string;
  status: "ok" | "unavailable";
  httpStatus: number | null;
  text: string;
  textHash: string | null;
  truncated: boolean;
  links: { title: string; url: string }[];
  error: string | null;
};
export type SearchResult = {
  query: string;
  retrievedAt: string;
  status: "ok" | "unavailable";
  results: { title: string; url: string }[];
  error: string | null;
};
const integer = (raw: unknown, fallback: number, min: number, max: number) => {
  const n = raw ?? fallback;
  ensure(
    typeof n === "number" && Number.isInteger(n) && n >= min && n <= max,
    "Invalid bounded research configuration.",
  );
  return n;
};
export function researchConfig(
  raw: unknown,
  context: PlaceContext,
): ResearchConfig {
  const v = raw ? object(raw, "research configuration") : {};
  const seeds = v.seedUrls ?? [...new Set(context.facts.map((f) => f.url))];
  ensure(
    Array.isArray(seeds) && seeds.length <= 20,
    "Provide at most 20 official seed URLs.",
  );
  const hosts = v.allowedHosts ?? [
    ...new Set(
      seeds.map((u) => new URL(String(u)).hostname.replace(/^www\./, "")),
    ),
  ];
  ensure(
    Array.isArray(hosts) && hosts.length > 0 && hosts.length <= 20,
    "Provide 1..20 official domains.",
  );
  const allowedHosts = hosts.map((h) =>
    text(h, "official host", 200).toLowerCase(),
  );
  ensure(
    allowedHosts.every(
      (h) =>
        /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/.test(h) &&
        !h.includes("..") &&
        !isIP(h),
    ),
    "Use explicit public official host names, without wildcards, URLs or IPs.",
  );
  const queries = v.queries ?? [];
  ensure(
    Array.isArray(queries) && queries.length <= 10,
    "Provide at most ten seed searches.",
  );
  const result = {
    allowedHosts,
    seedUrls: seeds.map((u) => text(u, "seed URL", 2000)),
    queries: queries.map((q) => text(q, "seed search", 500)),
    maxPages: integer(v.maxPages, 24, 1, 64),
    maxSearches: integer(v.maxSearches, 12, 0, 32),
    maxRounds: integer(v.maxRounds, 12, 1, 128),
    timeoutMs: integer(v.timeoutMs, 300000, 10000, 900000),
    maxPageChars: integer(v.maxPageChars, 96000, 2000, 200000),
  };
  for (const url of result.seedUrls)
    ensure(
      officialUrl(url, result.allowedHosts),
      "Seed URL is outside the trusted official domains.",
    );
  return result;
}
export function officialUrl(raw: string, hosts: string[]): string | null {
  try {
    if (raw.length > 2048) return null;
    const u = new URL(raw);
    if (
      u.protocol !== "https:" ||
      u.username ||
      u.password ||
      (u.port && u.port !== "443") ||
      !hosts.some((h) => u.hostname === h || u.hostname.endsWith(`.${h}`))
    )
      return null;
    u.hash = "";
    return u.href;
  } catch {
    return null;
  }
}
function publicIP(raw: string): boolean {
  const ip = raw.toLowerCase().replace(/^\[|\]$/g, "");
  if (isIP(ip) === 4) {
    const p = ip.split(".").map(Number);
    const [a, b] = p as [number, number];
    return !(
      a === 0 ||
      a === 10 ||
      a === 127 ||
      a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && (b === 168 || b === 0 || b === 2)) ||
      (a === 198 && (b === 18 || b === 19 || b === 51)) ||
      (a === 203 && b === 0)
    );
  }
  // Public global unicast only; disallow mapped/transition/documentation/local ranges.
  return (
    isIP(ip) === 6 &&
    /^[23]/.test(ip) &&
    !ip.startsWith("2001:db8:") &&
    !ip.startsWith("2001:0:") &&
    !ip.startsWith("2002:") &&
    !ip.includes(".")
  );
}
function searchTarget(raw: string): string | null {
  try {
    const url = new URL(raw);
    if (url.hostname === "bing.com" || url.hostname.endsWith(".bing.com")) {
      const encoded = url.searchParams.get("u");
      if (encoded?.startsWith("a1"))
        return Buffer.from(encoded.slice(2), "base64url").toString("utf8");
      return null;
    }
    return url.href;
  } catch {
    return null;
  }
}
export class ResearchBrowser {
  readonly pages: BrowserPage[] = [];
  readonly searches: SearchResult[] = [];
  private browser: Browser | null = null;
  private context: BrowserContext | null = null;
  private started = Date.now();
  private activeMs = 0;
  private deadlineTimer: ReturnType<typeof setTimeout> | null = null;
  private dns = new Map<string, Promise<boolean>>();
  private currentHosts: string[] = [];
  readonly config: ResearchConfig;
  private modelWaitBudgetMs: number;
  constructor(
    config: ResearchConfig,
    modelWaitBudgetMs = config.maxRounds * 180000,
  ) {
    this.config = config;
    this.modelWaitBudgetMs = modelWaitBudgetMs;
  }
  async open() {
    this.started = Date.now();
    try {
      this.browser = await chromium.launch({
        headless: true,
        chromiumSandbox: true,
        timeout: 30000,
      });
      this.context = await this.browser.newContext({
        acceptDownloads: false,
        serviceWorkers: "block",
        locale: "en-US",
        permissions: [],
      });
      await this.context.routeWebSocket("**/*", (socket) => socket.close());
      await this.context.route("**/*", async (route) => {
        const req = route.request();
        try {
          const url = new URL(req.url());
          const allowed =
            req.method() === "GET" &&
            ["document", "script", "stylesheet", "xhr", "fetch"].includes(
              req.resourceType(),
            ) &&
            Boolean(officialUrl(url.href, this.currentHosts)) &&
            (await this.publicHost(url.hostname));
          if (!allowed) return await route.abort();
          const chain = req.redirectedFrom();
          let redirects = 0;
          for (let r = chain; r; r = r.redirectedFrom()) redirects++;
          if (redirects > 5) return await route.abort();
          await route.continue();
        } catch {
          await route.abort().catch(() => {});
        }
      });
      this.context.on("page", (page) => {
        page.on("dialog", (dialog) => dialog.dismiss());
        page.on("download", (download) => download.cancel());
        void page
          .opener()
          .then((opener) => {
            if (opener) void page.close().catch(() => {});
          })
          .catch(() => {});
      });
      // Count navigation work separately from slow model inference between actions.
      this.deadlineTimer = setTimeout(() => {
        void this.browser?.close().catch(() => {});
      }, this.config.timeoutMs + this.modelWaitBudgetMs);
      this.deadlineTimer.unref();
    } catch {
      await this.close();
      throw new Error(
        "Headless Chromium could not start. Install its matching binary with npm run browser:install; no browser or AI result was simulated.",
      );
    }
  }
  private async publicHost(host: string) {
    if (!this.dns.has(host))
      this.dns.set(
        host,
        (async () => {
          try {
            const records = await Promise.race([
              lookup(host, { all: true, verbatim: true }),
              new Promise<never>((_, reject) => {
                const t = setTimeout(
                  () => reject(new Error("DNS timeout")),
                  3000,
                );
                t.unref();
              }),
            ]);
            return (
              records.length > 0 && records.every((r) => publicIP(r.address))
            );
          } catch {
            return false;
          }
        })(),
      );
    const result = await this.dns.get(host)!;
    if (!result) this.dns.delete(host);
    return result;
  }
  private ready() {
    ensure(
      this.context &&
        this.activeMs < this.config.timeoutMs &&
        Date.now() - this.started <
          this.config.timeoutMs + this.modelWaitBudgetMs,
      "Research browser time budget exhausted.",
    );
    return this.context;
  }
  async read(rawUrl: string, retryUnavailable = false): Promise<BrowserPage> {
    const url = officialUrl(rawUrl, this.config.allowedHosts);
    ensure(url, "Browser read URL is not an allowed official HTTPS URL.");
    const matches = this.pages.filter(
      (p) => p.requestedUrl === url || p.url === url,
    );
    const cached = matches.at(-1);
    if (cached && (cached.status === "ok" || !retryUnavailable)) return cached;
    ensure(
      matches.length < 3,
      "URL retry guard reached; choose another source or report unavailable.",
    );
    ensure(
      this.pages.length < this.config.maxPages,
      "Research page budget exhausted.",
    );
    const result: BrowserPage = {
      id: `page:${this.pages.length + 1}`,
      requestedUrl: url,
      url,
      title: "",
      retrievedAt: new Date().toISOString(),
      status: "unavailable",
      httpStatus: null,
      text: "",
      textHash: null,
      truncated: false,
      links: [],
      error: null,
    };
    this.pages.push(result);
    const page = await this.ready().newPage();
    const actionStarted = Date.now();
    const actionTimer = setTimeout(
      () => {
        void page.close().catch(() => {});
      },
      Math.max(1, this.config.timeoutMs - this.activeMs),
    );
    actionTimer.unref();
    page.setDefaultTimeout(
      Math.min(5000, this.config.timeoutMs - this.activeMs),
    );
    this.currentHosts = this.config.allowedHosts;
    try {
      const response = await page.goto(url, {
        waitUntil: "domcontentloaded",
        timeout: Math.max(
          1,
          Math.min(20000, this.config.timeoutMs - this.activeMs),
        ),
      });
      result.httpStatus = response?.status() ?? null;
      ensure(response && response.ok(), "Official page returned an error.");
      ensure(
        /text\/html|text\/plain/.test(response.headers()["content-type"] ?? ""),
        "This research reader supports text/HTML pages, not PDFs or downloads.",
      );
      const final = officialUrl(page.url(), this.config.allowedHosts);
      ensure(final, "Redirect left official allowlist.");
      result.url = final;
      await page.waitForFunction(
        () => (document.body?.innerText.trim().length ?? 0) >= 80,
        undefined,
        { timeout: Math.min(5000, this.config.timeoutMs - this.activeMs) },
      );
      const extracted = await page.evaluate(
        ({ maxChars }) => {
          const node =
            document.querySelector("main, article, [role=main]") ??
            document.body;
          const selected = (node as HTMLElement)?.innerText ?? "";
          const full =
            selected.trim().length >= 80
              ? selected
              : (document.body?.innerText ?? "");
          const links = Array.from(
            document.querySelectorAll<HTMLAnchorElement>("a[href]"),
          )
            .slice(0, 300)
            .map((a) => ({
              title: (a.innerText || a.getAttribute("aria-label") || "")
                .trim()
                .slice(0, 180),
              url: a.href,
            }));
          return {
            title: document.title.slice(0, 300),
            text: full.slice(0, maxChars),
            truncated: full.length > maxChars,
            links,
          };
        },
        { maxChars: this.config.maxPageChars },
      );
      ensure(
        extracted.text.trim().length >= 80,
        "Page text is empty, blocked, or requires unsupported interaction.",
      );
      result.title = extracted.title;
      result.text = extracted.text;
      result.truncated = extracted.truncated;
      result.links = extracted.links
        .flatMap((l) => {
          const target = officialUrl(l.url, this.config.allowedHosts);
          return target && l.title ? [{ title: l.title, url: target }] : [];
        })
        .slice(0, 60);
      result.textHash = createHash("sha256").update(result.text).digest("hex");
      result.status = "ok";
    } catch (error) {
      result.error =
        error instanceof Error &&
        !/playwright|Timeout|page\./i.test(error.message)
          ? error.message.slice(0, 500)
          : "Navigation/render/extraction failed within the bounded browser session; HTTP status is recorded separately.";
    } finally {
      clearTimeout(actionTimer);
      this.activeMs += Date.now() - actionStarted;
      await page.close().catch(() => {});
    }
    return result;
  }
  async search(query: string): Promise<SearchResult> {
    ensure(
      this.searches.length < this.config.maxSearches,
      "Research search budget exhausted.",
    );
    const q = text(query, "search query", 500);
    const result: SearchResult = {
      query: q,
      retrievedAt: new Date().toISOString(),
      status: "unavailable",
      results: [],
      error: null,
    };
    this.searches.push(result);
    const page = await this.ready().newPage();
    this.currentHosts = ["bing.com"];
    const actionStarted = Date.now();
    const actionTimer = setTimeout(
      () => {
        void page.close().catch(() => {});
      },
      Math.max(1, this.config.timeoutMs - this.activeMs),
    );
    actionTimer.unref();
    page.setDefaultTimeout(
      Math.min(5000, this.config.timeoutMs - this.activeMs),
    );
    try {
      const scoped = `${q} (${this.config.allowedHosts.map((h) => `site:${h}`).join(" OR ")})`;
      const response = await page.goto(
        `https://www.bing.com/search?${new URLSearchParams({ q: scoped })}`,
        {
          waitUntil: "domcontentloaded",
          timeout: Math.max(
            1,
            Math.min(20000, this.config.timeoutMs - this.activeMs),
          ),
        },
      );
      ensure(response?.ok(), "Search engine unavailable.");
      await page
        .locator("li.b_algo h2 a")
        .first()
        .waitFor({
          state: "attached",
          timeout: Math.min(5000, this.config.timeoutMs - this.activeMs),
        });
      const links = await page.locator("li.b_algo h2 a").evaluateAll((nodes) =>
        nodes.slice(0, 20).map((node) => ({
          title: (node.textContent ?? "").trim().slice(0, 200),
          url: (node as HTMLAnchorElement).href,
        })),
      );
      result.results = links
        .flatMap((l) => {
          const target = searchTarget(l.url);
          const url = target
            ? officialUrl(target, this.config.allowedHosts)
            : null;
          return url ? [{ title: l.title, url }] : [];
        })
        .slice(0, 8);
      ensure(
        result.results.length > 0,
        "No allowed results, or the search page was blocked/changed.",
      );
      result.status = "ok";
    } catch {
      result.error =
        "Search produced no readable official results; CAPTCHA/consent/layout changes are not bypassed.";
    } finally {
      clearTimeout(actionTimer);
      this.activeMs += Date.now() - actionStarted;
      await page.close().catch(() => {});
    }
    return result;
  }
  async close() {
    if (this.deadlineTimer) clearTimeout(this.deadlineTimer);
    await this.context?.close().catch(() => {});
    await this.browser?.close().catch(() => {});
    this.context = null;
    this.browser = null;
  }
}
