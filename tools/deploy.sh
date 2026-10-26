#!/bin/sh
# deploy.sh - copy tv/ (scripts + launcher/ incl. launcher/photos) to /media/developer/tv-debloat on the TV. Safe to re-run.
# Does not start or change anything on the TV by itself except writing files under that one folder.
# Ownership is forced to root and group/world write removed: these scripts run as root at boot (and /media/developer is world-writable).
cd "$(dirname "$0")/.." || exit 1
SSHO="-o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR"
sed -i 's/\r$//' tv/*.sh tv/zz-debloat 2>/dev/null
tar cf - -C tv . | ssh $SSHO root@10.0.0.63 'mkdir -p /media/developer/tv-debloat && rm -rf /media/developer/tv-debloat/launcher/photos; tar xf - -C /media/developer/tv-debloat 2>/dev/null; cd /media/developer/tv-debloat && chown -R root:root . ; chmod -R go-w . ; chmod 755 *.sh zz-debloat launcher launcher/photos launcher/photos/thumbs 2>/dev/null; echo "deployed; world-writable items: $(find . -perm -002 | wc -l)"'
