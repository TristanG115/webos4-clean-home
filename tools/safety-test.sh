#!/bin/sh
# safety-test.sh - runs ON the TV. Proves the recovery paths work (each test restores the launcher at the end):
#   A. launcher page missing -> home-on gives LG's Home back within ~35 s
#   B. crash-loop guard: boot-count 3 + boot.sh -> DISABLE created, nothing applied
#   C. API watchdog: kill the API, it comes back by itself
D=/media/developer/tv-debloat
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
lun() { luna-send -n 1 -w 6000 "$@" </dev/null 2>/dev/null; }
EXE=/usr/bin/com.webos.app.fullhome
home_state() { grep -q " $EXE " /proc/mounts && echo "launcher mounted" || echo "LG Home (no mount)"; }

echo "=== A. launcher fails to start -> automatic fallback to LG Home"
sh $D/home-off.sh temp >/dev/null 2>&1; sleep 2
mv $D/launcher/index.html $D/launcher/index.html.bak
T0=$(cut -d' ' -f1 /proc/uptime)
sh $D/home-on.sh
T1=$(cut -d' ' -f1 /proc/uptime)
echo "home-on returned after $(awk -v a=$T0 -v b=$T1 'BEGIN{printf "%d", b-a}') s; state: $(home_state)"
sleep 3
fg=$(lun luna://com.webos.applicationManager/running '{}' | grep -c '"id":"com.webos.app.fullhome","webprocessid":""')
echo "LG native Home process running again (native entry in SAM list): $fg"
mv $D/launcher/index.html.bak $D/launcher/index.html
[ -f $D/launcher/index.html ] && echo "launcher page restored on disk"
admanager_stub=$(grep -c " /usr/sbin/admanager " /proc/mounts); echo "admanager stub mounted while LG Home active: $admanager_stub (expect 0: LG Home needs it)"

echo "=== B. crash-loop guard"
sh $D/home-off.sh temp >/dev/null 2>&1
echo 3 > $D/state/boot-count; rm -f $D/DISABLE
sh $D/boot.sh
[ -e $D/DISABLE ] && echo "PASS: boot.sh created DISABLE after 4th unfinished boot" || echo "FAIL: no DISABLE"
echo "state after: $(home_state); hosts-block lines: $(grep -c '# tv-debloat' /etc/hosts)"
rm -f $D/DISABLE; echo 0 > $D/state/boot-count

echo "=== restore full state"
sh $D/debloat.sh apply >/dev/null 2>&1
sh $D/home-on.sh
echo "state: $(home_state)"

echo "=== C. API watchdog self-heal"
for p in $(pgrep -f "tcpsvd.* 8765 "); do kill $p 2>/dev/null; done
sleep 1; curl -s -m 3 http://127.0.0.1:8765/api/ping >/dev/null && echo "API still up?!" || echo "API killed (as intended)"
i=0; while [ $i -lt 14 ]; do sleep 2; i=$((i+1)); curl -s -m 3 http://127.0.0.1:8765/api/ping >/dev/null && { echo "PASS: API back after ~$((i*2)) s"; break; }; done
[ $i -ge 14 ] && echo "FAIL: API did not come back within 28 s"
echo "final: $(home_state); $(sh $D/debloat.sh status 2>&1 | tr '\n' ';')"
