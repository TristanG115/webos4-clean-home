#!/bin/sh
# debloat.sh apply|undo|status|state|sweep [item ...]
#   items: hosts remotelogger nudge contentminer admanager lgsettings voice iot preload idleapps epg updates cursorclear qspatch vmtune   (catalog: services.tsv)
#   apply   with no items = every item that is switched ON in state/svc.conf (defaults from services.tsv)
#   state   machine-readable "id active" lines (used by the Settings screen)
#   sweep   re-apply whatever LG may have started again (cheap and idempotent; run at boot for 5 minutes and every few minutes after)
# Every change is RAM-only (initctl stop, bind-mounted stubs, the tmpfs /etc/hosts, the preload manager's runtime policy) except
# `lgsettings`/`updates`, which flip LG's own switches through LG's settings service (originals saved by undo / left as found).
. /media/developer/tv-debloat/common.sh
ACTION=${1:-status}; [ $# -gt 0 ] && shift
# boot in two phases (boot.sh): apply-early = only what must be in place BEFORE our Home starts (the pointer pictures and the compositor patch: the patch restarts the compositor),
# apply-late = everything else, after Home is up. Both honour the switches exactly like apply.
PHASE=""; case $ACTION in apply-early) PHASE=early; ACTION=apply;; apply-late) PHASE=late; ACTION=apply;; esac
# revert.sh (and the crash-loop guard) create DISABLE: nothing may be switched on again behind their back (the boot sweep and the Home watchdog run `sweep` for minutes)
case $ACTION in apply|apply-early|apply-late|sweep) [ -e "$D/DISABLE" ] && { echo "DISABLE flag present: not applying"; exit 0; };; esac
ALL="hosts remotelogger nudge contentminer admanager lgsettings voice iot preload idleapps epg updates cursorclear qspatch vmtune lgmenus memguard bootcover"
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

if [ -n "$PHASE" ]; then
  ITEMS=$(for i in $ITEMS; do
    case $i in cursorclear|qspatch) [ "$PHASE" = early ] && echo $i;; *) [ "$PHASE" = late ] && echo $i;; esac
  done | tr '\n' ' ')
fi

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
# --- services (Upstart jobs on webOS 4, systemd units on webOS 5+: init.sh) --------------------------------------------------------------------------------------------------------
do_upstart() { # $1 = job (its Upstart name; init.sh maps it to the systemd unit)
  j=$1
  svc_known $j || { [ $ACTION = status ] && echo "$j: not present on this TV"; return 0; }       # a service this TV does not have is skipped, never an error
  case $ACTION in
    apply|sweep) if svc_running $j; then touch "$STATE/stopped-$j"; svc_stop $j; fi
           [ $ACTION = apply ] && { svc_running $j && echo "$j: still running" || echo "$j: stopped"; };;
    undo)  if [ -e "$STATE/stopped-$j" ] || ! svc_running $j; then svc_start $j; rm -f "$STATE/stopped-$j"; fi
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
PRELOAD_OFF="com.webos.app.googleassistant com.webos.app.browser com.webos.app.tips vudu amazon pooq com.webos.app.home"   # com.webos.app.home = LG's other (unused) Home: nothing to pre-load
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
# updates: LG SYSTEM (firmware) updates must never run (an update can remove root and bring LG's software back).
# Five layers: LG's own switch (support.automaticUpdate=off), the update servers in the hosts file (Homebrew blocks four of them already; we add the rest),
# the Upstart job `update` stopped, the program /usr/sbin/update replaced by a do-nothing stub (so nothing can start it again), and the sweep re-checks all of it.
# Locked ON: there is no way to turn it off from the UI, and the API refuses the LG keys. APP updates are the opposite and wanted: see appupdate.sh.
UPD_HOSTS="snu.lge.com snu-dev.lge.com su.lge.com su-dev.lge.com su-ssl.lge.com nsu.lge.com"
UPD_MARK="# tvd-update"
upd_hosts_present() { grep -q "$UPD_MARK" /etc/hosts; }
upd_hosts_apply() { upd_hosts_present && return 0; { echo "127.0.0.1 $UPD_HOSTS $UPD_MARK"; echo "::1 $UPD_HOSTS $UPD_MARK"; } >> /etc/hosts; }
upd_settings_ok() { lun luna://com.webos.settingsservice/getSystemSettings '{"category":"support","keys":["automaticUpdate"]}' | grep -q '"automaticUpdate": *"off"'; }
upd_settings_apply() { upd_settings_ok || LGSET '{"category":"support","settings":{"automaticUpdate":"off"}}'; sh "$D/appupdate.sh" apply; }      # app updates: auto unless the owner chose manual
upd_stub_ok() { is_mounted /usr/sbin/update; }
# qspatch: LG's quick-settings panel and the scroll-wheel pointer key, switched off inside the compositor (see qspatch.sh: it restarts the compositor, with automatic rollback)
do_qspatch() {
  case $ACTION in
    apply) sh "$D/qspatch.sh" boot;;
    sweep) :;;
    undo)  is_mounted /usr/lib/qt5/qml/KeyFilters/appLaunch.js && sh "$D/qspatch.sh" undo || echo "qspatch: not active";;
    status) echo "qspatch: $(sh "$D/qspatch.sh" status)";;
  esac
}
# cursorclear: the Magic Remote pointer is drawn from LG's pictures in /usr/share/im; a RAM copy with transparent pictures is bind-mounted over that folder (see cursorclear.sh). Applied BEFORE qspatch so the
# compositor restart that qspatch does at boot already loads the transparent pictures; switching it on later needs a compositor restart (or reboot) before the compositor loads them.
do_cursorclear() {
  case $ACTION in
    apply) echo "cursorclear: $(sh "$D/cursorclear.sh" on)";;
    sweep) is_mounted /usr/share/im || sh "$D/cursorclear.sh" on >/dev/null;;
    undo)  sh "$D/cursorclear.sh" off; echo "cursorclear: off";;
    status) echo "cursorclear: $(sh "$D/cursorclear.sh" status)";;
  esac
}
# bootcover: our own "starting up" screen over LG's Home while the TV boots (cover.sh); only a flag, read by cover.sh at boot
do_bootcover() {
  case $ACTION in
    apply|sweep) rm -f "$STATE/cover-off"; [ $ACTION = apply ] && echo "bootcover: on";;
    undo)  touch "$STATE/cover-off"; echo "bootcover: off";;
    status) [ -e "$STATE/cover-off" ] && echo "bootcover: off" || echo "bootcover: on";;
  esac
}
# memguard: watches free memory / swap-in and steps in before the TV thrashes (memguard.sh); a long-running loop, restarted by the sweep if it ever dies
do_memguard() {
  case $ACTION in
    apply|sweep) sh "$D/memguard.sh" start; [ $ACTION = apply ] && echo "memguard: watching";;
    undo)  sh "$D/memguard.sh" stop;;
    status) echo "memguard: $(sh "$D/memguard.sh" status)";;
  esac
}
# lgmenus: LG's hidden or leftover menus that the remote can still open (the mic key = voice assistant overlay, three presses of Mute = the hidden service / local-key menu,
# the Input Hub key = Home Connect). lastapp.sh closes them the moment SAM announces their launch (splash event, about 0.05 s after) while this flag exists.
do_lgmenus() {
  case $ACTION in
    apply|sweep) touch "$STATE/lgmenus.on"; [ $ACTION = apply ] && echo "lgmenus: guard on";;
    undo)  rm -f "$STATE/lgmenus.on"; echo "lgmenus: guard off";;
    status) [ -e "$STATE/lgmenus.on" ] && echo "lgmenus: guarding" || echo "lgmenus: off";;
  esac
}
# vmtune: the kernel swaps into LG's swap device (dm-linear: 600 MB of zram = compressed RAM first, then a small encrypted eMMC partition) with vm.swappiness=100 (it prefers swapping program memory over dropping cache). 20 keeps the
# running apps in RAM: measured on the dev TV for the same usage cycle, 42 % fewer swap-ins, 38 % fewer swap-outs, 41 % fewer major faults (results/r8-swappiness.txt).
# Runtime only (/proc/sys), the original value is kept in state/vm.orig and a reboot is stock.
VM_SWAPPINESS=20
do_vmtune() {
  case $ACTION in
    apply|sweep) [ -s "$STATE/vm.orig" ] || cat /proc/sys/vm/swappiness > "$STATE/vm.orig"
           # swap is compressed RAM (zram): reading one page back costs a decompression, so reading 8 neighbours "just in case" (page-cluster 3, the default) wastes memory and time
           [ -s "$STATE/vm.pc.orig" ] || cat /proc/sys/vm/page-cluster > "$STATE/vm.pc.orig"; [ "$(cat /proc/sys/vm/page-cluster)" = 0 ] || echo 0 > /proc/sys/vm/page-cluster
           [ "$(cat /proc/sys/vm/swappiness)" = "$VM_SWAPPINESS" ] || echo $VM_SWAPPINESS > /proc/sys/vm/swappiness
           [ $ACTION = apply ] && echo "vmtune: swappiness $VM_SWAPPINESS";;
    undo)  echo "$(cat "$STATE/vm.orig" 2>/dev/null || echo 100)" > /proc/sys/vm/swappiness; rm -f "$STATE/vm.orig"; echo "$(cat "$STATE/vm.pc.orig" 2>/dev/null || echo 3)" > /proc/sys/vm/page-cluster; rm -f "$STATE/vm.pc.orig"; echo "vmtune: swappiness and swap read-ahead back to stock";;
    status) echo "vmtune: swappiness $(cat /proc/sys/vm/swappiness), swap read-ahead $(cat /proc/sys/vm/page-cluster)";;
  esac
}
do_updates() {
  case $ACTION in
    apply|sweep) upd_settings_apply; upd_hosts_apply
           if svc_running update; then touch "$STATE/stopped-update"; svc_stop update; fi
           upd_stub_ok || stub_bin apply update >/dev/null
           [ $ACTION = apply ] && echo "updates: blocked (settings, hosts, update service, program stub)";;
    undo)  # only the revert path calls this; the Homebrew block lines stay either way
           grep -v "$UPD_MARK" /etc/hosts > /tmp/hosts.new && cat /tmp/hosts.new > /etc/hosts; rm -f /tmp/hosts.new
           stub_bin undo update >/dev/null
           if [ -e "$STATE/stopped-update" ] || ! svc_running update; then svc_start update; rm -f "$STATE/stopped-update"; fi
           echo "updates: our extra blocks removed (automatic updates stay off in LG's settings; Homebrew's own server block stays)";;
    status) n=0; upd_hosts_present && n=$((n+1)); svc_running update || n=$((n+1)); upd_settings_ok && n=$((n+1)); upd_stub_ok && n=$((n+1)); [ $n = 4 ] && echo "updates: BLOCKED (4/4)" || echo "updates: partly blocked ($n/4)";;
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
    qspatch) is_mounted /usr/lib/qt5/qml/KeyFilters/appLaunch.js && echo 1 || echo 0;;
    cursorclear) is_mounted /usr/share/im && echo 1 || echo 0;;
    bootcover) [ -e "$STATE/cover-off" ] && echo 0 || echo 1;;
    memguard) sh "$D/memguard.sh" status | grep -q running && echo 1 || echo 0;;
    lgmenus) [ -e "$STATE/lgmenus.on" ] && echo 1 || echo 0;;
    vmtune) [ "$(cat /proc/sys/vm/swappiness)" = "$VM_SWAPPINESS" ] && echo 1 || echo 0;;
  esac
}
if [ "$ACTION" = state ]; then for i in $ALL; do echo "$i $(active_of $i)"; done; exit 0; fi

for i in $ITEMS; do
  case $i in
    hosts) do_hosts;;
    remotelogger|nudge|contentminer) do_upstart $i; [ $i = contentminer ] && stub_bin $ACTION acr2;;       # acr2 = LG's viewing recognition (Live Plus): an on-demand service, stubbed like admanager
    admanager) do_admanager;;
    lgsettings) do_lgsettings;;
    voice) do_voice;;
    iot) do_iot;;
    preload) do_preload;;
    idleapps) do_idleapps;;
    epg) do_epg;;
    updates) do_updates;;
    cursorclear) do_cursorclear;;
    qspatch) do_qspatch;;
    bootcover) do_bootcover;;
    memguard) do_memguard;;
    lgmenus) do_lgmenus;;
    vmtune) do_vmtune;;
    *) echo "unknown item: $i";;
  esac
done
[ "$ACTION" = sweep ] || log "$ACTION $ITEMS"
