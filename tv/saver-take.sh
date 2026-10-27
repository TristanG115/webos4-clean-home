#!/bin/sh
# saver-take.sh - LG's own screensaver (no signal on an input, or LG's idle timer) just appeared: swap it for ours.
# Closes LG's saver, brings Home to the front and tells the page (/tmp/saver-now, read by /api/saver/take when the page is shown) to start our screensaver.
# Does nothing when our screensaver is switched off in Settings (then LG's stays), or state/saver-lg exists, or it ran in the last 10 s.
. /media/developer/tv-debloat/common.sh
[ -e "$STATE/saver-lg" ] && exit 0
python -c "
import json, sys
try: s = json.load(open('$STATE/settings.json'))
except Exception: s = {}
sys.exit(0 if (s.get('saver') or {}).get('on', True) else 1)" 2>/dev/null || exit 0
now=$(cut -d. -f1 /proc/uptime); last=$(cat /tmp/saver-take.last 2>/dev/null || echo -99)
[ $((now - last)) -ge 10 ] || exit 0
echo $now > /tmp/saver-take.last
log "saver-take: LG's screensaver appeared, showing ours"
up > /tmp/saver-now
lun luna://com.webos.applicationManager/closeByAppId '{"id":"com.webos.app.screensaver"}' >/dev/null
lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}" >/dev/null
