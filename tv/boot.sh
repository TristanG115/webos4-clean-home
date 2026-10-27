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
sleep 2
# what the TV came up on (LG starts on the last input): "Settings -> Power & timers -> When the TV turns on, go to" may send it back there once our Home is up
FG0=$(lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1)
# our own start-up screen over LG's Home (only when LG's Home is what would show); home-on.sh removes it the moment our Home is ready
sh "$D/cover.sh" show >/dev/null 2>&1
[ -e "$STATE/backlight.orig" ] && sh "$D/backlight.sh" restore      # a screensaver dim must never survive a reboot
# Only what must be in place before our Home starts goes first (the pointer pictures and the compositor patch, which restarts the compositor); every other switch that is ON
# in Settings -> Services & privacy (state/svc.conf, defaults in services.tsv) is applied right after Home is up. That gets our Home on screen about 15 s sooner.
sh "$D/debloat.sh" apply-early >/dev/null 2>&1
if sh "$D/home-on.sh" >/dev/null 2>&1; then sh "$D/cover.sh" hide >/dev/null 2>&1; echo 0 > "$STATE/boot-count"; log "boot: launcher up, boot-count reset"; sh "$D/poweron.sh" boot "$FG0" >/dev/null 2>&1; else sh "$D/cover.sh" hide >/dev/null 2>&1; log "boot: launcher not active (LG Home in use)"; fi
sh "$D/debloat.sh" apply-late >/dev/null 2>&1
# refresh the remote ad-block lists in the background (needs the network; skipped when they are fresh)
( sh "$D/blocklist.sh" maybe-update >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
# nudge/contentminer/voice start late (trigger events); sweep for 5 minutes. home-on.sh's watchdog keeps sweeping every 5 minutes after that.
i=0; while [ $i -lt 15 ]; do sleep 20; sh "$D/debloat.sh" sweep >/dev/null 2>&1; i=$((i+1)); done
sh "$D/cover.sh" hide >/dev/null 2>&1       # whatever happened above, the cover never stays
log "boot: done"
