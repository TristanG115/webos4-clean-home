#!/bin/sh
# boot.sh - started (detached) by /var/lib/webosbrew/init.d/zz-debloat. Never blocks the Homebrew startup script.
. /media/developer/tv-debloat/common.sh
log "boot: begin"
[ -e "$D/DISABLE" ] && { log "boot: DISABLE flag present, doing nothing"; exit 0; }
# crash-loop guard: boot-count is reset once the launcher reports ready; 4 unfinished boots in a row disables us
c=$(cat "$STATE/boot-count" 2>/dev/null || echo 0); c=$((c+1)); echo $c > "$STATE/boot-count"
[ "$c" -ge 4 ] && { touch "$D/DISABLE"; log "boot: $c unhealthy boots in a row -> DISABLE created"; exit 0; }
n=0
until lun luna://com.webos.applicationManager/running '{}' | grep -q returnValue; do
  sleep 3; n=$((n+3)); [ $n -gt 240 ] && { log "boot: SAM never answered"; exit 0; }
done
sleep 5
[ -e "$STATE/backlight.orig" ] && sh "$D/backlight.sh" restore      # a screensaver dim must never survive a reboot
# every switch that is ON in Settings -> Services & privacy (state/svc.conf, defaults in services.tsv)
sh "$D/debloat.sh" apply >/dev/null 2>&1
if sh "$D/home-on.sh" >/dev/null 2>&1; then echo 0 > "$STATE/boot-count"; log "boot: launcher up, boot-count reset"; else log "boot: launcher not active (LG Home in use)"; fi
# refresh the remote ad-block lists in the background (needs the network; skipped when they are fresh)
( sh "$D/blocklist.sh" maybe-update >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
# nudge/contentminer/voice start late (trigger events); sweep for 5 minutes. home-on.sh's watchdog keeps sweeping every 5 minutes after that.
i=0; while [ $i -lt 15 ]; do sleep 20; sh "$D/debloat.sh" sweep >/dev/null 2>&1; i=$((i+1)); done
log "boot: done"
