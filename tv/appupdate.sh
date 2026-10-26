#!/bin/sh
# appupdate.sh json|mode [auto|manual]|check|apply|pending - keep the TV's apps up to date so LG never shows the "update this app?" prompt.
#
# How LG does it (webOS 4.5, verified on the dev TV): every app installed from the LG Content Store has checkUpdateOnLaunch:true. When it is started and
# an update is waiting, SAM asks the user. With option.appUpdateMode = auto, appinstalld (AppUpdater) downloads and installs updates by itself instead.
# The waiting updates are listed by luna://com.webos.appUpdateService/statusAll ({"apps":[{"id","status":"Y"...}]}). The service's `check` method answers
# only to the activity manager, so "check now" creates an activity whose callback is that method (activitymanager then calls it with $activity).
#   json     one JSON object for the Settings screen: mode, pending ids, installed apps (id, title, version), last check time
#   mode     print / set option.appUpdateMode (auto|manual); manual is remembered in state/appupdate-manual and kept by `apply`
#   check    ask LG to look for app updates now (installs them when the mode is auto)
#   apply    make LG's switch match our choice (default auto); run at boot and by the 5-minute sweep
#   pending  ids that have an update waiting, one per line
#   due      yes|no: is a background check due (startup once per boot + every N hours; settings in state/appupdate.conf)
#   conf     print / set  startup on|off , every <hours>
# System (firmware) updates are a different thing and stay blocked: see do_updates in debloat.sh. This script never touches them.
. /media/developer/tv-debloat/common.sh
FLAG=$STATE/appupdate-manual; LAST=$STATE/appupdate-last; CONF=$STATE/appupdate.conf     # CONF: startup=on|off, every=<hours, 0 = never>
conf_get() { v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -1); echo "${v:-$2}"; }
conf_set() { { grep -v "^$1=" "$CONF" 2>/dev/null; echo "$1=$2"; } > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"; }
# due: is it time for a background check? (printed yes/no; the launcher watchdog asks every 20 s, so this must be cheap: no luna calls)
#   - once per boot, 30 s after the launcher is ready, when 'check when the TV starts' is on
#   - then every <every> hours (0 = never). Manual mode never checks on its own: LG asks the user instead.
due() {
  [ -e "$FLAG" ] && { echo no; return; }
  now=$(cut -d. -f1 /proc/uptime); last=$(cut -d. -f1 "$LAST" 2>/dev/null); ready=$(cut -d. -f1 "$STATE/launcher.ready" 2>/dev/null)
  [ -n "$ready" ] && [ $((now - ready)) -ge 30 ] || { echo no; return; }
  if [ -z "$last" ] || [ "$last" -gt "$now" ]; then [ "$(conf_get startup on)" = on ] && echo yes || echo no; return; fi
  ev=$(conf_get every 6); [ "$ev" -gt 0 ] 2>/dev/null && [ $((now - last)) -ge $((ev * 3600)) ] && echo yes || echo no
}
want_mode() { [ -e "$FLAG" ] && echo manual || echo auto; }
cur_mode() { lun luna://com.webos.settingsservice/getSystemSettings '{"category":"option","keys":["appUpdateMode"]}' | tr -d '\n ' | sed -n 's/.*"appUpdateMode":"\([a-z]*\)".*/\1/p'; }
set_mode() { lun luna://com.webos.settingsservice/setSystemSettings "{\"category\":\"option\",\"settings\":{\"appUpdateMode\":\"$1\"}}" | grep -q '"returnValue": *true'; }
pending() { lun luna://com.webos.appUpdateService/statusAll '{}' | tr -d '\n ' | grep -o '"id":"[^"]*","status":"Y"' | sed 's/"id":"\([^"]*\)".*/\1/'; }
check() {
  r=$(LW=15000 lun luna://com.webos.service.activitymanager/create '{"activity":{"name":"tvd-appcheck","description":"tv-debloat app update check","type":{"foreground":true,"persist":false,"explicit":true},"callback":{"method":"luna://com.webos.appUpdateService/check","params":{}}},"start":true,"replace":true}' | tr -d '\n')
  case $r in *'"returnValue": *true'*|*true*) up > "$LAST"; log "appupdate: check requested ($(cur_mode))"; return 0;; esac
  log "appupdate: check refused: $(echo "$r" | cut -c1-120)"; return 1
}
case ${1:-json} in
  mode)    if [ -n "$2" ]; then
             case $2 in auto) rm -f "$FLAG";; manual) touch "$FLAG";; *) echo "usage: mode auto|manual"; exit 1;; esac
             set_mode "$2" && echo "$2" || echo "failed"
           else echo "$(cur_mode)"; fi;;
  check)   check && echo "Asked the TV to check for app updates." || echo "The TV did not accept the request.";;
  apply)   w=$(want_mode); [ "$(cur_mode)" = "$w" ] || { set_mode "$w"; log "appupdate: appUpdateMode -> $w"; };;
  pending) pending;;
  due)     due;;
  conf)    case $2 in startup) case $3 in on|off) conf_set startup $3;; esac;; every) case $3 in ''|*[!0-9]*) ;; *) conf_set every $3;; esac;; esac
           echo "startup=$(conf_get startup on) every=$(conf_get every 6)";;
  json)    P=$(pending | tr '\n' ' ')
           lun luna://com.webos.applicationManager/listApps '{}' > /tmp/appupd.apps 2>/dev/null
           python - "$(cur_mode)" "$P" "$(cat "$LAST" 2>/dev/null)" "$(cut -d. -f1 /proc/uptime)" "$(conf_get startup on)" "$(conf_get every 6)" <<'PY'
import json, sys
mode, pend, last, up = sys.argv[1], sys.argv[2].split(), sys.argv[3], sys.argv[4]
try: apps = json.load(open('/tmp/appupd.apps')).get('apps', [])
except Exception: apps = []
out = [{'id': a['id'], 'title': a.get('title', a['id']), 'version': a.get('version', ''), 'pending': a['id'] in pend}
       for a in apps if not a.get('systemApp') and a.get('removable', True) and a.get('checkUpdateOnLaunch')]
out.sort(key=lambda a: a['title'].lower())
ago = None
try: ago = max(0, int(up) - int(float(last)))
except Exception: pass
print(json.dumps({'mode': mode, 'pending': pend, 'apps': out, 'lastCheckAgoSec': ago, 'startup': sys.argv[5], 'every': int(sys.argv[6])}))
PY
           ;;
esac
