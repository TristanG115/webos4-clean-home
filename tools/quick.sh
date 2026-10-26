#!/bin/sh
# quick.sh <label> - runs ON the TV: 10 s snapshot of memory/swap/interrupts/cpu + responsiveness. No apps are launched.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
L=${1:-x}; up() { cut -d' ' -f1 /proc/uptime; }
awk -v L="$L" '/^MemFree/{f=$2}/^MemAvailable/{a=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}END{printf "%s mem_free=%dMB avail=%dMB swap_used=%dMB\n",L,f/1024,a/1024,(st-sf)/1024}' /proc/meminfo
vmstat 1 11 | tail -10 | awk -v L="$L" '{si+=$7;so+=$8;i+=$11;c+=$12;id+=$15;n++}END{printf "%s swap_in=%.0fKB/s swap_out=%.0fKB/s irq=%.0f/s ctx=%.0f/s idle=%.1f%%\n",L,si/n,so/n,i/n,c/n,id/n}'
s=$(up); i=0; while [ $i -lt 300 ]; do /bin/true; i=$((i+1)); done; e=$(up); echo "$L fork300=$(awk -v a=$s -v b=$e 'BEGIN{printf "%d",(b-a)*1000}')ms"
s=$(up); i=0; while [ $i -lt 20 ]; do luna-send -n 1 -w 5000 luna://com.webos.service.systemservice/clock/getTime '{}' </dev/null >/dev/null 2>&1; i=$((i+1)); done; e=$(up); echo "$L luna_rtt=$(awk -v a=$s -v b=$e 'BEGIN{printf "%d",(b-a)*1000/20}')ms procs=$(ls /proc | grep -c '^[0-9]')"
