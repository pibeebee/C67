const { test } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { rankLinks, isAllowed, extractDocument } = require('./playwright-collect.cjs');

test('discovery ranks branch links and excludes unapproved or mutating URLs', () => {
  const links = [
    { url: 'https://example.org/contact', text: 'Contact' },
    { url: 'https://example.org/stores/cipete', text: 'Contoh Library Cipete Selatan' },
    { url: 'https://evil.example/stores/cipete', text: 'Contoh Library Cipete Selatan' },
    { url: 'https://example.org/logout', text: 'Contoh Library Cipete Selatan' },
    { url: 'http://example.org/contact', text: 'Contact' },
    { url: 'https://example.org:8443/contact', text: 'Contact' }
  ];
  const ranked = rankLinks(links, { names: ['Contoh Library Cipete Selatan'], branchTokens: ['Cipete'] }, new Set(['example.org']), new Set());
  assert.deepEqual(ranked.map((x) => x.url), ['https://example.org/stores/cipete', 'https://example.org/contact']);
  assert.equal(isAllowed(new URL('https://user:pass@example.org'), new Set(['example.org'])), false);
});

test('reader preserves actual JSON-LD and separates branch cards without injecting query hints', async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent(`<main><section><h2>Contoh Library Cipete Selatan</h2><p>Senin 09.00–17.00</p></section><section><h2>Contoh Library Kemang</h2><p>Setiap hari 10.00–22.00</p></section></main>
      <script type="application/ld+json">{"@type":"Library","name":"Contoh Library Cipete Selatan","address":"Jalan Cipete 12","openingHours":"Mo-Fr 09:00-17:00"}</script>
      <script type="application/ld+json">invalid</script>`);
    const result = await page.evaluate(extractDocument, { names: ['Contoh Library Cipete Selatan', 'Invented Unique Query'] });
    assert.equal(result.blocks.filter((b) => b.kind === 'jsonld').length, 1);
    const branch = result.blocks.find((b) => b.kind === 'branch');
    assert.ok(branch.text.includes('Cipete Selatan'));
    assert.ok(!branch.text.includes('Kemang'));
    assert.ok(!JSON.stringify(result).includes('Invented Unique Query'));
  } finally { await browser.close(); }
});

test('reference domains do not expand into unrelated generic branch directories', () => {
  const result = rankLinks([
    { url: 'https://bank.example/branches', text: 'Store locations' },
    { url: 'https://bank.example/dua-coffee-cipete', text: 'Dua Coffee Cipete' },
    { url: 'https://bank.example/bad%ZZ', text: 'Contact' }
  ], { names: ['Dua Coffee Cipete'], branchTokens: ['Cipete'], brandTokens: ['duacoffee'] }, new Set(['bank.example']), new Set());
  assert.deepEqual(result.map((r) => r.url), ['https://bank.example/dua-coffee-cipete']);
});
