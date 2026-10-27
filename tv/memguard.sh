#!/bin/sh
# memguard.sh start|stop|status|json|profile|conf [key value] - watches memory and steps in before the TV starts to thrash.
# One cheap sample every 10 s (two awk reads of /proc, no luna calls, nothing written to flash: history lives in /tmp). Thresholds are PERCENTAGES of the TV's
# RAM, so the same script protects a 1 GB set and a weaker one; the profile (auto: from MemTotal) only picks the percentages and how eager the actions are.
#   level ok        nothing to do
#   level low       free memory under the profile's "low" mark, or the kernel is swapping in steadily: close apps beyond the newest one (lastapp.sh evict 1)
#   level critical  free memory under the "critical" mark, swap nearly full, or heavy swap-in: also tell the Home page to drop its photos (FIFO command "lowmem")
#                   and drop the clean page cache. Leaving a level needs 3 calm samples in a row (no flapping); "normal" is sent when it is over.
# Profile weak (under 800 MB total, or chosen by hand): the Home page runs without background photos and the screensaver without photos all the time.
# Never kills LG services, never touches the app in front. Switch: Settings -> Services & privacy -> "Watch memory" (debloat item memguard).
#   json     for Settings -> About & updates and tools/memreport.sh: now, lowest free and highest swap since start, episodes, last action, last hour of samples
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/memguard.pid; HIST=/tmp/memguard.hist; STATS=/tmp/memguard.stats; CONFF=$STATE/memguard.conf; FIFO=/tmp/tvd-ui.fifo
conf_get() { v=$(sed -n "s/^$1=//p" "$CONFF" 2>/dev/null | head -1); echo "${v:-$2}"; }
conf_set() { { grep -v "^$1=" "$CONFF" 2>/dev/null; echo "$1=$2"; } > "$CONFF.tmp" && mv "$CONFF.tmp" "$CONFF"; }
total_mb() { awk '/^MemTotal/{printf "%d", $2/1024}' /proc/meminfo; }
profile() { p=$(conf_get profile auto); case $p in roomy|standard|weak) echo $p; return;; esac
  t=$(total_mb); if [ "$t" -ge 1400 ]; then echo roomy; elif [ "$t" -ge 800 ]; then echo standard; else echo weak; fi; }
# percentages of total RAM: low, critical; swap-in pages/s for low, critical; swap used % for critical
marks() { case $1 in roomy) echo "10 5 400 2000 92";; weak) echo "22 12 200 1000 85";; *) echo "15 8 300 1500 90";; esac; }
sample() { awk '/^MemTotal/{t=$2}/^MemAvailable/{a=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}END{printf "%d %d %d %d ",t,a,st,sf}' /proc/meminfo; awk '/^pswpin /{print $2}' /proc/vmstat; }
tell_page() { [ -p $FIFO ] && timeout -t 1 sh -c "echo $1 > $FIFO" </dev/null >/dev/null 2>&1; }
stat_get() { sed -n "s/^$1=//p" "$STATS" 2>/dev/null | head -1; }
stat_set() { { grep -v "^$1=" "$STATS" 2>/dev/null; echo "$1=$2"; } > "$STATS.tmp" && mv "$STATS.tmp" "$STATS"; }

loop() {
  : > "$HIST"; rm -f "$STATS"; stat_set level ok; stat_set low_n 0; stat_set crit_n 0
  prof=$(profile); set -- $(marks $prof); LOWP=$1; CRITP=$2; LOWS=$3; CRITS=$4; CRITSW=$5
  log "memguard: watching ($prof profile: low under $LOWP %, critical under $CRITP % free, $(total_mb) MB)"
  [ "$prof" != weak ] && tell_page normal          # a profile change must undo an earlier "lowmem"
  level=ok; calm=0; hot=0; prev_in=""; prev_t=""; tick=0; minav=999999999; maxsw=0
  while :; do
    set -- $(sample); tot=$1; av=$2; st=$3; sf=$4; pin=$5; now=$(cut -d. -f1 /proc/uptime)
    [ -n "$tot" ] && [ "$tot" -gt 0 ] || { sleep 10; continue; }
    sw=$(( (st - sf) / 1024 )); avmb=$((av / 1024)); pps=0
    if [ -n "$prev_in" ] && [ "$now" -gt "$prev_t" ]; then pps=$(( (pin - prev_in) / (now - prev_t) )); fi
    prev_in=$pin; prev_t=$now
    [ "$av" -lt "$minav" ] && { minav=$av; stat_set min_avail_mb $avmb; }
    [ "$sw" -gt "$maxsw" ] && { maxsw=$sw; stat_set max_swap_mb $sw; }
    pct=$(( av * 100 / tot )); swpct=0; [ "$st" -gt 0 ] && swpct=$(( (st - sf) * 100 / st ))
    # what the numbers say right now
    want=ok
    if [ "$pct" -lt "$LOWP" ]; then want=low; fi
    if [ "$pps" -gt "$LOWS" ]; then hot=$((hot+1)); [ $hot -ge 2 ] && want=low; else hot=0; fi
    if [ "$pct" -lt "$CRITP" ] || [ "$swpct" -ge "$CRITSW" ] || { [ "$pps" -gt "$CRITS" ] && [ $hot -ge 2 ]; }; then want=critical; fi
    rank() { case $1 in critical) echo 2;; low) echo 1;; *) echo 0;; esac; }
    if [ "$(rank $want)" -gt "$(rank $level)" ]; then
      level=$want; calm=0; stat_set level $level; stat_set last_up $now
      if [ $level = critical ]; then stat_set crit_n $(( $(stat_get crit_n) + 1 )); else stat_set low_n $(( $(stat_get low_n) + 1 )); fi
      log "memguard: $level ($avmb MB free = $pct %, swap $sw MB, swap-in $pps pages/s)"
      stat_set last_action "$level: closed idle apps$([ $level = critical ] && echo ', Home photos dropped, page cache dropped')"
      ( sh "$D/lastapp.sh" evict 1 ) </dev/null >/dev/null 2>&1 &
      [ $level = critical ] && { tell_page lowmem; echo 1 > /proc/sys/vm/drop_caches 2>/dev/null; }
    elif [ "$(rank $want)" -lt "$(rank $level)" ]; then
      calm=$((calm+1))
      if [ $calm -ge 3 ]; then level=$want; calm=0; stat_set level $level; log "memguard: back to $level ($avmb MB free)"; [ $level = ok ] && [ "$prof" != weak ] && tell_page normal; fi
    else
      calm=0
      # still critical: keep asking (a page that was restarting missed the first message) and keep the cache small, at most every 2 minutes
      if [ $level = critical ] && [ $((tick % 12)) = 0 ]; then tell_page lowmem; echo 1 > /proc/sys/vm/drop_caches 2>/dev/null; fi
    fi
    [ "$prof" = weak ] && [ $((tick % 6)) = 0 ] && tell_page lowmem          # weak TV: Home never holds photos (the page also forgets after a restart)
    # one history point a minute, last 3 hours, in RAM only
    if [ $((tick % 6)) = 0 ]; then echo "$now $avmb $sw $pps $level" >> "$HIST"; [ "$(wc -l < "$HIST")" -gt 180 ] && tail -n 120 "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"; fi
    tick=$((tick+1)); sleep 10
  done
}

case ${1:-status} in
  start)  [ -e "$D/DISABLE" ] && exit 0
          [ -s $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null && exit 0
          ( setsid sh "$0" run </dev/null >/dev/null 2>&1 & ); exit 0;;
  run)    echo $$ > $PIDF; loop;;
  stop)   [ -s $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF; log "memguard: stopped"; echo stopped;;
  status) [ -s $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null && echo "running ($(profile) profile, level $(stat_get level))" || echo "stopped";;
  profile) profile;;
  conf)   if [ -n "$2" ]; then case $2:$3 in profile:auto|profile:roomy|profile:standard|profile:weak) conf_set profile "$3"; [ -s $PIDF ] && { sh "$0" stop >/dev/null; sh "$0" start; };; esac; fi
          echo "profile=$(conf_get profile auto) effective=$(profile)";;
  json)   set -- $(sample); tot=$1; av=$2; st=$3; sf=$4
          printf '{"running":%s,"profile":"%s","setting":"%s","totalMB":%d,"availMB":%d,"swapUsedMB":%d,"swapTotalMB":%d,"level":"%s","minAvailMB":%s,"maxSwapMB":%s,"lowEpisodes":%s,"criticalEpisodes":%s,"lastAction":"%s","samples":[' \
            "$([ -s $PIDF ] && kill -0 "$(cat $PIDF)" 2>/dev/null && echo true || echo false)" "$(profile)" "$(conf_get profile auto)" $((tot/1024)) $((av/1024)) $(( (st-sf)/1024 )) $((st/1024)) "$(stat_get level)" "$(stat_get min_avail_mb | sed 's/^$/null/')" "$(stat_get max_swap_mb | sed 's/^$/null/')" "$(stat_get low_n | sed 's/^$/0/')" "$(stat_get crit_n | sed 's/^$/0/')" "$(stat_get last_action | tr -d '"\\')"
          tail -n 60 "$HIST" 2>/dev/null | awk '{printf "%s[%s,%s,%s]", (NR>1?",":""), $1, $2, $3}'; echo ']}';;
esac
