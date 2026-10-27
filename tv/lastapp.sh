#!/bin/sh
# lastapp.sh start|stop|status|top|before ID|clear [why]|conf [key value] - keeps a short history of the apps / inputs you used, newest last (/tmp/appstack, RAM only).
# It subscribes to SAM's foreground-app events and records every app that is not Home, our Settings or a system overlay. Lines are "<id> <epoch seconds>".
#   top          newest entry that is still running (Back on Home goes there; api.sh /api/back)
#   before ID    the newest still-running entry older than ID (backchain.sh: where Back from ID should land)
#   clear [why]  forget everything (Back then has nowhere to go: the TV feels freshly turned on)
#   conf         print the Back-button options; "conf key value" sets one (state/back.conf)
# Inputs (HDMI, TV) stay "running" in the background, normal apps disappear when closed, so closed apps are skipped when looking back.
# Options (Settings -> Remote & pointer -> Back button):
#   reset   never | saver | saver_standby   forget the history when the screensaver starts (ours or LG's) / also when the TV goes to standby
#   forget  0 | N                           forget apps you left more than N minutes ago (0 = never)
#   depth   1..8                            how many steps back Back can go
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/lastapp.pid; PIDP=/tmp/lastapp-power.pid; STK=/tmp/appstack; OUT=/tmp/lastapp; BC=$STATE/back.conf
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
bconf() { v=$(sed -n "s/^$1=//p" $BC 2>/dev/null | tail -1); echo "${v:-$2}"; }
stop() {
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  [ -f $PIDP ] && kill "$(cat $PIDP)" 2>/dev/null; rm -f $PIDP
  for p in $(pgrep -f "luna-send -i luna://com.webos.applicationManager/getForegroundAppInfo") $(pgrep -f "luna-send -i luna://com.webos.service.tvpower/power/getPowerState"); do kill "$p" 2>/dev/null; done
}
running_ids() { lun luna://com.webos.applicationManager/running '{}' | tr -d '\n ' | grep -o '"id":"[^"]*"' | sed 's/"id":"\(.*\)"/\1/'; }
# newest first, without the entries that are too old (forget)
newest_first() { now=$(date +%s); max=$(( $(bconf forget 0) * 60 )); [ -s $STK ] || return 0
  awk -v now=$now -v max=$max '{a[NR]=$1; t[NR]=($2 == "" ? now : $2)} END{for(i=NR;i>=1;i--) if (max == 0 || now - t[i] <= max) print a[i]}' $STK; }
do_clear() { : > $STK; rm -f $OUT; [ -n "$1" ] && log "lastapp: history cleared ($1)"; }
case ${1:-start} in
  stop) stop; log "lastapp: stopped"; exit 0;;
  status) alive && echo "running, history: $(tr '\n' ' ' < $STK 2>/dev/null)" || echo stopped; exit 0;;
  clear) do_clear "${2:-manual}"; exit 0;;
  conf) case $2 in
      reset) case $3 in never|saver|saver_standby) ;; *) exit 1;; esac;;
      forget) case $3 in ''|*[!0-9]*) exit 1;; esac; [ "$3" -le 1440 ] || exit 1;;
      depth) case $3 in 1|2|3|4|5|6|7|8) ;; *) exit 1;; esac;;
      '') printf '{"reset":"%s","forget":%s,"depth":%s}\n' "$(bconf reset saver)" "$(bconf forget 0)" "$(bconf depth 8)"; exit 0;;
      *) exit 1;;
    esac
    { grep -v "^$2=" $BC 2>/dev/null; echo "$2=$3"; } > $BC.tmp && mv $BC.tmp $BC; exit 0;;
  why) # called by the launcher page / watchers: "saver" or "standby" happened - forget the history if the options say so
    case "$(bconf reset saver)/$2" in saver/saver|saver_standby/saver|saver_standby/standby) do_clear "$2";; esac; exit 0;;
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
# TV going to standby (Quick Start "active standby" keeps RAM, so the history would survive): the power service tells us; the options decide what to do
( luna-send -i luna://com.webos.service.tvpower/power/getPowerState '{"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
    case "$l" in *tandby*|*uspend*|*"Screen Off"*|*Off*) sh "$0" why standby;; esac
  done ) </dev/null >/dev/null 2>&1 &
echo $! > $PIDP
while :; do
  luna-send -i luna://com.webos.applicationManager/getForegroundAppInfo '{"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
    id=$(printf %s "$l" | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p')
    case "$id" in com.webos.app.screensaver*) sh "$0" why saver; continue;; esac     # LG's own screensaver
    case "$id" in ''|"$HOME_ID"|"$SET_ID"|com.webos.app.quicksettings|com.webos.app.notification*) continue;; esac
    { grep -v -E "^$id( |\$)" $STK 2>/dev/null; echo "$id $(date +%s)"; } | tail -n $(( $(bconf depth 8) + 1 )) > $STK.tmp && mv $STK.tmp $STK
    printf %s "$id" > $OUT
    [ -e "$STATE/backlight.orig" ] && sh "$D/backlight.sh" restore      # left Home while the screensaver had the backlight down
  done
  alive || break
  sleep 5                                    # the subscription ended (SAM restarted?): subscribe again
done
rm -f $PIDF
