#!/bin/sh
# cursorclear.sh on|off|status - makes the Magic Remote pointer invisible, whatever the remote or the compositor does.
# The compositor draws the arrow from the pictures in /usr/share/im (cursorType*.png). We build a copy of that folder in RAM where every pointer picture is
# transparent (cursorclear.py) and bind-mount it over the original, so a "shown" pointer is drawn as nothing. Nothing is grabbed or intercepted: the remote, its keys, the
# wheel and clicks work exactly as before; the real folder (read-only squashfs) is never touched. Undo = umount (off), a reboot without the init hook is stock.
# The compositor may have cached the pictures: "on" reports whether a restart of surface-manager is needed for it to take effect (qspatch.sh restarts it anyway).
# Off switch: state/cursorclear-off (Settings -> Remote & pointer).
. /media/developer/tv-debloat/common.sh
IM=/usr/share/im
TMPD=/tmp/im-clear
CACHE=$STATE/im-clear-cache          # the finished pictures, kept on flash (about 100 KB): later boots mount this folder directly (no 15 s rebuild, no RAM copy)
# signature of what the pictures were built from: the original folder's names and sizes + the generator script
sig() { { ls -l "$IM" | awk '{print $5, $NF}'; md5sum "$D/cursorclear.py" 2>/dev/null | cut -d' ' -f1; } | md5sum | cut -d' ' -f1; }
mounted() { is_mounted "$IM"; }
do_off() {
  if mounted; then umount "$IM" 2>/dev/null || umount -l "$IM" 2>/dev/null; fi
  rm -rf "$TMPD"      # the flash cache stays: switching it on again is instant
  mounted && { log "cursorclear: could not unmount $IM"; return 1; }
  log "cursorclear: off (LG's pointer pictures are back)"; return 0
}
case ${1:-on} in
  off) do_off; exit $?;;
  status) mounted && echo "on ($(ls $IM 2>/dev/null | wc -l) files)" || echo off; exit 0;;
esac
[ -e "$STATE/cursorclear-off" ] && exit 0
[ -e "$D/DISABLE" ] && exit 0
mounted && exit 0
command -v python >/dev/null 2>&1 && [ -f "$D/cursorclear.py" ] || { log "cursorclear: python or cursorclear.py missing"; exit 1; }
[ -d "$IM" ] || { log "cursorclear: $IM not found (other webOS version?), skipped"; exit 1; }
# a valid cache is mounted as it is (instant, and it costs no RAM)
if [ -s "$CACHE/.sig" ] && [ "$(cat "$CACHE/.sig")" = "$(sig)" ] && [ "$(ls "$CACHE" | wc -l)" = "$(ls "$IM" | wc -l)" ] && mount --bind "$CACHE" "$IM"; then
  log "cursorclear: on (from the flash cache, $(ls "$CACHE" | wc -l) files, mounted over $IM)"; echo "on (cached)"; exit 0
fi
rm -rf "$TMPD"
r=$(python "$D/cursorclear.py" "$IM" "$TMPD" 2>&1) || { log "cursorclear: build failed: $r"; rm -rf "$TMPD"; exit 1; }
# sanity: same number of files as the original, otherwise do not mount (a half copy would break LG's other pictures)
a=$(ls "$IM" | wc -l); b=$(ls "$TMPD" | wc -l)
[ "$a" = "$b" ] && [ "$b" -gt 0 ] || { log "cursorclear: file count differs ($a vs $b), not mounted"; rm -rf "$TMPD"; exit 1; }
chmod -R go-w "$TMPD"
# keep the result on flash for the next boots (one write per firmware), then mount the RAM copy this time
( rm -rf "$CACHE.new" && cp -r "$TMPD" "$CACHE.new" && chmod -R go-w "$CACHE.new" && sig > "$CACHE.new/.sig" && rm -rf "$CACHE" && mv "$CACHE.new" "$CACHE" ) 2>/dev/null || rm -rf "$CACHE.new"
mount --bind "$TMPD" "$IM" || { log "cursorclear: mount failed"; rm -rf "$TMPD"; exit 1; }
log "cursorclear: on ($r, mounted over $IM)"
echo "on ($r)"
