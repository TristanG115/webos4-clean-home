#!/bin/sh
# revert.sh [--no-reboot]  - undo EVERYTHING tv-debloat did, then reboot. Runs on the TV:
#   ssh root@10.0.0.63 sh /media/developer/tv-debloat/revert.sh        (or via telnet, or from the PC wrapper ./revert.sh)
# Files are never deleted: the init hook is renamed so run-parts skips it.
D=/media/developer/tv-debloat
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
echo "[1/6] disable at boot (DISABLE flag)"; touch $D/DISABLE
echo "[2/6] LG Home back"; sh $D/home-off.sh temp 2>&1 | sed 's/^/      /'
echo "[3/6] debloat undo"; sh $D/debloat.sh undo 2>&1 | sed 's/^/      /'
echo "[4/6] stop launcher API, Settings hook, RAM copy"; sh $D/settings-hook.sh stop; sh $D/lastapp.sh stop; sh $D/backlight.sh restore; sh $D/backchain.sh stop; sh $D/pointer.sh on >/dev/null 2>&1; for p in $(pgrep -f "tcpsvd.* 8765 "); do kill $p 2>/dev/null; done; . $D/common.sh; ram_drop
echo "[5/6] rename init hook"
if [ -e /var/lib/webosbrew/init.d/zz-debloat ]; then
  mv /var/lib/webosbrew/init.d/zz-debloat /var/lib/webosbrew/init.d/zz-debloat.disabled && echo "      zz-debloat -> zz-debloat.disabled"
else echo "      (no init hook installed)"; fi
rm -f $D/state/boot-count
echo "[6/6] done - TV is stock again (launcher files stay in $D, inert while DISABLE exists)"
if [ "$1" = "--no-reboot" ]; then echo "(--no-reboot: not rebooting)"; exit 0; fi
echo "rebooting in 3 s..."; sleep 3
luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 || reboot
