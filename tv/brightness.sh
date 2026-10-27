#!/bin/sh
# brightness.sh apply | set <5-100|off> | status - one backlight brightness on every input, app and picture mode.
# LG keeps picture.backlight separately for every input x picture mode (Home, HDMI 1-4, Netflix, ... each have their own), which is why dimming one screen left the
# others at full power. With a value set (state/brightness) lastapp.sh calls `apply` every time the foreground changes: it reads the dimension that is active now and
# sets the backlight there if it differs. The first time a context is changed its original value is remembered (state/brightness.orig, one "dimension|value" line each),
# `set off` puts every remembered original back. The screensaver's own dim (backlight.sh) works on top of this: it dims from the value found at that moment.
# Safety: values are clamped to 5-100; nothing is touched while the screensaver dim is active (/tmp/saver-on); a reboot keeps LG's values, so `off` and the originals matter.
. /media/developer/tv-debloat/common.sh
F=$STATE/brightness; ORIG=$STATE/brightness.orig
raw() { lun luna://com.webos.settingsservice/getSystemSettings '{"category":"picture","keys":["backlight"]}' | tr -d '\n '; }
setbl() { lun luna://com.webos.settingsservice/setSystemSettings "{\"category\":\"picture\",\"dimension\":$1,\"settings\":{\"backlight\":\"$2\"}}" | grep -q '"returnValue": *true'; }
case ${1:-status} in
  apply) [ -s "$F" ] || exit 0; [ -e /tmp/saver-on ] && exit 0
    t=$(cat "$F"); r=$(raw); cur=$(printf %s "$r" | sed -n 's/.*"backlight":"\([0-9]*\)".*/\1/p'); dim=$(printf %s "$r" | sed -n 's/.*"dimension":\({[^}]*}\).*/\1/p')
    [ -n "$cur" ] && [ -n "$dim" ] || exit 0
    [ "$cur" = "$t" ] && exit 0
    grep -q -F "$dim|" "$ORIG" 2>/dev/null || echo "$dim|$cur" >> "$ORIG"
    setbl "$dim" "$t" && log "brightness: $cur -> $t ($(printf %s "$dim" | sed -n 's/.*"input":"\([^"]*\)".*/\1/p'))";;
  set) case $2 in
      off) rm -f "$F"
           if [ -s "$ORIG" ]; then while IFS='|' read -r dim v; do [ -n "$dim" ] && setbl "$dim" "$v"; done < "$ORIG"; log "brightness: originals restored"; rm -f "$ORIG"; fi;;
      ''|*[!0-9]*) exit 1;;
      *) [ "$2" -ge 5 ] && [ "$2" -le 100 ] || exit 1; echo "$2" > "$F"; sh "$0" apply;;
    esac;;
  status) [ -s "$F" ] && echo "$(cat "$F")" || echo off;;
esac
