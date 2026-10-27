import sharp from 'sharp';
import { createHash } from 'node:crypto';
export async function validateImage(bytes, declaredType) {
  if (bytes.length > 5242880) return { failure_code: 'too_large' };
  try {
    const image = sharp(bytes, { limitInputPixels: 20000000, failOn: 'warning', animated: false }).timeout({ seconds: 20 });
    const info = await image.metadata();
    if (!['jpeg', 'png'].includes(info.format) || `image/${info.format}` !== declaredType) return { failure_code: 'unsupported_type' };
    if ((info.pages ?? 1) !== 1 || info.width * info.height > 20000000) return { failure_code: 'dimensions_exceeded' };
    const { data, info: output } = await image.rotate().resize({ width: 2048, height: 2048, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer({ resolveWithObject: true });
    return { bytes: data, width: output.width, height: output.height, sha256: createHash('sha256').update(data).digest('hex') };
  } catch { return { failure_code: 'invalid_image' }; }
}
