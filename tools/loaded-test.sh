#!/bin/sh
# loaded-test.sh - runs ON the TV:  ./tv.sh -s < tools/loaded-test.sh > results/<label>.txt
# A repeatable "TV in real use" state: opens YouTube, Netflix and HDMI 2 (so all three stay resident), goes Home and measures how heavy the TV feels:
# memory, swap traffic, and the Settings-key latency (tools/settings-latency.sh). Opens apps on screen: run it when nobody is watching. Ends on Home.
D=/media/developer/tv-debloat; export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
L() { luna-send -n 1 -w 8000 luna://com.webos.applicationManager/launch "{\"id\":\"$1\"}" </dev/null >/dev/null 2>&1; }
vm() { awk '/^pswpin/{i=$2}/^pswpout/{o=$2}END{print i, o}' /proc/vmstat; }
for a in youtube.leanback.v4 netflix com.webos.app.hdmi2 com.webos.app.fullhome; do L $a; sleep 9; done
set -- $(vm); i0=$1; o0=$2
awk '/^MemFree/{f=$2}/^MemAvailable/{a=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}END{printf "loaded.mem_free_mb=%d\nloaded.mem_avail_mb=%d\nloaded.swap_used_mb=%d\n",f/1024,a/1024,(st-sf)/1024}' /proc/meminfo
echo "loaded.swappiness=$(cat /proc/sys/vm/swappiness)"
[ -f /tmp/sl.sh ] && sh /tmp/sl.sh 5
set -- $(vm); echo "loaded.swap_pages_in_during=$(( $1 - i0 )) out=$(( $2 - o0 ))"
for a in youtube.leanback.v4 netflix com.webos.app.hdmi2; do luna-send -n 1 luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$a\",\"forceMode\":true}" </dev/null >/dev/null 2>&1; done
L com.webos.app.fullhome
