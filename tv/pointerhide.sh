#!/bin/sh
# pointerhide.sh start|stop|status - keeps the Magic Remote pointer hidden (pointerhide.py: sends the "hide pointer" key the moment the remote's driver sends "show").
# Read-only on the remote's devices apart from that one injected key; nothing is grabbed, so stopping it (or it dying) changes nothing else.
# Off switch: state/pointerhide-off (Settings -> Remote & pointer). RAM only; a reboot without the init hook is stock.
. /media/developer/tv-debloat/common.sh
PIDF=/tmp/pointerhide.pid
alive() { [ -f $PIDF ] && kill -0 "$(cat $PIDF 2>/dev/null)" 2>/dev/null; }
case ${1:-start} in
  stop) touch /tmp/pointerhide.stop; [ -f $PIDF ] && kill "$(cat $PIDF)" 2>/dev/null; rm -f $PIDF; log "pointerhide: stopped"; exit 0;;
  status) alive && echo running || echo stopped; exit 0;;
esac
[ -e "$STATE/pointerhide-off" ] && exit 0
[ -e "$D/DISABLE" ] && exit 0
alive && exit 0
command -v python >/dev/null 2>&1 && [ -f "$D/pointerhide.py" ] || { log "pointerhide: python or pointerhide.py missing"; exit 1; }
rm -f /tmp/pointerhide.stop
python "$D/pointerhide.py" </dev/null >/dev/null 2>&1 &
echo $! > $PIDF
log "pointerhide: running (pid $(cat $PIDF))"
