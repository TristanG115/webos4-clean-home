#!/usr/bin/env node
// preview.js - build scratch/preview/ (launcher + mock data + the real icons pulled from the TV) and screenshot it with
// headless Edge/Chrome at 1920x1080, so the UI can be reviewed without touching the TV.
//   node tools/preview.js [shot-name] [query]     e.g.  node tools/preview.js home "mock=1"   |   node tools/preview.js saver "mock=1&saver=1"
const fs = require('fs'), path = require('path'), cp = require('child_process');
const root = path.resolve(__dirname, '..');
const pv = path.join(root, 'scratch', 'preview');
fs.mkdirSync(path.join(pv, 'icons'), { recursive: true });
fs.mkdirSync(path.join(pv, 'photos'), { recursive: true });
const lp = JSON.parse(fs.readFileSync(path.join(root, 'scratch', 'launchpoints.json'), 'utf8'));
const ssh = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'LogLevel=ERROR', 'root@10.0.0.63'];
for (const a of lp.launchPoints) for (const k of ['largeIcon', 'icon']) {
  const p = a[k]; if (!p || p[0] !== '/') continue;
  const local = path.join(pv, 'icons', p.split('/').slice(-2).join('_'));
  if (!fs.existsSync(local)) { const r = cp.spawnSync('ssh', ssh.concat(['cat', p]), { maxBuffer: 20e6 }); if (r.status === 0 && r.stdout.length) fs.writeFileSync(local, r.stdout); }
}
const demo = path.join(root, 'scratch', 'demo-photos'), real = path.join(root, 'tv', 'launcher', 'photos');
const src = fs.existsSync(real) && fs.readdirSync(real).length ? real : demo;
const photos = fs.existsSync(src) ? fs.readdirSync(src).filter(f => /\.jpe?g$/i.test(f)) : [];
photos.forEach(f => fs.copyFileSync(path.join(src, f), path.join(pv, 'photos', f)));
const mock = { '/api/apps': lp, '/api/photos': photos, iconBase: 'icons/', photoBase: 'photos/',
  '/api/net': { returnValue: true, isInternetConnectionAvailable: true, wired: { state: 'connected', ipAddress: '10.0.0.63' }, wifi: { state: 'disconnected' } },
  '/api/ready': { ok: true }, '/api/launch': { returnValue: true } };
fs.writeFileSync(path.join(pv, 'mock.js'), 'window.__MOCK__=' + JSON.stringify(mock) + ';');
for (const f of ['app.js','qr.js','phone.html']) if (fs.existsSync(path.join(root,'tv','launcher',f))) fs.copyFileSync(path.join(root,'tv','launcher',f), path.join(pv,f));
fs.writeFileSync(path.join(pv, 'index.html'), fs.readFileSync(path.join(root, 'tv', 'launcher', 'index.html'), 'utf8').replace('<!--MOCK-->', '<script src="mock.js"></script>'));
const name = process.argv[2] || 'home', query = process.argv[3] || 'mock=1';
const browsers = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'];
const b = browsers.find(fs.existsSync);
if (!b) { console.error('no Edge/Chrome found'); process.exit(1); }
const out = path.join(root, 'shots', name + '.png');
fs.mkdirSync(path.dirname(out), { recursive: true });
const url = 'file:///' + path.join(pv, 'index.html').replace(/\\/g, '/') + '?' + query;
cp.spawnSync(b, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1920,1080', '--force-device-scale-factor=1',
  '--virtual-time-budget=' + (process.env.BUDGET || '4000'), '--screenshot=' + out, '--user-data-dir=' + path.join(pv, '.profile'), url], { stdio: 'inherit', timeout: 60000 });
console.log(fs.existsSync(out) ? 'wrote ' + out : 'screenshot failed');
