#!/bin/sh
# caps.sh [print|json|write] - what THIS TV can do, found by looking, never assumed: the installer, Settings -> About and the porting guide use it.
# Read-only (writes only state/caps.conf with `write`). Every feature below is decided from facts about the TV, so a TV that lacks something simply reports it as "no" and the
# matching switch stays unavailable instead of failing half way.
#   print   key=value lines (human readable)          json   the same as one JSON object          write   print + save to state/caps.conf (run by install.sh and at boot)
. /media/developer/tv-debloat/common.sh
has() { command -v "$1" >/dev/null 2>&1 && echo yes || echo no; }
yn() { [ "$1" = yes ] && echo yes || echo no; }
facts() {
  echo "webos_release=$(head -1 /etc/starfish-release 2>/dev/null | tr -d '=' | tr ' ' '_')"
  echo "arch=$(uname -m)"
  echo "ram_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)"
  echo "swap_mb=$(awk '/SwapTotal/{printf "%d", $2/1024}' /proc/meminfo)"
  echo "root=$([ "$(id -u)" = 0 ] && echo yes || echo no)"
  echo "init=$(command -v initctl >/dev/null 2>&1 && echo upstart || { command -v systemctl >/dev/null 2>&1 && echo systemd || echo unknown; })"
  echo "homebrew_hook=$([ -d /var/lib/webosbrew/init.d ] && echo yes || echo no)"
  py=$(command -v python 2>/dev/null || command -v python3 2>/dev/null); echo "python=$([ -n "$py" ] && $py -V 2>&1 | tr ' ' '_' || echo none)"
  echo "input_event_bytes=$([ -n "$py" ] && $py -c "import struct;print(struct.calcsize('llHHi'))" 2>/dev/null || echo unknown)"
  for t in tcpsvd usleep timeout curl tar gzip awk sed od mount pgrep luna-send; do echo "tool_$(echo $t | tr '-' '_')=$(has $t)"; done
  echo "luna_sam=$(lun luna://com.webos.applicationManager/running '{}' | grep -q returnValue && echo yes || echo no)"
  echo "wam_launchapp=$(lun luna://com.palm.webappmanager/listRunningApps '{}' | grep -q returnValue && echo yes || echo no)"
  echo "home_app_id=$(lun luna://com.webos.settingsservice/getSystemSettings '{"category":"general","keys":["defaultApps"]}' | tr -d '\n ' | sed -n 's/.*"home":"\([^"]*\)".*/\1/p')"
  echo "home_exe=$(ls /usr/bin 2>/dev/null | grep -E '^com\.webos\.app\.(full)?home$' | tr '\n' ',' | sed 's/,$//')"
  echo "keyfilters=$([ -f /usr/lib/qt5/qml/KeyFilters/appLaunch.js ] && echo yes || echo no)"
  echo "pointer_pictures=$([ -d /usr/share/im ] && echo yes || echo no)"
  echo "input_devices=$(grep -c '^H: Handlers=.*event' /proc/bus/input/devices 2>/dev/null)"
  echo "internet=$(curl -s -m 4 -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/ 2>/dev/null | grep -q '^[234]' && echo yes || echo no)"
}
# which features of this project the TV supports, from the facts above (a missing fact turns the feature off, never on)
features() {
  f=$(facts); g() { echo "$f" | sed -n "s/^$1=//p" | head -1; }
  echo "feature_launcher=$( [ "$(g root)" = yes ] && [ "$(g homebrew_hook)" = yes ] && [ "$(g luna_sam)" = yes ] && [ "$(g wam_launchapp)" = yes ] && [ -n "$(g home_exe)" ] && [ "$(g tool_tcpsvd)" = yes ] && echo yes || echo no)"
  echo "feature_boot_hook=$( [ "$(g homebrew_hook)" = yes ] && [ "$(g init)" = upstart ] && echo yes || echo no)"
  echo "feature_service_stops=$( [ "$(g init)" = upstart ] && echo yes || echo 'no (systemd port needed)')"
  echo "feature_hosts_block=$( [ "$(g root)" = yes ] && echo yes || echo no)"
  echo "feature_settings_key_patch=$(g keyfilters)"
  echo "feature_invisible_pointer=$( [ "$(g pointer_pictures)" = yes ] && [ "$(g python)" != none ] && echo yes || echo no)"
  echo "feature_remote_emulator=$( [ "$(g python)" != none ] && [ "$(g input_devices)" -gt 0 ] 2>/dev/null && echo yes || echo no)"
  echo "feature_self_update=$( [ "$(g tool_curl)" = yes ] && [ "$(g tool_tar)" = yes ] && [ "$(g internet)" = yes ] && echo yes || echo no)"
  echo "feature_memory_guard=yes"
}
case ${1:-print} in
  print) facts; features;;
  json)  { facts; features; } | awk -F= 'BEGIN{printf "{"} {gsub(/"/,"",$2); printf "%s\"%s\":\"%s\"", (NR>1?",":""), $1, $2} END{printf "}"}';;
  write) { facts; features; } | tee "$STATE/caps.conf";;
esac
