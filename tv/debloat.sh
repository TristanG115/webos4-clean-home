#!/bin/sh
# debloat.sh apply|undo|status|state|sweep [item ...]
#   items: hosts remotelogger nudge contentminer admanager lgsettings voice iot preload idleapps epg updates   (catalog: services.tsv)
#   apply   with no items = every item that is switched ON in state/svc.conf (defaults from services.tsv)
#   state   machine-readable "id active" lines (used by the Settings screen)
#   sweep   re-apply whatever LG may have started again (cheap and idempotent; run at boot for 5 minutes and every few minutes after)
# Every change is RAM-only (initctl stop, bind-mounted stubs, the tmpfs /etc/hosts, the preload manager's runtime policy) except
# `lgsettings`/`updates`, which flip LG's own switches through LG's settings service (originals saved by undo / left as found).
. /media/developer/tv-debloat/common.sh
ACTION=${1:-status}; [ $# -gt 0 ] && shift
ALL="hosts remotelogger nudge contentminer admanager lgsettings voice iot preload idleapps epg updates"
CONF=$STATE/svc.conf; CATALOG=$D/services.tsv

# --- which items are switched on ---------------------------------------------------------------------------------------
want() { # id -> on|off
  [ "$1" = updates ] && { echo on; return; }                       # locked: never off
  v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | tail -1)
  [ -z "$v" ] && v=$(awk -F'|' -v id="$1" '$1==id{print $3}' "$CATALOG" 2>/dev/null)
  echo "${v:-off}"
}
wanted() { for i in $ALL; do [ "$(want $i)" = on ] && echo $i; done; }
if [ -n "$*" ]; then ITEMS=$*; elif [ "$ACTION" = apply ] || [ "$ACTION" = sweep ]; then ITEMS=$(wanted | tr '\n' ' '); else ITEMS=$ALL; fi

svc_running() { initctl status "$1" 2>/dev/null | grep -q "start/running"; }
LGSET() { lun luna://com.webos.settingsservice/setSystemSettings "$1" >/dev/null; }

# --- hosts (ad & tracker block lists live in blocklist.sh) ----------------------------------------------------------------
do_hosts() {
  case $ACTION in
    apply) sh "$D/blocklist.sh" apply >/dev/null; echo "hosts: $(grep -c "$MARK\$" /etc/hosts) ad/tracker names blocked";;
    sweep) grep -q "$MARK" /etc/hosts || { sh "$D/blocklist.sh" apply >/dev/null; echo "hosts: re-applied"; };;
    undo)  sh "$D/blocklist.sh" remove >/dev/null; echo "hosts: restored";;
    status) grep -q "$MARK" /etc/hosts && echo "hosts: BLOCKING" || echo "hosts: off";;
  esac
}
# --- Upstart jobs --------------------------------------------------------------------------------------------------------
do_upstart() { # $1 = job
  j=$1
  case $ACTION in
    apply|sweep) if svc_running $j; then touch "$STATE/stopped-$j"; initctl stop $j >/dev/null 2>&1; fi
           [ $ACTION = apply ] && { svc_running $j && echo "$j: still running" || echo "$j: stopped"; };;
    undo)  if [ -e "$STATE/stopped-$j" ] || ! svc_running $j; then initctl start $j >/dev/null 2>&1; rm -f "$STATE/stopped-$j"; fi
           svc_running $j && echo "$j: running" || echo "$j: not running (starts on its own trigger)";;
    status) svc_running $j && echo "$j: running" || echo "$j: STOPPED";;
  esac
}
# --- do-nothing stub over an on-demand luna service binary -----------------------------------------------------------------
stub_bin() { # action name
  B=/usr/sbin/$2
  [ -e "$B" ] || { [ "$1" = status ] && echo "$2: not present"; return; }
  case $1 in
    apply|sweep) printf '#!/bin/sh\nexit 0\n' > "$D/stub-noop"; chmod 755 "$D/stub-noop"
           is_mounted $B || mount --bind "$D/stub-noop" $B
           for p in $(pgrep -f "^$B"); do kill "$p" 2>/dev/null; done; sleep 1; for p in $(pgrep -f "^$B"); do kill -9 "$p" 2>/dev/null; done
           [ "$1" = apply ] && echo "$2: stubbed";;
    undo)  for m in $(awk -v b="$B" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; done; echo "$2: restored";;
    status) is_mounted $B && echo "$2: STUBBED" || { pgrep -f "^$B" >/dev/null && echo "$2: running" || echo "$2: idle"; };;
  esac
}
kill_webapp() { # appId  (a web app kept alive by WAM; it is relaunched on demand)
  lun luna://com.webos.applicationManager/closeByAppId "{\"id\":\"$1\",\"forceMode\":true}" >/dev/null
  lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$1\"}" >/dev/null
}
app_running() { lun luna://com.webos.applicationManager/running '{}' | grep -q "\"id\": *\"$1\""; }

do_admanager() {
  case $ACTION in
    apply|sweep) stub_bin apply admanager;;
    undo)  stub_bin undo admanager; echo "admanager: real binary restored (starts on demand)";;
    status) stub_bin status admanager;;
  esac
}
do_lgsettings() {
  SETTINGS_ON='{"category":"general","settings":{"homePromotion":"off","aiNudge":"off","adCookie":"off","customizedAd":"off","screenSaverAd":"off","lmt":"on","personalRecommend":{"changedByUser":true,"value":"off"}}}'
  SETTINGS_ORIG='{"category":"general","settings":{"homePromotion":"on","aiNudge":"on","adCookie":"on","personalRecommend":{"changedByUser":false,"value":"on"}}}'
  case $ACTION in
    apply) [ -e "$STATE/lgsettings.applied" ] || { LGSET "$SETTINGS_ON" && touch "$STATE/lgsettings.applied"; }
           echo "lgsettings: promotions, nudges, ad cookie, personalised recs off";;
    sweep) [ -e "$STATE/lgsettings.applied" ] || { LGSET "$SETTINGS_ON" && touch "$STATE/lgsettings.applied"; };;
    undo)  LGSET "$SETTINGS_ORIG"; rm -f "$STATE/lgsettings.applied"; echo "lgsettings: LG defaults restored";;
    status) [ -e "$STATE/lgsettings.applied" ] && echo "lgsettings: APPLIED" || echo "lgsettings: stock";;
  esac
}
# voice: remote mic button / voice search (type with the on-screen keyboard instead; MaliitServer stays).
do_voice() {
  case $ACTION in
    apply|sweep) do_upstart voiceinput; do_upstart voiceconductor; stub_bin $ACTION nlpmanager; [ $ACTION = apply ] && echo "voice: off";;
    undo)  stub_bin undo nlpmanager; do_upstart voiceinput; do_upstart voiceconductor; echo "voice: back";;
    status) do_upstart voiceinput; do_upstart voiceconductor; stub_bin status nlpmanager;;
  esac
}
# iot: LG ThinQ / smart-home pairing and HomeKit (NOT the second-screen gateway: Homebrew Channel needs that one)
do_iot() {
  case $ACTION in
    apply|sweep) for n in iot-client ocf-onboarding homekit; do stub_bin $ACTION $n; done
           for p in $(pgrep -f "ocf_memcheck.sh"); do kill "$p" 2>/dev/null; done; [ $ACTION = apply ] && echo "iot: off";;
    undo)  for n in iot-client ocf-onboarding homekit; do stub_bin undo $n; done; echo "iot: back";;
    status) for n in iot-client ocf-onboarding homekit; do stub_bin status $n; done;;
  esac
}
# preload: LG's preload manager keeps apps half-open in RAM. Its runtime policy is switched per app (no file is touched);
# the original enabled/disabled flags are saved the first time and restored by undo.
PRELOAD_OFF="com.webos.app.googleassistant com.webos.app.browser com.webos.app.tips vudu amazon pooq"
PL=com.webos.service.preloadmanager
preload_dump() { lun luna://$PL/getPreloadPolicy '{}' | python -c "
import sys,json
try:
    for a in json.load(sys.stdin)['applications']: print '%s=%d' % (a['id'], 1 if a.get('isEnabled') else 0)
except Exception: pass"; }
preload_set() { lun luna://$PL/setPreloadPolicy "{\"application\":{\"id\":\"$1\",\"isEnabled\":$2}}" >/dev/null; }
do_preload() {
  case $ACTION in
    apply|sweep) cur=$(preload_dump); [ -z "$cur" ] && { echo "preload: manager not answering"; return; }
           [ -s "$STATE/preload.orig" ] || echo "$cur" > "$STATE/preload.orig"
           for id in $PRELOAD_OFF; do echo "$cur" | grep -q "^$id=1" && preload_set $id false; done
           [ $ACTION = apply ] && echo "preload: only Home, favorites and inputs stay pre-loaded";;
    undo)  if [ -s "$STATE/preload.orig" ]; then for id in $PRELOAD_OFF; do grep -q "^$id=1" "$STATE/preload.orig" && preload_set $id true; done; rm -f "$STATE/preload.orig"; fi
           echo "preload: LG's pre-loading restored";;
    status) n=0; for id in $PRELOAD_OFF; do preload_dump | grep -q "^$id=1" && n=$((n+1)); done; [ $n = 0 ] && echo "preload: TRIMMED" || echo "preload: $n heavy app(s) still pre-loaded";;
  esac
}
# idleapps: apps LG keeps resident that nobody uses (Tips, Assistant, Browser). With `preload` on they stay closed; they start if opened.
do_idleapps() {
  case $ACTION in
    apply|sweep) for a in com.webos.app.tips com.webos.app.googleassistant com.webos.app.browser; do app_running $a && kill_webapp $a; done
           [ $ACTION = apply ] && echo "idleapps: Tips/Assistant/Browser closed";;
    undo)  echo "idleapps: nothing to undo (apps start on demand)";;
    status) n=0; for a in com.webos.app.tips com.webos.app.googleassistant com.webos.app.browser; do app_running $a && n=$((n+1)); done; [ $n = 0 ] && echo "idleapps: CLOSED" || echo "idleapps: $n resident";;
  esac
}
# epg: program-guide downloader for antenna/cable TV (off by default: only for people who never use Live TV)
do_epg() {
  case $ACTION in
    apply|sweep) do_upstart iepg; do_upstart broadcast-conf-downloader;;
    undo)  do_upstart iepg; do_upstart broadcast-conf-downloader;;
    status) do_upstart iepg; do_upstart broadcast-conf-downloader;;
  esac
}
# updates: LG firmware/app updates must never run (an update can remove root and bring LG's software back).
# Four layers: LG's own switches, the update servers in the hosts file (Homebrew blocks four of them already; we add the rest),
# the `update` service itself, and the sweep re-checks all of it. Locked ON: there is no way to turn it off from the UI.
UPD_HOSTS="snu.lge.com snu-dev.lge.com su.lge.com su-dev.lge.com su-ssl.lge.com nsu.lge.com"
UPD_MARK="# tvd-update"
upd_hosts_present() { grep -q "$UPD_MARK" /etc/hosts; }
upd_hosts_apply() { upd_hosts_present && return 0; { echo "127.0.0.1 $UPD_HOSTS $UPD_MARK"; echo "::1 $UPD_HOSTS $UPD_MARK"; } >> /etc/hosts; }
upd_settings_ok() { lun luna://com.webos.settingsservice/getSystemSettings '{"category":"support","keys":["automaticUpdate"]}' | grep -q '"automaticUpdate": *"off"' &&
                    lun luna://com.webos.settingsservice/getSystemSettings '{"category":"option","keys":["appUpdateMode"]}' | grep -q '"appUpdateMode": *"manual"'; }
upd_settings_apply() { upd_settings_ok || { LGSET '{"category":"support","settings":{"automaticUpdate":"off"}}'; LGSET '{"category":"option","settings":{"appUpdateMode":"manual"}}'; }; }
do_updates() {
  case $ACTION in
    apply|sweep) upd_settings_apply; upd_hosts_apply
           if svc_running update; then touch "$STATE/stopped-update"; initctl stop update >/dev/null 2>&1; fi
           [ $ACTION = apply ] && echo "updates: blocked (settings, hosts, update service)";;
    undo)  # only the revert path calls this; the Homebrew block lines stay either way
           grep -v "$UPD_MARK" /etc/hosts > /tmp/hosts.new && cat /tmp/hosts.new > /etc/hosts; rm -f /tmp/hosts.new
           if [ -e "$STATE/stopped-update" ] || ! svc_running update; then initctl start update >/dev/null 2>&1; rm -f "$STATE/stopped-update"; fi
           echo "updates: our extra blocks removed (automatic updates stay off in LG's settings; Homebrew's own server block stays)";;
    status) n=0; upd_hosts_present && n=$((n+1)); svc_running update || n=$((n+1)); upd_settings_ok && n=$((n+1)); [ $n = 3 ] && echo "updates: BLOCKED (3/3)" || echo "updates: partly blocked ($n/3)";;
  esac
}

# --- machine-readable state for the UI: "id 1|0" (1 = the tweak is currently in effect) ------------------------------------
active_of() {
  case $1 in
    hosts) grep -q "$MARK" /etc/hosts && echo 1 || echo 0;;
    remotelogger|nudge|contentminer) svc_running $1 && echo 0 || echo 1;;
    admanager) is_mounted /usr/sbin/admanager && echo 1 || echo 0;;
    lgsettings) [ -e "$STATE/lgsettings.applied" ] && echo 1 || echo 0;;
    voice) svc_running voiceinput && echo 0 || echo 1;;
    iot) is_mounted /usr/sbin/iot-client && echo 1 || echo 0;;
    preload) [ -s "$STATE/preload.orig" ] && echo 1 || echo 0;;
    idleapps) [ "$(want idleapps)" = on ] && echo 1 || echo 0;;
    epg) svc_running iepg && echo 0 || echo 1;;
    updates) upd_hosts_present && ! svc_running update && echo 1 || echo 0;;
  esac
}
if [ "$ACTION" = state ]; then for i in $ALL; do echo "$i $(active_of $i)"; done; exit 0; fi

for i in $ITEMS; do
  case $i in
    hosts) do_hosts;;
    remotelogger|nudge|contentminer) do_upstart $i;;
    admanager) do_admanager;;
    lgsettings) do_lgsettings;;
    voice) do_voice;;
    iot) do_iot;;
    preload) do_preload;;
    idleapps) do_idleapps;;
    epg) do_epg;;
    updates) do_updates;;
    *) echo "unknown item: $i";;
  esac
done
[ "$ACTION" = sweep ] || log "$ACTION $ITEMS"
