#!/bin/sh
# bench.sh <label> [reps]  - runs ON the TV (ssh root@tv sh -s <label> < bench.sh). Read-only except that it
# launches/closes a few apps and returns to Home. Output: key=value lines (see compare in bench-compare.sh).
# Latency = SAM launch-begin -> surface-manager window visible (from /var/log/messages, ms).
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
LABEL=${1:-unlabeled}; REPS=${2:-3}
HOME_ID=${HOME_ID:-com.webos.app.fullhome}
up() { cut -d' ' -f1 /proc/uptime; }
lun() { luna-send -n 1 -w 5000 "$@" </dev/null 2>/dev/null; }
fg() { lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId":"\([^"]*\)".*/\1/p'; }
ms() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%d", (b-a)*1000}'; }
kv() { echo "$LABEL.$1=$2"; }

kv uptime_s "$(up)"
kv loadavg1 "$(cut -d' ' -f1 /proc/loadavg)"
kv procs "$(ls /proc | grep -c '^[0-9]')"
awk -v L="$LABEL" '/^MemTotal/{t=$2}/^MemFree/{f=$2}/^MemAvailable/{a=$2}/^Cached/{c=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}
  END{printf "%s.mem_free_mb=%d\n%s.mem_avail_mb=%d\n%s.cache_mb=%d\n%s.swap_used_mb=%d\n",L,f/1024,L,a/1024,L,c/1024,L,(st-sf)/1024}' /proc/meminfo

# 10 s of vmstat: averages of swap-in/out, interrupts, ctx switches, cpu
vmstat 1 11 | tail -10 | awk -v L="$LABEL" '{si+=$7;so+=$8;in_+=$11;cs+=$12;us+=$13;sy+=$14;id+=$15;wa+=$16;n++}
  END{printf "%s.vm_si_kb_s=%.0f\n%s.vm_so_kb_s=%.0f\n%s.vm_irq_s=%.0f\n%s.vm_ctx_s=%.0f\n%s.cpu_us=%.1f\n%s.cpu_sy=%.1f\n%s.cpu_idle=%.1f\n%s.cpu_wa=%.1f\n",
  L,si/n,L,so/n,L,in_/n,L,cs/n,L,us/n,L,sy/n,L,id/n,L,wa/n}'

# system responsiveness: luna round trip and fork/exec cost (both suffer under swap/CPU pressure)
s=$(up); i=0; while [ $i -lt 20 ]; do lun luna://com.webos.service.systemservice/clock/getTime '{}' >/dev/null; i=$((i+1)); done; e=$(up)
kv luna_rtt_ms "$(awk -v a=$s -v b=$e 'BEGIN{printf "%d",(b-a)*1000/20}')"
s=$(up); i=0; while [ $i -lt 300 ]; do /bin/true; i=$((i+1)); done; e=$(up)
kv fork300_ms "$(ms $s $e)"

# top 6 resident processes (name:MB)
ps -o rss,comm 2>/dev/null | sort -rn | head -6 | awk -v L="$LABEL" '{printf "%s.top%d=%s:%dMB\n",L,NR,$2,$1/1024}'

LOG=/var/log/messages
# launch <id>, wait, then read SAM NL_APP_LAUNCH_BEGIN -> surface-manager NL_VSC visible:true (monotonic stamps) from the log.
launch_ms() {
  id=$1
  lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$id\",\"forceMode\":true}" >/dev/null
  # web apps (our launcher) survive a SAM close inside WAM; kill them there too so the launch is really cold (harmless error for native apps)
  lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$id\"}" >/dev/null; sleep 3
  n0=$(wc -l < $LOG)
  lun luna://com.webos.applicationManager/launch "{\"id\":\"$id\"}" >/dev/null
  sleep 9
  tail -n +$((n0+1)) $LOG | awk -v id="$id" '
    /SAM NL_APP_LAUNCH_BEGIN/ && index($0,"\"app_id\":\""id"\"") && !b { match($0,/\[[0-9.]+\]/); b=substr($0,RSTART+1,RLENGTH-2)+0 }
    /NL_VSC/ && index($0,"\"app_id\":\""id"\"") && /"visible":true/ && b && !v { match($0,/\[[0-9.]+\]/); v=substr($0,RSTART+1,RLENGTH-2)+0 }
    END { if (v && b) printf "%d", (v-b)*1000; else printf "NA" }'
}
for app in com.palm.app.settings youtube.leanback.v4 netflix; do
  r=1; all=""
  while [ $r -le $REPS ]; do
    all="$all $(launch_ms $app)"
    lun luna://com.webos.applicationManager/launch "{\"id\":\"$HOME_ID\"}" >/dev/null; sleep 4
    r=$((r+1))
  done
  lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$app\",\"forceMode\":true}" >/dev/null
  kv "launch_visible_ms_$app" "$all"
done
# Home from another app: Settings in front, then Home
r=1; all=""
while [ $r -le $REPS ]; do
  lun luna://com.webos.applicationManager/launch '{"id":"com.palm.app.settings"}' >/dev/null; sleep 5
  all="$all $(launch_ms $HOME_ID)"
  r=$((r+1))
done
lun luna://com.webos.applicationManager/closeByAppId '{"id":"com.palm.app.settings","forceMode":true}' >/dev/null
kv launch_visible_ms_home "$all"
# ads/telemetry traffic since boot (log counters)
kv admanager_requests_since_boot "$(grep -c 'NL_ADMAN_REQ' $LOG)"
kv admanager_impressions_since_boot "$(grep -c 'NL_ADMAN_IMP' $LOG)"
kv end_swap_used_mb "$(awk '/^SwapTotal/{t=$2}/^SwapFree/{f=$2}END{print int((t-f)/1024)}' /proc/meminfo)"
