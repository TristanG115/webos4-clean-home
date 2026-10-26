#!/bin/sh
# common.sh - sourced by the other tv-debloat scripts. Runs ON the TV (BusyBox ash).
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/tv-debloat
STATE=$D/state
MARK="# tv-debloat"
LOGF=$STATE/tv-debloat.log
mkdir -p "$STATE" 2>/dev/null
up() { cut -d' ' -f1 /proc/uptime; }
log() {
  echo "$(up) $(basename "$0")[$$]: $*" >> "$LOGF" 2>/dev/null
  [ "$(wc -c < "$LOGF" 2>/dev/null || echo 0)" -gt 200000 ] && tail -c 100000 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
  return 0
}
# luna-send needs stdin closed; -w bounds the wait so nothing can hang a boot script
lun() { luna-send -n 1 -w "${LW:-6000}" "$@" </dev/null 2>/dev/null; }
is_mounted() { grep -q " $1 " /proc/mounts; }
HOME_ID=com.webos.app.fullhome
HOME_EXE=/usr/bin/com.webos.app.fullhome
api_start() {
  [ -s "$STATE/token" ] || head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$STATE/token"
  pgrep -f "tcpsvd.* 8765 " >/dev/null || ( setsid tcpsvd -c 6 0.0.0.0 8765 timeout -t 120 sh "$D/api.sh" </dev/null >/dev/null 2>&1 & )
}
api_ok() { curl -s -m 3 -o /dev/null http://127.0.0.1:8765/api/ping; }
