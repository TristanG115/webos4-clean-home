#!/bin/sh
# settings-latency.sh [reps] - runs ON the TV:  ./tv.sh -s 5 < tools/settings-latency.sh
# How long from the Settings key to our overlay being visible. The key is simulated the way keys-test.sh does it (the lginput2 log line is appended to
# /var/log/messages), the end is the compositor's own "tv.debloat.settings visible:true" line. Both sides use the log clock, so the numbers are what
# the remote would give minus lginput2's own logging delay. Opens and closes the overlay on screen; run it when nobody is watching.
D=/media/developer/tv-debloat; LOG=/var/log/messages; export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
REPS=${1:-5}
now() { cut -d' ' -f1 /proc/uptime; }
vis_at() { grep 'NL_VSC' $LOG 2>/dev/null | grep '"app_id":"tv.debloat.settings"' | grep '"visible":true' | tail -1 | sed -n 's/.*\[\([0-9][0-9.]*\)\].*/\1/p'; }
sh $D/settings-open.sh close >/dev/null 2>&1; sleep 3; rm -f /tmp/gear-claim
all=""; r=1
while [ $r -le $REPS ]; do
  before=$(vis_at); t0=$(now)
  echo '2026-01-01T00:00:00.000000Z [1.1] user.info lginput2 [] lginput2 NL_BUTTON_CLICK {"remote_type":"LGE MR19","button_type":"KEY_SETTINGS"}' >> $LOG
  i=0; while [ $i -lt 120 ]; do v=$(vis_at); [ -n "$v" ] && [ "$v" != "$before" ] && break; usleep 100000; i=$((i+1)); done
  if [ -n "$v" ] && [ "$v" != "$before" ]; then ms=$(awk -v a=$t0 -v b=$v 'BEGIN{printf "%d",(b-a)*1000}'); else ms=NA; fi
  lo=$(grep 'settings overlay opened' $D/state/tv-debloat.log | tail -1 | cut -d' ' -f1)
  hk=$(awk -v a=$t0 -v b=$lo 'BEGIN{printf "%d",(b-a)*1000}')
  all="$all $ms(launch_returned_at=${hk})"
  sleep 3; sh $D/settings-open.sh close >/dev/null 2>&1; sleep 3
  r=$((r+1))
done
echo "settings_key_to_visible_ms:$all"
