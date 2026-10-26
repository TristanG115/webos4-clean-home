#!/bin/sh
# pointer.sh off|on - EXPERIMENTAL: ask the Magic Remote service (lginput2, com.webos.service.mrcu) to stop / resume pointer motion.
# LG has no setting for "no pointer"; this tries the service's own motion-sensor switch with the parameter names the binary knows.
# It only works while the Magic Remote is awake and connected (press any remote button first). RAM-only: a restart brings the pointer back.
# Prints ONE line of plain text (shown as a toast on the TV).
. /media/developer/tv-debloat/common.sh
M=luna://com.webos.service.mrcu
case ${1:-off} in off) v=false;; on) v=true;; *) echo "usage: pointer.sh off|on"; exit 1;; esac
st=$(lun $M/getConnectionStatus '{}' | tr -d '\n')
case $st in *'"connected": true'*) ;; *) echo "The Magic Remote is asleep or not connected. Press a button on it and try again."; exit 0;; esac
for body in "{\"activate\":$v}" "{\"enable\":$v}" "{\"enabled\":$v}" "{\"active\":$v}"; do
  r=$(lun $M/activateMotionSensor "$body" | tr -d '\n')
  case $r in *'"returnValue": true'*|*'"returnValue":true'*)
    [ $v = false ] && touch "$STATE/pointer-off" || rm -f "$STATE/pointer-off"
    log "pointer: activateMotionSensor $body accepted"
    [ $v = false ] && echo "Pointer motion switched off. Move the remote to check; a restart brings it back." || echo "Pointer motion switched on again."; exit 0;;
  esac
  log "pointer: activateMotionSensor $body -> $r"
done
echo "The TV did not accept the request (this model may not support it)."
