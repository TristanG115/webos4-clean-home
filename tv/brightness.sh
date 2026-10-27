#!/bin/sh
# brightness.sh apply | handle <msg> | seed | set <5-100|off> | status - one backlight brightness on every input, app and picture mode, set BEFORE the picture shows.
# LG keeps picture.backlight separately for every input x picture mode x 3D state (Home, HDMI 1-4, Netflix, HDR modes, ... each have their own), which is why dimming one screen
# left the others at full power. With a value set (state/brightness) two things keep every context at it:
#   seed     writes the value into EVERY valid context ahead of time (16 inputs x 28 picture modes; only rows that differ are written), so switching to any input, app or
#            picture mode never shows a different brightness, not even for a frame. Runs in the background after `set` and after a boot where the seeded value differs.
#   handle   safety net for anything the seed missed: lastapp.sh subscribes to LG's settings service, which pushes a message the instant the active context changes
#            (measured: 0.1 s after the window shows; the old way, a foreground event + sleep 1 + two luna calls, left the wrong brightness on screen for about 1 s).
#            Messages caused by our own tools (caller "lunasend") are ignored, so a value you set by hand sticks until the next context switch.
# The first time a context is changed its original value is remembered (state/brightness.orig, one "dimension|value" line each), `set off` puts every remembered original back.
# The screensaver's own dim (backlight.sh) works on top of this: it dims from the value found at that moment, and nothing is touched while it is active (/tmp/saver-on).
# Safety: values are clamped to 5-100; a reboot keeps LG's values, so `off` and the originals matter.
. /media/developer/tv-debloat/common.sh
F=$STATE/brightness; ORIG=$STATE/brightness.orig; SEEDED=$STATE/brightness.seeded; LOCK=/tmp/bl-seed.lock
INPUTS="default hdmi1 hdmi2 hdmi3 hdmi4 hdmi1_pc hdmi2_pc hdmi3_pc hdmi4_pc av1 av2 comp1 dtv atv camera"
MODES="normal vivid cinema eco sports game photo expert1 expert2 technicolor hdrStandard hdrVivid hdrCinema hdrCinemaBright hdrGame hdrEffect hdrTechnicolor dolbyHdrStandard dolbyHdrVivid dolbyHdrCinema dolbyHdrCinemaBright dolbyHdrGame technicolorHdrStandard technicolorHdrVivid technicolorHdrCinema technicolorHdrCinemaBright technicolorHdrGame technicolorHdrTechnicolor"
raw() { lun luna://com.webos.settingsservice/getSystemSettings '{"category":"picture","keys":["backlight"]}' | tr -d '\n '; }
setbl() { lun luna://com.webos.settingsservice/setSystemSettings "{\"category\":\"picture\",\"dimension\":$1,\"settings\":{\"backlight\":\"$2\"}}" | grep -q '"returnValue": *true'; }
getbl() { lun luna://com.webos.settingsservice/getSystemSettings "{\"category\":\"picture\",\"keys\":[\"backlight\"],\"dimension\":$1}" | tr -d '\n ' | sed -n 's/.*"backlight":"\([0-9]*\)".*"returnValue":true.*/\1/p'; }
# fix <dimension json> <current value>: remember the original once, then set the target
fix() { grep -q -F "$1|" "$ORIG" 2>/dev/null || echo "$1|$2" >> "$ORIG"; setbl "$1" "$t"; }
# the dimension of the context a message / reply is about, in the order LG prints it (the same text keys brightness.orig)
dim_of() { i=$(printf %s "$1" | sed -n 's/.*"input":"\([^"]*\)".*/\1/p'); m=$(printf %s "$1" | sed -n 's/.*"pictureMode":"\([^"]*\)".*/\1/p'); d3=$(printf %s "$1" | sed -n 's/.*"_3dStatus":"\([^"]*\)".*/\1/p')
  [ -n "$i" ] && [ -n "$m" ] && [ -n "$d3" ] && printf '{"pictureMode":"%s","input":"%s","_3dStatus":"%s"}' "$m" "$i" "$d3"; }
case ${1:-status} in
  apply) [ -s "$F" ] || exit 0; [ -e /tmp/saver-on ] && exit 0
    t=$(cat "$F"); r=$(raw); cur=$(printf %s "$r" | sed -n 's/.*"backlight":"\([0-9]*\)".*/\1/p'); dim=$(printf %s "$r" | sed -n 's/.*"dimension":\({[^}]*}\).*/\1/p')
    [ -n "$cur" ] && [ -n "$dim" ] || exit 0
    [ "$cur" = "$t" ] && exit 0
    fix "$dim" "$cur" && log "brightness: $cur -> $t ($(printf %s "$dim" | sed -n 's/.*"input":"\([^"]*\)".*/\1/p'))";;
  handle) # one message from the settings subscription (lastapp.sh): {"dimension":{...},"settings":{"backlight":"NN"},...}
    [ -s "$F" ] || exit 0; [ -e /tmp/saver-on ] && exit 0
    case "$2" in *lunasend*) exit 0;; esac
    t=$(cat "$F"); cur=$(printf %s "$2" | sed -n 's/.*"backlight":"\([0-9]*\)".*/\1/p'); [ -n "$cur" ] && [ "$cur" != "$t" ] || exit 0
    dim=$(dim_of "$2"); [ -n "$dim" ] || exit 0
    fix "$dim" "$cur" && log "brightness: $cur -> $t (context switch: $(printf %s "$dim" | sed -n 's/.*"input":"\([^"]*\)".*/\1/p') $(printf %s "$dim" | sed -n 's/.*"pictureMode":"\([^"]*\)".*/\1/p'))";;
  seed) [ -s "$F" ] || exit 0; mkdir "$LOCK" 2>/dev/null || exit 0; trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    t=$(cat "$F"); n=0; s0=$(cut -d. -f1 /proc/uptime)
    for i in $INPUTS; do for m in $MODES; do
      # switched off: stop. Changed meanwhile (the slider was moved again): hand over to a fresh seed of the new value (a call made while this one runs found the lock taken and gave up)
      if [ ! -s "$F" ]; then exit 0; fi
      if [ "$(cat "$F")" != "$t" ]; then rmdir "$LOCK" 2>/dev/null; trap - EXIT; exec sh "$0" seed; fi
      d="{\"pictureMode\":\"$m\",\"input\":\"$i\",\"_3dStatus\":\"2d\"}"
      [ -e /tmp/saver-on ] && [ "$d" = "$(cat "$STATE/backlight.dim" 2>/dev/null)" ] && continue      # the context the screensaver is dimming right now
      v=$(getbl "$d"); [ -n "$v" ] && [ "$v" != "$t" ] || continue
      fix "$d" "$v" && n=$((n+1))
    done; done
    echo "$t" > "$SEEDED"; log "brightness: seeded $t in every context ($n changed, $(( $(cut -d. -f1 /proc/uptime) - s0 )) s)";;
  set) case $2 in
      off) rm -f "$F" "$SEEDED"
           if [ -s "$ORIG" ]; then while IFS='|' read -r dim v; do [ -n "$dim" ] && setbl "$dim" "$v"; done < "$ORIG"; log "brightness: originals restored"; rm -f "$ORIG"; fi;;
      ''|*[!0-9]*) exit 1;;
      *) [ "$2" -ge 5 ] && [ "$2" -le 100 ] || exit 1; echo "$2" > "$F"; sh "$0" apply; ( setsid nice sh "$0" seed </dev/null >/dev/null 2>&1 & );;
    esac;;
  due) [ -s "$F" ] && [ "$(cat "$SEEDED" 2>/dev/null)" != "$(cat "$F")" ] && echo yes || echo no;;
  status) [ -s "$F" ] && echo "$(cat "$F")" || echo off;;
esac
