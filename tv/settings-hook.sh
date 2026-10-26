#!/bin/sh
# settings-hook.sh start|stop|status - makes the remote's Settings (gear) key open OUR Settings instead of LG's.
# LG's side panel is a QML overlay inside the compositor (com.webos.app.quicksettings): there is no file to replace, so this watches the
# system log for the panel appearing (and for LG's Settings app being started, e.g. by "All settings" in that panel), closes it and opens ours.
# It steps aside when our API is down (LG's panel then stays) or when state/gear-lg exists (Settings -> Remote: "Settings key opens LG's panel").
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/settings-hook.pid; LOG=/var/log/messages
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
stop() {
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  for p in $(pgrep -f "tail -F $LOG"); do kill "$p" 2>/dev/null; done      # the reader that feeds the loop below
}
case ${1:-start} in
  stop) stop; log "settings-hook: stopped"; exit 0;;
  status) alive && echo running || echo stopped; exit 0;;
esac
alive && exit 0
echo $$ > $PIDF
log "settings-hook: watching for the Settings key"
last=0
tail -F "$LOG" 2>/dev/null | awk '
  /NL_VSC/ && /com.webos.app.quicksettings/ && /"visible":true/ { print "QS"; fflush() }
  /NL_APP_LAUNCH_BEGIN/ && /"app_id":"com.palm.app.settings"/ { print "LGS"; fflush() }' | while read -r ev; do
  [ -e "$D/DISABLE" ] && continue
  [ -e "$STATE/gear-lg" ] && [ "$ev" = QS ] && continue
  now=$(cut -d. -f1 /proc/uptime); [ $((now - last)) -lt 2 ] && continue
  if [ "$ev" = LGS ]; then lg_settings_allowed && continue; fi
  api_ok || { log "settings-hook: API down, leaving LG's panel alone"; continue; }
  last=$now
  if [ "$ev" = QS ]; then lun luna://com.webos.surfacemanager/closeByAppId '{"id":"com.webos.app.quicksettings"}' >/dev/null
  else lun luna://com.webos.applicationManager/closeByAppId '{"id":"com.palm.app.settings","forceMode":true}' >/dev/null; fi
  sh "$D/settings-open.sh" toggle >/dev/null 2>&1
done
rm -f $PIDF
