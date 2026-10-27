#!/bin/sh
# lastapp.sh start|stop|status|top|before ID|clear [why]|conf [key value] - keeps a short history of the apps / inputs you used, newest last (/tmp/appstack, RAM only).
# It subscribes to SAM's foreground-app events and records every app that is not Home, our Settings or a system overlay. Lines are "<id> <epoch seconds>".
#   top          newest entry that is still running (Back on Home goes there; api.sh /api/back)
#   before ID    the newest still-running entry older than ID (backchain.sh: where Back from ID should land)
#   clear [why]  forget everything (Back then has nowhere to go: the TV feels freshly turned on)
#   cancel       Back while an app is still on its splash screen (foreground is still where the launch started): close the loading app and go back to where it was started
#                (exit 0 = a launch was cancelled now or within the last 3 s, exit 1 = nothing was launching). Used by backchain.sh and /api/back.
#   evict        keep only the app in front plus the most recent ones (option keep, default 2) in memory and close the other apps (called after every app change)
#   conf         print the Back-button options; "conf key value" sets one (state/back.conf)
# Inputs (HDMI, TV) stay "running" in the background, normal apps disappear when closed, so closed apps are skipped when looking back.
# Options (Settings -> Remote & pointer -> Back button):
#   reset   never | saver | saver_standby   forget the history when the screensaver starts (ours or LG's) / also when the TV goes to standby
#   forget  0 | N                           forget apps you left more than N minutes ago (0 = never)
#   depth   1..8                            how many steps back Back can go
#   leave   both | hold | double | off      leave an app with Back held / pressed twice quickly (backchain.sh, keywatch.py)
#   keep    0 | 1..8  (default 2)                       apps kept in memory: the one in front plus the most recent ones (2 = current + last); the others are closed when a new app
#                                           comes to the front, so going back to the last app is instant. Inputs count as apps. LG's own apps, Home, AirPlay and Homebrew are never closed. 0 = no limit.
#   closeinputs 0 | N                       close an HDMI input app that has been in the background for N minutes (default 5; frees 50-60 MB each, reopens in about 0.7 s)
#   closeidle 0 | N  (default 120)                        close a streaming app that has been sitting in the background for N minutes (0 = never; frees its memory, about 125 MB for
#                                           Netflix; it also stops music that plays in the background, so it is off by default). LG's own apps, inputs and Home are never closed.
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/lastapp.pid; PIDP=/tmp/lastapp-power.pid; PIDR=/tmp/lastapp-reap.pid; PIDS=/tmp/lastapp-saver.pid; PIDB=/tmp/lastapp-bright.pid; PIDL=/tmp/lastapp-life.pid; LEFT=/tmp/appleft; STK=/tmp/appstack; OUT=/tmp/lastapp; BC=$STATE/back.conf
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
bconf() { v=$(sed -n "s/^$1=//p" $BC 2>/dev/null | tail -1); echo "${v:-$2}"; }
stop() {
  [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF
  [ -f $PIDP ] && kill "$(cat $PIDP)" 2>/dev/null; rm -f $PIDP
  [ -f $PIDR ] && kill "$(cat $PIDR)" 2>/dev/null; rm -f $PIDR
  [ -f $PIDS ] && kill "$(cat $PIDS)" 2>/dev/null; rm -f $PIDS
  [ -f $PIDB ] && kill "$(cat $PIDB)" 2>/dev/null; rm -f $PIDB
  [ -f $PIDL ] && kill "$(cat $PIDL)" 2>/dev/null; rm -f $PIDL
  for p in $(pgrep -f "luna-send -i luna://com.webos.applicationManager/getForegroundAppInfo") $(pgrep -f "luna-send -i luna://com.webos.service.tvpower/power/getPowerState") $(pgrep -f "luna-send -i luna://com.webos.applicationManager/running") $(pgrep -f "luna-send -i luna://com.webos.settingsservice/getSystemSettings") $(pgrep -f "luna-send -i luna://com.webos.applicationManager/getAppLifeEvents"); do kill "$p" 2>/dev/null; done
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
      leave) case $3 in both|hold|double|off) ;; *) exit 1;; esac;;
      keep) case $3 in 0|1|2|3|4|5|6|7|8) ;; *) exit 1;; esac;;
      closeinputs) case $3 in ''|*[!0-9]*) exit 1;; esac; [ "$3" -le 1440 ] || exit 1;;
      closeidle) case $3 in ''|*[!0-9]*) exit 1;; esac; [ "$3" -le 1440 ] || exit 1;;
      '') printf '{"reset":"%s","forget":%s,"depth":%s,"closeidle":%s,"closeinputs":%s,"leave":"%s","keep":%s}\n' "$(bconf reset saver)" "$(bconf forget 0)" "$(bconf depth 8)" "$(bconf closeidle 120)" "$(bconf closeinputs 5)" "$(bconf leave both)" "$(bconf keep 2)"; exit 0;;
      *) exit 1;;
    esac
    { grep -v "^$2=" $BC 2>/dev/null; echo "$2=$3"; } > $BC.tmp && mv $BC.tmp $BC; exit 0;;
  why) # called by the launcher page / watchers: "saver" or "standby" happened - forget the history if the options say so
    case "$(bconf reset saver)/$2" in saver/saver|saver_standby/saver|saver_standby/standby) do_clear "$2";; esac; exit 0;;
  reap) # close streaming apps that have been in the background longer than closeidle minutes (called every 2 minutes by the loop below)
    n=$(bconf closeidle 120); ni=$(bconf closeinputs 5); [ -s $LEFT ] || exit 0
    now=$(date +%s); fg=$(lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1); run=$(running_ids)
    : > $LEFT.new
    while read -r id t; do
      [ -n "$id" ] || continue
      lim=$n
      case "$id" in
        com.webos.app.hdmi[0-9]*) lim=$ni;;                                      # an HDMI input app holds about 50-60 MB; it restarts in under a second
        com.webos.*|com.palm.*|"$HOME_ID"|"$SET_ID"|"$INP_ID") continue;;        # LG's other apps, Home and our overlays are never touched
      esac
      [ "$lim" -gt 0 ] 2>/dev/null || continue                                  # this kind is switched off
      if [ $((now - t)) -ge $((lim * 60)) ]; then
        [ "$id" = "$fg" ] && continue                                            # what is on screen is never touched
        if echo "$run" | grep -qx "$id"; then
          lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$id\",\"forceMode\":true}" >/dev/null; log "lastapp: closed $id (in the background for $(( (now - t) / 60 )) min)"
        fi
        continue
      fi
      echo "$id $t" >> $LEFT.new
    done < $LEFT
    mv $LEFT.new $LEFT; exit 0;;
  cancel) # a launch is in progress (the app's splash is up, the foreground is still where the launch started): Back means "never mind"
    n=$(up); n=${n%.*}; c=$(cat /tmp/launch-cancelled 2>/dev/null); [ -n "$c" ] && [ $((n - ${c%.*})) -lt 3 ] && { echo cancelled; exit 0; }
    [ -s /tmp/launching ] || exit 1
    IFS='|' read -r L FROM T < /tmp/launching
    [ -n "$L" ] && [ -n "$T" ] && [ $((n - ${T%.*})) -lt 12 ] || exit 1
    mv /tmp/launching /tmp/launching.x 2>/dev/null || exit 1; rm -f /tmp/launching.x; echo $n > /tmp/launch-cancelled
    case "$FROM" in ''|"$L"|com.webos.app.screensaver*|com.webos.app.quicksettings|com.webos.app.notification*|com.webos.app.splash|"$SET_ID"|"$INP_ID") FROM=$HOME_ID;; esac
    ( lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$L\",\"forceMode\":true}" >/dev/null ) </dev/null >/dev/null 2>&1 &
    LW=10000 lun luna://com.webos.applicationManager/launch "{\"id\":\"$FROM\",\"params\":{}}" >/dev/null
    log "lastapp: Back while $L was loading -> closed it, back to $FROM"; echo "$L"; exit 0;;
  evict) # called after an app (or input) comes to the front: keep it and the most recent ones, close every other app (option keep, default 2)
    k=$(bconf keep 2); [ "$k" -gt 0 ] 2>/dev/null || exit 0; [ -e "$D/DISABLE" ] && exit 0
    cur=$(cat /tmp/fgnow 2>/dev/null)
    case "$cur" in ''|"$HOME_ID"|"$SET_ID"|"$INP_ID"|com.webos.app.quicksettings|com.webos.app.screensaver*|com.webos.app.notification*|com.webos.app.splash) cur="";; esac
    keepset=$(awk '{a[NR]=$1} END{for(i=NR;i>=1;i--) print a[i]}' $STK 2>/dev/null | awk -v k="$k" '!s[$1]++ && n < k { print $1; n++ }')       # newest first; the app that just came to the front is the newest entry
    [ -n "$keepset" ] || exit 0
    for id in $(running_ids); do
      case "$id" in
        "$HOME_ID"|"$SET_ID"|"$INP_ID"|tv.debloat.*|org.webosbrew.*|airplay*|com.palm.*) continue;;     # Home, our overlays, Homebrew, AirPlay, LG's Settings
        com.webos.app.hdmi[0-9]*|com.webos.app.externalinput*) ;;                                      # inputs count as apps
        com.webos.*) continue;;                                                                         # LG's other system apps are never closed
      esac
      echo "$keepset" | grep -qx "$id" && continue
      [ "$id" = "$cur" ] && continue
      lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$id\",\"forceMode\":true}" >/dev/null; log "lastapp: closed $id (keep $k: in front/last = $(echo $keepset | tr ' ' ','))"
    done; exit 0;;
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
( while :; do sleep 120; sh "$0" reap; done ) </dev/null >/dev/null 2>&1 &
echo $! > $PIDR
# LG's own screensaver (no signal on an input): SAM's list of running apps names it while it exists, so the swap for ours does not depend on /var/log/messages (settings-hook.sh watches that too,
# but the log is tiny, rotates and sometimes does not exist). saver-take.sh ignores repeats within 10 s and closes LG's saver, which removes it from the list.
( luna-send -i luna://com.webos.applicationManager/running '{"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
    case "$l" in *'"id":"com.webos.app.screensaver"'*) [ -e "$D/DISABLE" ] || sh "$D/saver-take.sh";; esac
  done ) </dev/null >/dev/null 2>&1 &
echo $! > $PIDS
# One brightness on every input / app / picture mode (brightness.sh): LG's settings service pushes a message the instant the active picture context changes (and once when we
# subscribe), so a context that still has another backlight is fixed within about 0.1-0.2 s of the switch (the old foreground hook + sleep 1 left it wrong for about 1 s).
# The contexts are also seeded ahead of time, in the background, whenever the seeded value differs from the wanted one (brightness.sh seed).
( while :; do
    luna-send -i luna://com.webos.settingsservice/getSystemSettings '{"category":"picture","keys":["backlight"],"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
      [ -s "$STATE/brightness" ] && sh "$D/brightness.sh" handle "$l"
    done
    sleep 5
  done ) </dev/null >/dev/null 2>&1 &
echo $! > $PIDB
[ "$(sh "$D/brightness.sh" due)" = yes ] && ( setsid nice sh "$D/brightness.sh" seed </dev/null >/dev/null 2>&1 & )
# SAM's app life events: "splash" arrives 0.05 s after a launch (measured: Spotify 1.7 s and Netflix 3.3 s before the app is in front, and until then the foreground is still Home, so the
# app ignores Back and Home's Back used to relaunch the previous app); "foreground" is the app really in front. /tmp/launching = "<app>|<foreground when it started>|<uptime>" while a splash
# is up (read by `cancel`), /tmp/fgnow = the foreground app (read by backchain.sh instead of a luna call).
lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1 > /tmp/fgnow
( while :; do
    luna-send -i luna://com.webos.applicationManager/getAppLifeEvents '{"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
      ev=$(printf %s "$l" | sed -n 's/.*"event":"\([a-z]*\)".*/\1/p'); [ -n "$ev" ] || continue
      id=$(printf %s "$l" | sed -n 's/.*"appId":"\([^"]*\)".*/\1/p')
      # LG menus the remote can still open (debloat item lgmenus): close them the moment SAM announces them
      case "$ev:$id" in splash:com.webos.app.voice|splash:com.webos.app.tvhotkey|splash:com.webos.app.homeconnect|launch:com.webos.app.voice|launch:com.webos.app.tvhotkey|launch:com.webos.app.homeconnect)
        if [ -e "$STATE/lgmenus.on" ]; then lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$id\",\"forceMode\":true}" >/dev/null; log "lastapp: closed LG menu $id"; continue; fi;; esac
      case $ev in
        splash) case "$id" in ''|"$HOME_ID"|"$SET_ID"|"$INP_ID"|com.webos.app.quicksettings|com.webos.app.screensaver*|com.webos.app.notification*|com.webos.app.splash) ;;
                  *) printf '%s|%s|%s' "$id" "$(cat /tmp/fgnow 2>/dev/null)" "$(up)" > /tmp/launching;; esac;;
        foreground) printf %s "$id" > /tmp/fgnow; rm -f /tmp/launching;;
        close|stop) [ "$(cut -d'|' -f1 /tmp/launching 2>/dev/null)" = "$id" ] && rm -f /tmp/launching;;
      esac
    done
    sleep 5
  done ) </dev/null >/dev/null 2>&1 &
echo $! > $PIDL
prev=""
# input apps that are already running in the background when this starts (after a boot or a restart of this script) count as "left just now"
for id in $(running_ids | grep -E '^com\.webos\.app\.hdmi[0-9]'); do grep -q "^$id " $LEFT 2>/dev/null || echo "$id $(date +%s)" >> $LEFT; done
while :; do
  luna-send -i luna://com.webos.applicationManager/getForegroundAppInfo '{"subscribe":true}' </dev/null 2>/dev/null | while read -r l; do
    id=$(printf %s "$l" | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p')
    case "$id" in com.webos.app.screensaver*) sh "$0" why saver; continue;; esac     # LG's own screensaver
    # remember when an app went to the background (option "closeidle"): the previous foreground app left just now, the new one is back in front
    if [ -n "$id" ] && [ "$id" != "$prev" ]; then
      [ -n "$prev" ] && { grep -v "^$prev " $LEFT 2>/dev/null; echo "$prev $(date +%s)"; } > $LEFT.tmp && mv $LEFT.tmp $LEFT
      grep -v "^$id " $LEFT 2>/dev/null > $LEFT.tmp; mv $LEFT.tmp $LEFT; prev=$id
    fi
    case "$id" in ''|"$HOME_ID"|"$SET_ID"|com.webos.app.quicksettings|com.webos.app.notification*) continue;; esac
    { grep -v -E "^$id( |\$)" $STK 2>/dev/null; echo "$id $(date +%s)"; } | tail -n $(( $(bconf depth 8) + 1 )) > $STK.tmp && mv $STK.tmp $STK
    printf %s "$id" > $OUT
    ( sh "$D/lastapp.sh" evict ) </dev/null >/dev/null 2>&1 &      # keep only the app in front and the last one in memory (option keep)
    [ -e "$STATE/backlight.orig" ] && sh "$D/backlight.sh" restore      # left Home while the screensaver had the backlight down
  done
  alive || break
  sleep 5                                    # the subscription ended (SAM restarted?): subscribe again
done
rm -f $PIDF
