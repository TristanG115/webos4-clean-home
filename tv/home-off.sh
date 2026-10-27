#!/bin/sh
# home-off.sh [temp|perm] - bring LG's own Home back. perm also creates DISABLE so boots keep LG's Home.
. /media/developer/tv-debloat/common.sh
[ "$1" = perm ] && touch "$D/DISABLE"
# our Settings key hook and overlay go first: with LG's Home back, LG's own Settings panel is used again
sh "$D/settings-hook.sh" stop >/dev/null 2>&1
sh "$D/lastapp.sh" stop >/dev/null 2>&1
sh "$D/backlight.sh" restore >/dev/null 2>&1
sh "$D/backchain.sh" stop >/dev/null 2>&1
sh "$D/pointer.sh" stop >/dev/null 2>&1
sh "$D/pointerhide.sh" stop >/dev/null 2>&1
sh "$D/settings-open.sh" close >/dev/null 2>&1
# LG's Home may need the ad service the stub replaces, so un-stub it first
sh "$D/debloat.sh" undo admanager >/dev/null 2>&1
# stop the stand-in (and its SAM registration) FIRST: a bind-mounted script that is still running keeps the mount busy
pkill -f "[l]una-send -i -a $HOME_ID" 2>/dev/null
for p in $(pgrep -f "^/bin/sh $HOME_EXE"); do kill "$p" 2>/dev/null; done
sleep 1
for p in $(pgrep -f "^/bin/sh $HOME_EXE"); do kill -9 "$p" 2>/dev/null; done
for m in $(awk -v b="$HOME_EXE" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; done
is_mounted $HOME_EXE && log "home-off: WARNING stand-in still mounted"
lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$HOME_ID\"}" >/dev/null
lun luna://com.webos.settingsservice/setSystemSettings '{"category":"general","settings":{"screenSaverEnabled":"on"}}' >/dev/null
rm -f "$STATE/launcher.ready"
sleep 2
lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}" >/dev/null
log "home-off ($1): LG Home restored"
echo "LG Home restored"
