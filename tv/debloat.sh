#!/bin/sh
# debloat.sh apply|undo|status [item ...]   items: hosts remotelogger nudge contentminer admanager lgsettings voice iot idleapps
# Every change is RAM-only (initctl stop, bind mounts over /tmp copies, /etc/hosts tmpfs) except `lgsettings`,
# which flips LG's own toggles through LG's settings service (originals saved to state/ and restored by undo).
. /media/developer/tv-debloat/common.sh
ACTION=${1:-status}; [ $# -gt 0 ] && shift
ITEMS=${*:-hosts remotelogger nudge contentminer admanager lgsettings voice iot idleapps}

# Confirmed on this TV: us.* resolve (44.235.112.128), "info.lgsmartad.com" is embedded in /usr/sbin/admanager,
# media.bidr.io serves the cached ad creatives in /mnt/lg/cmn_data/admanager/cache, nl.*/eic.* come from the
# cleanyourtv-WebOS port's list and resolve.
AD_HOSTS="us.ad.lgsmartad.com us.info.lgsmartad.com nl.ad.lgsmartad.com nl.info.lgsmartad.com eic.ads.lgtvcommon.com media.bidr.io"
SETTINGS_ON='{"category":"general","settings":{"homePromotion":"off","aiNudge":"off","adCookie":"off","personalRecommend":{"changedByUser":true,"value":"off"}}}'
SETTINGS_ORIG='{"category":"general","settings":{"homePromotion":"on","aiNudge":"on","adCookie":"on","personalRecommend":{"changedByUser":false,"value":"on"}}}'

svc_running() { initctl status "$1" 2>/dev/null | grep -q "start/running"; }

do_hosts() {
  case $ACTION in
    apply) grep -q "$MARK" /etc/hosts || {
             echo "127.0.0.1 $AD_HOSTS $MARK" >> /etc/hosts
             echo "::1 $AD_HOSTS $MARK" >> /etc/hosts; }
           echo "hosts: ad servers blocked";;
    undo)  if grep -q "$MARK" /etc/hosts; then grep -v "$MARK" /etc/hosts > /tmp/hosts.new && cat /tmp/hosts.new > /etc/hosts; rm -f /tmp/hosts.new; fi
           echo "hosts: restored";;
    status) grep -q "$MARK" /etc/hosts && echo "hosts: BLOCKING" || echo "hosts: off";;
  esac
}
do_upstart() { # $1 = job
  j=$1
  case $ACTION in
    apply) if svc_running $j; then touch "$STATE/stopped-$j"; initctl stop $j >/dev/null 2>&1; fi
           svc_running $j && echo "$j: still running" || echo "$j: stopped";;
    undo)  if [ -e "$STATE/stopped-$j" ] || ! svc_running $j; then initctl start $j >/dev/null 2>&1; rm -f "$STATE/stopped-$j"; fi
           svc_running $j && echo "$j: running" || echo "$j: not running (starts on its own trigger)";;
    status) svc_running $j && echo "$j: running" || echo "$j: STOPPED";;
  esac
}
do_admanager() {
  B=/usr/sbin/admanager
  case $ACTION in
    apply) printf '#!/bin/sh\nexit 0\n' > "$D/stub-noop"; chmod 755 "$D/stub-noop"
           is_mounted $B || mount --bind "$D/stub-noop" $B
           for p in $(pgrep -f "^$B"); do kill "$p" 2>/dev/null; done
           echo "admanager: stubbed";;
    undo)  for m in $(awk -v b="$B" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null; done
           echo "admanager: real binary restored (starts on demand)";;
    status) is_mounted $B && echo "admanager: STUBBED" || { pgrep -f "^$B" >/dev/null && echo "admanager: running" || echo "admanager: idle (on-demand)"; };;
  esac
}
do_lgsettings() {
  case $ACTION in
    apply) [ -e "$STATE/lgsettings.applied" ] || { lun luna://com.webos.settingsservice/setSystemSettings "$SETTINGS_ON" >/dev/null && touch "$STATE/lgsettings.applied"; }
           echo "lgsettings: promotions, nudges, ad cookie, personalised recs off";;
    undo)  lun luna://com.webos.settingsservice/setSystemSettings "$SETTINGS_ORIG" >/dev/null; rm -f "$STATE/lgsettings.applied"
           echo "lgsettings: LG defaults restored";;
    status) [ -e "$STATE/lgsettings.applied" ] && echo "lgsettings: APPLIED" || echo "lgsettings: stock";;
  esac
}

# Generic on-demand luna service: bind a do-nothing stub over /usr/sbin/<name> and kill the running copy.
stub_bin() { # action name
  B=/usr/sbin/$2
  [ -e "$B" ] || { echo "$2: not present"; return; }
  case $1 in
    apply) printf '#!/bin/sh\nexit 0\n' > "$D/stub-noop"; chmod 755 "$D/stub-noop"
           is_mounted $B || mount --bind "$D/stub-noop" $B
           for p in $(pgrep -f "^$B"); do kill "$p" 2>/dev/null; done; sleep 1; for p in $(pgrep -f "^$B"); do kill -9 "$p" 2>/dev/null; done; echo "$2: stubbed";;
    undo)  for m in $(awk -v b="$B" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; done; echo "$2: restored";;
    status) is_mounted $B && echo "$2: STUBBED" || { pgrep -f "^$B" >/dev/null && echo "$2: running" || echo "$2: idle"; };;
  esac
}
kill_webapp() { # appId  (a web app kept alive by WAM; it is relaunched on demand)
  lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$1\",\"forceMode\":true}" >/dev/null
  lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$1\"}" >/dev/null
}
# voice: remote mic button / voice search (type with the on-screen keyboard instead; MaliitServer stays).
# The Google Assistant web app is NOT killed: LG's preload manager would just relaunch it every ~20 s.
do_voice() {
  case $ACTION in
    apply) do_upstart voiceinput; do_upstart voiceconductor; stub_bin apply nlpmanager; echo "voice: off";;
    undo)  stub_bin undo nlpmanager; do_upstart voiceinput; do_upstart voiceconductor; echo "voice: back";;
    status) do_upstart voiceinput; do_upstart voiceconductor; stub_bin status nlpmanager;;
  esac
}
# iot: LG ThinQ / smart-home pairing and HomeKit
do_iot() {
  case $ACTION in
    apply) for n in iot-client ocf-onboarding homekit; do stub_bin apply $n; done
           for p in $(pgrep -f "ocf_memcheck.sh"); do kill "$p" 2>/dev/null; done; echo "iot: off";;
    undo)  for n in iot-client ocf-onboarding homekit; do stub_bin undo $n; done; echo "iot: back";;
    status) for n in iot-client ocf-onboarding homekit; do stub_bin status $n; done;;
  esac
}
# idleapps: apps LG keeps resident that nobody uses (Tips). They start again if opened.
do_idleapps() {
  case $ACTION in
    apply) kill_webapp com.webos.app.tips; echo "idleapps: Tips closed";;
    undo)  echo "idleapps: nothing to undo (apps start on demand)";;
    status) echo "idleapps: Tips closed on apply";;
  esac
}

for i in $ITEMS; do
  case $i in
    hosts) do_hosts;;
    remotelogger|nudge|contentminer) do_upstart $i;;
    admanager) do_admanager;;
    lgsettings) do_lgsettings;;
    voice) do_voice;;
    iot) do_iot;;
    idleapps) do_idleapps;;
    *) echo "unknown item: $i";;
  esac
done
log "$ACTION $ITEMS"
