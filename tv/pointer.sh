#!/bin/sh
# pointer.sh off|on|apply|watch|stop|status - EXPERIMENTAL switch for the Magic Remote pointer (Settings -> Remote & pointer).
# LG has no setting for "no pointer". The remote service (lginput2, com.webos.service.mrcu) has two requests that act on it, but only while the
# remote is awake and connected, and a reconnect or restart resets them. So:
#   off   creates state/pointer-off, applies the requests now and keeps a small watcher that applies them again whenever the remote reconnects.
#   on    removes the flag, puts the defaults back, stops the watcher.
#   apply applies once (silently skips when the remote is asleep).
# What is applied: cursor/setWakeUpCondition {"condition":"shake"} (the arrow only wakes when the remote is shaken, not on every bit of motion)
#                  activateMotionSensor {"activate":false} (accepted by the service; its effect on the arrow was not visible in the first test)
# Prints one line of plain text (shown as a toast). RAM only; nothing here touches LG's settings database.
. /media/developer/tv-debloat/common.sh
M=luna://com.webos.service.mrcu; PIDF=/tmp/pointer.pid; FLAG=$STATE/pointer-off
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
connected() { lun $M/getConnectionStatus '{}' | tr -d '\n ' | grep -q '"connected":true'; }
ok() { case $1 in *'"returnValue": true'*|*'"returnValue":true'*) return 0;; esac; return 1; }
# set_mode off|on: 0 = the requests were accepted, 1 = refused, 2 = remote asleep
set_mode() {
  connected || return 2
  if [ "$1" = off ]; then cond=shake; act=false; else cond=motion; act=true; fi
  r1=$(lun $M/cursor/setWakeUpCondition "{\"condition\":\"$cond\"}" | tr -d '\n'); r2=$(lun $M/activateMotionSensor "{\"activate\":$act}" | tr -d '\n')
  # park the arrow on the bottom-right pixel: the arrow is drawn down and to the right of its tip, so there it is cut off and cannot be seen
  # even when the scroll wheel wakes it (the wheel shows the arrow where it last was). "on" puts it back in the middle of the screen.
  if [ "$1" = off ]; then x=1919; y=1079; else x=960; y=540; fi
  r3=$(lun $M/cursor/setPosition "{\"posX\":$x,\"posY\":$y}" | tr -d '\n')
  log "pointer: $1 -> wake=$(echo "$r1" | cut -c1-90) sensor=$(echo "$r2" | cut -c1-90) park=$(echo "$r3" | cut -c1-90)"
  ok "$r1" || ok "$r2" || ok "$r3"
}
stop() { [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF; }
watch() {
  alive && return 0
  ( was=0
    while [ -e "$FLAG" ] && [ ! -e "$D/DISABLE" ]; do
      if connected; then [ $was = 0 ] && set_mode off; was=1; else was=0; fi
      sleep 10
    done; rm -f $PIDF ) </dev/null >/dev/null 2>&1 &
  echo $! > $PIDF
}
case ${1:-status} in
  off)  touch "$FLAG"; watch
        set_mode off; r=$?
        case $r in 0) echo "Pointer switched off: it should only appear when you shake the remote.";;
                   2) echo "Saved. The remote is asleep: press a button on it and the setting is applied by itself.";;
                   *) echo "Saved, but the TV did not accept the request. This model may not support it.";; esac;;
  on)   rm -f "$FLAG"; stop; set_mode on >/dev/null; echo "Pointer back to normal.";;
  apply) [ -e "$FLAG" ] && set_mode off; exit 0;;
  watch) [ -e "$FLAG" ] && watch; exit 0;;
  stop) stop; exit 0;;
  status) [ -e "$FLAG" ] && echo off || echo on;;
esac
