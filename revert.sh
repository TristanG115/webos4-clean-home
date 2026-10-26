#!/bin/sh
# revert.sh [--no-reboot]  (PC wrapper) - runs the TV's own revert script over SSH. This undoes every change and reboots.
# If SSH is unreachable: telnet 10.0.0.63 (no password) and run:  sh /media/developer/tv-debloat/revert.sh
# Last resorts: delete/rename /var/lib/webosbrew/init.d/zz-debloat and reboot; then LG factory reset.
exec ssh -o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR root@10.0.0.63 sh /media/developer/tv-debloat/revert.sh "$@"
