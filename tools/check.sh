#!/bin/sh
# check.sh - runs ON the TV. Health check after every change: Home shows, an app opens, an HDMI input opens.
# Prints PASS/FAIL lines and a final RESULT. Uses SAM/surface-manager log events (launch -> window visible).
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
LOG=/var/log/messages
lun() { luna-send -n 1 -w 8000 "$@" </dev/null 2>/dev/null; }
fails=0
try() { # id label wait
  id=$1; n0=$(wc -l < $LOG 2>/dev/null || echo 0)
  lun luna://com.webos.applicationManager/launch "{\"id\":\"$id\"}" >/dev/null
  sleep ${3:-8}
  r=$(tail -n +$((n0+1)) $LOG 2>/dev/null | awk -v id="$id" '
    /SAM NL_APP_LAUNCH_BEGIN/ && index($0,"\"app_id\":\""id"\"") && !b { match($0,/\[[0-9.]+\]/); b=substr($0,RSTART+1,RLENGTH-2)+0 }
    /NL_VSC/ && index($0,"\"app_id\":\""id"\"") && /"visible":true/ && b && !v { match($0,/\[[0-9.]+\]/); v=substr($0,RSTART+1,RLENGTH-2)+0 }
    END { if (v && b) printf "%d", (v-b)*1000 }')
  fgid=$(lun luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' | grep -o '"appId":"[^"]*"' | grep -c "\"$id\"")
  if [ -n "$r" ]; then echo "PASS $2 ($id) visible in ${r} ms"
  elif [ "$fgid" -ge 1 ]; then echo "PASS $2 ($id) is foreground (no log event: overlay already visible or log rotated)"
  else echo "FAIL $2 ($id) never became visible"; fails=$((fails+1)); fi
}
HOME_ID=${HOME_ID:-com.webos.app.fullhome}
# LG's own Settings app is redirected to ours by settings-hook.sh; let it through for this test
echo $(( $(cut -d. -f1 /proc/uptime) + 40 )) > /media/developer/tv-debloat/state/lgsettings.allow
try com.palm.app.settings "LG Settings (legacy) opens" 8
rm -f /media/developer/tv-debloat/state/lgsettings.allow
# our Settings overlay (what the remote's Settings key opens)
sh /media/developer/tv-debloat/settings-open.sh open >/dev/null 2>&1
ok=0; i=0; while [ $i -lt 10 ]; do sleep 1; i=$((i+1)); lun luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' | grep -q '"appId":"tv.debloat.settings"' && { ok=1; break; }; done
if [ $ok = 1 ]; then echo "PASS our Settings overlay opens (after ${i} s)"; else echo "FAIL our Settings overlay did not open"; fails=$((fails+1)); fi
sh /media/developer/tv-debloat/settings-open.sh close >/dev/null 2>&1; sleep 2
try "$HOME_ID" "Home shows" 8
try netflix "App (Netflix) opens" 10
try "$HOME_ID" "Home shows again" 8
try com.webos.app.hdmi1 "HDMI 1 opens" 8
try "$HOME_ID" "Home shows after HDMI" 8
lun luna://com.webos.applicationManager/closeByAppId '{"id":"com.palm.app.settings","forceMode":true}' >/dev/null
lun luna://com.webos.applicationManager/closeByAppId '{"id":"netflix","forceMode":true}' >/dev/null
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)  swap_used_mb: $(awk '/^SwapTotal/{t=$2}/^SwapFree/{f=$2}END{print int((t-f)/1024)}' /proc/meminfo)  mem_avail_mb: $(awk '/^MemAvailable/{print int($2/1024)}' /proc/meminfo)"
[ $fails = 0 ] && echo "RESULT: ALL CHECKS PASSED" || echo "RESULT: $fails CHECK(S) FAILED"
