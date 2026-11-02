import https from 'node:https';
import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';
import { Failure } from './domain.ts';

export function publicAddress(address: string): boolean {
  if (isIP(address) === 6) {
    const value = address.toLowerCase();
    // Reject mapped/transition/special-use ranges instead of attempting IPv4 coercion.
    const second = parseInt(value.split(':')[1] || '0', 16);
    return (
      /^[23][0-9a-f]{3}:/.test(value) &&
      !value.startsWith('2001:db8:') &&
      !value.startsWith('2002:') &&
      !value.startsWith('3fff:') &&
      !(value.startsWith('2001:') && second < 0x200)
    );
  }
  if (isIP(address) !== 4) return false;
  const [a, b] = address.split('.').map(Number);
  return !(
    a === 0 ||
    a === 10 ||
    a === 127 ||
    a >= 224 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && [0, 168].includes(b)) ||
    (a === 198 && [18, 19, 51].includes(b)) ||
    (a === 203 && b === 0)
  );
}

export async function readPublicPage(
  raw: string,
  redirects = 0,
  signal?: AbortSignal,
): Promise<{ url: string; text: string }> {
  signal?.throwIfAborted();
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Failure('RESEARCH_URL_REJECTED');
  }
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    (url.port && url.port !== '443') ||
    redirects > 2
  )
    throw new Failure('RESEARCH_URL_REJECTED');
  const hostname = url.hostname.replace(/^\[|\]$/g, '');
  const addresses = await lookup(hostname, { all: true });
  signal?.throwIfAborted();
  if (!addresses.length || addresses.some((item) => !publicAddress(item.address)))
    throw new Failure('RESEARCH_URL_REJECTED');
  const chosen = addresses[0];
  const response = await new Promise<{
    status: number;
    location?: string;
    type: string;
    body: string;
  }>((resolve, reject) => {
    // Pin the checked address for the connection to prevent a second DNS lookup/rebinding.
    const request = https.get(
      url,
      {
        timeout: 8000,
        signal,
        headers: { 'User-Agent': 'C67-PlaceResearch/1.0', Accept: 'text/html,text/plain' },
        lookup: ((_host: string, options: { all?: boolean }, callback: Function) =>
          options.all
            ? callback(null, [{ address: chosen.address, family: chosen.family }])
            : callback(null, chosen.address, chosen.family)) as any,
      },
      (result) => {
        const chunks: Buffer[] = [];
        let size = 0;
        result.on('data', (chunk) => {
          size += chunk.length;
          if (size > 128 * 1024) {
            request.destroy(new Failure('RESEARCH_TOO_LARGE'));
            return;
          }
          chunks.push(chunk);
        });
        result.on('end', () =>
          resolve({
            status: result.statusCode ?? 500,
            location: result.headers.location,
            type: String(result.headers['content-type'] ?? ''),
            body: Buffer.concat(chunks).toString('utf8'),
          }),
        );
        result.on('error', reject);
      },
    );
    request.on('timeout', () => request.destroy(new Failure('RESEARCH_TIMEOUT', 504)));
    request.on('error', reject);
  });
  if ([301, 302, 303, 307, 308].includes(response.status) && response.location)
    return readPublicPage(new URL(response.location, url).href, redirects + 1, signal);
  if (response.status !== 200 || !/text\/(html|plain)/i.test(response.type))
    throw new Failure('RESEARCH_UNAVAILABLE', 503);
  const text = response.body
    .replace(/<(script|style|noscript)\b[^>]*>[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&(?:nbsp|amp|lt|gt|quot);/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 6000);
  return { url: url.href, text };
}
