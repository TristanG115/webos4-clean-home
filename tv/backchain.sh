#!/bin/sh
# backchain.sh start|stop|status - Back from an app returns to the previous app / input instead of Home (Home when there is none).
# keywatch.py reports each press of the remote's Back key. If the foreground is a normal app, we wait 2 s: when the app handled the key itself
# (a menu closed) it is still in front and nothing happens; when the app quit, the TV falls back to Home and we open the previous entry of the
# history that lastapp.sh keeps (skipping apps that are no longer running). Home, our Settings and LG overlays are never touched.
# Off switch: state/backchain-off (Settings -> Remote & pointer). RAM only; a reboot without the init hook is stock.
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/backchain.pid; KW=$D/keywatch.py
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
stop() {
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  for p in $(pgrep -f "python $KW"); do kill "$p" 2>/dev/null; done
}
fgid() { lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1; }
case ${1:-start} in
  stop) stop; log "backchain: stopped"; exit 0;;
  status) alive && echo running || echo stopped; exit 0;;
esac
alive && exit 0
command -v python >/dev/null 2>&1 && [ -f "$KW" ] || { log "backchain: python or keywatch.py missing"; exit 1; }
echo $$ > $PIDF
log "backchain: watching the Back key"
DEVS=""; for n in $(grep -A5 'Name="LGE' /proc/bus/input/devices | grep -o 'event[0-9]*'); do DEVS="$DEVS /dev/input/$n"; done
python $KW $DEVS 2>/dev/null | while read -r ev; do
  [ -e "$D/DISABLE" ] || [ -e "$STATE/backchain-off" ] && continue
  a=$(fgid)
  case "$a" in ''|"$HOME_ID"|"$SET_ID"|com.webos.app.quicksettings|com.webos.app.screensaver*|com.webos.app.notification*) continue;; esac
  sleep 2
  [ "$(fgid)" = "$HOME_ID" ] || continue            # the app is still in front: it used the key itself
  p=$(sh "$D/lastapp.sh" before "$a")
  [ -n "$p" ] || { log "backchain: $a quit, nothing before it: staying on Home"; continue; }
  log "backchain: $a quit -> $p"
  LW=10000 lun luna://com.webos.applicationManager/launch "{\"id\":\"$p\",\"params\":{}}" >/dev/null
done
rm -f $PIDF
