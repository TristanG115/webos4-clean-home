/* Home launcher logic for LG webOS 4.x (Chromium 53): ES5 style on purpose.
   Two modes share this file: Home (index.html) and the Settings overlay (settings.html, opened by the remote's Settings key). */
(function(){
'use strict';
var T0 = Date.now();

/* ================= configuration & settings ================= */
var API = 'http://127.0.0.1:8765';
var MOCK = window.__MOCK__ || null;
var MODE = window.__MODE__ || 'home';
if (MOCK && /mode=settings/.test(location.search)) MODE = 'settings';
if (MOCK && /mode=inputs/.test(location.search)) MODE = 'inputs';
var INPMODE = MODE === 'inputs';          // the Inputs overlay: only the Inputs panel (replaces LG's input picker)
var SETMODE = MODE === 'settings' || INPMODE;   // both overlays share the "no Home behaviour" switches
var CFG = {
  glow: {'netflix':'#e50914','youtube.leanback.v4':'#ff1f3d','hulu':'#1ce783','com.disney.disneyplus-prod':'#2a5bff','amazon':'#00a8e1',
         'com.apple.appletv':'#9aa3b5','com.wbd.stream':'#5b3dff','com.peacock.tv':'#f5c518','spotify-beehive':'#1db954','com.plutotv.app':'#fff200','com.tubitv.ott.tubi':'#7a2bff'},
  inputs: [['com.webos.app.hdmi1','HDMI 1'],['com.webos.app.hdmi2','HDMI 2'],['com.webos.app.hdmi3','HDMI 3'],['com.webos.app.hdmi4','HDMI 4'],
           ['com.webos.app.externalinput.av1','AV'],['com.webos.app.externalinput.component','Component'],['com.webos.app.livetv','Live TV']],
  fallbackPlace: {lat: 40.4259, lon: -86.9081, place: 'West Lafayette'}
};
// user settings, stored on the TV in state/settings.json (edited here, on the phone page, or by hand)
var DEFAULTS = {
  weather: {mode: 'auto', zip: '', unit: 'F'},
  clock24: false,
  bg: {on: true, everyMin: 10},
  saver: {on: true, idleMin: 2, photos: true, slideSec: 12, weather: true, dim: 30, backlight: 50},
  ui: {hideCursor: true},
  dock: ['netflix','youtube.leanback.v4','hulu','com.disney.disneyplus-prod'],
  hide: ['webos.day','com.webos.app.homeconnect','com.webos.app.home','com.webos.app.fullhome']
};
var S = clone(DEFAULTS);

function $(id){ return document.getElementById(id); }
function clone(o){ return JSON.parse(JSON.stringify(o)); }
function merge(d, s){ for (var k in s) { if (s[k] && typeof s[k] === 'object' && !(s[k] instanceof Array)) { if (!d[k] || typeof d[k] !== 'object') d[k] = {}; merge(d[k], s[k]); } else d[k] = s[k]; } return d; }
function el(tag, cls, html){ var e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
function p2(n){ return n < 10 ? '0' + n : '' + n; }
function lsGet(k){ try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch(e){ return null; } }
function lsSet(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch(e){} }
function noop(){}
function cls(e, c, on){ var has = (' ' + e.className + ' ').indexOf(' ' + c + ' ') >= 0; if (on && !has) e.className += (e.className ? ' ' : '') + c; else if (!on && has) e.className = (' ' + e.className + ' ').replace(' ' + c + ' ', ' ').replace(/^ +| +$/g, '').replace(/ {2,}/g, ' '); }

/* ================= http / api ================= */
function xhr(method, url, body, cb, timeout){
  if (window.__TVAPI__ && url.indexOf(API) === 0) { window.__TVAPI__(method, url.slice(API.length), body, cb); return; }      // rootless build (rootless.js): no local API
  var x = new XMLHttpRequest(); x.open(method, url, true); x.timeout = timeout || 10000;
  x.onload = function(){ var j = null; try { j = JSON.parse(x.responseText); } catch(e){} cb(x.status >= 200 && x.status < 300 ? null : new Error('HTTP ' + x.status), j); };
  x.onerror = x.ontimeout = function(){ cb(new Error('net'), null); };
  x.send(body || null);
}
function mockFor(path){
  var q = path.split('?'), p = q[0];
  if (p === '/api/lg/get') { var m = /cat=(\w+)/.exec(q[1] || ''); var d = (MOCK.lg || {})[m ? m[1] : ''] || {}; return {returnValue: true, settings: d, dimension: (MOCK.lgDim || {})[m ? m[1] : ''] || {}}; }
  return MOCK[p] !== undefined ? MOCK[p] : {};
}
function api(path, cb, timeout){ if (MOCK) { setTimeout(function(){ cb(null, clone(mockFor(path))); }, 15); return; } xhr('GET', API + path, null, cb, timeout || 12000); }
function apiPost(path, body, cb, timeout){ if (MOCK) { setTimeout(function(){ (cb || noop)(null, mockFor(path.split('?')[0]) || {ok: true, returnValue: true}); }, 15); return; } xhr('POST', API + path, body, cb || noop, timeout || 12000); }
var logN = 0;
function dlog(m){ if (MOCK || logN++ > 200) return; try { xhr('POST', API + '/api/log', String(m), noop, 3000); } catch(e){} }
window.onerror = function(m, u, l){ dlog('JSERR ' + m + ' @' + l); };
function toast(m){ var t = $('toast'); t.textContent = m; t.className = 'on'; clearTimeout(toast.h); toast.h = setTimeout(function(){ t.className = ''; }, 3200); }
// a note on Home when a newer version of this project is on GitHub (selfupdate.sh keeps the facts; this only reads them) and the result of the last install
function updPoll(){
  api('/api/update', function(err, j){
    var p = $('updpill'); if (err || !j) return;
    if (j.resultKind && !document.hidden) { toast(j.result || ''); api('/api/update/conf?k=ack&v=1', noop); }
    if (j.available && !j.busy) { p.innerHTML = 'Update <b></b> is ready &nbsp;·&nbsp; Settings › Software updates'; p.querySelector('b').textContent = j.available; p.className = 'on'; } else p.className = '';
  }, 8000);
}
// held keys repeat quickly: the longer a key is held the bigger the step (sliders, framing editor)
var lastKey = 0, lastKeyAt = 0, keyRun = 0;
function boost(k){ var n = Date.now(); if (k === lastKey && n - lastKeyAt < 160) keyRun++; else keyRun = 0; lastKey = k; lastKeyAt = n; return keyRun < 4 ? 1 : keyRun < 12 ? 3 : 6; }

/* ================= settings store ================= */
var saveT = null;
function saveSettings(){
  clearTimeout(saveT);
  saveT = setTimeout(function(){ saveT = null; apiPost('/api/settings', JSON.stringify(S), function(err){ if (err) dlog('settings save failed'); }); }, 400);
}
function setPath(path, v){ var p = path.split('.'), o = S; for (var i = 0; i < p.length - 1; i++) o = o[p[i]]; o[p[p.length - 1]] = v; saveSettings(); settingsChanged(path); }
function getPath(path){ var p = path.split('.'), o = S; for (var i = 0; i < p.length; i++) o = o[p[i]]; return o; }
function applyUi(){ cls(document.body, 'nocursor', !!(S.ui && S.ui.hideCursor)); }
function settingsChanged(path){
  if (SETMODE) { if (path.indexOf('ui.') === 0) applyUi(); return; }
  if (path.indexOf('weather.') === 0) wxLoad(true);
  if (path.indexOf('clock24') === 0) { lastT = ''; tick(); }
  if (path.indexOf('bg.') === 0) { bgApply(true); }
  if (path.indexOf('saver.') === 0) activity();
  if (path.indexOf('ui.') === 0) applyUi();
}
function applyRemoteSettings(j){
  if (!j || typeof j !== 'object') return;
  var n = merge(clone(DEFAULTS), j), a = JSON.stringify(n), b = JSON.stringify(S);
  if (a === b || saveT) return;      // unchanged, or we have an unsaved local edit
  var wxCh = JSON.stringify(n.weather) !== JSON.stringify(S.weather), bgCh = JSON.stringify(n.bg) !== JSON.stringify(S.bg);
  S = n; applyUi();
  if (SETMODE) { if (settingsOn) renderCat(false); return; }
  lastT = ''; tick(); if (wxCh) wxLoad(true); if (bgCh) bgApply(true); activity(); if (settingsOn) renderCat(false);
}
function loadSettings(cb){ api('/api/settings', function(err, j){ if (!err) applyRemoteSettings(j); if (cb) cb(); }); }

/* ================= clock ================= */
var DAYS = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'], MONS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
function fmtTime(d){ var h = d.getHours(), ap = ''; if (!S.clock24) { ap = h >= 12 ? 'PM' : 'AM'; h = h % 12; if (h === 0) h = 12; } else h = p2(h); return {t: h + ':' + p2(d.getMinutes()), ap: ap}; }
function fmtDate(d){ return DAYS[d.getDay()] + ', ' + MONS[d.getMonth()] + ' ' + d.getDate(); }
function fmtShort(d){ return DAYS[d.getDay()].slice(0, 3) + ', ' + MONS[d.getMonth()].slice(0, 3) + ' ' + d.getDate(); }
var lastT = '', lastD = '';
function tick(){
  var d = new Date(), f = fmtTime(d), ds = fmtDate(d), ts = f.t + ' ' + f.ap;
  if (ts !== lastT) { lastT = ts; $('time').innerHTML = f.t + (f.ap ? '<small>' + f.ap + '</small>' : ''); if (saverOn) $('sinfo').firstChild.innerHTML = f.t + (f.ap ? '<small>' + f.ap + '</small>' : ''); }
  if (ds !== lastD) { lastD = ds; $('date').textContent = ds; if (saverOn) $('sinfo').childNodes[1].textContent = ds; wxRender(); }
}

/* ================= weather (auto location by IP, or ZIP) ================= */
var WX = {
  sun:'<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="9" fill="#ffc83d"/><g stroke="#ffc83d" stroke-width="3" stroke-linecap="round"><path d="M24 4v6M24 38v6M4 24h6M38 24h6M9.9 9.9l4.2 4.2M33.9 33.9l4.2 4.2M9.9 38.1l4.2-4.2M33.9 14.1l4.2-4.2"/></g></svg>',
  moon:'<svg viewBox="0 0 48 48"><path d="M32 6a18 18 0 1 0 10 28A15 15 0 0 1 32 6z" fill="#cfd8ff"/></svg>',
  part:'<svg viewBox="0 0 48 48"><circle cx="18" cy="18" r="8" fill="#ffc83d"/><path d="M16 38a8 8 0 0 1 1-16 11 11 0 0 1 21 3 6.5 6.5 0 0 1-1 13z" fill="#e9eef7"/></svg>',
  cloud:'<svg viewBox="0 0 48 48"><path d="M13 38a9 9 0 0 1 1-18 12 12 0 0 1 23 3 7.5 7.5 0 0 1-1 15z" fill="#cdd5e3"/></svg>',
  rain:'<svg viewBox="0 0 48 48"><path d="M13 30a9 9 0 0 1 1-18 12 12 0 0 1 23 3 7.5 7.5 0 0 1-1 15z" fill="#aab4c8"/><g stroke="#5aa9ff" stroke-width="3" stroke-linecap="round"><path d="M16 36l-2 6M25 36l-2 6M34 36l-2 6"/></g></svg>',
  snow:'<svg viewBox="0 0 48 48"><path d="M13 30a9 9 0 0 1 1-18 12 12 0 0 1 23 3 7.5 7.5 0 0 1-1 15z" fill="#aab4c8"/><g fill="#fff"><circle cx="15" cy="39" r="2.2"/><circle cx="25" cy="41" r="2.2"/><circle cx="35" cy="39" r="2.2"/></g></svg>',
  storm:'<svg viewBox="0 0 48 48"><path d="M13 30a9 9 0 0 1 1-18 12 12 0 0 1 23 3 7.5 7.5 0 0 1-1 15z" fill="#8c97ad"/><path d="M26 28l-7 11h6l-2 8 9-13h-6z" fill="#ffc83d"/></svg>',
  fog:'<svg viewBox="0 0 48 48"><g stroke="#b8c1d3" stroke-width="3.5" stroke-linecap="round"><path d="M8 17h32M12 25h28M8 33h32"/></g></svg>'
};
function wxDecode(code, isDay){
  if (code === 0) return [isDay ? 'sun' : 'moon', 'Clear'];
  if (code === 1 || code === 2) return [isDay ? 'part' : 'cloud', code === 1 ? 'Mostly clear' : 'Partly cloudy'];
  if (code === 3) return ['cloud', 'Cloudy'];
  if (code === 45 || code === 48) return ['fog', 'Fog'];
  if (code >= 51 && code <= 57) return ['rain', 'Drizzle'];
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return ['rain', 'Rain'];
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return ['snow', 'Snow'];
  if (code >= 95) return ['storm', 'Thunderstorms'];
  return ['cloud', 'Cloudy'];
}
var wx = null, wxAt = 0;
function wxRender(){
  if (!wx) return;
  var d = wxDecode(wx.code, wx.day), now = new Date(), hl = wx.hi != null ? 'H ' + Math.round(wx.hi) + '°  L ' + Math.round(wx.lo) + '°  ·  ' : '';
  $('wicon').innerHTML = WX[d[0]] || '';
  $('wtemp').innerHTML = Math.round(wx.temp) + '°<small>' + d[1] + '</small>';
  $('wdesc').textContent = fmtShort(now) + '  ·  ' + hl + wx.place;
  $('weather').className = 'on';
  var w = $('sinfo').childNodes[2];
  w.innerHTML = (WX[d[0]] || '') + '<span>' + Math.round(wx.temp) + '° ' + d[1] + '</span><span class="p">' + hl + wx.place + '</span>';
  w.className = 'w' + (S.saver.weather ? ' on' : '');
  if (settingsOn && cats[catIdx] && cats[catIdx].id === 'weather' && !wxRender.busy) { wxRender.busy = true; renderCat(false); wxRender.busy = false; }
}
function geoResolve(cb){
  var w = S.weather, key = w.mode === 'zip' ? 'zip:' + w.zip : 'auto', c = lsGet('loc');
  if (c && c.key === key && (key !== 'auto' || Date.now() - c.at < 86400000)) return cb(c);
  function done(l){ l.key = key; l.at = Date.now(); lsSet('loc', l); cb(l); }
  function fallback(){ cb((c && c.key === key ? c : null) || {lat: CFG.fallbackPlace.lat, lon: CFG.fallbackPlace.lon, place: CFG.fallbackPlace.place, key: key, at: 0}); }
  if (MOCK) return cb({lat: CFG.fallbackPlace.lat, lon: CFG.fallbackPlace.lon, place: CFG.fallbackPlace.place, key: key});
  if (w.mode === 'zip') {
    if (!/^\d{5}$/.test(w.zip)) return fallback();
    xhr('GET', 'https://api.zippopotam.us/us/' + w.zip, null, function(err, j){
      if (err || !j || !j.places || !j.places[0]) { toast('ZIP code ' + w.zip + ' not found'); return fallback(); }
      var p = j.places[0]; done({lat: parseFloat(p.latitude), lon: parseFloat(p.longitude), place: p['place name'] + ', ' + p['state abbreviation']});
    }, 10000);
  } else {
    xhr('GET', 'https://ipwho.is/', null, function(err, j){
      if (!err && j && j.success && j.latitude) return done({lat: j.latitude, lon: j.longitude, place: j.city || 'Here'});
      xhr('GET', 'https://ipapi.co/json/', null, function(e2, k){
        if (!e2 && k && k.latitude) return done({lat: k.latitude, lon: k.longitude, place: k.city || 'Here'});
        fallback();
      }, 10000);
    }, 10000);
  }
}
function wxLoad(force){
  if (!force && Date.now() - wxAt < 10 * 60000) return;
  geoResolve(function(l){
    var unit = S.weather.unit === 'C' ? 'celsius' : 'fahrenheit';
    if (MOCK) { wx = {temp: 61, code: 2, day: 1, hi: 66, lo: 48, place: l.place}; wxAt = Date.now(); return wxRender(); }
    var u = 'https://api.open-meteo.com/v1/forecast?latitude=' + l.lat + '&longitude=' + l.lon + '&current_weather=true&daily=temperature_2m_max,temperature_2m_min' +
            '&temperature_unit=' + unit + '&timezone=auto&forecast_days=1';
    xhr('GET', u, null, function(err, j){
      if (err || !j || !j.current_weather) { dlog('weather failed ' + (err && err.message)); return; }
      var cw = j.current_weather;
      wx = {temp: cw.temperature, code: cw.weathercode, day: cw.is_day === 1, place: l.place,
            hi: j.daily && j.daily.temperature_2m_max ? j.daily.temperature_2m_max[0] : null, lo: j.daily && j.daily.temperature_2m_min ? j.daily.temperature_2m_min[0] : null};
      wxAt = Date.now(); lsSet('wx', {wx: wx, at: wxAt, unit: unit}); wxRender();
    }, 15000);
  });
}
(function(){ var c = lsGet('wx'); if (c && c.wx) { wx = c.wx; wxAt = c.at; } })();

/* ================= apps, tiles, focus ================= */
var apps = [], rows = [], R = 0, C = 0, lastX = null, viewY = 0;
function iconUrl(p){ if (!p) return ''; if (p.charAt(0) !== '/') return p; return MOCK && MOCK.iconBase ? MOCK.iconBase + p.split('/').slice(-2).join('_') : 'file://' + encodeURI(p); }
function glowFor(a){
  if (!a) return '#3a4a78'; if (CFG.glow[a.id]) return CFG.glow[a.id];
  var c = a.iconColor || a.bgColor || '';
  if (/^#[0-9a-f]{6}$/i.test(c) && c.toLowerCase() !== '#ffffff' && c.toLowerCase() !== '#000000') return c;
  var h = 0, s = a.id || ''; for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360; return 'hsl(' + h + ',70%,55%)';
}
function mkTile(a, big){
  var t = el('div', 'tile ' + (big ? 'big' : 'sm')), ic = el('div', 'ic'), img = el('img'); img.alt = ''; img.src = iconUrl(a.largeIcon || a.icon);
  ic.appendChild(img); ic.appendChild(el('div', 'ring')); t.appendChild(ic);
  var nm = el('div', 'nm'); nm.textContent = a.title || a.id; t.appendChild(nm); t._app = a; return t;
}
function buildApps(list){
  var dock = $('dock'), grid = $('grid'); dock.innerHTML = ''; grid.innerHTML = '';
  var byId = {}, inDock = {}; list.forEach(function(a){ byId[a.id] = a; });
  S.dock.forEach(function(id){ if (byId[id]) { dock.appendChild(mkTile(byId[id], true)); inDock[id] = 1; } });
  list.forEach(function(a){ if (inDock[a.id] || S.hide.indexOf(a.id) >= 0 || a.visible === false) return; grid.appendChild(mkTile(a, false)); });
  layoutRows();
}
function layoutRows(){
  var hb = [$('b-inputs'), $('b-net'), $('b-settings')], dock = [].slice.call($('dock').children), g = [].slice.call($('grid').children), gr = [], top = -1;
  g.forEach(function(t){ if (t.offsetTop !== top) { gr.push([]); top = t.offsetTop; } gr[gr.length - 1].push(t); });
  rows = [hb, dock].concat(gr).filter(function(r){ return r.length; });
  if (R >= rows.length) R = rows.length - 1; if (C >= rows[R].length) C = rows[R].length - 1;
}
function loadApps(cb){
  api('/api/apps', function(err, j){
    if (err || !j || !j.launchPoints) { dlog('apps failed ' + (err && err.message)); if (cb) cb(false); return; }
    apps = j.launchPoints; buildApps(apps); if (cb) cb(true);
  });
}
var lastFocus = null, glowSide = 0;
function setGlow(color){
  var a = $('glowA'), b = $('glowB'), n = glowSide ? a : b, o = glowSide ? b : a; glowSide = 1 - glowSide;
  n.style.background = 'radial-gradient(ellipse at 50% 0%, ' + color + ' 0%, rgba(0,0,0,0) 62%)'; n.className = 'on'; o.className = '';
}
function focusItem(r, c, keepX){
  if (!rows.length) return;
  R = Math.max(0, Math.min(rows.length - 1, r)); C = Math.max(0, Math.min(rows[R].length - 1, c));
  var e = rows[R][C];
  if (lastFocus && lastFocus !== e) lastFocus.className = lastFocus.className.replace(' foc', '');
  if (e.className.indexOf(' foc') < 0) e.className += ' foc';
  lastFocus = e;
  if (!keepX) { var rc = e.getBoundingClientRect(); lastX = rc.left + rc.width / 2; }
  setGlow(glowFor(e._app));
  var rc2 = e.getBoundingClientRect(), vh = window.innerHeight, fs = parseFloat(getComputedStyle(document.documentElement).fontSize);
  var bottom = rc2.bottom + viewY + 5 * fs, want = bottom > vh ? bottom - vh : 0;
  if (R <= 1) want = 0;
  viewY = want; $('view').style.transform = want ? 'translate3d(0,' + (-want) + 'px,0)' : 'translate3d(0,0,0)';
}
function move(dir){
  var r = R, c = C;
  if (dir === 'L' || dir === 'R') { c += dir === 'L' ? -1 : 1; if (c < 0 || c >= rows[R].length) return; focusItem(R, c); return; }
  r += dir === 'U' ? -1 : 1; if (r < 0 || r >= rows.length) return;
  var best = 0, bd = 1e9, x = lastX == null ? 0 : lastX;
  for (var i = 0; i < rows[r].length; i++) { var rc = rows[r][i].getBoundingClientRect(), d = Math.abs(rc.left + rc.width / 2 - x); if (d < bd) { bd = d; best = i; } }
  focusItem(r, best, true);
}
function launch(id){
  dlog('launch ' + id);
  var path = id === 'com.palm.app.settings' ? '/api/lg/open' : '/api/launch?id=' + encodeURIComponent(id);
  api(path, function(err, j){ if (err || (j && j.returnValue === false)) toast('Could not open ' + id + (j && j.errorText ? ' (' + j.errorText + ')' : '')); else if (SETMODE && id === 'com.palm.app.settings') closeSettings(); });
}

/* ================= photos (gallery), framing & Home background ================= */
var photos = [], photosLoaded = false, crops = {};
function photoBase(){ return MOCK && MOCK.photoBase ? MOCK.photoBase : 'photos/'; }
function photoUrl(n){ return photoBase() + encodeURIComponent(n); }
function thumbUrl(n){ return photoBase() + 'thumbs/' + encodeURIComponent(n); }
function httpPhotoUrl(n){ return MOCK ? photoUrl(n) : API + '/photos/' + encodeURIComponent(n); }      // the editor reads pixels, so it needs a CORS-enabled URL
function shuffle(a){ for (var i = a.length - 1; i > 0; i--) { var k = Math.floor(Math.random() * (i + 1)), t = a[i]; a[i] = a[k]; a[k] = t; } return a; }
function refreshPhotos(cb){
  api('/api/photos', function(err, j){
    if (err || !(j instanceof Array)) { if (cb) cb(false); return; }
    var changed = false, had = photos.slice();
    if (!photosLoaded) { photos = shuffle(j.slice()); photosLoaded = true; changed = true; }
    else {
      var keep = photos.filter(function(n){ return j.indexOf(n) >= 0; }), add = j.filter(function(n){ return photos.indexOf(n) < 0; });
      photos = keep.concat(add); changed = photos.length !== had.length || add.length > 0;
    }
    if (changed && photos.length && bgIx >= photos.length) bgIx = 0;
    api('/api/crops', function(e2, c){
      if (!e2 && c && typeof c === 'object') { var s1 = JSON.stringify(crops), s2 = JSON.stringify(c); if (s1 !== s2) { crops = c; changed = true; } }
      if (cb) cb(changed);
    });
  });
}
function setBodyBg(on){ cls(document.body, 'hasbg', on); }
function hasBg(){ return document.body.className.indexOf('hasbg') >= 0; }
function layerStage(layer){ if (!layer._st) { layer._st = Stage.make(); layer.appendChild(layer._st); } return layer._st; }
var bgIx = -1, bgFlip = 0, bgT = null, bgAt = 0, LOWMEM = false;      // LOWMEM: memguard.sh says the TV is short of memory (or is a weak one): no photos on Home or in the screensaver
function bgShow(ix){
  if (!photos.length || !S.bg.on || LOWMEM) return;
  bgIx = ((ix % photos.length) + photos.length) % photos.length; bgAt = Date.now(); lsSet('bgName', photos[bgIx]);
  var name = photos[bgIx], a = $(bgFlip ? 'bgB' : 'bgA'), b = $(bgFlip ? 'bgA' : 'bgB'), im = new Image();
  im.onload = function(){
    var st = layerStage(a); st.lastChild.src = im.src; Stage.place(st, im.naturalWidth, im.naturalHeight, crops[name]);
    a.className = 'bgl show'; b.className = 'bgl'; setBodyBg(true); bgFlip = 1 - bgFlip;
    setTimeout(function(){ if (b.className.indexOf('show') < 0) layerStage(b).lastChild.removeAttribute('src'); }, 3000);
  };
  im.onerror = function(){ dlog('bg photo failed ' + name); };
  im.src = photoUrl(name);
}
function bgPickNew(){
  if (!photos.length || !S.bg.on || LOWMEM) return;
  var last = lsGet('bgName'), n = photos.length, k = Math.floor(Math.random() * n);
  if (n > 1 && photos[k] === last) k = (k + 1 + Math.floor(Math.random() * (n - 1))) % n;
  bgShow(k);
}
function bgSchedule(){ clearTimeout(bgT); bgT = setTimeout(function(){ if (!document.hidden && !saverOn && !settingsOn) bgShow(bgIx + 1); bgSchedule(); }, Math.max(1, S.bg.everyMin) * 60000); }
function bgApply(reschedule){
  if (!S.bg.on || !photos.length || LOWMEM) { $('bgA').className = $('bgB').className = 'bgl'; setBodyBg(false); layerStage($('bgA')).lastChild.removeAttribute('src'); layerStage($('bgB')).lastChild.removeAttribute('src'); }
  else if (reschedule && bgIx < 0) bgPickNew();
  else if (!hasBg()) bgShow(bgIx < 0 ? 0 : bgIx);
  if (reschedule) bgSchedule();
}

/* ================= screensaver / AFK ================= */
var saverOn = false, pIx = 0, flip = 0, idleT = null, slideT = null, driftT = null, SV = null;
function svStages(){ if (!SV) { SV = [Stage.make(), Stage.make()]; var sv = $('saver'); sv.insertBefore(SV[0], sv.firstChild); sv.insertBefore(SV[1], sv.firstChild); } return SV; }
function showNext(){
  if (!saverOn) return;
  var sv = svStages(), a = sv[flip], b = sv[1 - flip];
  var name = photos[pIx], src = photoUrl(name); pIx = (pIx + 1) % photos.length; var im = new Image();
  im.onload = function(){
    if (!saverOn) return;
    a.lastChild.src = src; Stage.place(a, im.naturalWidth, im.naturalHeight, crops[name]); a.className = 'stage show'; b.className = 'stage'; flip = 1 - flip;
    slideT = setTimeout(showNext, Math.max(4, S.saver.slideSec) * 1000);
    setTimeout(function(){ if (a.className.indexOf('show') < 0) return; b.lastChild.removeAttribute('src'); }, 2200);
  };
  im.onerror = function(){ dlog('photo failed ' + src); slideT = setTimeout(showNext, 1000); };
  im.src = src;
}
function drift(){
  var s = $('sinfo'); s.style.left = (3 + Math.random() * 45) + 'rem'; s.style.bottom = (3 + Math.random() * 28) + 'rem';
  driftT = setTimeout(drift, 60000);
}
// the TV's real backlight: lowered while the screensaver runs (tv/backlight.sh keeps the original and restores it in five independent ways)
var blOn = false, blT = null;
function blDim(){
  var p = S.saver.backlight === undefined ? 50 : S.saver.backlight; if (p >= 100 || MOCK) return;
  blOn = true; api('/api/backlight?v=dim&pct=' + p, noop, 15000);
  clearInterval(blT); blT = setInterval(function(){ if (saverOn) api('/api/backlight?v=hold', noop); }, 60000);
}
function blRestore(){ clearInterval(blT); if (blOn) { blOn = false; api('/api/backlight?v=restore', noop, 15000); } }
function saverStart(){
  if (saverOn || document.hidden || mstack.length || settingsOn || SETMODE) return;
  saverOn = true; lastT = lastD = ''; tick(); wxRender();
  // free the Home background while the screensaver runs: two big photos at once would make the TV swap
  ['bgA', 'bgB'].forEach(function(id){ var l = $(id); l.className = 'bgl'; layerStage(l).lastChild.removeAttribute('src'); }); setBodyBg(false);
  var withPhotos = S.saver.photos && photos.length > 0 && !LOWMEM;
  $('saver').className = 'on' + (withPhotos ? '' : ' nophoto');
  $('sdim').style.opacity = ((S.saver.dim === undefined ? 30 : S.saver.dim) / 100);
  blDim(); api('/api/history?v=saver', noop);      // Back forgets where you were, if the options say so
  $('scrimS').style.display = withPhotos ? 'block' : 'none';
  if (withPhotos) { pIx = (bgIx + 1) % photos.length; showNext(); } else { drift(); }
  dlog('saver on photos=' + withPhotos);
}
function saverStop(){
  if (!saverOn) return;
  saverOn = false; clearTimeout(slideT); clearTimeout(driftT); $('saver').className = ''; $('sdim').style.opacity = 0; blRestore();
  var sv = svStages(); sv[0].className = 'stage'; sv[1].className = 'stage';
  var s = $('sinfo'); s.style.left = ''; s.style.bottom = '';
  setTimeout(function(){ if (!saverOn) { sv[0].lastChild.removeAttribute('src'); sv[1].lastChild.removeAttribute('src'); } }, 1500);
  if (photos.length && S.bg.on) setTimeout(function(){ if (!saverOn) bgShow(bgIx < 0 ? 0 : bgIx); }, 200);
}
function activity(){ clearTimeout(idleT); if (document.hidden || !S.saver.on || SETMODE) return; idleT = setTimeout(saverStart, Math.max(1, S.saver.idleMin) * 60000); }

/* ================= modal list (Inputs / Network / choices) ================= */
var mstack = [], pItems = [], pIdx = 0;
function mtop(){ return mstack[mstack.length - 1]; }
function mpush(n){ mstack.push(n); } function mpop(n){ var i = mstack.lastIndexOf(n); if (i >= 0) mstack.splice(i, 1); }
function panelOpen(title, list){
  $('ptitle').textContent = title; var box = $('plist'); box.innerHTML = ''; pItems = [];
  list.forEach(function(it){ var d = el('div', 'pitem'); d.innerHTML = '<span></span><span class="v"></span>'; d.firstChild.textContent = it[0]; d.lastChild.textContent = it[1] || ''; d._pick = it[2]; box.appendChild(d); pItems.push(d); });
  $('panel').className = 'on'; if (mtop() !== 'panel') mpush('panel'); panelFocus(0);
}
function panelFocus(i){ pIdx = Math.max(0, Math.min(pItems.length - 1, i)); pItems.forEach(function(d, k){ d.className = 'pitem' + (k === pIdx ? ' foc' : ''); }); }
function panelClose(){ if (mtop() === 'panel') mpop('panel'); $('panel').className = ''; if (INPMODE) apiPost('/api/settings/close?id=inputs', ''); }      // the Inputs overlay is only its panel: closing it ends the page
function openInputs(){ panelOpen('Inputs', CFG.inputs.map(function(i){ return [i[1], '', function(){ panelClose(); launch(i[0]); }]; })); }
function openNet(){
  api('/api/net', function(err, j){
    var l = [];
    if (j && j.returnValue) { var w = j.wired || {}, f = j.wifi || {};
      l.push(['Ethernet', w.state === 'connected' ? (w.ipAddress || 'connected') : 'not connected']);
      l.push(['Wi-Fi', f.state === 'connected' ? ((f.ssid || 'connected') + (f.ipAddress ? '  ' + f.ipAddress : '')) : 'not connected']);
      l.push(['Internet', j.isInternetConnectionAvailable ? 'available' : 'not available']);
    } else l.push(['Network status', 'unavailable']);
    l.push(['More network settings', '', function(){ panelClose(); openSettings('net'); }]);
    panelOpen('Network', l); for (var i = 0; i < pItems.length; i++) if (pItems[i]._pick) { panelFocus(i); break; }
  });
}
function activate(){
  var e = rows[R] && rows[R][C]; if (!e) return;
  if (e._app) launch(e._app.id); else if (e.id === 'b-inputs') openInputs(); else if (e.id === 'b-net') openNet(); else if (e.id === 'b-settings') openSettings();
}

/* ================= keypad (ZIP entry) ================= */
var kVal = '', kIdx = 0, kBtns = [], kDone = null, kMax = 5;
function keypadOpen(title, initial, max, done){
  kVal = initial || ''; kMax = max; kDone = done; $('ktitle').textContent = title;
  var pad = $('kpad'); pad.innerHTML = ''; kBtns = [];
  ['1','2','3','4','5','6','7','8','9','⌫','0','✓'].forEach(function(k){ var b = el('div', 'kk', k); b._k = k; pad.appendChild(b); kBtns.push(b); });
  kIdx = 0; keypadDraw(); $('keym').className = 'on'; mpush('keypad');
}
function keypadDraw(){ $('kdisp').textContent = kVal || '–'; kBtns.forEach(function(b, i){ b.className = 'kk' + (i === kIdx ? ' foc' : ''); }); }
function keypadPress(k){
  if (k === '⌫') kVal = kVal.slice(0, -1);
  else if (k === '✓') { var v = kVal; keypadClose(); if (kDone) kDone(v); return; }
  else if (kVal.length < kMax) kVal += k;
  keypadDraw();
}
function keypadClose(){ mpop('keypad'); $('keym').className = ''; }
function keypadKey(k, e){
  if (k >= 48 && k <= 57) { keypadPress(String.fromCharCode(k)); return; }
  if (k === 461 || k === 27) { keypadClose(); return; }
  if (k === 8) { keypadPress('⌫'); return; }
  if (k === 37) kIdx = kIdx % 3 ? kIdx - 1 : kIdx; else if (k === 39) kIdx = (kIdx % 3) < 2 ? kIdx + 1 : kIdx;
  else if (k === 38) kIdx = kIdx >= 3 ? kIdx - 3 : kIdx; else if (k === 40) kIdx = kIdx < 9 ? kIdx + 3 : kIdx;
  else if (k === 13) { keypadPress(kBtns[kIdx]._k); return; }
  keypadDraw();
}

/* ================= QR / phone link ================= */
var qrPoll = null;
// qr.js (57 KB) is only needed for the phone-link QR code: load it then, not at every start of Home and Settings
function withQr(cb){
  if (typeof qrcode === 'function') return cb();
  var s = document.createElement('script'); s.src = 'qr.js'; s.onload = cb; s.onerror = function(){ toast('QR failed'); }; document.head.appendChild(s);
}
function qrOpen(){ withQr(qrOpen2); }
function qrOpen2(){
  api('/api/info', function(err, j){
    if (err || !j || !j.ip) { toast('Could not read the TV address'); return; }
    var url = MOCK ? 'http://10.0.0.63:8765/?t=demo' : 'http://' + j.ip + ':' + j.port + '/?t=' + j.token;
    var cv = $('qrcv'), ctx = cv.getContext('2d'), qr;
    try { qr = qrcode(0, 'M'); qr.addData(url); qr.make(); } catch(e){ toast('QR failed'); return; }
    var n = qr.getModuleCount(), cell = Math.floor(280 / n), off = Math.floor((280 - cell * n) / 2);
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 280, 280); ctx.fillStyle = '#000';
    for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) if (qr.isDark(r, c)) ctx.fillRect(off + c * cell, off + r * cell, cell, cell);
    $('qrurl').textContent = url.replace(/\?t=.*/, '');
    $('qrm').className = 'on'; mpush('qr');
    qrPoll = setInterval(function(){ refreshPhotos(function(ch){ if (ch) { toast(photos.length + ' photos in the gallery'); if (settingsOn) renderCat(false); } }); }, 3000);
  });
}
function qrClose(){ clearInterval(qrPoll); mpop('qr'); $('qrm').className = ''; refreshPhotos(function(){ if (settingsOn) renderCat(false); if (!SETMODE && !hasBg()) bgApply(true); }); }

/* ================= LG settings access ================= */
var LGC = {}, LGD = {};
function lgLoad(cat, keys, cb){
  api('/api/lg/get?cat=' + cat + '&keys=' + keys.join(','), function(err, j){
    if (j && j.settings) { LGC[cat] = j.settings; LGD[cat] = j.dimension || {}; } else if (!LGC[cat]) LGC[cat] = {};
    cb();
  });
}
function lgLoadMany(list, cb){ var i = 0; (function next(){ if (i >= list.length) return cb(); var l = list[i++]; lgLoad(l[0], l[1], next); })(); }
function lgSet(cat, key, val, after){
  var st = {}; st[key] = String(val); (LGC[cat] = LGC[cat] || {})[key] = String(val);
  apiPost('/api/lg/set', JSON.stringify({category: cat, settings: st}), function(err, j){
    if (err || (j && j.returnValue === false)) { toast('The TV refused that setting' + (j && j.errorText ? ': ' + j.errorText : '')); }
    if (after) after();
  });
}
function lgHas(cat, key){ return !!LGC[cat] && LGC[cat][key] !== undefined; }

/* ================= Settings screen ================= */
var paneOpen = false;
var settingsOn = false, cats = [], catIdx = 0, sArea = 'cats', sRows = [], sR = 0, sC = 0, setY = 0, catY = 0;
var ICON = {
  home: '<svg viewBox="0 0 24 24"><path d="M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10"/></svg>',
  bolt: '<svg viewBox="0 0 24 24"><path d="M13 2.5L5.5 13.5H11l-1 8 8-11.5h-5.5z"/></svg>',
  update: '<svg viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.6-5.9M20 4v5h-5"/><path d="M12 8v5l3 2"/></svg>',
  cloud: '<svg viewBox="0 0 24 24"><path d="M7 18a4 4 0 0 1 0-8 5.5 5.5 0 0 1 10.5 1.5A3.5 3.5 0 0 1 17 18z"/></svg>',
  image: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/></svg>',
  pic: '<svg viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/><circle cx="9" cy="7" r="2" fill="#0b0e14"/><circle cx="15" cy="12" r="2" fill="#0b0e14"/><circle cx="8" cy="17" r="2" fill="#0b0e14"/></svg>',
  sound: '<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9zM16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12"/></svg>',
  power: '<svg viewBox="0 0 24 24"><path d="M12 3v9M6.5 6.5a8 8 0 1 0 11 0"/></svg>',
  net: '<svg viewBox="0 0 24 24"><path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/></svg>',
  info: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/></svg>',
  grid: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="6" height="6"/><rect x="14" y="4" width="6" height="6"/><rect x="4" y="14" width="6" height="6"/><rect x="14" y="14" width="6" height="6"/></svg>',
  shield: '<svg viewBox="0 0 24 24"><path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M8.5 12l2.5 2.5 4.5-5"/></svg>',
  block: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/></svg>',
  hdmi: '<svg viewBox="0 0 24 24"><path d="M4 8h16v6l-3 3H7l-3-3zM9 11h6"/></svg>',
  remote: '<svg viewBox="0 0 24 24"><rect x="8" y="2.5" width="8" height="19" rx="3"/><circle cx="12" cy="8" r="1.6"/><path d="M12 12.5v.5M12 16v.5"/></svg>',
  access: '<svg viewBox="0 0 24 24"><circle cx="12" cy="5" r="2"/><path d="M5 9l7 1.5L19 9M12 10.5V15l-3 5.5M12 15l3 5.5"/></svg>'
};
function tgl(label, desc, get, set){ return {type: 'toggle', label: label, desc: desc, get: get, set: set}; }
// Back-button history options live on the TV (lastapp.sh, state/back.conf); the Remote page's data object holds the current values
function backOpt(k, v){ var d = cats[catIdx].data = cats[catIdx].data || {}; d.back = d.back || {}; d.back[k] = (k === 'reset' || k === 'leave') ? v : parseInt(v, 10); api('/api/history?k=' + k + '&n=' + v, function(){ toast('Saved'); }); }
function chc(label, desc, opts, get, set){ return {type: 'choice', label: label, desc: desc, opts: opts, get: get, set: set}; }
function sld(label, desc, min, max, step, get, set){ return {type: 'slider', label: label, desc: desc, min: min, max: max, step: step, get: get, set: set}; }
function inf(label, value, desc){ return {type: 'info', label: label, value: value, desc: desc}; }
function act(label, desc, run, val){ return {type: 'action', label: label, desc: desc, run: run, val: val}; }
function head(label){ return {type: 'head', label: label}; }
function optsOf(it){ return typeof it.opts === 'function' ? it.opts() : it.opts; }
// rows backed by LG's settings service; a row disappears when the TV does not have that key for the current input / picture mode
function lgTgl(cat, key, label, desc, onv, offv){ onv = onv || 'on'; offv = offv || 'off';
  var it = tgl(label, desc, function(){ return String((LGC[cat] || {})[key]) === onv; }, function(b){ lgSet(cat, key, b ? onv : offv); }); it.show = function(){ return lgHas(cat, key); }; return it; }
function lgChc(cat, key, label, desc, opts, reload){
  var it = chc(label, desc, opts, function(){ return (LGC[cat] || {})[key]; }, function(v){ lgSet(cat, key, v, reload ? function(){ renderCat(true); } : null); }); it.show = function(){ return lgHas(cat, key); }; return it; }
function lgSld(cat, key, label, desc, min, max, step){
  var it = sld(label, desc, min, max, step, function(){ return parseInt((LGC[cat] || {})[key] || '0', 10); }, function(v){ clearTimeout(it._t); it._t = setTimeout(function(){ lgSet(cat, key, v); }, 350); });
  it.local = function(v){ (LGC[cat] = LGC[cat] || {})[key] = String(v); }; it.show = function(){ return lgHas(cat, key); }; return it;
}
var OFFON = [['off','Off'],['on','On']];
var ASPECTS = [['16x9','16:9'],['original','Original'],['full_wide','Full wide'],['4x3','4:3'],['14x9','14:9'],['zoom','Zoom'],['zoom2','Zoom 2'],['cinema_zoom','Cinema zoom'],['21x9','21:9']];
var SOUNDMODES = [['standard','Standard'],['movie','Cinema'],['news','Clear voice / News'],['sports','Sports'],['music','Music'],['game','Game'],['asc','AI sound'],['bass','Bass']];
var SLEEPS = [['off','Off'],['10','10 min'],['20','20 min'],['30','30 min'],['60','1 hour'],['90','1.5 hours'],['120','2 hours'],['180','3 hours'],['240','4 hours']];
var LEVELS = [['off','Off'],['low','Low'],['medium','Medium'],['high','High']];
var MINS = function(v){ return v + ' min'; };
var PICMODES = {vivid:'Vivid', normal:'Standard', eco:'Eco', cinema:'Cinema', sports:'Sports', game:'Game', photo:'Photo', expert1:'Expert (bright room)', expert2:'Expert (dark room)',
  hdrVivid:'HDR Vivid', hdrStandard:'HDR Standard', hdrCinemaBright:'HDR Cinema Bright', hdrCinema:'HDR Cinema', hdrGame:'HDR Game', hdrEffect:'HDR Effect', technicolor:'Technicolor', hdrTechnicolor:'HDR Technicolor',
  dolbyHdrVivid:'Dolby Vision Vivid', dolbyHdrStandard:'Dolby Vision Standard', dolbyHdrCinemaBright:'Dolby Vision Bright', dolbyHdrCinema:'Dolby Vision Dark', dolbyHdrGame:'Dolby Vision Game'};
function picModes(){
  var cur = (LGC.picture || {}).pictureMode || 'normal', fam = /^dolby/.test(cur) ? /^dolby/ : /^(hdr|technicolor)/.test(cur) ? /^(hdr|technicolor)/ : null, out = [];
  for (var k in PICMODES) { var isH = /^(hdr|technicolor|dolby)/.test(k); if (fam ? fam.test(k) : !isH) out.push([k, PICMODES[k]]); }
  if (!out.length) out.push([cur, cur]); return out;
}
var SOUNDOUT = [['tv_speaker','TV speaker'],['external_arc','HDMI ARC / eARC'],['external_optical','Optical'],['bt_soundbar','Bluetooth soundbar'],['lineout','Line out'],['headphone','Headphones'],['bt_audio','Bluetooth device'],['tv_external_speaker','TV speaker + external'],['tv_speaker_headphone','TV speaker + headphones']];
function fmtDate2(sec){ if (!sec) return 'never'; var d = new Date(sec * 1000); return MONS[d.getMonth()].slice(0, 3) + ' ' + d.getDate() + ', ' + d.getFullYear(); }
function num(n){ return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }

cats = [
  {id: 'quick', name: 'Quick settings', icon: 'bolt', title: 'Quick settings', desc: 'The same shortcuts as LG’s quick panel: picture mode, aspect ratio, sound mode, sound out, sleep timer, network, and all settings.', info: '/api/net',
    lg: [['picture', ['pictureMode','aspectRatio']], ['sound', ['soundMode','soundOutput']], ['time', ['sleepTimer']]], build: function(){ var j = this.data || {}, w = j.wired || {}, f = j.wifi || {}; return [
    chc('Same brightness everywhere', 'LG keeps a separate backlight for every input and app, so dimming one screen leaves the others bright. Pick a value and it is applied on every input and app (also in the dark: choose Lowest at night). Off puts each input back to its own value.', [['off','Off: each input keeps its own'],['5','Lowest'],['25','25 %'],['50','50 %'],['75','75 %'],['100','Full']], function(){ return BRV === null ? 'off' : BRV; }, function(v){ BRV = v; api('/api/brightness?v=' + v, function(){ toast(v === 'off' ? 'Each input has its own brightness again' : 'Same brightness everywhere'); }, 70000); }),
    lgChc('picture', 'pictureMode', 'Picture mode', '', picModes, true),
    lgChc('picture', 'aspectRatio', 'Aspect ratio', '', ASPECTS),
    lgChc('sound', 'soundMode', 'Sound mode', '', SOUNDMODES),
    lgChc('sound', 'soundOutput', 'Sound out', 'Where the sound plays. If the TV goes silent, pick TV speaker.', SOUNDOUT),
    lgChc('time', 'sleepTimer', 'Sleep timer', 'Turns the TV off after this time', SLEEPS),
    inf('Network', function(){ return (w.state === 'connected' ? 'Ethernet' : f.state === 'connected' ? 'Wi-Fi ' + (f.ssid || '') : 'Offline') + (w.ipAddress || f.ipAddress ? '  ·  ' + (w.ipAddress || f.ipAddress) : ''); }),
    act('All settings', 'LG’s own full Settings app', function(){ launch('com.palm.app.settings'); })
  ]; }},
  {id: 'home', name: 'Home & Screensaver', icon: 'home', title: 'Home & Screensaver', desc: 'Background photos, the idle (AFK) screen and the clock.', build: function(){ return [
    tgl('Photo background on Home', 'Uses the photos in your gallery', function(){ return S.bg.on; }, function(b){ setPath('bg.on', b); }),
    chc('Change background every', '', [[5,'5 min'],[10,'10 min'],[20,'20 min'],[30,'30 min'],[60,'1 hour']], function(){ return S.bg.everyMin; }, function(v){ setPath('bg.everyMin', v); }),
    tgl('Screensaver when idle', 'Clock, date and weather after a while', function(){ return S.saver.on; }, function(b){ setPath('saver.on', b); }),
    chc('Start after', '', [[1,'1 min'],[2,'2 min'],[5,'5 min'],[10,'10 min'],[15,'15 min'],[30,'30 min']], function(){ return S.saver.idleMin; }, function(v){ setPath('saver.idleMin', v); }),
    tgl('Show gallery photos in screensaver', 'Off = dark screen with clock', function(){ return S.saver.photos; }, function(b){ setPath('saver.photos', b); }),
    chc('Photo changes every', '', [[8,'8 s'],[12,'12 s'],[20,'20 s'],[30,'30 s'],[60,'1 min']], function(){ return S.saver.slideSec; }, function(v){ setPath('saver.slideSec', v); }),
    tgl('Show weather in screensaver', '', function(){ return S.saver.weather; }, function(b){ setPath('saver.weather', b); wxRender(); }),
    sld('Screensaver dimming', 'Darkens the photo so the screensaver is easy on the eyes; the clock stays bright. 0 = no dimming', 0, 80, 5, function(){ return S.saver.dim === undefined ? 30 : S.saver.dim; }, function(v){ setPath('saver.dim', v); }),
    sld('Screensaver backlight', 'Lowers the TV’s real backlight while the screensaver runs (saves power, easier on the eyes). 100 = unchanged. It is always restored when you wake the TV.', 10, 100, 5, function(){ return S.saver.backlight === undefined ? 50 : S.saver.backlight; }, function(v){ setPath('saver.backlight', v); }),
    tgl('24-hour clock', '', function(){ return S.clock24; }, function(b){ setPath('clock24', b); })
  ]; }},
  {id: 'weather', name: 'Weather', icon: 'cloud', title: 'Weather', desc: 'Free forecasts from Open-Meteo.', build: function(){ return [
    chc('Location', 'Automatic uses this TV’s internet connection', [['auto','Automatic'],['zip','ZIP code']], function(){ return S.weather.mode; }, function(v){ setPath('weather.mode', v); renderCat(true); }),
    {type: 'text', label: 'ZIP code', desc: 'US ZIP codes. OK to type it with the remote.', show: function(){ return S.weather.mode === 'zip'; },
      get: function(){ return S.weather.zip || 'not set'; }, run: function(){ keypadOpen('ZIP code', S.weather.zip, 5, function(v){ if (/^\d{5}$/.test(v)) { S.weather.mode = 'zip'; setPath('weather.zip', v); renderCat(true); } else toast('Enter 5 digits'); }); }},
    chc('Units', '', [['F','°F'],['C','°C']], function(){ return S.weather.unit; }, function(v){ setPath('weather.unit', v); }),
    inf('Showing', function(){ return wx ? wx.place : 'loading…'; }),
    act('Refresh now', '', function(){ lsSet('loc', null); wxLoad(true); toast('Updating weather…'); })
  ]; }},
  {id: 'gallery', name: 'Photo gallery', icon: 'image', title: 'Photo gallery', desc: 'Photos used for the Home background and screensaver. Choose a photo to adjust its framing.', build: function(){ return [
    act('Add photos from your phone', 'Shows a QR code to scan. The phone page can also adjust framing and edit the ad-block lists.', function(){ qrOpen(); }, 'QR'),
    inf('Photos in gallery', function(){ return String(photos.length); }),
    tgl('Photo background on Home', '', function(){ return S.bg.on; }, function(b){ setPath('bg.on', b); }),
    tgl('Show photos in screensaver', '', function(){ return S.saver.photos; }, function(b){ setPath('saver.photos', b); }),
    act('Reset phone link', 'Old QR codes stop working', function(){ panelOpen('Reset the phone link?', [['Yes, reset it', '', function(){ panelClose(); apiPost('/api/resettoken', '', function(){ toast('Phone link reset'); }); }], ['Cancel', '', panelClose]]); }),
    {type: 'thumbs'}
  ]; }},
  {id: 'picture', name: 'Picture', icon: 'pic', title: 'Picture', desc: 'Applies to what is on screen now: the current input and picture mode.',
    lg: [['picture', ['pictureMode','backlight','contrast','brightness','sharpness','color','tint','colorTemperature','energySaving','dynamicContrast','localDimming','peakBrightness','superResolution','noiseReduction','mpegNoiseReduction','gamma','colorGamut','blackLevel','dynamicColor','hdrDynamicToneMapping','truMotionMode','truMotionJudder','truMotionBlur','motionEyeCare','eyeComfortMode','aspectRatio']]], build: function(){ return [
    lgChc('picture', 'pictureMode', 'Picture mode', '', picModes, true),
    lgSld('picture', 'backlight', 'Backlight', '', 0, 100, 1), lgSld('picture', 'contrast', 'Contrast', '', 0, 100, 1),
    lgSld('picture', 'brightness', 'Brightness', '', 0, 100, 1), lgSld('picture', 'sharpness', 'Sharpness', '', 0, 50, 1),
    lgSld('picture', 'color', 'Color', '', 0, 100, 1), lgSld('picture', 'tint', 'Tint', '', -50, 50, 1), lgSld('picture', 'colorTemperature', 'Color temperature', 'Negative = warmer, positive = cooler', -50, 50, 1),
    lgChc('picture', 'energySaving', 'Energy saving', '', [['off','Off'],['auto','Auto'],['min','Minimum'],['med','Medium'],['max','Maximum'],['screen_off','Screen off']]),
    head('Picture options'),
    lgChc('picture', 'dynamicContrast', 'Dynamic contrast', '', LEVELS), lgChc('picture', 'localDimming', 'Local dimming', '', LEVELS), lgChc('picture', 'peakBrightness', 'Peak brightness', '', LEVELS),
    lgChc('picture', 'superResolution', 'Super resolution', '', LEVELS), lgChc('picture', 'noiseReduction', 'Noise reduction', '', [['off','Off'],['low','Low'],['medium','Medium'],['high','High'],['auto','Auto']]),
    lgChc('picture', 'mpegNoiseReduction', 'MPEG noise reduction', '', [['off','Off'],['low','Low'],['medium','Medium'],['high','High'],['auto','Auto']]),
    lgChc('picture', 'gamma', 'Gamma', '', [['low','Low'],['medium','Medium'],['high1','High 1'],['high2','High 2']]), lgChc('picture', 'colorGamut', 'Color gamut', '', [['auto','Auto'],['wide','Wide'],['extended','Extended'],['srgb','sRGB']]),
    lgChc('picture', 'blackLevel', 'Black level', '', [['auto','Auto'],['low','Low'],['high','High']]), lgChc('picture', 'dynamicColor', 'Dynamic color', '', LEVELS),
    lgChc('picture', 'hdrDynamicToneMapping', 'HDR tone mapping', '', [['on','On'],['off','Off'],['HGIG','HGIG']]),
    lgChc('picture', 'truMotionMode', 'TruMotion', 'Motion smoothing', [['off','Off'],['smooth','Smooth'],['clear','Clear'],['user','User']]),
    lgSld('picture', 'truMotionJudder', 'De-judder', '', 0, 10, 1), lgSld('picture', 'truMotionBlur', 'De-blur', '', 0, 10, 1),
    lgTgl('picture', 'motionEyeCare', 'Motion eye care', ''), lgTgl('picture', 'eyeComfortMode', 'Eye comfort mode', 'Warmer, easier on the eyes at night'),
    lgChc('picture', 'aspectRatio', 'Aspect ratio', '', ASPECTS)
  ]; }},
  {id: 'sound', name: 'Sound', icon: 'sound', title: 'Sound', desc: 'TV speaker and audio output options.',
    lg: [['sound', ['soundMode','clearVoice','autoVolume','virtualSurround','soundOutput','audioBalance','soundOptimizer','soundOutputDigital','hdmiArcMode','eArcSupport','lgSoundSync','startupSound','tvPowerSound']]], build: function(){ return [
    lgChc('sound', 'soundMode', 'Sound mode', '', SOUNDMODES),
    lgChc('sound', 'clearVoice', 'Clear Voice', 'Makes speech easier to hear', [['off','Off'],['level1','Level 1'],['level2','Level 2'],['level3','Level 3']]),
    lgTgl('sound', 'autoVolume', 'Auto volume', 'Evens out loud ads and quiet scenes'), lgTgl('sound', 'virtualSurround', 'Virtual surround', ''),
    lgSld('sound', 'audioBalance', 'Balance', 'Left / right', -50, 50, 1),
    lgChc('sound', 'soundOutput', 'Sound output', 'Where the sound plays. If the TV goes silent, pick TV speaker.', SOUNDOUT),
    lgChc('sound', 'soundOptimizer', 'TV placement', '', [['normal','Normal'],['stand','On a stand'],['wall_mount','Wall mounted']]),
    head('Digital audio'),
    lgChc('sound', 'soundOutputDigital', 'Digital sound output', '', [['pcm','PCM'],['auto','Auto'],['passThrough','Pass-through']]),
    lgTgl('sound', 'hdmiArcMode', 'HDMI ARC', ''), lgTgl('sound', 'eArcSupport', 'eARC', ''), lgTgl('sound', 'lgSoundSync', 'LG Sound Sync', ''),
    lgTgl('sound', 'startupSound', 'Startup sound', ''), lgTgl('sound', 'tvPowerSound', 'Power-on sound', '')
  ]; }},
  {id: 'power', name: 'Power & timers', icon: 'power', title: 'Power & timers', desc: '',
    lg: [['option', ['quickStartMode','standByLight','logoLight','powerOnLight']], ['general', ['homeAutoLaunch']], ['time', ['autoClock','daylightSaving','sleepTimer','noOperationAutoOff','automaticStandBy','noSignalAutoOff','timeZone']]], build: function(){ var tz = (LGC.time || {}).timeZone; return [
    lgTgl('option', 'quickStartMode', 'Quick Start', 'Turns on in a couple of seconds instead of a full start. Uses a little more power while off. On is recommended: it works with this launcher and makes no difference to LG updates being blocked.'),
    lgTgl('general', 'homeAutoLaunch', 'Show Home when the TV turns on', ''),
    lgTgl('option', 'standByLight', 'Standby light', ''), lgChc('option', 'logoLight', 'LG logo light', '', LEVELS), lgTgl('option', 'powerOnLight', 'Power-on light', ''),
    head('Timers'),
    lgChc('time', 'sleepTimer', 'Sleep timer', 'Turns the TV off after this time', SLEEPS),
    lgChc('time', 'noOperationAutoOff', 'Turn off when nobody uses the remote', 'In hours', [['off','Off'],['3','3 h'],['6','6 h'],['12','12 h'],['24','24 h']]),
    lgChc('time', 'automaticStandBy', 'Automatic standby', 'In hours without any activity', [['0','Off'],['2','2 h'],['4','4 h'],['6','6 h'],['8','8 h']]),
    lgTgl('time', 'noSignalAutoOff', 'Turn off when there is no signal', ''),
    head('Clock'),
    lgTgl('time', 'autoClock', 'Set the clock automatically', ''), lgChc('time', 'daylightSaving', 'Daylight saving time', '', [['auto','Automatic'],['on','On'],['off','Off']]),
    inf('Time zone', function(){ return tz && tz.City ? tz.City + ' (' + (tz.Description || '') + ')' : '–'; }, 'Change the time zone in LG Settings (legacy) if you move.'),
    head('Restart'),
    act('Restart TV', 'Reboots; Home is back in about a minute', function(){ panelOpen('Restart the TV?', [['Restart now', '', function(){ panelClose(); apiPost('/api/reboot', '', function(){ toast('Restarting…'); }); }], ['Cancel', '', panelClose]]); })
  ]; }},
  {id: 'inputs', name: 'Inputs & HDMI', icon: 'hdmi', title: 'Inputs & HDMI', desc: 'Per-port picture format and device control.',
    lg: [['other', ['uhdDeepColorHDMI1','uhdDeepColorHDMI2','uhdDeepColorHDMI3','uhdDeepColorHDMI4','gameOptimizationHDMI1','gameOptimizationHDMI2','gameOptimizationHDMI3','gameOptimizationHDMI4','simplinkEnable','simplinkAutoPowerOn']],
         ['sound', ['inputAudioFormatHDMI1','inputAudioFormatHDMI2','inputAudioFormatHDMI3','inputAudioFormatHDMI4']]], build: function(){
    var o = [head('HDMI ULTRA HD Deep Colour (needed for 4K HDR; turn off if a device has no picture)')], i, n;
    for (i = 1; i <= 4; i++) o.push(lgTgl('other', 'uhdDeepColorHDMI' + i, 'HDMI ' + i + ' Deep Colour', ''));
    o.push(head('Game optimization (low delay)')); for (i = 1; i <= 4; i++) o.push(lgTgl('other', 'gameOptimizationHDMI' + i, 'HDMI ' + i + ' game optimization', ''));
    o.push(head('HDMI audio format')); for (i = 1; i <= 4; i++) o.push(lgChc('sound', 'inputAudioFormatHDMI' + i, 'HDMI ' + i + ' audio', '', [['pcm','PCM'],['bitstream','Bitstream']]));
    o.push(head('Device control (SIMPLINK / HDMI-CEC)'));
    o.push(lgTgl('other', 'simplinkEnable', 'SIMPLINK', 'Lets connected devices turn the TV on and control it'), lgTgl('other', 'simplinkAutoPowerOn', 'SIMPLINK auto power on', ''));
    return o; }},
  {id: 'remote', name: 'Remote & pointer', icon: 'remote', title: 'Remote & pointer', desc: 'The Settings button and the Magic Remote pointer. LG has no real off switch for the pointer, so the first option asks the remote itself to stay quiet (experimental) and the rest tune it.', info: '/api/gear',
    lg: [['option', ['pointerSpeed','pointerSize','pointerShape','pointerAlignment']], ['other', ['cursorAutoRemover']]], build: function(){ var self = this; return [
    chc('Settings button opens', 'The gear button on the remote', [['ours','This Settings screen'],['lg','LG’s quick panel']], function(){ return (self.data && self.data.gear) || 'ours'; }, function(v){ self.data = self.data || {}; self.data.gear = v; api('/api/gear?v=' + v, function(){ toast(v === 'ours' ? 'The Settings button now opens this screen' : 'The Settings button opens LG’s panel again'); }); }),
    tgl('Back from an app returns to the previous app', 'When an app quits on Back, open the app or input you were in before it. With nothing before it you land on Home, as usual.', function(){ return !(self.data && self.data.chain === 'off'); }, function(b){ self.data = self.data || {}; self.data.chain = b ? 'on' : 'off'; api('/api/backchain?v=' + (b ? 'on' : 'off'), function(){ toast(b ? 'Back now returns to the previous app' : 'Back from an app goes to Home again'); }); }),
    chc('Leave an app with Back', 'Apps decide what a normal Back press does (Netflix ignores it on its start screen). With this on, holding Back or pressing it twice quickly takes you out of the app: to the previous app, or Home when there is none.', [['both','Hold or press twice'],['hold','Hold Back'],['double','Press twice quickly'],['off','Let the app decide']], function(){ return (self.data && self.data.back && self.data.back.leave) || 'both'; }, function(v){ backOpt('leave', v); }),
    chc('Forget where I was', 'The Back button can take you back to the apps and inputs you used. Choose when that memory is wiped, so the TV feels freshly turned on.', [['never','Never'],['saver','When the screensaver starts'],['saver_standby','Screensaver or TV off']], function(){ return (self.data && self.data.back && self.data.back.reset) || 'saver'; }, function(v){ backOpt('reset', v); }),
    chc('Forget apps I left a while ago', 'Apps and inputs you left longer ago than this are skipped by Back.', [['0','Never'],['5','5 minutes'],['15','15 minutes'],['30','30 minutes'],['60','1 hour'],['240','4 hours']], function(){ return String((self.data && self.data.back && self.data.back.forget) || 0); }, function(v){ backOpt('forget', v); }),
    chc('How many steps Back can go', 'How far back Back can walk through the apps you used.', [['1','1'],['2','2'],['3','3'],['5','5'],['8','8']], function(){ return String((self.data && self.data.back && self.data.back.depth) || 8); }, function(v){ backOpt('depth', v); }),
    chc('Apps kept in memory', 'The app in front plus the last one you used stay in memory, so switching back is instant; opening a third app closes the oldest one. Fewer apps in memory means a quicker TV. A music app you left playing stops once it is pushed out. Inputs count as apps; Home, AirPlay and LG’s system apps are never closed.', [['0','No limit'],['1','Only the current one'],['2','Current + last (2)'],['3','3 apps'],['4','4 apps']], function(){ return String((self.data && self.data.back && self.data.back.keep !== undefined) ? self.data.back.keep : 2); }, function(v){ backOpt('keep', v); }),
    chc('Close inputs I left after', 'An HDMI input you left in the background holds about 50-60 MB of memory. Closing it frees that; coming back to it takes about 0.7 s instead of 0.3 s. Your devices stay connected.', [['0','Never'],['2','2 minutes'],['5','5 minutes'],['15','15 minutes'],['60','1 hour']], function(){ return String((self.data && self.data.back && self.data.back.closeinputs !== undefined) ? self.data.back.closeinputs : 5); }, function(v){ backOpt('closeinputs', v); }),
    chc('Close apps I left on Home after', 'Frees memory so the TV stays quick: a streaming app you left in the background is closed after this time (Netflix alone holds about 125 MB). It starts again when you open it. Music that plays in the background stops too, so choose Never if you use a music app. LG’s own apps and inputs are never closed.', [['0','Never'],['30','30 minutes'],['60','1 hour'],['120','2 hours'],['300','5 hours']], function(){ return String((self.data && self.data.back && self.data.back.closeidle !== undefined) ? self.data.back.closeidle : 120); }, function(v){ backOpt('closeidle', v); }),
    tgl('Hide the Magic Remote pointer', 'Second layer under "Make the Magic Remote pointer invisible" (Services & privacy): the moment the remote asks for its arrow (shake, movement, wheel) the TV is told to hide it again. Clicks and buttons keep working.', function(){ return !(self.data && self.data.pointerhide === 'off'); }, function(b){ self.data = self.data || {}; self.data.pointerhide = b ? 'on' : 'off'; api('/api/pointerhide?v=' + (b ? 'on' : 'off'), function(){ toast(b ? 'The pointer is hidden' : 'The pointer behaves like LG’s again'); }); }),
    tgl('Pointer only when I shake the remote', 'Experimental. Asks the Magic Remote to show the arrow only after a shake, not on every movement. Applied again by itself each time the remote wakes up. Press a button on the remote first, then switch this on.', function(){ return !!(self.data && self.data.pointer === 'off'); }, function(b){ self.data = self.data || {}; self.data.pointer = b ? 'off' : 'on'; api('/api/pointer?v=' + (b ? 'off' : 'on'), function(err, j){ toast((j && j.msg) || (err ? 'Could not reach the TV' : 'Done')); }, 25000); }),
    tgl('Hide the pointer on Home and in Settings', 'Asks the browser not to draw an arrow on Home and in Settings. LG draws its own pointer on top, so it may still appear.', function(){ return !!S.ui.hideCursor; }, function(b){ setPath('ui.hideCursor', b); }),
    head('LG pointer options'),
    lgChc('option', 'pointerSpeed', 'Pointer speed', '', [['slow','Slow'],['normal','Normal'],['fast','Fast']]), lgChc('option', 'pointerSize', 'Pointer size', '', [['small','Small'],['medium','Medium'],['large','Large']]),
    lgChc('option', 'pointerShape', 'Pointer shape', '', [['a','Shape A'],['b','Shape B'],['c','Shape C'],['d','Shape D']]), lgTgl('option', 'pointerAlignment', 'Pointer alignment', 'Keeps the pointer on the item you selected with the arrow keys'),
    lgTgl('other', 'cursorAutoRemover', 'Hide the pointer after a few seconds', 'LG hides the pointer by itself when you stop moving the remote')
  ]; }},
  {id: 'access', name: 'Accessibility', icon: 'access', title: 'Accessibility', desc: '',
    lg: [['option', ['highContrast','audioGuidance','audioGuidanceSpeed','audioGuidanceVolume','audioGuidancePitch','menuTransparency','animationGuide','baloonHelp','focusedItemEnlarged']], ['sound', ['audioDescription','visualImpaired']], ['caption', ['captionEnable','hardOfHearing']]], build: function(){ return [
    lgTgl('caption', 'captionEnable', 'Subtitles / captions', 'Show captions when the program has them'), lgTgl('caption', 'hardOfHearing', 'Captions for the hard of hearing', ''),
    head('Vision'),
    lgTgl('option', 'highContrast', 'High contrast', ''), lgTgl('option', 'focusedItemEnlarged', 'Enlarge the selected item', ''), lgTgl('option', 'menuTransparency', 'Menu transparency', ''),
    lgTgl('option', 'audioGuidance', 'Audio guidance', 'Reads menus out loud'), lgChc('option', 'audioGuidanceSpeed', 'Audio guidance speed', '', [['verySlow','Very slow'],['slow','Slow'],['medium','Medium'],['fast','Fast'],['veryFast','Very fast']]),
    lgChc('option', 'audioGuidanceVolume', 'Audio guidance volume', '', [['veryLow','Very low'],['low','Low'],['medium','Medium'],['high','High'],['veryHigh','Very high']]),
    lgChc('option', 'audioGuidancePitch', 'Audio guidance pitch', '', [['veryLow','Very low'],['low','Low'],['medium','Medium'],['high','High'],['veryHigh','Very high']]),
    lgTgl('sound', 'audioDescription', 'Audio description', 'Narration of what happens on screen'), lgTgl('sound', 'visualImpaired', 'Audio for the visually impaired', ''),
    head('Help'), lgTgl('option', 'animationGuide', 'Animation guide', ''), lgTgl('option', 'baloonHelp', 'Help balloons', '')
  ]; }},
  {id: 'net', name: 'Network', icon: 'net', title: 'Network', desc: '', info: '/api/net', lg: [['network', ['wolwowlOnOff','bleAdvertisingOnOff','allowMobileDeviceAccess']]], build: function(){ var self = this, j = this.data || {}, w = j.wired || {}, f = j.wifi || {}; if (!self.wifi && !self.wifiAsked) { self.wifiAsked = true; api('/api/wifi', function(err, x){ if (x) { self.wifi = x; if (settingsOn && cats[catIdx].id === 'net') renderCat(false); } }, 10000); } return [
    inf('Connection', function(){ return w.state === 'connected' ? 'Ethernet' : f.state === 'connected' ? 'Wi-Fi' : 'Offline'; }),
    inf('IP address', function(){ return w.ipAddress || f.ipAddress || '–'; }),
    inf('Wi-Fi network', function(){ return f.state === 'connected' ? (f.ssid || 'connected') : '–'; }),
    inf('Gateway (router)', function(){ return w.gateway || f.gateway || '–'; }),
    inf('Wi-Fi radio', function(){ var s = (self.wifi && self.wifi.status && self.wifi.status.status) || ''; return !self.wifi ? '–' : s === 'serviceEnabled' ? 'on' : s ? s : '–'; }),
    inf('Saved Wi-Fi networks', function(){ var l = (self.wifi && self.wifi.saved && self.wifi.saved.profileList) || []; if (!self.wifi) return '–'; return l.length ? l.map(function(p){ return p.wifiProfile && p.wifiProfile.ssid; }).join(', ') : 'none'; }, 'Networks the TV remembers. To join a new one, use the last row.'),
    inf('DNS', function(){ return w.dns1 || f.dns1 || '–'; }),
    inf('Internet', function(){ return j.isInternetConnectionAvailable ? 'available' : 'not available'; }),
    lgTgl('network', 'wolwowlOnOff', 'Turn on with a network signal', 'Wake on LAN / Wi-Fi: lets your phone or computer switch the TV on', 'true', 'false'),
    lgTgl('network', 'bleAdvertisingOnOff', 'Bluetooth advertising', 'Lets nearby phones find the TV'),
    lgTgl('network', 'allowMobileDeviceAccess', 'Allow mobile devices to connect', '', 'true', 'false'),
    act('Join a Wi-Fi network (LG Settings)', 'Opens LG’s own Settings for Wi-Fi setup', function(){ launch('com.palm.app.settings'); })
  ]; }},
  {id: 'access', name: 'Remote access', icon: 'remote', title: 'Remote access (SSH / Telnet)', desc: 'How to find this TV and reach it from a computer on the same network. SSH is the safe way in and stays on. Telnet is the emergency door with no password.', info: '/api/remote', build: function(){
    var self = this, j = this.data || {}, ssh = j.ssh || {}, tel = j.telnet || {}, ip = j.ethIp || j.wifiIp || 'the TV’s IP address', rows = [];
    rows.push(head('Find this TV'));
    rows.push(inf('Name', j.host || '–'));
    rows.push(inf('Wired IP address', j.ethIp || 'not connected', 'Use this one when the TV is on a cable. Give it a fixed address in your router (DHCP reservation) so it never changes.'));
    rows.push(inf('Wi-Fi IP address', j.wifiIp || 'not connected'));
    rows.push(inf('MAC address (wired)', j.ethMac || '–', 'What you enter in the router to reserve the address above.'));
    if (j.wifiMac) rows.push(inf('MAC address (Wi-Fi)', j.wifiMac));
    rows.push(head('SSH (secure shell)'));
    rows.push(inf('Status', ssh.listening ? 'on, always' : 'not running', 'SSH is how the project is installed and repaired, so it cannot be switched off here.'));
    rows.push(inf('Connect with', 'ssh root@' + ip, 'Run that in a terminal on a computer on the same network.'));
    rows.push(inf('Keys installed', String(ssh.keys === undefined ? '–' : ssh.keys), ssh.keys > 0 ? 'Key login works from the computer that has the matching key.' : 'No key yet: add one with  ssh-copy-id root@' + ip));
    rows.push(head('Telnet (no password)'));
    rows.push(tgl('Telnet', 'On: anyone on your network can open a root shell with  telnet ' + ip + '. It is the emergency way in if SSH ever breaks. Off: only SSH works. Turning it off needs an SSH key to be installed first, and turning the whole project off (revert.sh) turns it back on.', function(){ return !!tel.listening; }, function(b){
      if (!b && !self.confirmOff) { self.confirmOff = true; toast('Press again to turn Telnet off'); setTimeout(function(){ self.confirmOff = false; if (settingsOn && cats[catIdx].id === 'access') renderCat(false); }, 6000); renderCat(false); return; }
      self.confirmOff = false;
      api('/api/remote/telnet?v=' + (b ? 'on' : 'off'), function(err, r){ toast((r && r.msg) ? ('Telnet: ' + r.msg) : 'Could not change that'); setTimeout(function(){ if (settingsOn && cats[catIdx].id === 'access') renderCat(true); }, 1500); }, 20000); }));
    rows.push(inf('Connect with', 'telnet ' + ip));
    rows.push(head('For developers'));
    rows.push(inf('Debug page (DevTools)', j.devtools && j.devtools.on ? 'on, port 9998' : 'off', 'Only on while the DEBUG flag exists. Normally off.'));
    rows.push(inf('TV helper service', 'port ' + ((j.api && j.api.port) || 8765), 'Used by the Home screen and the phone page. Only the phone page and photo routes answer to other devices, and only with the secret link.'));
    return rows; }},
  {id: 'block', name: 'Ad blocking', icon: 'block', title: 'Ad blocking', desc: 'Pi-hole style: names on these lists are made unreachable for every app on the TV. A name is never blocked if it is on the always-allowed list.', info: '/api/block', build: function(){
    var self = this, d = this.data || {}, lists = d.lists || [], out = [];
    out.push(inf('Names blocked right now', num(d.blocked || 0), 'Each name lookup takes a few milliseconds longer per thousand names.'));
    out.push(head('Block lists'));
    lists.forEach(function(l){
      var sub = l.desc + '  (' + num(l.count) + ' names' + (l.kind === 'remote' ? (l.stamp ? ', updated ' + fmtDate2(l.stamp) : ', not downloaded yet') : '') + ')';
      out.push(tgl(l.name, sub, function(){ return l.on; }, function(b){ l.on = b; toast(b ? 'Turning on ' + l.name + '…' : 'Turning off ' + l.name + '…');
        apiPost('/api/block/set?id=' + l.id + '&v=' + (b ? 'on' : 'off'), '', function(err, j){ if (err || !j || !j.lists) { toast('Could not change that'); } else { self.data = j; toast('Now blocking ' + num(j.blocked) + ' names'); } if (settingsOn) renderCat(false); }, 90000); }));
    });
    out.push(head('Maintenance'));
    out.push(act('Update the downloaded lists now', 'The TV also refreshes them by itself every week. Takes about half a minute.', function(){ apiPost('/api/block/update', '', function(){ toast('Updating the lists…'); setTimeout(function(){ if (settingsOn && cats[catIdx].id === 'block') renderCat(true); }, 30000); }); }));
    out.push(head('Your own lists'));
    out.push(inf('Names you blocked yourself', num(d.custom || 0), 'Add or remove names from your phone: Photo gallery, Add photos from your phone, then scroll to Ad blocking.'));
    out.push(inf('Names you always allow', num(d.allowCustom || 0), 'A name on this list is never blocked, even if a list asks for it. Use it if an app stops working.'));
    return out; }},
  {id: 'services', name: 'Services & privacy', icon: 'shield', title: 'Services & privacy', desc: 'Turn LG’s background services on or off. Everything here is reversible and re-applied after every restart.', info: '/api/svc', build: function(){
    var self = this, list = this.data instanceof Array ? this.data : [], out = [], g = '';
    list.forEach(function(s){
      if (s.group !== g) { g = s.group; out.push(head(g)); }
      if (s.locked) { out.push(inf(s.name, 'Always on', s.desc)); return; }
      out.push(tgl(s.name, s.desc, function(){ return s.on; }, function(b){ s.on = b; toast((b ? 'Turning on: ' : 'Turning off: ') + s.name + '…');
        apiPost('/api/svc/set?id=' + s.id + '&v=' + (b ? 'on' : 'off'), '', function(err, j){ if (err || !(j instanceof Array)) { toast('Could not change that'); return; } self.data = j; toast('Done'); if (settingsOn) renderCat(false); }, 60000); }));
    });
    if (!list.length) out.push(inf('Services', 'unavailable'));
    return out; }},
  {id: 'swupd', name: 'Software updates', icon: 'update', title: 'Software updates', desc: 'Keeps this Home screen and the cleanup current from the project on GitHub. Every install makes a safety copy first, and if the new version does not start the old one comes back by itself.', info: '/api/update', build: function(){
    var self = this, j = this.data || {}, av = j.available, rows = [];
    function again(ms){ setTimeout(function(){ if (settingsOn && cats[catIdx].id === 'swupd') renderCat(true); }, ms); }
    function watch(n){ if (n <= 0) return; setTimeout(function(){ if (!(settingsOn && cats[catIdx].id === 'swupd')) return; api('/api/update', function(err, d){ if (d) { self.data = d; renderCat(false); } watch(n - 1); }, 5000); }, 4000); }
    if (j.busy) rows.push(inf('Working on it', j.status || '…', 'Home restarts for a few seconds when the new version is in.'));
    if (j.resultKind) rows.push(inf(j.resultKind === 'ok' ? 'Last update' : 'Last update did not work', j.result || '', 'Choose “Dismiss” below to clear this message.'));
    rows.push(head('Version'));
    rows.push(inf('Installed', j.installed || '–'));
    rows.push(inf('Newest on GitHub', av ? av + '    ·  update available' : (j.error ? 'could not check' : 'you have the newest'), j.error || ''));
    rows.push(inf('Last check', function(){ var a = j.lastAgoSec; return a === null || a === undefined ? 'not since the TV started' : a < 90 ? 'just now' : a < 5400 ? Math.round(a / 60) + ' min ago' : a < 172800 ? Math.round(a / 3600) + ' h ago' : Math.round(a / 86400) + ' days ago'; }));
    if (av) rows.push(act('Install ' + av + ' now', 'Downloads it, makes a safety copy, installs it and restarts Home (about 20 seconds). If anything goes wrong the old version is put back.', function(){ if (j.busy) return; toast('Installing ' + av + '…'); api('/api/update/apply', function(err){ if (err) { toast('Could not start the update'); return; } j.busy = true; j.status = 'starting'; renderCat(false); watch(15); }, 8000); }));
    rows.push(act('Check for updates now', 'Looks at GitHub right away', function(){ toast('Checking…'); api('/api/update/check', function(err, r){ toast((r && r.msg) || 'Could not reach the TV'); again(800); }, 50000); }));
    if (j.resultKind) rows.push(act('Dismiss', 'Clears the message above', function(){ api('/api/update/conf?k=ack&v=1', function(){ again(300); }); }));
    rows.push(head('Automatic checks'));
    rows.push(chc('When an update is found', 'Tell me: a note appears on Home and you choose when to install. Install by itself: it waits for a quiet moment (screensaver on) and installs. Never: no automatic look at GitHub.', [['notify', 'Tell me'], ['auto', 'Install by itself'], ['off', 'Never check']], function(){ return self.data && self.data.mode || 'notify'; }, function(v){ self.data = self.data || {}; self.data.mode = v; api('/api/update/conf?k=mode&v=' + v, noop); }));
    rows.push(tgl('Check when the TV starts', 'A quiet look at GitHub two minutes after Home is up.', function(){ return (self.data && self.data.startup) !== 'off'; }, function(b){ self.data = self.data || {}; self.data.startup = b ? 'on' : 'off'; api('/api/update/conf?k=startup&v=' + (b ? 'on' : 'off'), noop); }));
    rows.push(chc('Then check every', 'While the TV stays on or in Quick Start standby', [[6, '6 hours'], [12, '12 hours'], [24, '1 day'], [72, '3 days'], [168, '1 week']], function(){ return self.data && self.data.every !== undefined ? Number(self.data.every) : 12; }, function(v){ self.data = self.data || {}; self.data.every = v; api('/api/update/conf?k=every&v=' + v, noop); }));
    var ns = j.notes instanceof Array ? j.notes : [], shown = [];
    function vnew(a, b){ var x = String(a).split('.'), y = String(b).split('.'), i, p, q; for (i = 0; i < Math.max(x.length, y.length); i++) { p = parseInt(x[i], 10) || 0; q = parseInt(y[i], 10) || 0; if (q !== p) return q > p; } return false; }
    ns.forEach(function(e){ if (e && e.v && (av ? vnew(j.installed, e.v) : shown.length < 5)) shown.push(e); });
    rows.push(head(av ? 'What is new in ' + av : 'Recent changes'));
    shown.forEach(function(e){ rows.push(inf(e.v + '    ' + (e.title || ''), e.date || '', (e.notes instanceof Array ? e.notes.join('   •   ') : ''))); });
    if (!shown.length) rows.push(inf('Change notes', 'none yet'));
    if (j.hasBackup) { rows.push(head('If something is wrong')); rows.push(act('Go back to the previous version', 'Puts the safety copy from before the last update back and restarts Home.', function(){ toast('Going back…'); api('/api/update/rollback', function(){ watch(15); }, 8000); })); }
    rows.push(inf('Source', (j.repo || '') + '  (' + (j.branch || '') + ')', 'Only the TV’s own code is replaced. Your photos, settings and the block lists you made are never touched. LG firmware updates stay blocked.'));
    return rows; }},
  {id: 'appupd', name: 'App updates', icon: 'update', title: 'App updates', desc: 'The TV updates your apps by itself, so LG never asks “update this app?” before opening one. TV system (firmware) updates are blocked for good.', info: '/api/appupdates', build: function(){
    var self = this, j = this.data || {}, apps = j.apps || [], pend = (j.pending || []).length;
    var rows = [
    tgl('Update apps automatically', 'On: the TV downloads and installs app updates in the background. Off: LG asks before it opens an app that has an update.', function(){ return (self.data && self.data.mode) !== 'manual'; }, function(b){ self.data = self.data || {}; self.data.mode = b ? 'auto' : 'manual'; api('/api/appupdates/mode?v=' + (b ? 'auto' : 'manual'), function(){ toast(b ? 'Apps now update automatically' : 'LG will ask before updating apps'); }); }),
    tgl('Check when the TV starts', 'A quiet check in the background 30 seconds after the launcher is up, so updates are done before you notice.', function(){ return (self.data && self.data.startup) !== 'off'; }, function(b){ self.data = self.data || {}; self.data.startup = b ? 'on' : 'off'; api('/api/appupdates/conf?k=startup&v=' + (b ? 'on' : 'off'), noop); }),
    chc('Then check every', 'While the TV stays on or in Quick Start standby', [[0, 'Never'], [1, '1 hour'], [3, '3 hours'], [6, '6 hours'], [12, '12 hours'], [24, '24 hours']], function(){ return self.data && self.data.every !== undefined ? self.data.every : 6; }, function(v){ self.data = self.data || {}; self.data.every = v; api('/api/appupdates/conf?k=every&v=' + v, noop); }),
    inf('Flagged by LG', pend ? pend + (pend === 1 ? ' app' : ' apps') : 'none', 'Apps LG’s updater lists for an update. The TV installs them itself when automatic updates are on.'),
    inf('Last check', function(){ var a = j.lastCheckAgoSec; return a === null || a === undefined ? 'since the last restart: not yet' : a < 90 ? 'just now' : a < 5400 ? Math.round(a / 60) + ' min ago' : Math.round(a / 3600) + ' h ago'; }),
    act('Check for app updates now', 'Asks the TV to look right away', function(){ api('/api/appupdates/check', function(err, r){ toast((r && r.msg) || 'Could not reach the TV'); setTimeout(function(){ if (settingsOn && cats[catIdx].id === 'appupd') renderCat(true); }, 10000); }, 30000); }),
    inf('TV system updates', 'Blocked', 'Firmware updates are switched off and re-checked every 5 minutes. They cannot be turned on from here.'),
    head('Installed apps (' + apps.length + ')')];
    apps.forEach(function(a){ rows.push(inf(a.title, a.version + (a.pending ? '    ·  update waiting' : ''))); });
    return rows; }},
  {id: 'about', name: 'About & updates', icon: 'info', title: 'About & updates', desc: '', info: '/api/sysinfo', lg: [['support', ['automaticUpdate']], ['option', ['appUpdateMode']]], build: function(){ var j = this.data || {}, lg = j.lg || {}, m = j.mem || {}; return [
    inf('Model', function(){ return lg.modelName || '–'; }), inf('Firmware', function(){ return lg.firmwareVersion || '–'; }), inf('webOS SDK', function(){ return lg.sdkVersion || '–'; }),
    inf('Memory free', function(){ return (m.availMB || 0) + ' of ' + (m.totalMB || 0) + ' MB'; }), inf('Swap in use', function(){ return (m.swapUsedMB || 0) + ' MB'; }),
    inf('Running for', function(){ var s = j.uptime || 0, h = Math.floor(s / 3600), mi = Math.floor((s % 3600) / 60); return h + ' h ' + mi + ' min'; }), inf('Processes', function(){ return String(j.procs || '–'); }),
    head('Memory guard'),
    inf('Guard', function(){ var g = j.guard || {}; return !g.running ? 'off' : g.level === 'ok' ? 'watching, all fine' : g.level === 'low' ? 'LOW: closing idle apps' : 'CRITICAL: Home photos dropped'; }, 'Checks free memory and swapping every 10 seconds and steps in before the TV slows down. Switch in Services & privacy.'),
    inf('Lowest free memory since start', function(){ var g = j.guard || {}; return g.minAvailMB === null || g.minAvailMB === undefined ? '–' : g.minAvailMB + ' MB'; }),
    inf('Most swap used since start', function(){ var g = j.guard || {}; return g.maxSwapMB === null || g.maxSwapMB === undefined ? '–' : g.maxSwapMB + ' of ' + (g.swapTotalMB || 0) + ' MB'; }),
    inf('Times it had to step in', function(){ var g = j.guard || {}; return (g.lowEpisodes || 0) + ' low, ' + (g.criticalEpisodes || 0) + ' critical'; }, function(){ var g = j.guard || {}; return g.lastAction ? 'Last: ' + g.lastAction : 'It has not needed to act since the TV started.'; }),
    chc('Memory profile', 'How strict the guard is. Automatic picks from the TV’s memory (under 800 MB = Weak: no Home photos at all).', [['auto', 'Automatic'], ['roomy', 'Roomy'], ['standard', 'Standard'], ['weak', 'Weak']], function(){ return (j.guard && j.guard.setting) || 'auto'; }, function(v){ j.guard = j.guard || {}; j.guard.setting = v; api('/api/mem/conf?v=' + v, function(){ toast('Profile: ' + v); }); }),
    head('Updates are blocked on purpose'),
    inf('Automatic system updates', function(){ return (LGC.support || {}).automaticUpdate === 'off' ? 'Off (locked)' : 'ON - will be switched off shortly'; }, 'A firmware update could remove root access and bring LG’s ads back, so this stays off and the update servers are blocked.'),
    inf('Automatic app updates', function(){ return (LGC.option || {}).appUpdateMode === 'manual' ? 'Manual (locked)' : 'Automatic - will be switched off shortly'; }),
    inf('Home', function(){ return 'tv-debloat launcher'; }, 'Undo everything: run revert.sh from the PC, or remove /var/lib/webosbrew/init.d/zz-debloat and reboot.')
  ]; }},
  {id: 'lgall', name: 'LG Settings (legacy)', icon: 'grid', title: 'LG Settings (legacy)', desc: 'Almost everything is in this screen now. LG’s own Settings app is still there for Wi-Fi setup, accounts, channel tuning and the rest.', build: function(){ return [
    act('Open LG Settings', 'LG’s own full Settings app', function(){ launch('com.palm.app.settings'); })
  ]; }}
];

function renderCats(){
  var box = $('setcats'); box.innerHTML = '';
  cats.forEach(function(c, i){ var d = el('div', 'scat', ICON[c.icon] + '<span></span>'); d.lastChild.textContent = c.name; c._el = d; box.appendChild(d); });
  catClass();
}
function catClass(){
  cats.forEach(function(c, i){ c._el.className = 'scat' + (i === catIdx ? (sArea === 'cats' ? ' foc' : ' cur') : ''); });
  var box = $('setcatsbox'), e = cats[catIdx]._el, h = box.clientHeight, bot = e.offsetTop + e.offsetHeight, want = bot > h ? bot - h + 8 : 0;
  catY = want; $('setcats').style.transform = want ? 'translate3d(0,' + (-want) + 'px,0)' : 'translate3d(0,0,0)';
  // while the rail is folded, the name of the highlighted icon floats next to it (the rail itself clips, so it is a separate element)
  var tip = $('cattip'), showTip = sArea === 'cats' && !paneOpen;
  cls($('settings'), 'tip', showTip);
  if (showTip) { tip.textContent = cats[catIdx].name; tip.style.top = (box.offsetTop + e.offsetTop - want + e.offsetHeight / 2 - tip.offsetHeight / 2) + 'px'; }
}
function renderCat(reload){
  var c = cats[catIdx];
  function draw(){
    $('settitle').textContent = c.title; $('setdesc').textContent = c.desc || '';
    var box = $('setrows'); box.innerHTML = ''; sRows = [];
    var items = c.build.call(c);
    items.forEach(function(it){
      if (it.show && !it.show()) return;
      if (it.type === 'thumbs') { renderThumbs(box); return; }
      var r = rowEl(it); box.appendChild(r); if (it.type !== 'head') sRows.push([r]);
    });
    regroupThumbs();      // thumbs group their cells into visual rows
    if (sArea === 'pane') sFocus(Math.min(sR, sRows.length - 1), sC, true);
  }
  if (reload !== false && (c.lg || c.info)) {
    $('settitle').textContent = c.title; $('setdesc').textContent = 'Loading…'; $('setrows').innerHTML = ''; sRows = [];
    var tok = ++renderCat.tok;
    var done = function(){ if (tok === renderCat.tok && settingsOn) draw(); };
    var step2 = function(){ if (c.info) api(c.info, function(err, j){ c.data = j || {}; done(); }, 20000); else done(); };
    if (c.lg) lgLoadMany(c.lg, step2); else step2();
  } else draw();
}
renderCat.tok = 0;
function rowEl(it){
  if (it.type === 'head') { var h = el('div', 'shead'); h.textContent = it.label; it._el = h; return h; }
  var r = el('div', 'srow' + (it.type === 'action' || it.type === 'text' ? ' act' : '')), lab = el('div', 'lab'), val = el('div', 'val');
  var d = typeof it.desc === 'function' ? it.desc() : it.desc;
  lab.innerHTML = '<span></span>' + (d ? '<small></small>' : ''); lab.firstChild.textContent = it.label; if (d) lab.lastChild.textContent = d;
  r.appendChild(lab); r.appendChild(val); r._it = it; it._el = r; paintRow(it); return r;
}
function paintRow(it){
  var val = it._el.lastChild, t = it.type;
  if (t === 'toggle') val.innerHTML = '<div class="tg' + (it.get() ? ' on' : '') + '"></div>';
  else if (t === 'choice') { var v = it.get(), lab = String(v), o = optsOf(it); for (var i = 0; i < o.length; i++) if (String(o[i][0]) === String(v)) lab = o[i][1]; val.innerHTML = '<span class="ch">◀&nbsp; <b></b> &nbsp;▶</span>'; val.querySelector('b').textContent = lab; }
  else if (t === 'slider') { var s = it.get(), pct = Math.max(0, Math.min(100, (s - it.min) * 100 / (it.max - it.min))); val.innerHTML = '<div class="sl"><i style="width:' + pct + '%"></i></div><span>' + s + '</span>'; }
  else if (t === 'info') val.textContent = typeof it.value === 'function' ? it.value() : it.value;
  else if (t === 'text') val.textContent = it.get();
  else if (t === 'action') val.textContent = it.val || '▶';
}
function thumbCell(n){
  var d = el('div', 'gt'), st = Stage.make(), im = st.lastChild; d.appendChild(st);
  im.onload = function(){ Stage.place(st, im.naturalWidth, im.naturalHeight, crops[n]); };
  im.src = thumbUrl(n); d._it = {type: 'thumb', name: n}; return d;
}
function renderThumbs(box){
  var g = el('div', 'gthumbs'); box.appendChild(g);
  photos.forEach(function(n){ g.appendChild(thumbCell(n)); });
  if (!photos.length) { var e = el('div', 'srow', 'No photos yet. Choose “Add photos from your phone”.'); g.appendChild(e); }
  g._isThumbs = true;
}
function regroupThumbs(){
  var g = $('setrows').querySelector('.gthumbs'); if (!g) return;
  var cells = [].slice.call(g.querySelectorAll('.gt')), top = -1, row = null;
  cells.forEach(function(c){ if (c.offsetTop !== top) { top = c.offsetTop; row = []; sRows.push(row); } row.push(c); });
}
function sFocus(r, c, keep){
  if (!sRows.length) return;
  var old = sRows[sR] && sRows[sR][sC]; if (old) old.className = old.className.replace(' foc', '');
  sR = Math.max(0, Math.min(sRows.length - 1, r)); sC = Math.max(0, Math.min(sRows[sR].length - 1, c));
  var e = sRows[sR][sC]; e.className += ' foc';
  var pane = $('setpane'), pr = pane.getBoundingClientRect(), er = e.getBoundingClientRect(), fs = parseFloat(getComputedStyle(document.documentElement).fontSize);
  var rel = er.bottom + setY - pr.top;           // position inside the un-scrolled content
  var h = pr.height, want = rel > h - 2 * fs ? rel - h + 2 * fs : 0;
  setY = want; $('setinner').style.transform = want ? 'translate3d(0,' + (-want) + 'px,0)' : 'translate3d(0,0,0)';
}
function setArea(a){ sArea = a; catClass(); if (a === 'pane') { sFocus(0, 0); } else { var o = sRows[sR] && sRows[sR][sC]; if (o) o.className = o.className.replace(' foc', ''); } }
function paneSet(on){ paneOpen = on; cls($('settings'), 'open', on); catClass(); }
// OK on an icon of the rail: unfold that category next to the rail and move into it
function openPane(){ paneSet(true); sArea = 'pane'; sR = sC = 0; setY = 0; $('setinner').style.transform = ''; catClass(); renderCat(true); }
var BRV = null;
function brLoad(){ api('/api/brightness', function(err, j){ if (j && j.brightness) { BRV = j.brightness; if (settingsOn) renderCat(false); } }); }
function openSettings(id){
  if (settingsOn) return;
  brLoad();
  settingsOn = true; paneOpen = false; $('settings').className = 'on'; mpush('settings'); clearTimeout(idleT);
  if (!$('setcats').firstChild) renderCats();
  var named = false;
  catIdx = 0;
  if (id) for (var i = 0; i < cats.length; i++) if (cats[i].id === id) { catIdx = i; named = true; }
  sArea = 'cats'; sR = sC = 0; setY = 0; $('setinner').style.transform = ''; catClass();
  if (named) openPane();
}
function closeSettings(){
  settingsOn = false; mpop('settings'); $('settings').className = '';
  if (SETMODE) { apiPost('/api/settings/close', ''); return; }
  activity(); refreshPhotos(function(){ if (!hasBg()) bgApply(true); });
}
function adjust(it, dir){
  var t = it.type;
  if (t === 'toggle') { it.set(!it.get()); }
  else if (t === 'choice') { var o = optsOf(it), i = 0; for (var k = 0; k < o.length; k++) if (String(o[k][0]) === String(it.get())) i = k; i = Math.max(0, Math.min(o.length - 1, i + dir)); if (String(o[i][0]) === String(it.get())) return true; it.set(o[i][0]); }
  else if (t === 'slider') { var v = Math.max(it.min, Math.min(it.max, it.get() + dir * it.step * (adjust.mult || 1))); if (v === it.get()) return true; if (it.local) it.local(v); it.set(v); }
  else return false;
  paintRow(it); return true;
}
function settingsKey(k, e){
  if (sArea === 'cats') {
    if (k === 38 && catIdx > 0) { catIdx--; catClass(); if (paneOpen) renderCat(true); }
    else if (k === 40 && catIdx < cats.length - 1) { catIdx++; catClass(); if (paneOpen) renderCat(true); }
    else if (k === 39 || k === 13) { if (!paneOpen) openPane(); else if (sRows.length) setArea('pane'); }
    else if (k === 461 || k === 27 || k === 8 || k === 37) { if (paneOpen) paneSet(false); else closeSettings(); }
    return;
  }
  var cell = sRows[sR] && sRows[sR][sC], it = cell && cell._it, multi = sRows[sR] && sRows[sR].length > 1 || (it && it.type === 'thumb');
  adjust.mult = (k === 37 || k === 39) ? boost(k) : 1;
  if (k === 38) { if (sR > 0) { var nr = sR - 1, x = cell.getBoundingClientRect().left, b = 0, bd = 1e9; for (var i = 0; i < sRows[nr].length; i++) { var d = Math.abs(sRows[nr][i].getBoundingClientRect().left - x); if (d < bd) { bd = d; b = i; } } sFocus(nr, b); } }
  else if (k === 40) { if (sR < sRows.length - 1) { var nr2 = sR + 1, x2 = cell.getBoundingClientRect().left, b2 = 0, bd2 = 1e9; for (var j = 0; j < sRows[nr2].length; j++) { var d2 = Math.abs(sRows[nr2][j].getBoundingClientRect().left - x2); if (d2 < bd2) { bd2 = d2; b2 = j; } } sFocus(nr2, b2); } }
  else if (k === 37) { if (multi) { if (sC > 0) sFocus(sR, sC - 1); else setArea('cats'); } else if (it.type === 'choice' || it.type === 'slider') adjust(it, -1); else setArea('cats'); }
  else if (k === 39) { if (multi) { if (sC < sRows[sR].length - 1) sFocus(sR, sC + 1); } else adjust(it, 1); }
  else if (k === 13) {
    if (it.type === 'thumb') thumbMenu(it.name);
    else if (it.type === 'toggle') adjust(it, 1);
    else if (it.type === 'choice') adjust(it, 1);
    else if (it.type === 'action' || it.type === 'text') it.run();
  }
  else if (k === 461 || k === 27 || k === 8) { paneSet(false); setArea('cats'); }
}
function thumbMenu(name){
  panelOpen('Photo', [
    ['Adjust framing', 'move / zoom, see Home on top', function(){ panelClose(); edOpen(name); }],
    ['Use as Home background now', '', function(){ panelClose(); var i = photos.indexOf(name); if (i >= 0 && !SETMODE) { S.bg.on = true; saveSettings(); bgShow(i); toast('Background changed'); } else toast('Close Settings to see it'); }],
    ['Delete this photo', '', function(){ panelOpen('Delete this photo?', [['Yes, delete', '', function(){ panelClose();
        api('/api/delete?name=' + encodeURIComponent(name), function(err){ if (err) return toast('Could not delete'); photos = photos.filter(function(n){ return n !== name; }); delete crops[name]; if (bgIx >= photos.length) bgIx = 0; renderCat(false); toast('Photo deleted'); if (!photos.length && !SETMODE) bgApply(true); }); }], ['Cancel', '', panelClose]]); }],
    ['Cancel', '', panelClose]]);
}

/* ================= photo framing editor (TV remote) ================= */
// The photo fills the screen exactly as it will on Home / the screensaver. Arrow keys move the view, OK switches to zoom,
// Back opens the menu. A see-through copy of Home lies on top so you can see what the clock and the app row will cover.
var ed = null;
function ghostBuild(done){
  function go(){
    var g = $('ghost'); g.innerHTML = '';
    var v = $('view').cloneNode(true); v.style.transform = 'none';
    [].forEach.call(v.querySelectorAll('.foc'), function(n){ n.className = n.className.replace(' foc', ''); });
    g.appendChild(v); done();
  }
  if (!apps.length) { loadApps(function(){ lastT = ''; tick(); wxRender(); go(); }); } else { tick(); go(); }
}
function edOpen(name){
  var c0 = crops[name] || null;
  ed = {name: name, c: Stage.norm(c0 && c0.x !== undefined ? c0 : Stage.auto(c0)), orig: c0, mode: 'move', ghost: true, im: null, nw: 0, nh: 0, st: null};
  ed.c.a = c0 && c0.a; ed.c.e = c0 && c0.e;
  $('edstage').innerHTML = ''; $('edinfo').textContent = 'Loading…'; $('editor').className = 'on'; mpush('editor'); edMode();
  ghostBuild(function(){ cls($('ghost'), 'on', ed && ed.ghost); });
  var im = new Image(); if (!MOCK) im.crossOrigin = 'anonymous';
  im.onload = function(){
    if (!ed || ed.name !== name) return;
    var st = Stage.make(); st.lastChild.src = im.src; $('edstage').appendChild(st);
    ed.im = im; ed.nw = im.naturalWidth; ed.nh = im.naturalHeight; ed.st = st; ed.c = Stage.norm(ed.c, ed.nw, ed.nh);
    if (!ed.c.e && !MOCK) { var e0 = Stage.sample(im, 5); if (e0) ed.c.e = e0; }      // measured now so the edge fade is visible while you move the photo
    edRender();
  };
  im.onerror = function(){ toast('Could not load the photo'); edClose(); };
  im.src = httpPhotoUrl(name);
}
function edMode(){ $('edmode').textContent = ed && ed.mode === 'zoom' ? 'Zoom: ▲ in  ▼ out' : 'Move'; }
function edRender(){
  if (!ed || !ed.st) return;
  Stage.place(ed.st, ed.nw, ed.nh, ed.c);
  $('edinfo').textContent = 'Zoom ' + ed.c.z.toFixed(2) + '×   ·   ' + Math.round(ed.c.x * 100) + '% across, ' + Math.round(ed.c.y * 100) + '% down';
}
function edKey(k){
  if (k === 461 || k === 27 || k === 8) { edMenu(); return; }
  if (k === 13) { ed.mode = ed.mode === 'move' ? 'zoom' : 'move'; edMode(); return; }
  var d = k === 37 ? [-1, 0] : k === 39 ? [1, 0] : k === 38 ? [0, -1] : k === 40 ? [0, 1] : null;
  if (!d || !ed.st) return;
  var m = boost(k), c = ed.c;
  if (ed.mode === 'zoom' && d[1]) { c.z = Stage.clamp(c.z * (d[1] < 0 ? 1 + 0.035 * m : 1 / (1 + 0.035 * m)), Stage.minZoom(ed.nw, ed.nh), 3.5); }
  else { var g = Stage.geom(ed.nw, ed.nh, c); c.x = Stage.clamp(c.x + d[0] * 0.012 * m / g.w, 0, 1); c.y = Stage.clamp(c.y + d[1] * 0.012 * m / g.h, 0, 1); }
  edRender();
}
function edMenu(){
  panelOpen('Photo framing', [
    ['Save', '', function(){ panelClose(); edSave(); }],
    ['Keep editing', '', panelClose],
    ['Home overlay', ed.ghost ? 'showing' : 'hidden', function(){ ed.ghost = !ed.ghost; cls($('ghost'), 'on', ed.ghost); panelClose(); }],
    ['Reset to automatic', '', function(){ var a = Stage.auto(ed.c); ed.c.x = a.x; ed.c.y = a.y; ed.c.z = 1; delete ed.c.e; panelClose(); edRender(); }],
    ['Discard changes', '', function(){ panelClose(); edClose(); }]]);
}
function edSave(){
  var name = ed.name, c = {x: Math.round(ed.c.x * 1000) / 1000, y: Math.round(ed.c.y * 1000) / 1000, z: Math.round(ed.c.z * 1000) / 1000};
  if (ed.c.a) c.a = ed.c.a;
  var e = (!MOCK && ed.im) ? Stage.sample(ed.im, 5) : null; if (e) c.e = e; else if (ed.c.e) c.e = ed.c.e;
  crops[name] = c;
  apiPost('/api/crop?name=' + encodeURIComponent(name), JSON.stringify(c), function(err){ toast(err ? 'Could not save the framing' : 'Framing saved'); });
  edClose();
  if (!SETMODE && photos[bgIx] === name) bgShow(bgIx);
  if (settingsOn) renderCat(false);
}
function edClose(){ mpop('editor'); $('editor').className = ''; $('ghost').innerHTML = ''; $('edstage').innerHTML = ''; ed = null; }

/* ================= input ================= */
var KEYS = {37: 'L', 38: 'U', 39: 'R', 40: 'D'};
// Back on Home returns to the app / input you were in before Home (the TV side remembers it: lastapp.sh)
function goBack(){ api('/api/back', function(err, j){ if (err) return toast('Could not reach the TV'); if (!j || !j.back) toast('Nothing to go back to yet'); }); }
function onKey(e){
  var k = e.keyCode, wasSaver = saverOn;
  activity();
  if (wasSaver) { saverStop(); e.preventDefault(); return; }
  var m = mtop();
  if (m === 'keypad') { keypadKey(k, e); e.preventDefault(); return; }
  if (m === 'qr') { if (k === 461 || k === 27 || k === 8 || k === 13) qrClose(); e.preventDefault(); return; }
  if (m === 'panel') {
    if (k === 38) panelFocus(pIdx - 1); else if (k === 40) panelFocus(pIdx + 1);
    else if (k === 13) { var d = pItems[pIdx]; if (d && d._pick) d._pick(); }
    else if (k === 461 || k === 27 || k === 8 || k === 37) panelClose();
    e.preventDefault(); return;
  }
  if (m === 'editor') { edKey(k); e.preventDefault(); return; }
  if (m === 'settings') { settingsKey(k, e); e.preventDefault(); return; }
  if (SETMODE) return;
  if (k === 461 || k === 27 || k === 8) { goBack(); e.preventDefault(); return; }
  if (KEYS[k]) { move(KEYS[k]); e.preventDefault(); } else if (k === 13) { activate(); e.preventDefault(); }
}
document.addEventListener('keydown', onKey);
// the Magic Remote's scroll wheel (which is also what makes the pointer appear) moves the highlight up / down, like the arrow keys, in lists, panels and Settings
var wheelAt = 0;
document.addEventListener('wheel', function(e){
  var now = Date.now(); if (now - wheelAt < 90) return; wheelAt = now;
  var k = e.deltaY > 0 ? 40 : e.deltaY < 0 ? 38 : 0; if (!k) return;
  onKey({keyCode: k, preventDefault: function(){ try { e.preventDefault(); } catch (x) {} }});
});
document.addEventListener('mousemove', function(){ if (saverOn) saverStop(); activity(); });
function upTo(n, re, stop){ while (n && n !== stop) { if (n.className && re.test(n.className)) return n; n = n.parentNode; } return null; }
// pointer (if it ever shows): hover moves the highlight on Home and on the Settings rail, a click does what OK does
document.addEventListener('mouseover', function(e){
  if (saverOn) return;
  var m = mtop();
  if (m === 'settings') { if (paneOpen || sArea !== 'cats') return; var c = upTo(e.target, /(^| )scat( |$)/, document.body); if (c) for (var i = 0; i < cats.length; i++) if (cats[i]._el === c && catIdx !== i) { catIdx = i; catClass(); } return; }
  if (SETMODE || m) return;
  var n = upTo(e.target, /(^| )(tile|hbtn)( |$)/, document.body);
  if (n) for (var r = 0; r < rows.length; r++) for (var q = 0; q < rows[r].length; q++) if (rows[r][q] === n) { focusItem(r, q); return; }
});
// pop-up lists (inputs, network, photo menu...), the number pad and the QR page also answer the pointer
$('panel').addEventListener('mouseover', function(e){ var n = upTo(e.target, /(^| )pitem( |$)/, this); if (n) { var i = pItems.indexOf(n); if (i >= 0 && i !== pIdx) panelFocus(i); } });
$('panel').addEventListener('click', function(e){
  var n = upTo(e.target, /(^| )pitem( |$)/, this);
  if (n) { var i = pItems.indexOf(n); if (i >= 0) { panelFocus(i); if (n._pick) n._pick(); } } else if (e.target === this) panelClose();
});
$('keym').addEventListener('click', function(e){ var n = upTo(e.target, /(^| )kk( |$)/, this); if (n) { var i = kBtns.indexOf(n); if (i >= 0) { kIdx = i; keypadDraw(); keypadKey(13, null); } } });
$('qrm').addEventListener('click', function(){ qrClose(); });
$('settings').addEventListener('click', function(e){
  if (mtop() !== 'settings') return;
  var c = upTo(e.target, /(^| )scat( |$)/, this);
  if (c) { for (var i = 0; i < cats.length; i++) if (cats[i]._el === c) { catIdx = i; openPane(); } return; }
  var rw = upTo(e.target, /(^| )(srow|gt)( |$)/, this);
  if (rw) for (var r = 0; r < sRows.length; r++) for (var q = 0; q < sRows[r].length; q++) if (sRows[r][q] === rw) { sArea = 'pane'; catClass(); sFocus(r, q); settingsKey(13); }
});
document.addEventListener('click', function(e){
  var n = e.target; while (n && n !== document.body) { if (n.className && /(^| )(tile|hbtn)( |$)/.test(n.className)) break; n = n.parentNode; }
  if (!n || n === document.body || mstack.length) return;
  for (var r = 0; r < rows.length; r++) for (var c = 0; c < rows[r].length; c++) if (rows[r][c] === n) { focusItem(r, c); activate(); }
});

/* ================= lifecycle ================= */
function netLabel(){ api('/api/net', function(err, j){ if (!j || !j.returnValue) return; $('netlabel').textContent = (j.wired && j.wired.state === 'connected') ? 'Ethernet' : (j.wifi && j.wifi.state === 'connected') ? 'Wi-Fi' : 'Offline'; }); }
var appsAt = 0;
function onShow(){
  tick(); activity();
  api('/api/saver/take', function(err, j){ if (j && j.take && S.saver.on) saverStart(); });      // LG's own screensaver was replaced by ours (saver-take.sh)
  if (Date.now() - appsAt > 60000) { appsAt = Date.now(); loadApps(function(ok){ if (ok) focusItem(Math.min(1, rows.length - 1), 0); }); }
  wxLoad(false); loadSettings(); refreshPhotos(function(ch){ if (ch) bgApply(true); });
  if (photos.length && S.bg.on && Date.now() - bgAt > Math.max(1, S.bg.everyMin) * 60000) bgShow(bgIx + 1);
  netLabel();
}
function onHide(){ clearTimeout(idleT); if (saverOn) saverStop(); if (mtop() === 'panel') panelClose(); }

if (INPMODE) {
  /* ---- Inputs overlay: only the Inputs list (opened by the Input / Guide keys); a second press of the key (webOSRelaunch) closes it ---- */
  document.documentElement.className = 'mode-settings'; cls(document.body, 'mode-settings', true);
  loadSettings(function(){ openInputs(); });
  var inpAt = Date.now(); document.addEventListener('webOSRelaunch', function(){ if (Date.now() - inpAt > 1500) panelClose(); });
  requestAnimationFrame(function(){ requestAnimationFrame(function(){ api('/api/qs?m=inputs-painted', noop); }); });
} else if (SETMODE) {
  /* ---- Settings overlay: only the Settings screen; Back at the top level closes the page ---- */
  document.documentElement.className = 'mode-settings'; cls(document.body, 'mode-settings', true);
  tick();
  loadSettings(function(){ refreshPhotos(function(){ if (settingsOn && cats[catIdx].id === 'gallery') renderCat(false); }); });
  openSettings(); var T1 = Date.now();
  // the Settings key while we are open: WebAppMgr launches the running page again and tells it so (webOSRelaunch) -> close (not in the first 1.5 s, in case the first launch sends one too)
  var setAt = Date.now(); document.addEventListener('webOSRelaunch', function(){ if (Date.now() - setAt > 1500) closeSettings(); });
  requestAnimationFrame(function(){ requestAnimationFrame(function(){ var t = window.performance && performance.timing || {}, n = t.navigationStart || 0; api('/api/qs?m=settings-painted_nav=' + (Date.now() - n) + '_dom=' + (t.domContentLoadedEventEnd - n) + '_load=' + (t.loadEventEnd - n) + '_resp=' + (t.responseEnd - n) + '_dl=' + (t.domLoading - n) + '_script=' + (t.domInteractive - n) + '_js0=' + (T0 - n) + '_js1=' + (T1 - n), noop); }); });     // first frame is on screen: lets the TV log how long the key took
  if (MOCK && /settings=(\w+)/.test(location.search)) setTimeout(function(){ for (var i = 0; i < cats.length; i++) if (cats[i].id === /settings=(\w+)/.exec(location.search)[1]) { catIdx = i; } catClass(); openPane(); if (/row=(\d+)/.test(location.search)) sFocus(parseInt(/row=(\d+)/.exec(location.search)[1], 10), 0); }, 1200);
} else {
  document.addEventListener('visibilitychange', function(){ if (document.hidden) onHide(); else { if (!settingsOn) focusItem(1, 0); onShow(); } });
  document.addEventListener('webOSRelaunch', function(){ if (saverOn) saverStop(); while (mstack.length) { var t = mtop(); if (t === 'settings') closeSettings(); else if (t === 'panel') panelClose(); else if (t === 'qr') qrClose(); else if (t === 'keypad') keypadClose(); else if (t === 'editor') edClose(); else mstack.pop(); } focusItem(1, 0); onShow(); });
  window.addEventListener('resize', function(){ layoutRows(); });
  // the Settings overlay sits on top of Home without hiding it, so Home never gets a "visible" event: pick up what changed when the overlay closes
  window.addEventListener('focus', function(){ if (document.hidden || saverOn) return; updPoll(); loadSettings(); refreshPhotos(function(ch){ if (ch) { if (!hasBg()) bgApply(true); else if (photos[bgIx]) bgShow(bgIx); } }); });
  setInterval(function(){ if (!document.hidden) tick(); }, 1000);
  setInterval(function(){ if (!document.hidden) wxLoad(false); }, 60000);
  // pick up changes made from the phone page (settings, uploads, framing): cheap local calls every 30 s while Home is visible
  setInterval(function(){ if (document.hidden || saverOn || ed) return; loadSettings(); refreshPhotos(function(ch){ if (ch) { if (!hasBg()) bgApply(true); if (settingsOn && cats[catIdx].id === 'gallery') renderCat(false); } }); }, 30000);

  /* ================= start ================= */
  tick(); appsAt = Date.now(); focusItem(0, 0);
  loadSettings(function(){
    wxLoad(true);
    refreshPhotos(function(){ bgPickNew(); bgSchedule(); });
  });
  loadApps(function(ok){
    layoutRows(); focusItem(Math.min(1, rows.length - 1), 0);
    api('/api/ready', function(){ dlog('ready apps=' + apps.length + ' ok=' + ok + ' ua=' + navigator.userAgent.slice(-40)); });
  });
  setTimeout(function(){ api('/api/ready', noop); }, 4000);    // ready even if the app list is slow, so the 30 s Home watchdog only trips when the API is gone
  netLabel(); activity();
  // fast path of the Settings key (api.sh /api/ui/*): while Home is in front the compositor hands the key to this page, which opens its own Settings instead of a second page
  function uiWait(){
    if (MOCK) return;
    xhr('GET', API + '/api/ui/wait', null, function(err, j){
      if (j && j.cmd === 'settings') { api('/api/ui/ack', noop, 3000); uiSettings(); }
      else if (j && (j.cmd === 'lowmem' || j.cmd === 'normal')) memMode(j.cmd === 'lowmem');
      setTimeout(uiWait, err ? 3000 : 30);
    }, 110000);
  }
  function memMode(on){ if (LOWMEM === on) return; LOWMEM = on; dlog('memory mode ' + (on ? 'low' : 'normal')); bgApply(true); }
  function uiSettings(){
    if (settingsOn) { closeSettings(); return; }
    if (saverOn) saverStop();
    while (mstack.length) { var t = mtop(); if (t === 'panel') panelClose(); else if (t === 'qr') qrClose(); else if (t === 'keypad') keypadClose(); else if (t === 'editor') edClose(); else mstack.pop(); }
    openSettings(); api('/api/qs?m=inhome-settings-open', noop);
  }
  setTimeout(uiWait, 1500);
  setTimeout(updPoll, MOCK ? 1200 : 25000); setInterval(function(){ if (!document.hidden && !saverOn) updPoll(); }, 600000);
  if (MOCK && /saver/.test(location.search)) setTimeout(saverStart, 1200);
  if (MOCK && /settings=(\w+)/.test(location.search)) setTimeout(function(){ openSettings(/settings=(\w+)/.exec(location.search)[1]); setArea('pane'); if (/row=(\d+)/.test(location.search)) sFocus(parseInt(/row=(\d+)/.exec(location.search)[1], 10), 0); }, 1500);
  if (MOCK && /rail=1/.test(location.search)) setTimeout(function(){ openSettings(); }, 1500);
  if (MOCK && /edit=(\S+?)(&|$)/.test(location.search)) setTimeout(function(){ edOpen(/edit=(\S+?)(&|$)/.exec(location.search)[1]); }, 1500);
}
applyUi();
window.__tvhome = {set: setPath, saver: saverStart, stop: saverStop, bg: function(){ bgShow(bgIx + 1); }, settings: openSettings, photos: function(){ return photos.length; }, S: function(){ return S; }, wx: function(){ return wx; }, crops: function(){ return crops; }, edit: edOpen, key: function(k){ document.dispatchEvent(new KeyboardEvent('keydown', {keyCode: k})); }};
})();
