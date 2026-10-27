#!/bin/sh
# qspatch.sh build|apply|reapply|undo|status|boot|wait - small, safe patches to LG's compositor (surface-manager), loaded from RAM over the read-only originals.
#
# WHAT (all inserted from our own snippets in tv/qs/, never a copy of LG's code in this repo):
#   KeyFilters/appLaunch.js   openSettings()  -> opens / closes OUR Settings overlay straight from the key (lunaCall -> WebAppMgr launchApp / killApp), LG's quick panel never opens.
#                             The old way waited for the key to show up in the system log, which BusyBox polls once a second: 0.6-0.9 s late. The shell hook stays as the
#                             fallback (it opens Settings itself if the compositor did not "claim" the key within 2 s).
#                             Also: the boot-time pre-load of LG's quick panel (QML tree in RAM) is dropped, it is never shown.
#   KeyFilters/systemUi.js    init() reports in; the three key handlers swallow Key_webOS_CursorShow (the scroll wheel's "show the pointer" key). NOTE: the `compositor`
#                             object does not exist in this script (ReferenceError, found the hard way); it is only visible inside the QML files.
#   POINTER (tried, does not work, removed): inside the QML files `compositor.cursorVisible` is READ-ONLY ("Cannot assign to read-only property") and
#   `compositor.mouseEventEnabled` is already false and does not gate the Magic Remote pointer. See docs/AUDIT.md for the leads that are left.
# HOW: files are generated on the TV from the TV's own originals into /tmp/keyfilters-patched and bind-mounted over them. The compositor reads them only when it starts,
# so apply restarts it (`initctl restart surface-manager`): the screen goes dark for about 10 s and every app is closed. Nothing on the read-only system partition
# changes; a reboot is stock.
# SAFETY (all automatic): files are only used if the generated copies pass checks (marker counts, brace balance, size); after the restart the script waits for the
# compositor, WebAppMgr (emitting `wam-start` if Upstart does not start it), the app manager, Home, and for our patched scripts to report in (/api/qs?e=loaded);
# any failure -> unmount, restart again, flag removed; a RAM watchdog reboots the TV after 180 s if the script itself hangs (a reboot is stock).
# state/qspatch.trying marks an unfinished attempt so a boot never repeats a failed one.
. /media/developer/tv-debloat/common.sh
KF=/usr/lib/qt5/qml/KeyFilters; YS=/usr/lib/qt5/qml/YSM; SN=$D/qs; PD=/tmp/keyfilters-patched; BUSY=/tmp/qspatch.busy
FLAG=$STATE/qspatch-on; TRY=$STATE/qspatch.trying; VERIFIED=$STATE/qspatch.verified; BOOTMODE=0
sum_built() { for e in $(cat $PD/list); do cat $PD/${e%%:*}; done | md5sum | cut -d' ' -f1; }
FILES="$KF/appLaunch.js $KF/systemUi.js"
svc_up() { initctl status "$1" 2>/dev/null | grep -q "start/running"; }
patched() { is_mounted $KF/appLaunch.js; }

bal() { echo $(( $(tr -cd '{' < $1 | wc -c) - $(tr -cd '}' < $1 | wc -c) )) ; }     # braces open minus closed
build() { # generate the patched files from the originals; prints nothing on success
  rm -rf $PD; mkdir -p $PD || return 1
  # when already mounted the visible file is the patched one: a build would patch the patch, so refuse
  patched && return 1
  for f in appLaunch.head.js systemUi.head.js; do [ -s "$SN/$f" ] || return 1; done
  [ -f "$RAMDIR/.complete" ] || ram_sync >/dev/null 2>&1
  DESC=$(settings_appdesc) || return 1; [ -n "$DESC" ] || return 1; export DESC
  awk -v HEAD="$SN/appLaunch.head.js" '
    function emit(file,   l, i) { while ((getline l < file) > 0) { i = index(l, "__APPDESC__"); if (i) l = substr(l, 1, i - 1) ENVIRON["DESC"] substr(l, i + 11); print l } close(file) }
    /^function openSettings\(params\) \{/ { emit(HEAD); print; print "    if (tvdOpenSettings(params)) return;   // tv-debloat"; print "    return;   // tv-debloat: our Settings overlay replaces LG'"'"'s quick panel"; n++; next }
    /lunaCall\.send\(.com\.webos\.service\.systemUIManager., .\/launch., JSON\.stringify\(\{"appId": "com\.webos\.app\.quicksettings", "reason": "preload"\}\)\);/ { print "    // tv-debloat: LG'"'"'s quick panel is never shown, so it is not pre-loaded either (saves its QML tree in RAM)"; p++; next }
    { print }
    END { if (n != 1 || p != 1) exit 3 }' $KF/appLaunch.js > $PD/appLaunch.js || return 1
  awk -v HEAD="$SN/systemUi.head.js" '
    function emit(file,   l) { while ((getline l < file) > 0) print l; close(file) }
    /^function init\(\) \{/ { emit(HEAD); print; print "    try { tvdInit(); } catch (e) {}   // tv-debloat: report in"; n++; next }
    /^function (handleScreenSaver|handleHomeKeys|handleSystemKeys)\(key, pressed, autoRepeat\) \{/ { print; print "    if (key === WebOS.Key_webOS_CursorShow) { try { compositor.mouseEventEnabled = false; compositor.cursorVisible = false; } catch (e) {} return KeyPolicy.Accepted; }   // tv-debloat: wheel must not show the pointer"; m++; next }
    { print }
    END { if (n != 1 || m != 3) exit 3 }' $KF/systemUi.js > $PD/systemUi.js || return 1
  echo "appLaunch.js:$KF systemUi.js:$KF" > $PD/list
  # checks: equal numbers of braces as the original, sizes within 12 KB of it, our marker present
  for e in $LIST; do f=${e%%:*}; dir=${e#*:}
    [ "$(bal $dir/$f)" = "$(bal $PD/$f)" ] || return 1
    sa=$(wc -c < $dir/$f); sb=$(wc -c < $PD/$f); [ $((sb - sa)) -ge 0 ] && [ $((sb - sa)) -le 12288 ] || return 1
    grep -q 'tv-debloat' $PD/$f || return 1
  done
  return 0
}
mount_patch() { for e in $(cat $PD/list); do f=${e%%:*}; dir=${e#*:}; mount --bind $PD/$f $dir/$f || return 1; done; }
umount_patch() { for p in $FILES $YS/StarfishKeyFilter.qml; do for m in $(awk -v b="$p" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; done; done; }

ui_healthy() { # the compositor, the web app manager, the app manager and Home are all back
  svc_up surface-manager && svc_up WebAppMgr || return 1
  lun luna://com.webos.applicationManager/running '{}' | grep -q returnValue || return 1
  return 0
}
restart_ui() { # restart the compositor and bring everything back; 0 = healthy
  log "qspatch: restarting surface-manager"
  rm -f /tmp/qs-loaded-appLaunch /tmp/qs-loaded-systemUi
  initctl restart surface-manager >/dev/null 2>&1
  i=0; while [ $i -lt 30 ]; do sleep 2; i=$((i+2)); svc_up surface-manager && break; done
  sleep 4
  svc_up WebAppMgr || { log "qspatch: WebAppMgr not up, emitting wam-start"; initctl emit --no-wait wam-start >/dev/null 2>&1; sleep 5; }
  svc_up WebAppMgr || { initctl start WebAppMgr >/dev/null 2>&1; sleep 5; }
  i=0; while [ $i -lt 60 ]; do ui_healthy && break; sleep 3; i=$((i+3)); done
  ui_healthy || return 1
  # at boot Home is not ours yet (home-on.sh runs after this) and during revert.sh it is LG's again: then there is no launcher to wait for
  [ "$BOOTMODE" = 1 ] || is_mounted "$HOME_EXE" || return 0
  # Home: SAM normally starts it again; make sure, then wait for the launcher page to report ready (our stand-in is bind-mounted, so SAM runs it)
  rm -f "$STATE/launcher.ready"
  lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}" >/dev/null
  i=0; while [ $i -lt 45 ]; do [ -e "$STATE/launcher.ready" ] && return 0; sleep 3; i=$((i+3)); done
  log "qspatch: launcher did not report ready after the restart"; return 1
}
loaded_ok() { # the patched scripts must have run (they call /api/qs?e=loaded); only checkable when our API is up
  api_ok || return 0
  want="appLaunch systemUi"
  i=0; while [ $i -lt 20 ]; do m=""; for w in $want; do [ -e /tmp/qs-loaded-$w ] || m="$m $w"; done; [ -z "$m" ] && return 0; sleep 2; i=$((i+2)); done
  log "qspatch: patched files did not report in:$m"; return 1
}
rollback() { log "qspatch: ROLLBACK ($1)"; umount_patch; rm -f "$FLAG" "$STATE/qspatch.verified"; restart_ui || { log "qspatch: UI not healthy after rollback, rebooting"; rm -f "$BUSY"; luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 || reboot; }; rm -f "$BUSY" "$TRY"; }
watchdog() { ( sleep 180; if [ -e "$BUSY" ]; then log "qspatch: watchdog: still busy after 180 s, rebooting (stock after reboot)"; umount_patch; rm -f "$FLAG" "$BUSY" "$TRY"; luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 || reboot; fi ) </dev/null >/dev/null 2>&1 & }

case ${1:-status} in
  build)  build && { echo "patched files built in $PD (not mounted):"; for e in $(cat $PD/list); do f=${e%%:*}; dir=${e#*:}; echo "== $f"; diff $dir/$f $PD/$f | cut -c1-200; done; true; } || echo "build failed";;
  apply)  patched && { echo "already applied"; exit 0; }
          [ -e "$D/DISABLE" ] && { echo "DISABLE flag present"; exit 1; }
          [ "$2" = boot ] || { sh "$D/settings-hook.sh" status | grep -q running || { echo "refused: our Settings key hook is not running, the gear key would do nothing"; exit 1; }; }
          [ "$2" = boot ] && BOOTMODE=1
          build || { echo "refused: files failed the checks"; exit 1; }
          # a build is only applied at boot when the very same build has already run (and reported in) on this TV: apply it once from a running TV first
          if [ "$BOOTMODE" = 1 ] && [ "$(sum_built)" != "$(cat $VERIFIED 2>/dev/null)" ]; then log "qspatch: this build was never proven on a running TV, not applying it at boot (apply it once from Settings or ssh)"; echo "unverified build, skipped"; exit 0; fi
          touch "$BUSY"; date > "$TRY"; watchdog
          mount_patch || { rollback "mount failed"; echo "mount failed"; exit 1; }
          if restart_ui && loaded_ok; then [ "$BOOTMODE" = 1 ] || sum_built > $VERIFIED; touch "$FLAG"; rm -f "$BUSY" "$TRY"; log "qspatch: applied, UI healthy"; echo "applied"
          else rollback "UI not healthy or patched scripts silent after the restart"; echo "rolled back"; exit 1; fi;;
  reapply) patched || { echo "not applied"; exit 1; }   # regenerate and reload after this script or a snippet changed (one restart)
          touch "$BUSY"; date > "$TRY"; watchdog; umount_patch
          if build && mount_patch && restart_ui && loaded_ok; then sum_built > $VERIFIED; touch "$FLAG"; rm -f "$BUSY" "$TRY"; log "qspatch: re-applied, UI healthy"; echo "re-applied"; else rollback "re-apply failed"; echo "rolled back"; exit 1; fi;;
  undo)   touch "$BUSY"; watchdog; umount_patch; rm -f "$FLAG"
          if restart_ui; then log "qspatch: undone, UI healthy"; echo "undone"; else rollback "UI not healthy after undo"; fi; rm -f "$BUSY" "$TRY";;
  boot)   # used by debloat.sh (boot and the Settings switch): never repeats an attempt that did not finish
          if [ -e "$TRY" ]; then log "qspatch: previous attempt never finished: switched off in Services (turn it on again to retry)"; rm -f "$FLAG" "$TRY"
            grep -v '^qspatch=' "$STATE/svc.conf" 2>/dev/null > "$STATE/svc.conf.tmp"; echo 'qspatch=off' >> "$STATE/svc.conf.tmp"; mv "$STATE/svc.conf.tmp" "$STATE/svc.conf"; exit 0; fi
          sh "$0" apply boot;;
  wait)   i=0; while [ -e "$BUSY" ] && [ $i -lt 200 ]; do sleep 2; i=$((i+2)); done;;
  status) if patched; then n=0; for p in $FILES; do is_mounted $p && n=$((n+1)); done
            echo "ACTIVE ($n of 2 files: Settings opens straight from the key, LG's quick panel disabled)"; else echo "off"; fi;;
esac
