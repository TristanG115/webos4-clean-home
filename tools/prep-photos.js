#!/usr/bin/env node
// prep-photos.js <source-folder> [out-folder]
// Turns your pictures into TV-ready 1920x1080 JPEGs (+ 320x180 thumbnails for the gallery).
//  - EXIF rotation applied, every photo is cropped to true 16:9 at full quality (no blur, no bars, no upscaling of a small strip)
//  - the crop window is chosen by sharp's "attention" strategy (saliency + skin-tone bias), so faces/subjects stay in frame
//  - originals are never modified. Output default: tv/launcher/photos (git-ignored: private)
//   cd tools && npm install && node prep-photos.js "C:\path\to\photos"
const fs = require('fs'), path = require('path');
const sharp = require('sharp');
const src = process.argv[2];
if (!src) { console.error('usage: node prep-photos.js <source-folder> [out-folder]'); process.exit(1); }
const out = path.resolve(process.argv[3] || path.join(__dirname, '..', 'tv', 'launcher', 'photos'));
fs.mkdirSync(path.join(out, 'thumbs'), { recursive: true });
for (const f of fs.readdirSync(out)) if (/\.jpg$/i.test(f)) fs.unlinkSync(path.join(out, f));     // mirror: start clean
for (const f of fs.readdirSync(path.join(out, 'thumbs'))) fs.unlinkSync(path.join(out, 'thumbs', f));
const files = fs.readdirSync(src).filter(f => /\.(jpe?g|png|webp|tif?f|heic)$/i.test(f)).sort();
(async () => {
  let n = 0;
  for (const f of files) {
    try {
      const name = 'photo' + String(++n).padStart(3, '0') + '.jpg';
      const img = sharp(path.join(src, f), { failOn: 'none' }).rotate();               // .rotate() with no args = apply EXIF orientation
      const meta = await sharp(path.join(src, f)).rotate().toBuffer({ resolveWithObject: true });
      await sharp(meta.data).resize(1920, 1080, { fit: 'cover', position: sharp.strategy.attention, kernel: 'lanczos3' })
        .jpeg({ quality: 88, mozjpeg: true }).toFile(path.join(out, name));
      await sharp(meta.data).resize(320, 180, { fit: 'cover', position: sharp.strategy.attention }).jpeg({ quality: 78 }).toFile(path.join(out, 'thumbs', name));
      console.log(`${f} -> ${name}  (${meta.info.width}x${meta.info.height})`);
    } catch (e) { n--; console.warn('skipped', f, e.message); }
  }
  console.log(`wrote ${n} photos (+thumbs) to ${out}`);
})();
