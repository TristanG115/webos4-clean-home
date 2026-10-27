#!/bin/sh
# backchain.sh start|stop|status - what the Back key does in apps and inputs.
# keywatch.py reports each press of the remote's Back key (the Magic Remote sends code 412, the IR remote 158) and a "LEAVE" when Back is held or pressed twice quickly.
#   BACK   the app gets the key first (Netflix ignores it on its start screen, YouTube steps back inside itself). 1.5 s later, if the app quit, the TV lands where SAM
#          put it (often the last input); we move it to where you expect: the previous app of your history (lastapp.sh) or Home when there is none.
#   LEAVE  you want out, whatever the app does with Back: go to the previous app / Home at once (the app stays open in the background, like the Home key).
# Home, our Settings and LG overlays are never touched. Options (Settings -> Remote & pointer): state/backchain-off = no previous-app landing (Home instead),
# leave=both|hold|double|off in state/back.conf. RAM only; a reboot without the init hook is stock.
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/backchain.pid; KW=$D/keywatch.py
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
stop() {
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  for p in $(pgrep -f "python $KW"); do kill "$p" 2>/dev/null; done
}
fgid() { lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1; }
launch() { LW=10000 lun luna://com.webos.applicationManager/launch "{\"id\":\"$1\",\"params\":{}}" >/dev/null; }
skip_app() { case "$1" in ''|"$HOME_ID"|"$SET_ID"|com.webos.app.quicksettings|com.webos.app.screensaver*|com.webos.app.notification*) return 0;; esac; return 1; }
target() { p=""; [ -e "$STATE/backchain-off" ] || p=$(sh "$D/lastapp.sh" before "$1"); if [ -n "$p" ]; then echo "$p"; else echo "$HOME_ID"; fi; }
case ${1:-start} in
  stop) stop; log "backchain: stopped"; exit 0;;
  status) alive && echo running || echo stopped; exit 0;;
esac
alive && exit 0
command -v python >/dev/null 2>&1 && [ -f "$KW" ] || { log "backchain: python or keywatch.py missing"; exit 1; }
echo $$ > $PIDF
log "backchain: watching the Back key"
python $KW 2>/dev/null | while read -r ev; do
  [ -e "$D/DISABLE" ] && continue
  a=$(fgid); skip_app "$a" && continue
  case $ev in
    LEAVE) t=$(target "$a"); log "backchain: Back held / pressed twice in $a -> $t"; launch "$t";;
    BACK)  [ -e "$STATE/backchain-off" ] && continue
           ( usleep 1500000
             b=$(fgid); [ -n "$b" ] && [ "$b" != "$a" ] || exit 0        # still in the app: it used the key itself
             t=$(target "$a"); [ "$b" = "$t" ] && exit 0
             log "backchain: $a quit (TV showed $b) -> $t"; launch "$t" ) </dev/null >/dev/null 2>&1 &;;
  esac
done
rm -f $PIDF
