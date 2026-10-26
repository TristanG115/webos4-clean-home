#!/usr/bin/env node
// bench-compare.js [labels...] - markdown table from results/*.txt (output of bench.sh). Default: every label found, in file order.
//   node tools/bench-compare.js baseline debloat-only after-fresh after-steady
const fs = require('fs'), path = require('path');
const dir = path.resolve(__dirname, '..', 'results');
const data = {};
for (const f of fs.readdirSync(dir).filter(f => /\.txt$/.test(f) && !/^snap/.test(f)).sort()) {
  for (const line of fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/)) {
    const m = line.match(/^([\w-]+)\.([\w.+-]+)=(.*)$/); if (!m) continue;
    (data[m[1]] = data[m[1]] || {})[m[2]] = m[3].trim();
  }
}
const labels = process.argv.length > 2 ? process.argv.slice(2) : Object.keys(data);
const med = s => { const n = String(s).split(/\s+/).map(Number).filter(x => !isNaN(x)).sort((a, b) => a - b); return n.length ? n[Math.floor(n.length / 2)] : null; };
const rows = [
  ['Home, cold start (median ms)', 'launch_visible_ms_home', med, 'lower'],
  ['Settings opens (median ms)', 'launch_visible_ms_com.palm.app.settings', med, 'lower'],
  ['YouTube opens (median ms)', 'launch_visible_ms_youtube.leanback.v4', med, 'lower'],
  ['Netflix opens (median ms)', 'launch_visible_ms_netflix', med, 'lower'],
  ['Swap in use (MB)', 'swap_used_mb', Number, 'lower'],
  ['RAM available (MB)', 'mem_avail_mb', Number, 'higher'],
  ['RAM free (MB)', 'mem_free_mb', Number, 'higher'],
  ['Processes', 'procs', Number, 'lower'],
  ['CPU idle (%)', 'cpu_idle', Number, 'higher'],
  ['Interrupts / s', 'vm_irq_s', Number, 'lower'],
  ['Context switches / s', 'vm_ctx_s', Number, 'lower'],
  ['Luna round trip (ms)', 'luna_rtt_ms', Number, 'lower'],
  ['300 fork+exec (ms)', 'fork300_ms', Number, 'lower'],
  ['Uptime at test (min)', 'uptime_s', v => Math.round(Number(v) / 60), null],
];
const out = ['| Metric | ' + labels.join(' | ') + ' |', '|---|' + labels.map(() => '---:').join('|') + '|'];
for (const [name, key, fn] of rows) {
  const cells = labels.map(l => { const v = data[l] && data[l][key]; if (v === undefined) return '–'; if (/NA|TIMEOUT/.test(v) && fn === med) { const r = med(v.replace(/NA|TIMEOUT/g, '')); return r === null ? 'n/a' : String(r); } const r = fn(v); return r === null || isNaN(r) ? 'n/a' : String(r); });
  out.push('| ' + name + ' | ' + cells.join(' | ') + ' |');
}
const ads = labels.map(l => data[l] ? 'ad impressions logged since boot: ' + (data[l].admanager_impressions_since_boot || '–') + ', requests: ' + (data[l].admanager_requests_since_boot || '–') : '');
console.log(out.join('\n') + '\n\n' + labels.map((l, i) => '- **' + l + '**: ' + ads[i]).join('\n'));
