/* rootless.js - EXPERIMENTAL adapter that lets the launcher run as an ordinary (developer-mode) webOS app, without the rooted TV's local API.
   app.js sends every "API" request through window.__TVAPI__ when it exists; this file answers them from what a normal app may do:
   LG's luna services through PalmServiceBridge (which services a non-root app may call depends on the TV: untested, see rootless/README.md),
   settings kept in localStorage, no photo gallery. Nothing here is used on a rooted TV (tools/make-ipk.js adds this file only to the IPK). ES5. */
(function(){
  var STORE = 'tvd.settings';
  function luna(uri, params, cb){
    try {
      var b = new PalmServiceBridge();
      b.onservicecallback = function(m){ var j = null; try { j = JSON.parse(m); } catch(e){} cb(null, j); };
      b.call(uri, JSON.stringify(params || {}));
    } catch (e) { cb(e, null); }
  }
  function q(path, name){ var m = new RegExp('[?&]' + name + '=([^&]*)').exec(path); return m ? decodeURIComponent(m[1]) : ''; }
  var R = {
    '/api/apps':    function(p, b, cb){ luna('luna://com.webos.applicationManager/listLaunchPoints', {}, cb); },
    '/api/running': function(p, b, cb){ luna('luna://com.webos.applicationManager/running', {}, cb); },
    '/api/fg':      function(p, b, cb){ luna('luna://com.webos.applicationManager/getForegroundAppInfo', {}, cb); },
    '/api/launch':  function(p, b, cb){ luna('luna://com.webos.applicationManager/launch', {id: q(p, 'id'), params: {}}, cb); },
    '/api/net':     function(p, b, cb){ luna('luna://com.webos.service.connectionmanager/getStatus', {}, cb); },
    '/api/lg/get':  function(p, b, cb){ var k = q(p, 'keys'); luna('luna://com.webos.settingsservice/getSystemSettings', {category: q(p, 'cat'), keys: k ? k.split(',') : []}, cb); },
    '/api/lg/set':  function(p, b, cb){ var o = null; try { o = JSON.parse(b); } catch(e){} if (!o) return cb(new Error('bad json'), null); luna('luna://com.webos.settingsservice/setSystemSettings', o, cb); },
    '/api/lg/open': function(p, b, cb){ luna('luna://com.webos.applicationManager/launch', {id: 'com.palm.app.settings', params: {}}, cb); },
    '/api/settings': function(p, b, cb){
      if (b) { try { localStorage.setItem(STORE, b); } catch(e){} return cb(null, {ok: true}); }
      var s = null; try { s = JSON.parse(localStorage.getItem(STORE) || 'null'); } catch(e){} cb(null, s || {}); },
    '/api/photos':  function(p, b, cb){ cb(null, []); },
    '/api/crops':   function(p, b, cb){ cb(null, {}); },
    '/api/ready':   function(p, b, cb){ cb(null, {ok: true}); },
    '/api/log':     function(p, b, cb){ cb(null, {ok: true}); },
    '/api/back':    function(p, b, cb){ cb(null, {back: ''}); },
    '/api/info':    function(p, b, cb){ cb(null, {ip: '', port: 0, token: ''}); }
  };
  window.__ROOTLESS__ = true;
  window.__TVAPI__ = function(method, path, body, cb){
    var key = path.split('?')[0], h = R[key];
    if (h) return h(path, body, function(err, j){ cb(err, j); });
    cb(new Error('not available without root'), {returnValue: false, errorText: 'not available without root'});
  };
})();
