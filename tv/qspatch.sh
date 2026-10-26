#!/bin/sh
# qspatch.sh build|apply|undo|status|boot|wait - stop LG's quick-settings panel for good (our Settings overlay replaces it) and try to stop the pointer
# waking on the scroll wheel, by loading patched copies of two of LG's key-filter scripts into the compositor.
#
# WHY: the gear key makes LG's compositor (surface-manager) draw its QML quick panel (about 86 KB of QML, preloaded) 0.5 s after the key. We can only close it
# afterwards, so it flashes for about a second and steals CPU while our overlay starts. The key handling is plain JavaScript in /usr/lib/qt5/qml/KeyFilters/:
#   appLaunch.js  openSettings(params)  -> we make it return at once (the gear / picture / aspect / sleep hotkeys no longer open LG's panel)
#   systemUi.js   handleScreenSaver / handleHomeKeys / handleSystemKeys -> swallow Key_webOS_CursorShow, the key the scroll wheel sends to show the pointer.
#                 UNVERIFIED: LG's comment says cursor keys are handled in the C++ compositor, which may see that key before these filters do.
# HOW: the patched files are generated on the TV from the TV's own originals (LG's code is never copied into this repo), placed in RAM (/tmp/keyfilters-patched)
# and bind-mounted over the originals. The compositor reads them only when it starts, so apply restarts it (`initctl restart surface-manager`): the screen goes
# dark for several seconds and every app is closed. Nothing on the read-only system partition changes; a reboot is stock.
# SAFETY (all automatic): the patch is only applied if the generated files pass checks; after the restart the script waits for the compositor, WebAppMgr (emitting
# `wam-start` if Upstart does not start it), the app manager and Home; any failure -> unmount, restart again, flag removed; a RAM watchdog reboots the TV after 180 s
# if the script itself hangs (a reboot is stock). state/qspatch.trying marks an unfinished attempt so a boot never repeats a failed one.
. /media/developer/tv-debloat/common.sh
KF=/usr/lib/qt5/qml/KeyFilters; PD=/tmp/keyfilters-patched; BUSY=/tmp/qspatch.busy
FLAG=$STATE/qspatch-on; TRY=$STATE/qspatch.trying
svc_up() { initctl status "$1" 2>/dev/null | grep -q "start/running"; }
patched() { is_mounted $KF/appLaunch.js; }

build() { # generate the two patched files from the originals; prints nothing on success
  rm -rf $PD; mkdir -p $PD || return 1
  # when already mounted the visible file is the patched one: take the original from a fresh read of the underlying squashfs path is not possible, so refuse
  patched && return 1
  awk '{print} /^function openSettings\(params\) \{/ {print "    return;   // tv-debloat: our Settings overlay replaces LG'"'"'s quick panel"; n++} END{if (n != 1) exit 3}' $KF/appLaunch.js > $PD/appLaunch.js || return 1
  awk '{print} /^function (handleScreenSaver|handleHomeKeys|handleSystemKeys)\(key, pressed, autoRepeat\) \{/ {print "    if (key === WebOS.Key_webOS_CursorShow) return KeyPolicy.Accepted;   // tv-debloat: wheel must not show the pointer"; n++} END{if (n != 3) exit 3}' $KF/systemUi.js > $PD/systemUi.js || return 1
  # checks: one inserted line in appLaunch.js, equal numbers of braces and brackets as the original, sizes within 1 KB
  [ "$(grep -c 'tv-debloat' $PD/appLaunch.js)" = 1 ] || return 1
  for f in appLaunch.js systemUi.js; do
    a=$(tr -cd '{}[]' < $KF/$f | wc -c); b=$(tr -cd '{}[]' < $PD/$f | wc -c); [ "$a" = "$b" ] || return 1
    sa=$(wc -c < $KF/$f); sb=$(wc -c < $PD/$f); [ $((sb - sa)) -ge 0 ] && [ $((sb - sa)) -le 1024 ] || return 1
  done
  return 0
}
mount_patch() { for f in appLaunch.js systemUi.js; do mount --bind $PD/$f $KF/$f || return 1; done; }
umount_patch() { for f in appLaunch.js systemUi.js; do for m in $(awk -v b="$KF/$f" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; done; done; }

ui_healthy() { # the compositor, the web app manager, the app manager and Home are all back
  svc_up surface-manager && svc_up WebAppMgr || return 1
  lun luna://com.webos.applicationManager/running '{}' | grep -q returnValue || return 1
  return 0
}
restart_ui() { # restart the compositor and bring everything back; 0 = healthy
  log "qspatch: restarting surface-manager"
  initctl restart surface-manager >/dev/null 2>&1
  i=0; while [ $i -lt 30 ]; do sleep 2; i=$((i+2)); svc_up surface-manager && break; done
  sleep 4
  svc_up WebAppMgr || { log "qspatch: WebAppMgr not up, emitting wam-start"; initctl emit --no-wait wam-start >/dev/null 2>&1; sleep 5; }
  svc_up WebAppMgr || { initctl start WebAppMgr >/dev/null 2>&1; sleep 5; }
  i=0; while [ $i -lt 60 ]; do ui_healthy && break; sleep 3; i=$((i+3)); done
  ui_healthy || return 1
  # Home: SAM normally starts it again; make sure, then wait for the launcher page to report ready (our stand-in is bind-mounted, so SAM runs it)
  rm -f "$STATE/launcher.ready"
  lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}" >/dev/null
  i=0; while [ $i -lt 45 ]; do [ -e "$STATE/launcher.ready" ] && return 0; sleep 3; i=$((i+3)); done
  log "qspatch: launcher did not report ready after the restart"; return 1
}
rollback() { log "qspatch: ROLLBACK ($1)"; umount_patch; rm -f "$FLAG"; restart_ui || { log "qspatch: UI not healthy after rollback, rebooting"; rm -f "$BUSY" "$TRY"; luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 || reboot; }; rm -f "$BUSY" "$TRY"; }
watchdog() { ( sleep 180; if [ -e "$BUSY" ]; then log "qspatch: watchdog: still busy after 180 s, rebooting (stock after reboot)"; umount_patch; rm -f "$FLAG" "$BUSY" "$TRY"; luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 || reboot; fi ) </dev/null >/dev/null 2>&1 & }

case ${1:-status} in
  build)  build && { echo "patched files built in $PD (not mounted):"; diff $KF/appLaunch.js $PD/appLaunch.js; diff $KF/systemUi.js $PD/systemUi.js; true; } || echo "build failed";;
  apply)  patched && { echo "already applied"; exit 0; }
          [ -e "$D/DISABLE" ] && { echo "DISABLE flag present"; exit 1; }
          [ "$2" = boot ] || { sh "$D/settings-hook.sh" status | grep -q running || { echo "refused: our Settings key hook is not running, the gear key would do nothing"; exit 1; }; }
          touch "$BUSY"; date > "$TRY"; watchdog
          build || { rollback "generated files failed the checks"; echo "refused: files failed the checks"; exit 1; }
          mount_patch || { rollback "mount failed"; echo "mount failed"; exit 1; }
          if restart_ui; then touch "$FLAG"; rm -f "$BUSY" "$TRY"; log "qspatch: applied, UI healthy"; echo "applied"
          else rollback "UI not healthy after the restart"; echo "rolled back"; exit 1; fi;;
  undo)   touch "$BUSY"; watchdog; umount_patch; rm -f "$FLAG"
          if restart_ui; then log "qspatch: undone, UI healthy"; echo "undone"; else rollback "UI not healthy after undo"; fi; rm -f "$BUSY" "$TRY";;
  boot)   # used by debloat.sh (boot and the Settings switch): never repeats an attempt that did not finish
          if [ -e "$TRY" ]; then log "qspatch: previous attempt never finished: switched off in Services (turn it on again to retry)"; rm -f "$FLAG" "$TRY"
            grep -v '^qspatch=' "$STATE/svc.conf" 2>/dev/null > "$STATE/svc.conf.tmp"; echo 'qspatch=off' >> "$STATE/svc.conf.tmp"; mv "$STATE/svc.conf.tmp" "$STATE/svc.conf"; exit 0; fi
          sh "$0" apply boot;;
  wait)   i=0; while [ -e "$BUSY" ] && [ $i -lt 200 ]; do sleep 2; i=$((i+2)); done;;
  status) if patched; then echo "ACTIVE (LG's quick panel disabled, pointer key swallowed)"; else echo "off"; fi;;
esac
