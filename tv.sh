#!/bin/sh
# usage: ./tv.sh 'command'   |  ./tv.sh -s < script.sh
SSHO="-o BatchMode=yes -o ConnectTimeout=8 -o LogLevel=ERROR"
if [ "$1" = "-s" ]; then exec ssh $SSHO root@10.0.0.63 sh -s; else exec ssh $SSHO root@10.0.0.63 "$@"; fi
