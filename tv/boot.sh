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
sh "$D/debloat.sh" apply hosts remotelogger nudge contentminer lgsettings admanager voice iot idleapps >/dev/null 2>&1
if sh "$D/home-on.sh" >/dev/null 2>&1; then echo 0 > "$STATE/boot-count"; log "boot: launcher up, boot-count reset"; else log "boot: launcher not active (LG Home in use)"; fi
# nudge/contentminer start late (trigger events); sweep for 5 minutes
i=0; while [ $i -lt 15 ]; do sleep 20; sh "$D/debloat.sh" apply remotelogger nudge contentminer voice >/dev/null 2>&1; i=$((i+1)); done
log "boot: done"
