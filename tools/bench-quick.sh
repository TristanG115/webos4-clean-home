#!/bin/sh
# bench-quick.sh <label> [reps] - runs ON the TV:  ./tv.sh -s <label> 3 < tools/bench-quick.sh > results/<label>.txt
# A shorter version of bench.sh (about 3 minutes): memory snapshot, then cold launch latency of Home (killed in WAM first),
# YouTube and Netflix (SAM launch-begin -> window visible, from /var/log/messages). Opens and closes those apps on screen; ends on Home.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
LABEL=${1:-quick}; REPS=${2:-3}
HOME_ID=${HOME_ID:-com.webos.app.fullhome}; LOG=/var/log/messages
lun() { luna-send -n 1 -w 5000 "$@" </dev/null 2>/dev/null; }
kv() { echo "$LABEL.$1=$2"; }
awk -v L="$LABEL" '/^MemFree/{f=$2}/^MemAvailable/{a=$2}/^Cached/{c=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}
  END{printf "%s.mem_free_mb=%d\n%s.mem_avail_mb=%d\n%s.cache_mb=%d\n%s.swap_used_mb=%d\n",L,f/1024,L,a/1024,L,c/1024,L,(st-sf)/1024}' /proc/meminfo
kv procs "$(ls /proc | grep -c '^[0-9]')"
launch_ms() {
  id=$1
  lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$id\",\"forceMode\":true}" >/dev/null
  lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$id\"}" >/dev/null; sleep 3
  t0=$(cut -d. -f1 /proc/uptime)
  lun luna://com.webos.applicationManager/launch "{\"id\":\"$id\"}" >/dev/null
  sleep 9
  cat $LOG.* $LOG 2>/dev/null | awk -v id="$id" -v t0="$t0" '
    /SAM NL_APP_LAUNCH_BEGIN/ && index($0,"\"app_id\":\""id"\"") && !b { match($0,/\[[0-9.]+\]/); x=substr($0,RSTART+1,RLENGTH-2)+0; if (x >= t0) b=x }
    /NL_VSC/ && index($0,"\"app_id\":\""id"\"") && /"visible":true/ && b && !v { match($0,/\[[0-9.]+\]/); y=substr($0,RSTART+1,RLENGTH-2)+0; if (y >= b) v=y }
    END { if (v && b) printf "%d", (v-b)*1000; else printf "NA" }'
}
for app in youtube.leanback.v4 netflix; do
  r=1; all=""
  while [ $r -le $REPS ]; do
    all="$all $(launch_ms $app)"
    lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}" >/dev/null; sleep 4
    r=$((r+1))
  done
  lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$app\",\"forceMode\":true}" >/dev/null
  kv "launch_visible_ms_$app" "$all"
done
r=1; all=""
while [ $r -le $REPS ]; do
  lun luna://com.webos.applicationManager/launch '{"id":"netflix"}' >/dev/null; sleep 5
  all="$all $(launch_ms $HOME_ID)"
  r=$((r+1))
done
lun luna://com.webos.applicationManager/closeByAppId '{"id":"netflix","forceMode":true}' >/dev/null
kv launch_visible_ms_home "$all"
kv end_swap_used_mb "$(awk '/^SwapTotal/{t=$2}/^SwapFree/{f=$2}END{print int((t-f)/1024)}' /proc/meminfo)"
