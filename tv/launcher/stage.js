/* stage.js - how a photo is framed on the TV. Shared by the TV (app.js) and the phone page (phone.html), so both always draw the same picture.
   ES5 on purpose (Chromium 53 on the TV).

   A photo keeps its full image; the framing is three numbers:  x, y = the point of the photo (0..1) that sits in the middle of the screen,
   z = zoom (1 = the photo just covers the screen, like a normal "crop to fill"; below 1 the whole photo shrinks and the screen edges that
   are no longer covered get a colour fade taken from the photo's own edge; above 1 you zoom in).
   Edge colours (c.e = {l,r,t,b: five hex colours along each edge}) are measured once when the framing is saved, because the TV page may not read
   the pixels of a local image itself.

   Everything is done with percentages of the screen, so the same numbers work for the 1920x1080 screen, a thumbnail and the phone preview. */
var Stage = (function(){
'use strict';
var FA = 16 / 9;            // screen aspect ratio
var DARK = '8,10,15';       // colour the fade runs out to (matches the Home background)

function clamp(v, a, b){ return v < a ? a : v > b ? b : v; }
function def(){ return {x: 0.5, y: 0.5, z: 1}; }
// size of the photo (as fractions of the screen width / height) when it just covers the screen
function cover(nw, nh){ var ar = nw / nh; return ar >= FA ? {w: ar / FA, h: 1} : {w: 1, h: FA / ar}; }
// smallest zoom that still shows the whole photo (never above 1)
function minZoom(nw, nh){ var c = cover(nw, nh); return Math.min(1, 1 / Math.max(c.w, c.h)); }
function norm(c, nw, nh){
  c = c || def();
  return {x: clamp(+c.x, 0, 1), y: clamp(+c.y, 0, 1), z: clamp(+c.z || 1, nw ? minZoom(nw, nh) : 0.3, 3.5), a: c.a, e: c.e};
}
// where the photo lands on the screen, as fractions of the screen: l/t = top-left corner, w/h = size
function geom(nw, nh, c){
  var cv = cover(nw, nh), w = cv.w * c.z, h = cv.h * c.z;
  return {l: 0.5 - c.x * w, t: 0.5 - c.y * h, w: w, h: h};
}
function pct(v){ return (Math.round(v * 10000) / 100) + '%'; }

function make(){
  var d = document.createElement('div'); d.className = 'stage';
  d.innerHTML = '<div class="fl"></div><div class="fl"></div><div class="fl"></div><div class="fl"></div><img alt="">';
  return d;
}
// colour stops along one edge, positioned along the photo's extent on the screen (a = start, len = extent, both fractions of the screen)
function stops(cols, a, len){
  var n = cols.length, out = [];
  for (var i = 0; i < n; i++) out.push('#' + cols[i] + ' ' + pct(a + len * (n === 1 ? 0.5 : i / (n - 1))));
  return out.join(',');
}
function hexOk(arr){ if (!arr || !arr.length) return null; for (var i = 0; i < arr.length; i++) if (!/^[0-9a-fA-F]{6}$/.test(arr[i])) return null; return arr; }

// size / position the photo inside a stage element made by make(); nw, nh = natural size of the image already loaded in it
function place(stage, nw, nh, crop){
  if (!nw || !nh) return;
  var c = norm(crop, nw, nh), g = geom(nw, nh, c), img = stage.lastChild, f = stage.children, e = c.e || {};
  img.style.left = pct(g.l); img.style.top = pct(g.t); img.style.width = pct(g.w); img.style.height = pct(g.h);
  var base = '#' + '0e1118';
  // left / right gaps (full height) and top / bottom gaps (full width); each = colour stops of the photo edge + a fade to dark away from the photo
  function gap(el, on, pos, bg){ if (!on) { el.style.display = 'none'; return; } el.style.display = 'block'; for (var k in pos) el.style[k] = pos[k]; el.style.background = bg; }
  var eps = 0.002;
  var cl = hexOk(e.l), cr = hexOk(e.r), ct = hexOk(e.t), cb = hexOk(e.b);
  function vcol(cols){ return cols ? 'linear-gradient(to bottom,' + stops(cols, g.t, g.h) + ')' : 'linear-gradient(' + base + ',' + base + ')'; }
  function hcol(cols){ return cols ? 'linear-gradient(to right,' + stops(cols, g.l, g.w) + ')' : 'linear-gradient(' + base + ',' + base + ')'; }
  var fadeL = 'linear-gradient(to right,rgba(' + DARK + ',.94),rgba(' + DARK + ',0))', fadeR = 'linear-gradient(to left,rgba(' + DARK + ',.94),rgba(' + DARK + ',0))';
  var fadeT = 'linear-gradient(to bottom,rgba(' + DARK + ',.94),rgba(' + DARK + ',0))', fadeB = 'linear-gradient(to top,rgba(' + DARK + ',.94),rgba(' + DARK + ',0))';
  gap(f[0], g.l > eps, {left: '0', top: '0', width: pct(Math.max(0, g.l)), height: '100%'}, fadeL + ',' + vcol(cl));
  gap(f[1], g.l + g.w < 1 - eps, {left: pct(Math.min(1, g.l + g.w)), top: '0', width: pct(Math.max(0, 1 - g.l - g.w)), height: '100%'}, fadeR + ',' + vcol(cr));
  gap(f[2], g.t > eps, {left: '0', top: '0', width: '100%', height: pct(Math.max(0, g.t))}, fadeT + ',' + hcol(ct));
  gap(f[3], g.t + g.h < 1 - eps, {left: '0', top: pct(Math.min(1, g.t + g.h)), width: '100%', height: pct(Math.max(0, 1 - g.t - g.h))}, fadeB + ',' + hcol(cb));
}

// measure the colours along the four edges of an already-loaded <img> (same-origin or CORS-enabled, or the canvas is tainted and null is returned)
function sample(img, n){
  n = n || 5;
  try {
    var nw = img.naturalWidth, nh = img.naturalHeight, w = 64, h = Math.max(8, Math.round(64 * nh / nw));
    var cv = document.createElement('canvas'); cv.width = w; cv.height = h;
    var x = cv.getContext('2d'); x.drawImage(img, 0, 0, w, h);
    var d = x.getImageData(0, 0, w, h).data;
    function avg(x0, y0, x1, y1){
      var r = 0, g = 0, b = 0, k = 0;
      for (var yy = y0; yy < y1; yy++) for (var xx = x0; xx < x1; xx++) { var p = (yy * w + xx) * 4; r += d[p]; g += d[p + 1]; b += d[p + 2]; k++; }
      function hx(v){ v = Math.round(v / (k || 1)); return (v < 16 ? '0' : '') + v.toString(16); }
      return hx(r) + hx(g) + hx(b);
    }
    var depth = 3, out = {l: [], r: [], t: [], b: []};
    for (var i = 0; i < n; i++) {
      var y0 = Math.floor(i * h / n), y1 = Math.max(y0 + 1, Math.floor((i + 1) * h / n)), x0 = Math.floor(i * w / n), x1 = Math.max(x0 + 1, Math.floor((i + 1) * w / n));
      out.l.push(avg(0, y0, depth, y1)); out.r.push(avg(w - depth, y0, w, y1)); out.t.push(avg(x0, 0, x1, depth)); out.b.push(avg(x0, h - depth, x1, h));
    }
    return out;
  } catch (err) { return null; }
}
// the framing a photo gets when nobody has set one
function auto(c){ return c && c.a && c.a.length === 2 ? {x: c.a[0], y: c.a[1], z: 1, a: c.a} : def(); }
return {FA: FA, def: def, auto: auto, norm: norm, geom: geom, minZoom: minZoom, make: make, place: place, sample: sample, clamp: clamp};
})();
