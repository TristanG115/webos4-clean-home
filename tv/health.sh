#!/bin/sh
# health.sh [json|print|log] - a fast self-check (no UI, a few file tests and one luna call): is everything this project promises actually in force right now?
#   json   {"ok":true|false,"pass":N,"warn":N,"fail":N,"checks":[{"n":name,"s":ok|warn|fail,"m":text}...]}   (Settings -> About & updates, /api/health)
#   print  one line per check          log   only the checks that are not ok, to state/tv-debloat.log (the 5-minute sweep runs this: problems leave a trace even when nobody looks)
# Honest limits: it proves things are mounted / running / flagged, not that every screen looks right (tools/check.sh opens real screens).
. /media/developer/tv-debloat/common.sh
OUT=/tmp/health.$$; : > $OUT
chk() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> $OUT; }       # name | ok/warn/fail | message
alive() { [ -s "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
[ -e "$D/DISABLE" ] && chk "enabled" fail "the DISABLE flag exists: the project is switched off" || chk "enabled" ok "on"
[ -e "$D/DEBUG" ] && chk "debug port" warn "DEBUG flag exists: the page is inspectable on port 9998" || chk "debug port" ok "closed"
is_mounted "$HOME_EXE" && chk "our Home" ok "mounted over LG's Home" || chk "our Home" fail "LG's own Home is in use"
[ -e "$STATE/launcher.ready" ] && chk "launcher" ok "reported ready" || chk "launcher" fail "never reported ready since the last start"
api_ok && chk "helper service" ok "answering" || chk "helper service" fail "port 8765 does not answer"
sh "$D/settings-hook.sh" status 2>/dev/null | grep -q running && chk "settings key watcher" ok "running" || chk "settings key watcher" warn "not running"
sh "$D/lastapp.sh" status 2>/dev/null | grep -q running && chk "app tracker" ok "running" || chk "app tracker" warn "not running"
sh "$D/backchain.sh" status 2>/dev/null | grep -q running && chk "Back chain" ok "running" || chk "Back chain" warn "not running"
sh "$D/memguard.sh" status 2>/dev/null | grep -q running && chk "memory guard" ok "running" || chk "memory guard" warn "not running"
grep -q "$MARK" /etc/hosts 2>/dev/null && chk "ad blocking" ok "block list in /etc/hosts" || chk "ad blocking" warn "no block list in /etc/hosts"
is_mounted /usr/sbin/admanager && chk "ad service" ok "stubbed" || chk "ad service" warn "LG's ad service is not stubbed"
sh "$D/debloat.sh" status updates 2>/dev/null | grep -q "BLOCKED (4/4)" && chk "firmware updates" ok "blocked 4/4" || chk "firmware updates" fail "not fully blocked: a firmware update could remove root"
if [ -e "$STATE/qspatch-on" ] || is_mounted /usr/lib/qt5/qml/KeyFilters/appLaunch.js; then is_mounted /usr/lib/qt5/qml/KeyFilters/appLaunch.js && chk "compositor patch" ok "active" || chk "compositor patch" warn "was on but is not mounted (reboot-safe: stock keys)"; fi
free=$(df -k /media/developer 2>/dev/null | awk 'NR==2{print int($4/1024)}'); [ -n "$free" ] && { [ "$free" -ge 50 ] && chk "disk space" ok "$free MB free" || chk "disk space" warn "only $free MB free for /media/developer"; }
lvl=$(sed -n 's/^level=//p' /tmp/memguard.stats 2>/dev/null | head -1); case "$lvl" in critical) chk "memory" warn "critical right now";; low) chk "memory" warn "low right now";; *) chk "memory" ok "fine";; esac
netstat -tln 2>/dev/null | grep -q ':22 ' && chk "SSH" ok "listening" || chk "SSH" fail "SSH is not listening: this is the way back in"
netstat -tln 2>/dev/null | grep -q ':23 ' && chk "Telnet" ok "listening" || chk "Telnet" warn "off (fine if you switched it off with an SSH key installed)"
case "${1:-json}" in
  json) awk -F'|' 'BEGIN{p=w=f=0; s=""} {n=$1; st=$2; m=$3; gsub(/"/,"",m); gsub(/"/,"",n); if(st=="ok")p++; else if(st=="warn")w++; else f++; s=s (NR>1?",":"") "{\"n\":\"" n "\",\"s\":\"" st "\",\"m\":\"" m "\"}"} END{printf "{\"ok\":%s,\"pass\":%d,\"warn\":%d,\"fail\":%d,\"checks\":[%s]}", (f==0?"true":"false"), p, w, f, s}' $OUT;;
  print) awk -F'|' '{printf "%-5s %-24s %s\n", toupper($2), $1, $3}' $OUT;;
  log)   awk -F'|' '$2!="ok"{print $2": "$1" - "$3}' $OUT | while read -r l; do log "health: $l"; done;;
esac
rm -f $OUT
