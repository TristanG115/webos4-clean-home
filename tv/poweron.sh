#!/bin/sh
# poweron.sh get | set <home|last|hdmi1..hdmi4> | go [wake] | boot <app the TV started on> - where the TV goes when it is turned on (Settings -> Power & timers).
#   home   our Home screen (default). Also switches LG's own "Show Home when the TV turns on" (general.homeAutoLaunch) on, so LG helps too.
#   last   LG's own behaviour: whatever input or app was in front when you turned it off.
#   hdmi1..hdmi4   that input.
# `go wake` is run by lastapp.sh when the power service reports the TV coming back from standby / screen off (Quick Start wake-ups never restart anything, so no boot hook runs);
# `boot` is run by boot.sh at the end of a full start, with the app the TV came up on (LG starts on the last input).
# Our own handler enforces the choice instead of trusting LG's switch, which is not honoured on every wake-up. Nothing happens while DISABLE exists.
. /media/developer/tv-debloat/common.sh
CONF=$STATE/poweron.conf
dest() { d=$(cat "$CONF" 2>/dev/null); case $d in home|last|hdmi1|hdmi2|hdmi3|hdmi4) echo "$d";; *) echo home;; esac; }
target() { case $1 in home) echo "$HOME_ID";; hdmi[1-4]) echo "com.webos.app.$1";; *) echo "";; esac; }
fgid() { cat /tmp/fgnow 2>/dev/null; }
case ${1:-get} in
  get) printf '{"dest":"%s"}' "$(dest)";;
  set) case $2 in home|last|hdmi1|hdmi2|hdmi3|hdmi4) echo "$2" > "$CONF"; log "poweron: destination $2"
         # LG's own switch follows: on only for Home
         v=off; [ "$2" = home ] && v=on
         lun luna://com.webos.settingsservice/setSystemSettings "{\"category\":\"general\",\"settings\":{\"homeAutoLaunch\":\"$v\"}}" >/dev/null
         printf '{"dest":"%s"}' "$2";; *) echo '{"error":"bad destination"}'; exit 1;; esac;;
  go)  [ -e "$D/DISABLE" ] && exit 0
       d=$(dest); id=$(target "$d"); [ -n "$id" ] || exit 0
       [ "$2" = wake ] && sleep 1                         # let LG finish resuming first
       cur=$(fgid)
       if [ "$id" = "$HOME_ID" ]; then case "$cur" in ''|"$HOME_ID"|"$SET_ID"|"$INP_ID"|"$COVER_ID") exit 0;; esac
       else [ "$cur" = "$id" ] && exit 0; fi
       log "poweron: $d (was $cur)"
       LW=10000 lun luna://com.webos.applicationManager/launch "{\"id\":\"$id\",\"params\":{}}" >/dev/null;;
  boot) [ -e "$D/DISABLE" ] && exit 0
       d=$(dest)
       case $d in
         home) ;;                                          # home-on.sh already put our Home in front
         last) a=$2; case "$a" in ''|"$HOME_ID"|com.webos.app.home|com.webos.app.splash|"$COVER_ID") ;; *) log "poweron: back to $a (last)"; lun luna://com.webos.applicationManager/launch "{\"id\":\"$a\",\"params\":{}}" >/dev/null;; esac;;
         *) sh "$0" go;;
       esac;;
esac
