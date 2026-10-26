import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { validateImage } from './image.mjs';
test('decodes/re-encodes private image without source metadata', async () => {
  const input = await sharp({ create: { width: 16, height: 12, channels: 3, background: 'red' } }).withMetadata().png().toBuffer();
  const result = await validateImage(input, 'image/png');
  assert.equal(result.width, 16);assert.equal(result.height, 12);assert.equal(result.sha256.length, 64);
  const metadata = await sharp(result.bytes).metadata();assert.equal(metadata.format, 'jpeg');assert.equal(metadata.exif, undefined);
});
test('rejects fake bytes, mismatched format and oversize input', async () => {
  assert.equal((await validateImage(Buffer.from('not an image'), 'image/jpeg')).failure_code, 'invalid_image');
  const png = await sharp({ create: { width: 2, height: 2, channels: 3, background: 'red' } }).png().toBuffer();
  assert.equal((await validateImage(png, 'image/jpeg')).failure_code, 'unsupported_type');
  assert.equal((await validateImage(Buffer.alloc(5242881), 'image/png')).failure_code, 'too_large');
});
