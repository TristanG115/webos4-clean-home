#!/usr/bin/env node
// preview.js - build scratch/preview/ (launcher + mock data + the real icons pulled from the TV) and screenshot it with
// headless Edge/Chrome at 1920x1080, so the UI can be reviewed without touching the TV.
//   node tools/preview.js [shot-name] [query]     e.g.  node tools/preview.js home "mock=1"   |   node tools/preview.js saver "mock=1&saver=1"
const fs = require('fs'), path = require('path'), cp = require('child_process');
const root = path.resolve(__dirname, '..');
const pv = path.join(root, 'scratch', 'preview');
fs.mkdirSync(path.join(pv, 'icons'), { recursive: true });
fs.mkdirSync(path.join(pv, 'photos'), { recursive: true });
function tvTarget() { try { return 'root@' + /^TV_IP=(\S+)/m.exec(fs.readFileSync(path.join(root, 'tv.conf'), 'utf8'))[1]; } catch (e) { return 'root@tv.invalid'; } }
const lp = JSON.parse(fs.readFileSync(path.join(root, 'scratch', 'launchpoints.json'), 'utf8'));
const ssh = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', '-o', 'LogLevel=ERROR', tvTarget()];
for (const a of lp.launchPoints) for (const k of ['largeIcon', 'icon']) {
  const p = a[k]; if (!p || p[0] !== '/') continue;
  const local = path.join(pv, 'icons', p.split('/').slice(-2).join('_'));
  if (!fs.existsSync(local)) { const r = cp.spawnSync('ssh', ssh.concat(['cat', p]), { maxBuffer: 20e6 }); if (r.status === 0 && r.stdout.length) fs.writeFileSync(local, r.stdout); }
}
const demo = path.join(root, 'scratch', 'demo-photos'), real = path.join(root, 'tv', 'launcher', 'photos');
// PV_PUBLIC=1 (used for the README pictures): NO photos at all, a generic weather place and a generic IP, so nothing personal can end up in an image
const PUBLIC = !!process.env.PV_PUBLIC;
const src = fs.existsSync(real) && fs.readdirSync(real).length ? real : demo;
const photos = !PUBLIC && fs.existsSync(src) ? fs.readdirSync(src).filter(f => /\.jpe?g$/i.test(f)) : [];
if (PUBLIC) { fs.rmSync(path.join(pv, 'photos'), { recursive: true, force: true }); }
fs.mkdirSync(path.join(pv, 'photos', 'thumbs'), { recursive: true });
photos.forEach(f => { fs.copyFileSync(path.join(src, f), path.join(pv, 'photos', f)); const t = path.join(src, 'thumbs', f); if (fs.existsSync(t)) fs.copyFileSync(t, path.join(pv, 'photos', 'thumbs', f)); });
// extra fixtures for the Settings pages: real LG values captured from the TV (scratch/lg-mock.json), the services catalog, the block lists, saved framing
const lgm = fs.existsSync(path.join(root, 'scratch', 'lg-mock.json')) ? JSON.parse(fs.readFileSync(path.join(root, 'scratch', 'lg-mock.json'), 'utf8')) : {};
const lg = {}, lgDim = {}; for (const c in lgm) { lg[c] = lgm[c].settings; lgDim[c] = lgm[c].dimension; }
const readLines = f => fs.readFileSync(f, 'utf8').split('\n').map(l => l.replace(/\r$/, '')).filter(l => l && l[0] !== '#');
const svc = readLines(path.join(root, 'tv', 'services.tsv')).map(l => { const f = l.split('|');
  return { id: f[0], group: f[1], name: f[4], desc: f[5], locked: +f[3], on: f[2] === 'on' || f[3] === '1', active: f[2] === 'on' }; });
const lists = readLines(path.join(root, 'tv', 'blocklists', 'lists.tsv')).map(l => { const f = l.split('|');
  return { id: f[0], kind: f[1], on: f[2] === 'on', name: f[3], desc: f[4], count: { lg: 83, ads: 324, trackers: 129, streaming: 34, pgl: 3563, perflyst: 498, adaway: 6500 }[f[0]] || 0, stamp: f[1] === 'remote' ? 1793000000 : 0 }; });
const cropsDir = path.join(real, 'crops'), cropsObj = {};
if (!PUBLIC && fs.existsSync(cropsDir)) for (const f of fs.readdirSync(cropsDir)) cropsObj[f.replace(/\.json$/, '.jpg')] = JSON.parse(fs.readFileSync(path.join(cropsDir, f), 'utf8'));
const mock = { '/api/apps': lp, '/api/photos': photos, iconBase: 'icons/', photoBase: 'photos/', lg: lg, lgDim: lgDim, '/api/svc': svc, '/api/gear': { gear: 'ours', pointer: 'off', chain: 'on' },
  '/api/remote': { host: 'LGwebOSTV', ethIp: '192.168.1.50', wifiIp: '', ethMac: 'aa:bb:cc:dd:ee:ff', wifiMac: '', ssh: { listening: true, port: 22, keys: 1, atBoot: true }, telnet: { listening: true, port: 23, atBoot: true }, devtools: { on: false, port: 9998 }, api: { port: 8765 } },
  '/api/wifi': { saved: { profileList: [{ wifiProfile: { profileId: 1, ssid: 'Home Wi-Fi' } }] }, status: { status: 'serviceEnabled' } },
  '/api/poweron': { dest: 'home' },
  '/api/health': { ok: true, pass: 16, warn: 1, fail: 0, checks: [{ n: 'Telnet', s: 'warn', m: 'off (fine if you switched it off with an SSH key installed)' }] },
  '/api/caps': { webos_release: 'webOS 4.5', arch: 'armv7l', ram_mb: '964', feature_launcher: 'yes', feature_boot_hook: 'yes', feature_service_stops: 'yes', feature_hosts_block: 'yes', feature_settings_key_patch: 'yes', feature_invisible_pointer: 'yes', feature_remote_emulator: 'yes', feature_self_update: 'yes', feature_memory_guard: 'yes' },
  '/api/update': { installed: '2026.10.27.1', available: '2026.10.28.1', mode: 'notify', startup: 'on', every: 12, lastAgoSec: 600, status: '', busy: false, error: '', failed: '', resultKind: '', resultVersion: '', result: '', repo: 'owner/webos4-clean-home', branch: 'main', hasBackup: true, notes: [{ v: '2026.10.28.1', date: '2026-10-28', title: 'Example update', notes: ['Something got faster.', 'Something got fixed.'] }, { v: '2026.10.27.1', date: '2026-10-27', title: 'Software updates', notes: ['The TV can now update itself from GitHub.'] }] },
  '/api/appupdates': { mode: 'auto', startup: 'on', every: 6, pending: ['com.peacock.tv'], lastCheckAgoSec: 1800, apps: [['Apple TV', 'com.apple.appletv', '17.0.3'], ['Disney+', 'com.disney.disneyplus-prod', '24.5.8'], ['HBO Max', 'com.wbd.stream', '7.8.0'], ['Hulu', 'hulu', '7.0.6'], ['Netflix', 'netflix', '1.3.5'], ['Peacock', 'com.peacock.tv', '6.4.202'], ['Prime Video', 'amazon', '4.5.25'], ['Spotify', 'spotify-beehive', '2.0.37'], ['YouTube', 'youtube.leanback.v4', '1.0.18']].map(a => ({ title: a[0], id: a[1], version: a[2], pending: a[1] === 'com.peacock.tv' })) },
  '/api/block': { blocked: 4414, custom: 0, allowCustom: 0, lists: lists }, '/api/crops': cropsObj,
  '/api/sysinfo': { uptime: 5400, mem: { totalMB: 964, availMB: 365, swapUsedMB: 235 }, procs: 261, guard: { running: true, profile: 'standard', setting: 'auto', totalMB: 964, availMB: 365, swapUsedMB: 235, swapTotalMB: 699, level: 'ok', minAvailMB: 171, maxSwapMB: 240, lowEpisodes: 0, criticalEpisodes: 0, lastAction: '' }, lg: { modelName: 'UM7300PUA', firmwareVersion: '05.40.97', sdkVersion: '4.5.0' } },
  '/api/net': { returnValue: true, isInternetConnectionAvailable: true, wired: { state: 'connected', ipAddress: '192.168.1.50' }, wifi: { state: 'disconnected' } },
  '/api/ready': { ok: true }, '/api/launch': { returnValue: true } };
fs.writeFileSync(path.join(pv, 'mock.js'), 'window.__MOCK__=' + JSON.stringify(mock) + ';');
for (const f of ['app.js','qr.js','stage.js','phone.html']) if (fs.existsSync(path.join(root,'tv','launcher',f))) fs.copyFileSync(path.join(root,'tv','launcher',f), path.join(pv,f));
if (PUBLIC) { let a = fs.readFileSync(path.join(pv, 'app.js'), 'utf8'); a = a.replace(/fallbackPlace: \{[^}]*\}/, "fallbackPlace: {lat: 39.78, lon: -89.65, place: 'Springfield'}").replace('https://ipwho.is/', 'https://invalid.invalid/'); fs.writeFileSync(path.join(pv, 'app.js'), a); }
fs.writeFileSync(path.join(pv, 'index.html'), fs.readFileSync(path.join(root, 'tv', 'launcher', 'index.html'), 'utf8').replace('<!--MOCK-->', '<script src="mock.js"></script><style>*{transition:none !important}</style>'));
const name = process.argv[2] || 'home', query = process.argv[3] || 'mock=1';
const browsers = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'];
const b = browsers.find(fs.existsSync);
if (!b) { console.error('no Edge/Chrome found'); process.exit(1); }
const out = path.join(root, 'shots', name + '.png');
fs.mkdirSync(path.dirname(out), { recursive: true });
const url = 'file:///' + path.join(pv, 'index.html').replace(/\\/g, '/') + '?' + query;
if (PUBLIC) fs.rmSync(path.join(pv, '.profile'), { recursive: true, force: true });      // no cached weather place / settings from earlier runs
cp.spawnSync(b, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--window-size=1920,1080', '--force-device-scale-factor=1',
  '--virtual-time-budget=' + (process.env.BUDGET || '4000'), '--screenshot=' + out, '--user-data-dir=' + path.join(pv, '.profile'), url], { stdio: 'inherit', timeout: 60000 });
console.log(fs.existsSync(out) ? 'wrote ' + out : 'screenshot failed');
