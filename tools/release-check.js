// release-check.js - the TV's self-update reads tv/VERSION and tv/notes.json from GitHub. This proves they are consistent before a push.
//   node tools/release-check.js            exit 1 with a list of problems, 0 when everything is fine
// Rules (also in AGENTS.md section 11): newest entry first, tv/VERSION == notes[0].v, versions strictly increasing from the bottom, every entry has
// v (YYYY.MM.DD.N), date, title, and 1+ plain-language notes. The page and the shell scripts are syntax-checked too, because the TV refuses a broken tree.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const root = path.join(__dirname, '..'), bad = [];
const ver = fs.readFileSync(path.join(root, 'tv', 'VERSION'), 'utf8').trim();
let notes = [];
try { notes = JSON.parse(fs.readFileSync(path.join(root, 'tv', 'notes.json'), 'utf8')); } catch (e) { bad.push('tv/notes.json is not valid JSON: ' + e.message); }
const num = v => v.split('.').map(Number);
const cmp = (a, b) => { const x = num(a), y = num(b); for (let i = 0; i < Math.max(x.length, y.length); i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return d; } return 0; };
if (!/^\d{4}\.\d{2}\.\d{2}\.\d+$/.test(ver)) bad.push('tv/VERSION must look like 2026.10.27.1 (YYYY.MM.DD.N), got "' + ver + '"');
if (!Array.isArray(notes) || !notes.length) bad.push('tv/notes.json must be a non-empty array');
else {
  if (notes[0].v !== ver) bad.push('tv/VERSION (' + ver + ') must equal the newest note (' + notes[0].v + '), which must be first');
  notes.forEach((n, i) => {
    if (!/^\d{4}\.\d{2}\.\d{2}\.\d+$/.test(n.v || '')) bad.push('note ' + i + ': bad v');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(n.date || '')) bad.push('note ' + (n.v || i) + ': date must be YYYY-MM-DD');
    if (!n.title) bad.push('note ' + (n.v || i) + ': missing title');
    if (!Array.isArray(n.notes) || !n.notes.length || n.notes.some(t => typeof t !== 'string' || !t.trim())) bad.push('note ' + (n.v || i) + ': notes must be a list of sentences');
    if (i && cmp(notes[i - 1].v, n.v) <= 0) bad.push('note ' + n.v + ' must be older than the one above it');
  });
}
try { cp.execFileSync(process.execPath, ['--check', path.join(root, 'tv', 'launcher', 'app.js')], { stdio: 'pipe' }); } catch (e) { bad.push('tv/launcher/app.js: ' + String(e.stderr).split('\n')[0]); }
for (const f of fs.readdirSync(path.join(root, 'tv')).filter(f => f.endsWith('.sh') || f === 'zz-debloat')) {
  const t = fs.readFileSync(path.join(root, 'tv', f), 'utf8'); if (/\r/.test(t)) bad.push('tv/' + f + ' has CRLF line endings');
  try { cp.execFileSync('sh', ['-n', path.join(root, 'tv', f)], { stdio: 'pipe' }); } catch (e) { if (e.code !== 'ENOENT') bad.push('tv/' + f + ': ' + String(e.stderr).split('\n')[0]); }
}
if (bad.length) { console.error('release-check: ' + bad.length + ' problem(s)\n - ' + bad.join('\n - ')); process.exit(1); }
console.log('release-check: OK, version ' + ver + ', ' + notes.length + ' change note(s)');
