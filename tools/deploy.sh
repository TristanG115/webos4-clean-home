#!/bin/sh
# deploy.sh [--no-photos] - copy tv/ (scripts + launcher/ incl. launcher/photos + blocklists/) to /media/developer/tv-debloat on the TV. Safe to re-run.
# Does not start or change anything on the TV by itself except writing files under that one folder. State (settings, crops, block lists, logs)
# lives in state/ and is never overwritten (the automatic framing from tools/prep-photos.js is copied to state/crops/ only for photos you have not re-framed since). Photos are only ADDED/overwritten, never deleted (photos you uploaded from the phone stay).
# Ownership is forced to root and group/world write removed: these scripts run as root at boot (and /media/developer is world-writable).
cd "$(dirname "$0")/.." || exit 1
SSHO="-o BatchMode=yes -o ConnectTimeout=25 -o LogLevel=ERROR"
sed -i 's/\r$//' tv/*.sh tv/zz-debloat tv/*.tsv tv/blocklists/* 2>/dev/null
EXCL=""; [ "$1" = "--no-photos" ] && EXCL="--exclude=./launcher/photos"
tar cf - $EXCL -C tv . | ssh $SSHO root@10.0.0.63 'mkdir -p /media/developer/tv-debloat && tar xf - -C /media/developer/tv-debloat 2>/dev/null; cd /media/developer/tv-debloat && chown -R root:root . ; chmod -R go-w . ; chmod 755 *.sh zz-debloat launcher launcher/photos launcher/photos/thumbs blocklists 2>/dev/null; mkdir -p state/crops; for f in launcher/photos/crops/*.json; do [ -f "$f" ] || continue; b=${f##*/}; p=launcher/photos/${b%.json}.jpg; d=state/crops/$b; if [ ! -e "$d" ] || [ "$p" -nt "$d" ]; then cp "$f" "$d"; fi; done; rm -rf launcher/photos/crops; echo "deployed; world-writable items: $(find . -perm -002 | wc -l)"'
