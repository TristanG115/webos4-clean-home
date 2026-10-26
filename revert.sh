#!/bin/sh
# revert.sh [--no-reboot]  (PC wrapper) - runs the TV's own revert script over SSH. This undoes every change and reboots.
# If SSH is unreachable: telnet <tv-ip> (no password) and run:  sh /media/developer/tv-debloat/revert.sh
# Last resorts: delete/rename /var/lib/webosbrew/init.d/zz-debloat and reboot; then LG factory reset.
. "$(dirname "$0")/tv-env.sh"
exec ssh -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR "$TV_TARGET" sh /media/developer/tv-debloat/revert.sh "$@"
