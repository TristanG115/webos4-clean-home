#!/bin/sh
# lastapp.sh start|stop|status|top|before ID - keeps a short history of the apps / inputs you used, newest last (/tmp/appstack, RAM only).
# It subscribes to SAM's foreground-app events and records every app that is not Home, our Settings or a system overlay.
#   top          newest entry that is still running (Back on Home goes there; api.sh /api/back)
#   before ID    the newest still-running entry older than ID (backchain.sh: where Back from ID should land)
# Inputs (HDMI, TV) stay "running" in the background, normal apps disappear when closed, so closed apps are skipped when looking back.
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/lastapp.pid; STK=/tmp/appstack; OUT=/tmp/lastapp
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
stop() {
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  for p in $(pgrep -f "luna-send -i luna://com.webos.applicationManager/getForegroundAppInfo"); do kill "$p" 2>/dev/null; done
}
running_ids() { lun luna://com.webos.applicationManager/running '{}' | tr -d '\n ' | grep -o '"id":"[^"]*"' | sed 's/"id":"\(.*\)"/\1/'; }
newest_first() { awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}' $STK; }
case ${1:-start} in
  stop) stop; log "lastapp: stopped"; exit 0;;
  status) alive && echo "running, history: $(tr '\n' ' ' < $STK 2>/dev/null)" || echo stopped; exit 0;;
  top) [ -s $STK ] || exit 0; run=$(running_ids)
    for id in $(newest_first); do echo "$run" | grep -qx "$id" && { echo "$id"; exit 0; }; done
    exit 0;;
  before) # walk from the newest entry; skip everything up to and including $2, then print the first running one
    [ -s $STK ] || exit 0; run=$(running_ids); seen=0
    for id in $(newest_first); do
      if [ $seen = 0 ]; then [ "$id" = "$2" ] && seen=1; continue; fi
      echo "$run" | grep -qx "$id" && { echo "$id"; exit 0; }
    done
    exit 0;;
esac
alive && exit 0
echo $$ > $PIDF
log "lastapp: tracking the foreground app"
while :; do
  luna-send -i luna://com.webos.applicationManager/getForegroundAppInfo '{"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
    id=$(printf %s "$l" | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p')
    case "$id" in ''|"$HOME_ID"|"$SET_ID"|com.webos.app.quicksettings|com.webos.app.screensaver*|com.webos.app.notification*) continue;; esac
    { grep -vx "$id" $STK 2>/dev/null; echo "$id"; } | tail -n 8 > $STK.tmp && mv $STK.tmp $STK
    printf %s "$id" > $OUT
  done
  alive || break
  sleep 5                                    # the subscription ended (SAM restarted?): subscribe again
done
rm -f $PIDF
