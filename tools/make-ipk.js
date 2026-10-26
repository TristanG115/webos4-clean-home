#!/usr/bin/env node
// make-ipk.js - EXPERIMENTAL: package the launcher as an ordinary webOS app (developer mode, no root) -> dist/tv.debloat.launcher_*.ipk
//   node tools/make-ipk.js            builds scratch/ipk/ and, when the LG CLI is installed (npm i -g @webos-tools/cli), runs ares-package
// Installing needs the "Developer Mode" app on the TV and a TV registered with `ares-setup-device`; see rootless/README.md for the steps and the limits.
// The rootless build uses tv/launcher/rootless.js instead of the rooted TV's local API. It can show the clock, weather and favourites; whether it can
// LAUNCH apps depends on what the TV lets a non-root app call (untested).
const fs = require('fs'), path = require('path'), cp = require('child_process');
const root = path.join(__dirname, '..'), src = path.join(root, 'tv', 'launcher'), stage = path.join(root, 'scratch', 'ipk'), dist = path.join(root, 'dist');
fs.rmSync(stage, { recursive: true, force: true }); fs.mkdirSync(stage, { recursive: true }); fs.mkdirSync(dist, { recursive: true });
for (const f of ['app.js', 'qr.js', 'stage.js', 'rootless.js']) fs.copyFileSync(path.join(src, f), path.join(stage, f));
let html = fs.readFileSync(path.join(src, 'index.html'), 'utf8');
if (!html.includes('<script src="app.js">')) throw new Error('index.html changed: cannot inject rootless.js');
fs.writeFileSync(path.join(stage, 'index.html'), html.replace('<script src="app.js">', '<script src="rootless.js"></script><script src="app.js">'));
fs.writeFileSync(path.join(stage, 'appinfo.json'), JSON.stringify({ id: 'tv.debloat.launcher', version: '1.0.0', vendor: 'tv-debloat', type: 'web', main: 'index.html', title: 'Clean Home',
  icon: 'icon.png', largeIcon: 'largeIcon.png', bgColor: '#0a0c11', resolution: '1920x1080', disableBackHistoryAPI: true }, null, 2));
const svg = s => Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="' + s + '" height="' + s + '" viewBox="0 0 24 24"><rect width="24" height="24" rx="5" fill="#0a0c11"/><path d="M5 12l7-6 7 6M7 11v7h4v-4h2v4h4v-7" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>');
let sharp; try { sharp = require('sharp'); } catch (e) { console.error('sharp missing: run  npm install  in tools/ first'); process.exit(1); }
(async () => {
  await sharp(svg(80)).resize(80, 80).png().toFile(path.join(stage, 'icon.png'));
  await sharp(svg(130)).resize(130, 130).png().toFile(path.join(stage, 'largeIcon.png'));
  console.log('staged ' + stage);
  const r = cp.spawnSync('ares-package', ['--no-minify', stage, '-o', dist], { stdio: 'inherit', shell: true });
  if (r.status === 0) console.log('IPK written to ' + dist + '. Install: ares-install --device <name> ' + dist + '/tv.debloat.launcher_1.0.0_all.ipk');
  else console.log('ares-package not available: install the LG CLI (npm i -g @webos-tools/cli) and run:  ares-package --no-minify scratch/ipk -o dist');
})();
