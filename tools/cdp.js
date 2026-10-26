#!/usr/bin/env node
// cdp.js - tiny Chrome DevTools Protocol client for the TV's web app manager (remote debugging port 9998).
//   node tools/cdp.js list
//   node tools/cdp.js eval  <title-or-url-substring> "<js expression>"
//   node tools/cdp.js shot  <title-or-url-substring> out.jpg [quality]
//   node tools/cdp.js logs  <title-or-url-substring> [seconds]      (console + exceptions, then exit)
//   node tools/cdp.js key   <title-or-url-substring> <keyCode> [count]   (inject a remote-control key press)
//   node tools/cdp.js reload <title-or-url-substring>
const fs = require('fs');
const HOST = process.env.TV_HOST || (() => { try { return /^TV_IP=(\S+)/m.exec(require('fs').readFileSync(require('path').join(__dirname, '..', 'tv.conf'), 'utf8'))[1]; } catch (e) { console.error('Set TV_HOST or create tv.conf (see tv.conf.example)'); process.exit(2); } })();
const PORT = process.env.TV_CDP_PORT || '9998';

async function pages() {
  const r = await fetch(`http://${HOST}:${PORT}/json`, { signal: AbortSignal.timeout(8000) });
  return r.json();
}
function pick(list, q) {
  q = (q || '').toLowerCase();
  return list.filter(p => p.type === 'page' && ((p.title || '') + ' ' + p.url).toLowerCase().includes(q));
}
function connect(page) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(page.webSocketDebuggerUrl.replace('127.0.0.1', HOST));
    let id = 0; const waiting = {}; const listeners = [];
    ws.onopen = () => resolve({
      send: (method, params = {}) => new Promise((res, rej) => {
        const i = ++id; waiting[i] = [res, rej];
        ws.send(JSON.stringify({ id: i, method, params }));
        const t = setTimeout(() => { if (waiting[i]) { delete waiting[i]; rej(new Error('timeout ' + method)); } }, 20000);
        waiting[i].push(t);
      }),
      on: f => listeners.push(f),
      close: () => ws.close(),
    });
    ws.onerror = e => reject(new Error('ws error ' + (e.message || '')));
    ws.onmessage = m => {
      const d = JSON.parse(m.data);
      if (d.id && waiting[d.id]) { const [res, rej, t] = waiting[d.id]; clearTimeout(t); delete waiting[d.id]; d.error ? rej(new Error(JSON.stringify(d.error))) : res(d.result); }
      else listeners.forEach(f => f(d));
    };
  });
}

(async () => {
  const [cmd, q, a, b] = process.argv.slice(2);
  const list = await pages();
  if (cmd === 'list') { list.forEach(p => console.log(`${p.type}\t${p.title}\t${p.url}`)); return; }
  const m = pick(list, q);
  if (!m.length) { console.error('no page matches "' + q + '"; have: ' + list.map(p => p.title || p.url).join(' | ')); process.exit(2); }
  const c = await connect(m[0]);
  if (cmd === 'eval') {
    const r = await c.send('Runtime.evaluate', { expression: a, returnByValue: true, awaitPromise: false });
    console.log(r.exceptionDetails ? 'EXCEPTION ' + JSON.stringify(r.exceptionDetails) : JSON.stringify(r.result.value === undefined ? r.result : r.result.value, null, 1));
  } else if (cmd === 'shot') {
    const r = await c.send('Page.captureScreenshot', { format: 'jpeg', quality: parseInt(b || '80', 10) });
    fs.writeFileSync(a, Buffer.from(r.data, 'base64')); console.log('wrote ' + a);
  } else if (cmd === 'logs') {
    await c.send('Runtime.enable'); await c.send('Log.enable');
    c.on(d => {
      if (d.method === 'Runtime.consoleAPICalled') console.log('[console.' + d.params.type + ']', d.params.args.map(x => x.value !== undefined ? x.value : x.description).join(' '));
      if (d.method === 'Runtime.exceptionThrown') console.log('[exception]', JSON.stringify(d.params.exceptionDetails).slice(0, 600));
      if (d.method === 'Log.entryAdded') console.log('[log]', d.params.entry.level, d.params.entry.text, d.params.entry.url || '');
    });
    await new Promise(r => setTimeout(r, (parseFloat(a) || 5) * 1000));
  } else if (cmd === 'key') {
    const code = parseInt(a, 10), n = parseInt(b || '1', 10);
    for (let i = 0; i < n; i++) {
      for (const type of ['rawKeyDown', 'keyUp'])
        await c.send('Input.dispatchKeyEvent', { type, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code, key: String(code) });
      await new Promise(r => setTimeout(r, 120));
    }
    console.log('sent key ' + code + ' x' + n);
  } else if (cmd === 'reload') {
    await c.send('Page.reload'); console.log('reloaded');
  }
  c.close();
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
