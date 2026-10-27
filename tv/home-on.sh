#!/bin/sh
# home-on.sh - replace LG's Home with the web launcher (RAM only; a reboot without zz-debloat restores LG's Home).
# 30 s verification + watchdog: if the launcher never reports ready, or the API dies for good, LG's Home comes back.
# The launcher code is served from a tmpfs copy (see ram_sync in common.sh); if that copy cannot be made the flash copy is used.
. /media/developer/tv-debloat/common.sh
[ -e "$D/DISABLE" ] && { echo "DISABLE flag present"; exit 0; }
[ -f "$D/launcher/index.html" ] || { echo "no launcher files"; exit 1; }
is_mounted $HOME_EXE && { echo "launcher already active"; exit 0; }
api_start; sleep 1
api_ok || { log "home-on: API not answering, aborting"; echo "API failed"; exit 1; }
ram_sync && log "home-on: launcher code copied to RAM ($RAMDIR)" || { log "home-on: RAM copy failed, using flash"; rm -f "$RAMDIR/.complete"; }
DIR=$(launcher_dir)
APP=$(app_desc "$D/launcher/appinfo.json" "$DIR")
# DevTools (port 9998) for the launcher page only while this flag exists: touch /media/developer/tv-debloat/DEBUG
[ -e "$D/DEBUG" ] && APP=$(echo "$APP" | sed 's/"defaultWindowType":"home",/"defaultWindowType":"home","inspectable":true,/')
printf '{"appDesc":%s,"parameters":{},"launchingAppId":"","launchingProcId":"","instanceId":"tv-debloat-home"}' "$APP" > "$STATE/wam-launch.json"
rm -f "$STATE/launcher.ready"
chmod 755 "$D/home-standin.sh"
mount --bind "$D/home-standin.sh" $HOME_EXE || { log "home-on: bind mount failed"; echo "mount failed"; exit 1; }
log "home-on: stand-in mounted over $HOME_EXE (page from $DIR)"
lun luna://com.webos.settingsservice/setSystemSettings '{"category":"general","settings":{"screenSaverEnabled":"off"}}' >/dev/null
for p in $(pgrep -f "^$HOME_EXE"); do kill "$p" 2>/dev/null; done
sleep 3
fg=$(lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}")
log "home-on: launch Home -> $fg"
ok=0; i=0
while [ $i -lt 15 ]; do
  [ -e "$STATE/launcher.ready" ] && { ok=1; break; }
  sleep 2; i=$((i+1))
done
if [ $ok = 1 ]; then
  log "home-on: launcher reported ready"; echo "launcher active"
else
  log "home-on: launcher did not report ready in 30 s -> LG Home"; echo "launcher failed; restoring LG Home"
  sh "$D/home-off.sh" temp; exit 1
fi
# the remote's Settings key opens our Settings (see settings-hook.sh)
( setsid sh "$D/settings-hook.sh" start </dev/null >/dev/null 2>&1 & )
# Back on Home returns to the last app (lastapp.sh), and the optional pointer switch is re-applied when the remote wakes (pointer.sh)
( setsid sh "$D/lastapp.sh" start </dev/null >/dev/null 2>&1 & )
( setsid sh "$D/pointer.sh" watch </dev/null >/dev/null 2>&1 & )
( setsid sh "$D/backchain.sh" start </dev/null >/dev/null 2>&1 & )
( setsid sh "$D/pointerhide.sh" start </dev/null >/dev/null 2>&1 & )
# watchdog: API self-heal every 20 s; every 5 min re-apply whatever LG restarted (debloat.sh sweep); every hour refresh the ad-block lists
( bad=0; tick=0
  while is_mounted $HOME_EXE; do
    sleep 20; tick=$((tick+1))
    [ -e "$STATE/backlight.orig" ] && sh "$D/backlight.sh" sweep >/dev/null 2>&1      # restore a stale screensaver dim
    is_mounted $HOME_EXE || break      # reverted while we slept: do not restart anything
    if api_ok; then bad=0; else api_start; sleep 1; if api_ok; then bad=0; else bad=$((bad+1)); fi; fi
    [ $bad -ge 3 ] && { log "home-on: watchdog -> LG Home"; sh "$D/home-off.sh" temp; break; }
    if [ $((tick % 15)) = 0 ] && mkdir /tmp/tvd-sweep.lock 2>/dev/null; then
      ( sh "$D/debloat.sh" sweep >/dev/null 2>&1; ( setsid sh "$D/settings-hook.sh" start </dev/null >/dev/null 2>&1 & ); ( setsid sh "$D/lastapp.sh" start </dev/null >/dev/null 2>&1 & ); ( setsid sh "$D/pointer.sh" watch </dev/null >/dev/null 2>&1 & ); ( setsid sh "$D/backchain.sh" start </dev/null >/dev/null 2>&1 & ); ( setsid sh "$D/pointerhide.sh" start </dev/null >/dev/null 2>&1 & ); rmdir /tmp/tvd-sweep.lock ) </dev/null >/dev/null 2>&1 &
    fi
    [ $((tick % 180)) = 0 ] && ( sh "$D/blocklist.sh" maybe-update >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
    # app updates: a quiet background check once after each start and then every N hours (Settings -> App updates; appupdate.sh due)
    [ "$(sh "$D/appupdate.sh" due 2>/dev/null)" = yes ] && ( sh "$D/appupdate.sh" check >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
  done ) </dev/null >/dev/null 2>&1 &
exit 0
