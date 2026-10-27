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
# The log shows the press first: lginput2 logs KEY_SETTINGS about 0.5 s before LG's panel is drawn. We start our overlay right then (so it is up
# as early as possible) and close LG's panel the moment it shows. Our overlay's own visible/hidden events keep /tmp/set-vis (the toggle state).
tail -F "$LOG" 2>/dev/null | awk '
  /NL_BUTTON_CLICK/ && /"button_type":"KEY_SETTINGS"/ { print "KEY"; fflush() }
  /NL_VSC/ && /com.webos.app.quicksettings/ && /"visible":true/ { print "QS"; fflush() }
  /NL_VSC/ && /tv.debloat.settings/ && /"visible":true/ { print "SON"; fflush() }
  /NL_VSC/ && /tv.debloat.settings/ && /"visible":false/ { print "SOFF"; fflush() }
  /NL_APP_LAUNCH_BEGIN/ && /"app_id":"com.palm.app.settings"/ { print "LGS"; fflush() }' | while read -r ev; do
  case $ev in SON) touch /tmp/set-vis; continue;; SOFF) rm -f /tmp/set-vis; continue;; esac
  [ -e "$D/DISABLE" ] && continue
  [ -e "$STATE/gear-lg" ] && [ "$ev" != LGS ] && continue
  now=$(cut -d. -f1 /proc/uptime)
  claim=$(cat /tmp/gear-claim 2>/dev/null); [ -n "$claim" ] || claim=-99
  case $ev in
    KEY)  [ $((now - last)) -lt 2 ] && continue
          api_ok || { log "settings-hook: API down, leaving LG's panel alone"; continue; }
          last=$now; echo $now > /tmp/gear-claim
          if grep -q tvdOpenSettings /usr/lib/qt5/qml/KeyFilters/appLaunch.js 2>/dev/null; then
            # the patched compositor (qspatch.sh) opens / closes Settings itself the moment the key arrives and tells the API ("claim"); step in only when it did not
            ( sleep 2; c=$(cut -d. -f1 /tmp/qs-claim 2>/dev/null)
              [ -n "$c" ] && [ "$c" -ge $((now - 2)) ] && exit 0
              log "settings-hook: the compositor did not open Settings, doing it from the hook"
              if [ -e /tmp/set-vis ]; then sh "$D/settings-open.sh" close; else sh "$D/settings-open.sh" launch; fi ) </dev/null >/dev/null 2>&1 &
            continue
          fi
          if [ -e /tmp/set-vis ]; then sh "$D/settings-open.sh" close >/dev/null 2>&1 &
          else sh "$D/settings-open.sh" launch >/dev/null 2>&1 & fi;;
    QS)   lun luna://com.webos.service.systemUIManager/closeByAppId '{"appId":"com.webos.app.quicksettings"}' >/dev/null &
          if [ $((now - claim)) -gt 3 ]; then       # not the Settings key (picture / aspect / sleep hotkeys, or a test): open ours as well
            [ $((now - last)) -lt 2 ] && continue
            api_ok || { log "settings-hook: API down, leaving LG's panel alone"; continue; }
            last=$now; sh "$D/settings-open.sh" launch >/dev/null 2>&1 &
          fi;;
    LGS)  lg_settings_allowed && continue
          api_ok || continue
          lun luna://com.webos.applicationManager/closeByAppId '{"id":"com.palm.app.settings","forceMode":true}' >/dev/null
          [ $((now - last)) -lt 2 ] && continue
          last=$now; sh "$D/settings-open.sh" launch >/dev/null 2>&1 &
          ;;
  esac
done
rm -f $PIDF
