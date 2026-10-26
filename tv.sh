#!/bin/sh
# usage: ./tv.sh 'command'   |  ./tv.sh -s < script.sh      (the TV comes from tv.conf, see tv-env.sh)
. "$(dirname "$0")/tv-env.sh"
if [ "$1" = "-s" ]; then exec ssh $SSHO "$TV_TARGET" sh -s; else exec ssh $SSHO "$TV_TARGET" "$@"; fi
