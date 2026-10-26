#!/bin/sh
# Stand-in for LG's native Home program (/usr/bin/com.webos.app.fullhome). home-on.sh bind-mounts THIS file over it, so
# SAM still has LG's Home manifest and starts this script whenever Home is launched. It asks the web app manager (WAM)
# to open the launcher page as com.webos.app.fullhome, registers with SAM so the Home key sends a "relaunch", and
# stays running. Design follows lasharor/cleanyourtv-WebOS scripts/home-standin.sh (MIT). Log: state/tv-debloat.log
. /media/developer/tv-debloat/common.sh
for p in $(pgrep -f "^/bin/sh $0"); do [ "$p" != $$ ] && kill "$p" 2>/dev/null; done
pkill -f "[l]una-send -i -a $HOME_ID" 2>/dev/null
show() {
  r=$(luna-send -n 1 -w 8000 luna://com.palm.webappmanager/launchApp "$(cat "$STATE/wam-launch.json")" </dev/null 2>&1 | tr -d '\n')
  if echo "$r" | grep -q '"returnValue": *true'; then log "standin: launcher shown ($1)"; return 0; fi
  log "standin: WAM refused: $(echo "$r" | cut -c1-200)"; return 1
}
log "standin: started (args: $*)"
show start || { sleep 2; show retry; }
# SAM tells us which registration it wants in the launch arguments ("interfaceMethod":"registerApp" on this firmware)
case "$*" in *'"interfaceMethod":"registerNativeApp"'*) METHODS="registerNativeApp registerApp";; *) METHODS="registerApp registerNativeApp";; esac
for m in $METHODS; do
  luna-send -i -a $HOME_ID "luna://com.webos.applicationManager/$m" '{}' </dev/null 2>&1 | while read -r line; do
    case "$line" in
      *'"event"'*relaunch*) show relaunch;;
      *'"event"'*close*) log "standin: closed by SAM"; kill $$ 2>/dev/null; exit 0;;
      *'"event"'*registered*) log "standin: registered with SAM ($m)";;
      *'"returnValue"'*false*) log "standin: $m refused: $(echo "$line" | cut -c1-160)"; pkill -f "[l]una-send -i -a $HOME_ID" 2>/dev/null;;
    esac
  done
  log "standin: $m ended"
done
log "standin: running unregistered; SAM restarts this script on the Home key"
while :; do sleep 60; done
