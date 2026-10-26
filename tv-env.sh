#!/bin/sh
# tv-env.sh - sourced by tv.sh, revert.sh, tools/*.sh: where is the TV?  Order: environment (TV_IP=...), then tv.conf next to this file, else a clear error.
#   tv.conf (one line each, no spaces around =):   TV_IP=192.168.1.50     TV_USER=root
# `./install.sh 192.168.1.50` writes it for you. Nothing else in the repo contains an address.
TVROOT=$(cd "$(dirname "$0")" && pwd); [ -f "$TVROOT/tv-env.sh" ] || TVROOT=$(cd "$TVROOT/.." && pwd)
[ -f "$TVROOT/tv.conf" ] && . "$TVROOT/tv.conf"
TV_USER=${TV_USER:-root}
[ -n "$TV_IP" ] || { echo "Which TV? Run ./install.sh <tv-ip>  (or create tv.conf with TV_IP=<tv-ip>, see tv.conf.example)" >&2; exit 2; }
SSHO="-o BatchMode=yes -o ConnectTimeout=25 -o LogLevel=ERROR"
TV_TARGET="$TV_USER@$TV_IP"
