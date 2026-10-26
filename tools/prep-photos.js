#!/usr/bin/env node
// prep-photos.js <source-folder> [out-folder]
// Turns your pictures into TV-ready gallery photos:
//  - EXIF rotation applied; the WHOLE picture is kept (not cropped) at up to 2048 px on the long side / 2.6 megapixels (about the size of the screen: bigger pictures make the TV's browser swap), so the framing can be changed later
//    on the TV (Settings -> Photo gallery -> choose a photo) or on the phone page, and so zooming in stays sharp
//  - a small preview (480 px) for the gallery grid
//  - an automatic framing (sharp's "attention" strategy: saliency + skin-tone bias, so faces/subjects stay in view) written to photos/crops/NAME.json;
//    tools/deploy.sh puts those into the TV's state/crops/ unless you already changed the framing on the TV since
//  - originals are never modified. Output default: tv/launcher/photos (git-ignored: private)
//   cd tools && npm install && node prep-photos.js "C:\path\to\photos"
const fs = require('fs'), path = require('path');
const sharp = require('sharp');
const src = process.argv[2];
if (!src) { console.error('usage: node prep-photos.js <source-folder> [out-folder]'); process.exit(1); }
const out = path.resolve(process.argv[3] || path.join(__dirname, '..', 'tv', 'launcher', 'photos'));
const FA = 16 / 9;
fs.mkdirSync(path.join(out, 'thumbs'), { recursive: true });
fs.mkdirSync(path.join(out, 'crops'), { recursive: true });
for (const f of fs.readdirSync(out)) if (/\.jpg$/i.test(f)) fs.unlinkSync(path.join(out, f));     // mirror: start clean
for (const f of fs.readdirSync(path.join(out, 'thumbs'))) fs.unlinkSync(path.join(out, 'thumbs', f));
for (const f of fs.readdirSync(path.join(out, 'crops'))) fs.unlinkSync(path.join(out, 'crops', f));
const files = fs.readdirSync(src).filter(f => /\.(jpe?g|png|webp|tif?f|heic)$/i.test(f)).sort();
const r3 = v => Math.round(v * 1000) / 1000;
(async () => {
  let n = 0;
  for (const f of files) {
    try {
      const name = 'photo' + String(++n).padStart(3, '0');
      const rotated = await sharp(path.join(src, f), { failOn: 'none' }).rotate().toBuffer({ resolveWithObject: true });
      const nw = rotated.info.width, nh = rotated.info.height;
      // where would "crop to fill the screen" put the window? (automatic framing)
      const fill = await sharp(rotated.data).resize(1920, 1080, { fit: 'cover', position: sharp.strategy.attention }).toBuffer({ resolveWithObject: true });
      const s = Math.max(1920 / nw, 1080 / nh), cw = Math.round(nw * s), ch = Math.round(nh * s);
      const fx = Math.min(1, Math.max(0, (Math.abs(fill.info.cropOffsetLeft || 0) + 960) / cw)), fy = Math.min(1, Math.max(0, (Math.abs(fill.info.cropOffsetTop || 0) + 540) / ch));
      const k = Math.min(1, 2048 / Math.max(nw, nh), Math.sqrt(2600000 / (nw * nh)));
      await sharp(rotated.data).resize(Math.round(nw * k), Math.round(nh * k), { kernel: 'lanczos3' }).jpeg({ quality: 88, mozjpeg: true }).toFile(path.join(out, name + '.jpg'));
      await sharp(rotated.data).resize({ width: 480, height: 480, fit: 'inside' }).jpeg({ quality: 78 }).toFile(path.join(out, 'thumbs', name + '.jpg'));
      fs.writeFileSync(path.join(out, 'crops', name + '.json'), JSON.stringify({ x: r3(fx), y: r3(fy), z: 1, a: [r3(fx), r3(fy)] }));
      console.log(`${f} -> ${name}.jpg  (${nw}x${nh}, auto focus ${Math.round(fx * 100)}%/${Math.round(fy * 100)}%${nw / nh >= FA ? ', wider than the screen' : ''})`);
    } catch (e) { n--; console.warn('skipped', f, e.message); }
  }
  console.log(`wrote ${n} photos (+thumbs +automatic framing) to ${out}`);
})();
