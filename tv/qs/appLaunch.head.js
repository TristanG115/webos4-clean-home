// ---- tv-debloat (inserted by qspatch.sh in front of openSettings): open OUR Settings overlay straight from the key press ----
// The key reaches this script at once; the old way waited for the system log, which BusyBox polls once a second (0.6-0.9 s late on average).
// Everything is inside try/catch. If WebAppMgr refuses the call, or this script cannot reach the TV-side API, the shell hook (settings-hook.sh) notices that
// no "claim" arrived and opens Settings the old way, so a failed patch can only be slower, never leave you without Settings.
var tvdLastKey = 0;
var TVD_LAUNCH = JSON.stringify({appDesc: __APPDESC__, parameters: {}, launchingAppId: "", launchingProcId: "", instanceId: "tv-debloat-settings"});
var tvdKeep = [];   // a request object that is only a local variable can be garbage-collected before it is sent
function tvdApi(path, body) {
    try {
        var x = new XMLHttpRequest();
        tvdKeep.push(x);
        x.onreadystatechange = function() { if (x.readyState === 4) { var i = tvdKeep.indexOf(x); if (i >= 0) tvdKeep.splice(i, 1); } };
        x.open(body === undefined ? "GET" : "POST", "http://127.0.0.1:8765" + path);
        x.send(body === undefined ? null : body);
    } catch (e) {}
}
function tvdSettingsDone(payload) {
    var ok = false, msg = "";
    try { var j = JSON.parse(payload); ok = (j.returnValue === true); msg = j.errorText || ""; } catch (e) { msg = "noparse"; }
    if (ok) tvdApi("/api/qs?e=claim");
    else { tvdApi("/api/qs?e=fail&m=" + encodeURIComponent(msg.substring(0, 120))); tvdApi("/api/settings/launch"); }
}
function tvdOpenSettings(params) {
    try {
        var t = new Date().getTime();
        if (t - tvdLastKey < 600) return true;
        tvdLastKey = t;
        tvdApi("/api/qs?m=key");
        // always "launch": when the overlay is already running WebAppMgr sends the page a relaunch event and the page closes itself (the key toggles)
        lunaCall.send("com.palm.webappmanager", "/launchApp", TVD_LAUNCH, tvdSettingsDone);
        return true;
    } catch (e) {
        tvdApi("/api/qs?e=fail&m=" + encodeURIComponent("exc " + e));
        return false;
    }
}
tvdApi("/api/qs?e=loaded&m=appLaunch");   // proves to qspatch.sh that this script was parsed and run
// ---- end tv-debloat ----
