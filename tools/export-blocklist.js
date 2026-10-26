#!/usr/bin/env node
// export-blocklist.js - the built-in ad / tracker / telemetry lists in tv/blocklists/ as files a ROUTER or Pi-hole / AdGuard Home can use.
// This is the no-root way to get the ad blocking: every TV on the network benefits, and nothing is installed on the TV.
//   node tools/export-blocklist.js            -> dist/blocklist-domains.txt   one name per line (Pi-hole "Adlists", plain list)
//                                                dist/blocklist-hosts.txt     0.0.0.0 name        (hosts-file format, dnsmasq addn-hosts)
//                                                dist/blocklist-adguard.txt   ||name^             (AdGuard Home custom filter)
//                                                dist/update-servers.txt      LG firmware update servers, kept apart: block them too if you want updates off network-wide
// Names in tv/blocklists/allow.txt (never blocked) are left out. Note: LG's firmware/update servers are NOT in these files on purpose; see rootless/README.md.
const fs = require('fs'), path = require('path');
const dir = path.join(__dirname, '..', 'tv', 'blocklists'), out = path.join(__dirname, '..', 'dist');
const lines = f => fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split(/\r?\n/).map(l => l.replace(/#.*/, '').trim().toLowerCase()).filter(Boolean) : [];
const allow = new Set(lines(path.join(dir, 'allow.txt')));
const cat = lines(path.join(dir, 'lists.tsv')).map(l => l.split('|')).filter(c => c[1] === 'builtin' && c[2] === 'on');
const names = new Set();
for (const c of cat) for (const n of lines(path.join(dir, c[0] + '.txt'))) if (/^[a-z0-9_-]+(\.[a-z0-9_-]+)+$/.test(n) && !allow.has(n)) names.add(n);
const list = [...names].sort();
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'blocklist-domains.txt'), list.join('\n') + '\n');
fs.writeFileSync(path.join(out, 'blocklist-hosts.txt'), list.map(n => '0.0.0.0 ' + n).join('\n') + '\n');
fs.writeFileSync(path.join(out, 'blocklist-adguard.txt'), list.map(n => '||' + n + '^').join('\n') + '\n');
// LG firmware update servers (what the rooted install blocks with its 'updates' item): a separate file so you choose
fs.writeFileSync(path.join(out, 'update-servers.txt'), ['snu.lge.com', 'snu-dev.lge.com', 'su.lge.com', 'su-dev.lge.com', 'su-ssl.lge.com', 'nsu.lge.com'].join(String.fromCharCode(10)) + String.fromCharCode(10));
console.log(list.length + ' names from ' + cat.map(c => c[0]).join(', ') + ' -> ' + out);
