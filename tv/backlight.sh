#!/bin/sh
# backlight.sh dim <level> | hold | restore | sweep | status - lower the TV's REAL backlight while the screensaver runs, and always put it back.
# The screensaver's software dim layer only darkens pixels; an LCD's backlight stays at full power. This sets LG's picture.backlight for the picture
# context that is active when the screensaver starts (Home = input "default") to <level> on LG's 0-100 scale (an absolute value, 5-100, never above the normal one), and remembers the original value AND
# that context (LG keeps backlight per input / picture mode: restoring while another input is in front would otherwise set the wrong one).
# Safety: the original is restored (1) when the screensaver stops (page -> /api/backlight?v=restore), (2) when anything other than Home comes to the front
# (lastapp.sh), (3) at boot (boot.sh), (4) by the sweep when the screensaver has not refreshed /tmp/saver-on for 3 minutes (page crashed, TV powered off),
# (5) by home-off.sh and revert.sh. Persistent original: state/backlight.orig (+ .dim), RAM marker: /tmp/saver-on. A reboot cannot leave the TV dim.
. /media/developer/tv-debloat/common.sh
ORIG=$STATE/backlight.orig; DIMF=$STATE/backlight.dim; ON=/tmp/saver-on
raw() { lun luna://com.webos.settingsservice/getSystemSettings '{"category":"picture","keys":["backlight"]}' | tr -d '\n '; }
get() { raw | sed -n 's/.*"backlight":"\([0-9]*\)".*/\1/p'; }
cur_dim() { raw | sed -n 's/.*"dimension":\({[^}]*}\).*/\1/p'; }
# set_bl <value> [<dimension json>]
set_bl() { if [ -n "$2" ]; then d="\"dimension\":$2,"; else d=""; fi
  lun luna://com.webos.settingsservice/setSystemSettings "{\"category\":\"picture\",$d\"settings\":{\"backlight\":\"$1\"}}" | grep -q '"returnValue": *true'; }
case ${1:-status} in
  dim)  lvl=${2:-15}; case $lvl in ''|*[!0-9]*) exit 1;; esac; [ "$lvl" -ge 5 ] || lvl=5; [ "$lvl" -le 100 ] || lvl=100      # an absolute level on LG's 0-100 scale (never brighter than the normal one, below)
        if [ ! -e "$ORIG" ]; then cur=$(get); [ -n "$cur" ] || exit 1; cur_dim > "$DIMF"; echo "$cur" > "$ORIG"; fi
        o=$(cat "$ORIG"); t=$lvl; [ $t -ge 5 ] || t=5; [ $t -le $o ] || t=$o
        touch "$ON"; { set_bl $t "$(cat "$DIMF" 2>/dev/null)" && log "backlight: $o -> $t"; };;
  hold) [ -e "$ORIG" ] && touch "$ON";;
  restore) if [ -e "$ORIG" ]; then o=$(cat "$ORIG"); if set_bl "$o" "$(cat "$DIMF" 2>/dev/null)"; then rm -f "$ORIG" "$DIMF"; log "backlight: restored to $o"; fi; fi; rm -f "$ON";;
  sweep) [ -e "$ORIG" ] || exit 0
        if [ ! -e "$ON" ] || [ -n "$(find "$ON" -mmin +3 2>/dev/null)" ]; then sh "$0" restore; fi;;
  status) [ -e "$ORIG" ] && echo "dimmed (original $(cat "$ORIG"), now $(get))" || echo "normal ($(get))";;
esac
