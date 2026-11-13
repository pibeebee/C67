import { PocError, ensure } from "./domain.ts";

export class Http {
  calls: Record<string, number> = {};
  private fetcher: typeof fetch;
  private signal: AbortSignal;
  constructor(
    fetcher: typeof fetch = fetch,
    signal: AbortSignal = AbortSignal.timeout(180000),
  ) {
    this.fetcher = fetcher;
    this.signal = signal;
  }

  async json(
    label: string,
    url: string,
    init: RequestInit = {},
    timeoutMs = 30000,
  ): Promise<unknown> {
    this.calls[label] = (this.calls[label] ?? 0) + 1;
    let response: Response;
    try {
      response = await this.fetcher(url, {
        ...init,
        redirect: "error",
        signal: AbortSignal.any([this.signal, AbortSignal.timeout(timeoutMs)]),
      });
    } catch {
      throw new PocError(
        `${label}: network request failed or timed out. No simulated fallback was used.`,
      );
    }
    // Do not log provider bodies, request headers or URLs containing credentials.
    if (!response.ok) {
      await response.body?.cancel();
      throw new PocError(
        `${label}: HTTP ${response.status}. Check credentials, quota, supported parameters and service configuration.`,
      );
    }
    const reader = response.body?.getReader();
    ensure(reader, `${label}: empty response.`);
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        size += chunk.value.length;
        if (size > 2 * 1024 * 1024) {
          await reader.cancel();
          throw new PocError(`${label}: response exceeds the PoC size limit.`);
        }
        chunks.push(chunk.value);
      }
      return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
    } catch (error) {
      if (error instanceof PocError) throw error;
      throw new PocError(`${label}: response could not be read as JSON.`);
    } finally {
      reader.releaseLock();
    }
  }
}
