/* Home launcher logic for LG webOS 4.x (Chromium 53): ES5 style on purpose. */
(function(){
'use strict';

/* ================= configuration & settings ================= */
var API = 'http://127.0.0.1:8765';
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
  saver: {on: true, idleMin: 2, photos: true, slideSec: 12, weather: true},
  dock: ['netflix','youtube.leanback.v4','hulu','com.disney.disneyplus-prod'],
  hide: ['webos.day','com.webos.app.homeconnect','com.webos.app.home','com.webos.app.fullhome']
};
var MOCK = window.__MOCK__ || null;
var S = clone(DEFAULTS);

function $(id){ return document.getElementById(id); }
function clone(o){ return JSON.parse(JSON.stringify(o)); }
function merge(d, s){ for (var k in s) { if (s[k] && typeof s[k] === 'object' && !(s[k] instanceof Array)) { if (!d[k] || typeof d[k] !== 'object') d[k] = {}; merge(d[k], s[k]); } else d[k] = s[k]; } return d; }
function el(tag, cls, html){ var e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
function p2(n){ return n < 10 ? '0' + n : '' + n; }
function lsGet(k){ try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch(e){ return null; } }
function lsSet(k, v){ try { localStorage.setItem(k, JSON.stringify(v)); } catch(e){} }
function noop(){}

/* ================= http / api ================= */
function xhr(method, url, body, cb, timeout){
  var x = new XMLHttpRequest(); x.open(method, url, true); x.timeout = timeout || 10000;
  x.onload = function(){ var j = null; try { j = JSON.parse(x.responseText); } catch(e){} cb(x.status >= 200 && x.status < 300 ? null : new Error('HTTP ' + x.status), j); };
  x.onerror = x.ontimeout = function(){ cb(new Error('net'), null); };
  x.send(body || null);
}
function mockFor(path){
  var q = path.split('?'), p = q[0];
  if (p === '/api/lg/get') { var m = /cat=(\w+)/.exec(q[1] || ''); return {returnValue: true, settings: (MOCK.lg || {})[m ? m[1] : ''] || {}}; }
  return MOCK[p] !== undefined ? MOCK[p] : {};
}
function api(path, cb){ if (MOCK) { setTimeout(function(){ cb(null, clone(mockFor(path))); }, 15); return; } xhr('GET', API + path, null, cb, 12000); }
function apiPost(path, body, cb){ if (MOCK) { setTimeout(function(){ cb(null, {ok: true, returnValue: true}); }, 15); return; } xhr('POST', API + path, body, cb || noop, 12000); }
var logN = 0;
function dlog(m){ if (MOCK || logN++ > 200) return; try { xhr('POST', API + '/api/log', String(m), noop, 3000); } catch(e){} }
window.onerror = function(m, u, l){ dlog('JSERR ' + m + ' @' + l); };
function toast(m){ var t = $('toast'); t.textContent = m; t.className = 'on'; clearTimeout(toast.h); toast.h = setTimeout(function(){ t.className = ''; }, 3000); }

/* ================= settings store ================= */
var saveT = null, lastSavedJson = '';
function saveSettings(){
  clearTimeout(saveT);
  saveT = setTimeout(function(){ saveT = null; lastSavedJson = JSON.stringify(S); apiPost('/api/settings', lastSavedJson, function(err){ if (err) dlog('settings save failed'); }); }, 400);
}
function setPath(path, v){ var p = path.split('.'), o = S; for (var i = 0; i < p.length - 1; i++) o = o[p[i]]; o[p[p.length - 1]] = v; saveSettings(); settingsChanged(path); }
function getPath(path){ var p = path.split('.'), o = S; for (var i = 0; i < p.length; i++) o = o[p[i]]; return o; }
function settingsChanged(path){
  if (path.indexOf('weather.') === 0) wxLoad(true);
  if (path.indexOf('clock24') === 0) { lastT = ''; tick(); }
  if (path.indexOf('bg.') === 0) { bgApply(true); }
  if (path.indexOf('saver.') === 0) activity();
}
function applyRemoteSettings(j){
  if (!j || typeof j !== 'object') return;
  var n = merge(clone(DEFAULTS), j), a = JSON.stringify(n), b = JSON.stringify(S);
  if (a === b || saveT) return;      // unchanged, or we have an unsaved local edit
  var wxCh = JSON.stringify(n.weather) !== JSON.stringify(S.weather), bgCh = JSON.stringify(n.bg) !== JSON.stringify(S.bg);
  S = n; lastT = ''; tick(); if (wxCh) wxLoad(true); if (bgCh) bgApply(true); activity(); if (settingsOn) renderCat(false);
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
  if (MOCK) return cb({lat: 40.42, lon: -86.9, place: 'West Lafayette', key: key});
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
  api('/api/launch?id=' + encodeURIComponent(id), function(err, j){ if (err || (j && j.returnValue === false)) toast('Could not open ' + id + (j && j.errorText ? ' (' + j.errorText + ')' : '')); });
}

/* ================= photos (gallery) & Home background ================= */
var photos = [], photosLoaded = false;
function photoUrl(n){ return (MOCK && MOCK.photoBase ? MOCK.photoBase : 'photos/') + encodeURIComponent(n); }
function thumbUrl(n){ return (MOCK && MOCK.photoBase ? MOCK.photoBase : 'photos/') + 'thumbs/' + encodeURIComponent(n); }
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
    if (cb) cb(changed);
  });
}
var bgIx = -1, bgFlip = 0, bgT = null, bgAt = 0;
function bgShow(ix){
  if (!photos.length || !S.bg.on) return;
  bgIx = ((ix % photos.length) + photos.length) % photos.length; bgAt = Date.now(); lsSet('bgName', photos[bgIx]);
  var a = $(bgFlip ? 'bgB' : 'bgA'), b = $(bgFlip ? 'bgA' : 'bgB'), im = new Image();
  im.onload = function(){
    a.firstChild.src = im.src; a.className = 'bgl show'; b.className = 'bgl'; document.body.className = 'hasbg'; bgFlip = 1 - bgFlip;
    setTimeout(function(){ if (b.className.indexOf('show') < 0) b.firstChild.removeAttribute('src'); }, 3000);
  };
  im.onerror = function(){ dlog('bg photo failed ' + photos[bgIx]); };
  im.src = photoUrl(photos[bgIx]);
}
function bgPickNew(){
  if (!photos.length || !S.bg.on) return;
  var last = lsGet('bgName'), n = photos.length, k = Math.floor(Math.random() * n);
  if (n > 1 && photos[k] === last) k = (k + 1 + Math.floor(Math.random() * (n - 1))) % n;
  bgShow(k);
}
function bgSchedule(){ clearTimeout(bgT); bgT = setTimeout(function(){ if (!document.hidden && !saverOn && !settingsOn) bgShow(bgIx + 1); bgSchedule(); }, Math.max(1, S.bg.everyMin) * 60000); }
function bgApply(reschedule){
  if (!S.bg.on || !photos.length) { $('bgA').className = $('bgB').className = 'bgl'; document.body.className = ''; $('bgA').firstChild.removeAttribute('src'); $('bgB').firstChild.removeAttribute('src'); }
  else if (reschedule && bgIx < 0) bgPickNew();
  else if (document.body.className !== 'hasbg') bgShow(bgIx < 0 ? 0 : bgIx);
  if (reschedule) bgSchedule();
}

/* ================= screensaver / AFK ================= */
var saverOn = false, pIx = 0, flip = 0, idleT = null, slideT = null, driftT = null;
function showNext(){
  if (!saverOn) return;
  var a = $(flip ? 'sb' : 'sa'), b = $(flip ? 'sa' : 'sb');
  var src = photoUrl(photos[pIx]); pIx = (pIx + 1) % photos.length; var im = new Image();
  im.onload = function(){
    if (!saverOn) return;
    a.src = src; a.className = 'show'; b.className = ''; flip = 1 - flip;
    slideT = setTimeout(showNext, Math.max(4, S.saver.slideSec) * 1000);
    setTimeout(function(){ if (!a.className) return; b.removeAttribute('src'); }, 2200);
  };
  im.onerror = function(){ dlog('photo failed ' + src); slideT = setTimeout(showNext, 1000); };
  im.src = src;
}
function drift(){
  var s = $('sinfo'); s.style.left = (3 + Math.random() * 45) + 'rem'; s.style.bottom = (3 + Math.random() * 28) + 'rem';
  driftT = setTimeout(drift, 60000);
}
function saverStart(){
  if (saverOn || document.hidden || mstack.length || settingsOn) return;
  saverOn = true; lastT = lastD = ''; tick(); wxRender();
  var withPhotos = S.saver.photos && photos.length > 0;
  $('saver').className = 'on' + (withPhotos ? '' : ' nophoto');
  $('scrimS').style.display = withPhotos ? 'block' : 'none';
  if (withPhotos) { pIx = (bgIx + 1) % photos.length; showNext(); } else { drift(); }
  dlog('saver on photos=' + withPhotos);
}
function saverStop(){
  if (!saverOn) return;
  saverOn = false; clearTimeout(slideT); clearTimeout(driftT); $('saver').className = ''; $('sa').className = ''; $('sb').className = '';
  var s = $('sinfo'); s.style.left = ''; s.style.bottom = '';
  setTimeout(function(){ if (!saverOn) { $('sa').removeAttribute('src'); $('sb').removeAttribute('src'); } }, 1500);
}
function activity(){ clearTimeout(idleT); if (document.hidden || !S.saver.on) return; idleT = setTimeout(saverStart, Math.max(1, S.saver.idleMin) * 60000); }

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
function panelClose(){ if (mtop() === 'panel') mpop('panel'); $('panel').className = ''; }
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
function qrOpen(){
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
function qrClose(){ clearInterval(qrPoll); mpop('qr'); $('qrm').className = ''; refreshPhotos(function(){ if (settingsOn) renderCat(false); if (!document.body.className) bgApply(true); }); }

/* ================= LG settings access ================= */
var LGC = {};
function lgLoad(cat, keys, cb){
  api('/api/lg/get?cat=' + cat + '&keys=' + keys.join(','), function(err, j){
    if (j && j.settings) LGC[cat] = j.settings; else if (!LGC[cat]) LGC[cat] = {};
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

/* ================= Settings screen ================= */
var settingsOn = false, cats = [], catIdx = 0, sArea = 'cats', sRows = [], sR = 0, sC = 0, setY = 0;
var ICON = {
  home: '<svg viewBox="0 0 24 24"><path d="M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10"/></svg>',
  cloud: '<svg viewBox="0 0 24 24"><path d="M7 18a4 4 0 0 1 0-8 5.5 5.5 0 0 1 10.5 1.5A3.5 3.5 0 0 1 17 18z"/></svg>',
  image: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/></svg>',
  pic: '<svg viewBox="0 0 24 24"><path d="M4 7h16M4 12h16M4 17h16"/><circle cx="9" cy="7" r="2" fill="#0b0e14"/><circle cx="15" cy="12" r="2" fill="#0b0e14"/><circle cx="8" cy="17" r="2" fill="#0b0e14"/></svg>',
  sound: '<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9zM16 8.5a5 5 0 0 1 0 7M18.5 6a8.5 8.5 0 0 1 0 12"/></svg>',
  power: '<svg viewBox="0 0 24 24"><path d="M12 3v9M6.5 6.5a8 8 0 1 0 11 0"/></svg>',
  net: '<svg viewBox="0 0 24 24"><path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/></svg>',
  info: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/></svg>',
  grid: '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="6" height="6"/><rect x="14" y="4" width="6" height="6"/><rect x="4" y="14" width="6" height="6"/><rect x="14" y="14" width="6" height="6"/></svg>'
};
function tgl(label, desc, get, set){ return {type: 'toggle', label: label, desc: desc, get: get, set: set}; }
function chc(label, desc, opts, get, set){ return {type: 'choice', label: label, desc: desc, opts: opts, get: get, set: set}; }
function sld(label, desc, min, max, step, get, set){ return {type: 'slider', label: label, desc: desc, min: min, max: max, step: step, get: get, set: set}; }
function inf(label, value, desc){ return {type: 'info', label: label, value: value, desc: desc}; }
function act(label, desc, run, val){ return {type: 'action', label: label, desc: desc, run: run, val: val}; }
function lgTgl(cat, key, label, desc){ return tgl(label, desc, function(){ return (LGC[cat] || {})[key] === 'on'; }, function(b){ lgSet(cat, key, b ? 'on' : 'off'); }); }
function lgChc(cat, key, label, desc, opts, reload){ return chc(label, desc, opts, function(){ return (LGC[cat] || {})[key]; }, function(v){ lgSet(cat, key, v, reload ? function(){ renderCat(true); } : null); }); }
function lgSld(cat, key, label, desc, min, max, step){
  var it = sld(label, desc, min, max, step, function(){ return parseInt((LGC[cat] || {})[key] || '0', 10); }, function(v){ clearTimeout(it._t); it._t = setTimeout(function(){ lgSet(cat, key, v); }, 350); });
  it.local = function(v){ (LGC[cat] = LGC[cat] || {})[key] = String(v); };
  return it;
}
var MINS = function(v){ return v + ' min'; };
cats = [
  {id: 'home', name: 'Home & Screensaver', icon: 'home', title: 'Home & Screensaver', desc: 'Background photos, the idle (AFK) screen and the clock.', build: function(){ return [
    tgl('Photo background on Home', 'Uses the photos in your gallery', function(){ return S.bg.on; }, function(b){ setPath('bg.on', b); }),
    chc('Change background every', '', [[5,'5 min'],[10,'10 min'],[20,'20 min'],[30,'30 min'],[60,'1 hour']], function(){ return S.bg.everyMin; }, function(v){ setPath('bg.everyMin', v); }),
    tgl('Screensaver when idle', 'Clock, date and weather after a while', function(){ return S.saver.on; }, function(b){ setPath('saver.on', b); }),
    chc('Start after', '', [[1,'1 min'],[2,'2 min'],[5,'5 min'],[10,'10 min'],[15,'15 min'],[30,'30 min']], function(){ return S.saver.idleMin; }, function(v){ setPath('saver.idleMin', v); }),
    tgl('Show gallery photos in screensaver', 'Off = dark screen with clock', function(){ return S.saver.photos; }, function(b){ setPath('saver.photos', b); }),
    chc('Photo changes every', '', [[8,'8 s'],[12,'12 s'],[20,'20 s'],[30,'30 s'],[60,'1 min']], function(){ return S.saver.slideSec; }, function(v){ setPath('saver.slideSec', v); }),
    tgl('Show weather in screensaver', '', function(){ return S.saver.weather; }, function(b){ setPath('saver.weather', b); wxRender(); }),
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
  {id: 'gallery', name: 'Photo gallery', icon: 'image', title: 'Photo gallery', desc: 'Photos used for the Home background and screensaver.', build: function(){ return [
    act('Add photos from your phone', 'Shows a QR code to scan', function(){ qrOpen(); }, 'QR'),
    inf('Photos in gallery', function(){ return String(photos.length); }),
    tgl('Photo background on Home', '', function(){ return S.bg.on; }, function(b){ setPath('bg.on', b); }),
    tgl('Show photos in screensaver', '', function(){ return S.saver.photos; }, function(b){ setPath('saver.photos', b); }),
    act('Reset phone link', 'Old QR codes stop working', function(){ panelOpen('Reset the phone link?', [['Yes, reset it', '', function(){ panelClose(); apiPost('/api/resettoken', '', function(){ toast('Phone link reset'); }); }], ['Cancel', '', panelClose]]); }),
    {type: 'thumbs'}
  ]; }},
  {id: 'picture', name: 'Picture', icon: 'pic', title: 'Picture', desc: 'Applies to the current input and picture mode.', lg: [['picture', ['pictureMode','backlight','contrast','brightness','color','sharpness','energySaving']]], build: function(){ return [
    lgChc('picture', 'pictureMode', 'Picture mode', '', [['vivid','Vivid'],['normal','Standard'],['eco','Eco'],['cinema','Cinema'],['sports','Sports'],['game','Game']], true),
    lgSld('picture', 'backlight', 'Backlight', '', 0, 100, 5), lgSld('picture', 'contrast', 'Contrast', '', 0, 100, 5),
    lgSld('picture', 'brightness', 'Brightness', '', 0, 100, 5), lgSld('picture', 'color', 'Color', '', 0, 100, 5), lgSld('picture', 'sharpness', 'Sharpness', '', 0, 50, 5),
    lgChc('picture', 'energySaving', 'Energy saving', '', [['off','Off'],['min','Minimum'],['med','Medium'],['max','Maximum'],['auto','Auto']])
  ]; }},
  {id: 'sound', name: 'Sound', icon: 'sound', title: 'Sound', desc: 'TV speaker sound options.', lg: [['sound', ['soundMode','clearVoice','autoVolume','virtualSurround']]], build: function(){ return [
    lgChc('sound', 'soundMode', 'Sound mode', '', [['standard','Standard'],['cinema','Cinema'],['clearVoice','Clear Voice'],['sports','Sports'],['music','Music'],['game','Game']]),
    lgTgl('sound', 'clearVoice', 'Clear Voice', 'Makes speech easier to hear'), lgTgl('sound', 'autoVolume', 'Auto volume', 'Evens out loud ads and quiet scenes'),
    lgTgl('sound', 'virtualSurround', 'Virtual surround', '')
  ]; }},
  {id: 'power', name: 'Power & startup', icon: 'power', title: 'Power & startup', desc: '', lg: [['option', ['quickStartMode','standByLight','logoLight']], ['general', ['homeAutoLaunch']], ['time', ['noSignalAutoOff']]], build: function(){ return [
    lgTgl('option', 'quickStartMode', 'Quick Start', 'Turns on faster; uses a little standby power'),
    lgTgl('general', 'homeAutoLaunch', 'Show Home when the TV turns on', ''),
    lgTgl('option', 'standByLight', 'Standby light', ''), lgTgl('option', 'logoLight', 'LG logo light', ''),
    lgTgl('time', 'noSignalAutoOff', 'Turn off when there is no signal', ''),
    act('Restart TV', 'Reboots; Home is back in about a minute', function(){ panelOpen('Restart the TV?', [['Restart now', '', function(){ panelClose(); apiPost('/api/reboot', '', function(){ toast('Restarting…'); }); }], ['Cancel', '', panelClose]]); })
  ]; }},
  {id: 'net', name: 'Network', icon: 'net', title: 'Network', desc: '', info: '/api/net', build: function(){ var j = this.data || {}, w = j.wired || {}, f = j.wifi || {}; return [
    inf('Connection', function(){ return w.state === 'connected' ? 'Ethernet' : f.state === 'connected' ? 'Wi-Fi' : 'Offline'; }),
    inf('IP address', function(){ return w.ipAddress || f.ipAddress || '–'; }),
    inf('Wi-Fi network', function(){ return f.state === 'connected' ? (f.ssid || 'connected') : '–'; }),
    inf('DNS', function(){ return w.dns1 || f.dns1 || '–'; }),
    inf('Internet', function(){ return j.isInternetConnectionAvailable ? 'available' : 'not available'; }),
    act('Join a Wi-Fi network (LG)', 'Opens the LG network settings', function(){ launch('com.palm.app.settings'); })
  ]; }},
  {id: 'about', name: 'About this TV', icon: 'info', title: 'About this TV', desc: '', info: '/api/sysinfo', build: function(){ var j = this.data || {}, lg = j.lg || {}, m = j.mem || {}; return [
    inf('Model', function(){ return lg.modelName || '–'; }), inf('Firmware', function(){ return lg.firmwareVersion || '–'; }), inf('webOS SDK', function(){ return lg.sdkVersion || '–'; }),
    inf('Memory free', function(){ return (m.availMB || 0) + ' of ' + (m.totalMB || 0) + ' MB'; }), inf('Swap in use', function(){ return (m.swapUsedMB || 0) + ' MB'; }),
    inf('Running for', function(){ var s = j.uptime || 0, h = Math.floor(s / 3600), mi = Math.floor((s % 3600) / 60); return h + ' h ' + mi + ' min'; }), inf('Processes', function(){ return String(j.procs || '–'); }),
    inf('Home', function(){ return 'tv-debloat launcher'; }, 'Undo everything: run revert.sh from the PC, or remove /var/lib/webosbrew/init.d/zz-debloat and reboot.')
  ]; }},
  {id: 'lgall', name: 'All LG settings', icon: 'grid', title: 'All LG settings', desc: 'Everything else (accessibility, language, support, ...) lives in LG’s own Settings app.', build: function(){ return [
    act('Open LG Settings', '', function(){ launch('com.palm.app.settings'); })
  ]; }}
];

function renderCats(){
  var box = $('setcats'); box.innerHTML = '';
  cats.forEach(function(c, i){ var d = el('div', 'scat', ICON[c.icon] + '<span></span>'); d.lastChild.textContent = c.name; c._el = d; box.appendChild(d); });
  catClass();
}
function catClass(){ cats.forEach(function(c, i){ c._el.className = 'scat' + (i === catIdx ? (sArea === 'cats' ? ' foc' : ' cur') : ''); }); }
function renderCat(reload){
  var c = cats[catIdx];
  function draw(){
    $('settitle').textContent = c.title; $('setdesc').textContent = c.desc || '';
    var box = $('setrows'); box.innerHTML = ''; sRows = [];
    var items = c.build.call(c);
    items.forEach(function(it){ if (it.show && !it.show()) return; if (it.type === 'thumbs') { renderThumbs(box); return; } var r = rowEl(it); box.appendChild(r); sRows.push([r]); });
    // thumbs group their cells into visual rows
    regroupThumbs();
    if (sArea === 'pane') sFocus(Math.min(sR, sRows.length - 1), sC, true);
  }
  if (reload !== false && (c.lg || c.info)) {
    $('settitle').textContent = c.title; $('setdesc').textContent = 'Loading…'; $('setrows').innerHTML = ''; sRows = [];
    var tok = ++renderCat.tok;
    var done = function(){ if (tok === renderCat.tok && settingsOn) draw(); };
    if (c.lg) lgLoadMany(c.lg, done); else api(c.info, function(err, j){ c.data = j || {}; done(); });
  } else draw();
}
renderCat.tok = 0;
function rowEl(it){
  var r = el('div', 'srow' + (it.type === 'action' || it.type === 'text' ? ' act' : '')), lab = el('div', 'lab'), val = el('div', 'val');
  lab.innerHTML = '<span></span>' + (it.desc ? '<small></small>' : ''); lab.firstChild.textContent = it.label; if (it.desc) lab.lastChild.textContent = it.desc;
  r.appendChild(lab); r.appendChild(val); r._it = it; it._el = r; paintRow(it); return r;
}
function paintRow(it){
  var val = it._el.lastChild, t = it.type;
  if (t === 'toggle') val.innerHTML = '<div class="tg' + (it.get() ? ' on' : '') + '"></div>';
  else if (t === 'choice') { var v = it.get(), lab = String(v); for (var i = 0; i < it.opts.length; i++) if (String(it.opts[i][0]) === String(v)) lab = it.opts[i][1]; val.innerHTML = '<span class="ch">◀&nbsp; <b></b> &nbsp;▶</span>'; val.querySelector('b').textContent = lab; }
  else if (t === 'slider') { var s = it.get(), pct = Math.max(0, Math.min(100, (s - it.min) * 100 / (it.max - it.min))); val.innerHTML = '<div class="sl"><i style="width:' + pct + '%"></i></div><span>' + s + '</span>'; }
  else if (t === 'info') val.textContent = typeof it.value === 'function' ? it.value() : it.value;
  else if (t === 'text') val.textContent = it.get();
  else if (t === 'action') val.textContent = it.val || '▶';
}
function renderThumbs(box){
  var g = el('div', 'gthumbs'); box.appendChild(g);
  photos.forEach(function(n){ var d = el('div', 'gt'), im = el('img'); im.alt = ''; im.src = thumbUrl(n); d.appendChild(im); d._it = {type: 'thumb', name: n}; g.appendChild(d); });
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
function openSettings(id){
  if (settingsOn) return;
  settingsOn = true; $('settings').className = 'on'; mpush('settings'); clearTimeout(idleT);
  if (!$('setcats').firstChild) renderCats();
  if (id) for (var i = 0; i < cats.length; i++) if (cats[i].id === id) catIdx = i;
  sArea = 'cats'; sR = sC = 0; setY = 0; $('setinner').style.transform = ''; catClass(); renderCat(true);
}
function closeSettings(){ settingsOn = false; mpop('settings'); $('settings').className = ''; activity(); refreshPhotos(function(){ if (!document.body.className) bgApply(true); }); }
function adjust(it, dir){
  var t = it.type;
  if (t === 'toggle') { it.set(!it.get()); }
  else if (t === 'choice') { var i = 0; for (var k = 0; k < it.opts.length; k++) if (String(it.opts[k][0]) === String(it.get())) i = k; i = Math.max(0, Math.min(it.opts.length - 1, i + dir)); if (String(it.opts[i][0]) === String(it.get())) return true; it.set(it.opts[i][0]); }
  else if (t === 'slider') { var v = Math.max(it.min, Math.min(it.max, it.get() + dir * it.step)); if (v === it.get()) return true; if (it.local) it.local(v); it.set(v); }
  else return false;
  paintRow(it); return true;
}
function settingsKey(k, e){
  if (sArea === 'cats') {
    if (k === 38 && catIdx > 0) { catIdx--; catClass(); renderCat(true); }
    else if (k === 40 && catIdx < cats.length - 1) { catIdx++; catClass(); renderCat(true); }
    else if (k === 39 || k === 13) { if (sRows.length) setArea('pane'); }
    else if (k === 461 || k === 27 || k === 8 || k === 37) closeSettings();
    return;
  }
  var cell = sRows[sR] && sRows[sR][sC], it = cell && cell._it, multi = sRows[sR] && sRows[sR].length > 1 || (it && it.type === 'thumb');
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
  else if (k === 461 || k === 27 || k === 8) setArea('cats');
}
function thumbMenu(name){
  panelOpen('Photo', [
    ['Use as Home background now', '', function(){ panelClose(); var i = photos.indexOf(name); if (i >= 0) { S.bg.on = true; saveSettings(); bgShow(i); toast('Background changed'); } }],
    ['Delete this photo', '', function(){ panelOpen('Delete this photo?', [['Yes, delete', '', function(){ panelClose();
        api('/api/delete?name=' + encodeURIComponent(name), function(err){ if (err) return toast('Could not delete'); photos = photos.filter(function(n){ return n !== name; }); if (bgIx >= photos.length) bgIx = 0; renderCat(false); toast('Photo deleted'); if (!photos.length) bgApply(true); }); }], ['Cancel', '', panelClose]]); }],
    ['Cancel', '', panelClose]]);
  // the first panel is replaced by the confirmation (panelOpen resets the list), so keep the stack consistent
}

/* ================= input ================= */
var KEYS = {37: 'L', 38: 'U', 39: 'R', 40: 'D'};
document.addEventListener('keydown', function(e){
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
  if (m === 'settings') { settingsKey(k, e); e.preventDefault(); return; }
  if (KEYS[k]) { move(KEYS[k]); e.preventDefault(); } else if (k === 13) { activate(); e.preventDefault(); }
});
document.addEventListener('mousemove', function(){ if (saverOn) saverStop(); activity(); });
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
  if (Date.now() - appsAt > 60000) { appsAt = Date.now(); loadApps(function(ok){ if (ok) focusItem(Math.min(1, rows.length - 1), 0); }); }
  wxLoad(false); loadSettings(); refreshPhotos(function(ch){ if (ch) bgApply(true); });
  if (photos.length && S.bg.on && Date.now() - bgAt > Math.max(1, S.bg.everyMin) * 60000) bgShow(bgIx + 1);
  netLabel();
}
function onHide(){ clearTimeout(idleT); if (saverOn) saverStop(); if (mtop() === 'panel') panelClose(); }
document.addEventListener('visibilitychange', function(){ if (document.hidden) onHide(); else { if (!settingsOn) focusItem(1, 0); onShow(); } });
document.addEventListener('webOSRelaunch', function(){ if (saverOn) saverStop(); while (mstack.length) { var t = mtop(); if (t === 'settings') closeSettings(); else if (t === 'panel') panelClose(); else if (t === 'qr') qrClose(); else if (t === 'keypad') keypadClose(); else mstack.pop(); } focusItem(1, 0); onShow(); });
window.addEventListener('resize', function(){ layoutRows(); });
setInterval(function(){ if (!document.hidden) tick(); }, 1000);
setInterval(function(){ if (!document.hidden) wxLoad(false); }, 60000);
// pick up changes made from the phone page (settings, uploads): cheap local calls every 30 s while Home is visible
setInterval(function(){ if (document.hidden || saverOn) return; loadSettings(); refreshPhotos(function(ch){ if (ch) { if (!document.body.className) bgApply(true); if (settingsOn && cats[catIdx].id === 'gallery') renderCat(false); } }); }, 30000);

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
if (MOCK && /saver/.test(location.search)) setTimeout(saverStart, 1200);
if (MOCK && /settings=(\w+)/.test(location.search)) setTimeout(function(){ openSettings(/settings=(\w+)/.exec(location.search)[1]); setArea('pane'); if (/row=(\d+)/.test(location.search)) sFocus(parseInt(/row=(\d+)/.exec(location.search)[1], 10), 0); }, 1500);
window.__tvhome = {set: setPath, saver: saverStart, stop: saverStop, bg: function(){ bgShow(bgIx + 1); }, settings: openSettings, photos: function(){ return photos.length; }, S: function(){ return S; }, wx: function(){ return wx; }};
})();
