#!/bin/sh
# diagnose.sh - READ-ONLY compatibility report for a TV. Changes nothing. Run from the PC:   ./tv.sh -s < tools/diagnose.sh
# Prints facts the installer and the porting guide (AGENTS.md sections 8-9) need, then a verdict per feature:  OK / WARN / NO
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
say() { printf '%-34s %s\n' "$1" "$2"; }
verdict() { printf '  [%s] %s\n' "$1" "$2"; }
echo "== system"
say "webOS release" "$(cat /etc/starfish-release 2>/dev/null | head -1)"
say "kernel / arch" "$(uname -rm)"
say "memory (MB)" "$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}/SwapTotal/{s=$2}END{printf "total %d, available %d, swap %d",t/1024,a/1024,s/1024}' /proc/meminfo)"
say "model / firmware" "$(luna-send -n 1 -w 4000 luna://com.webos.service.tv.systemproperty/getSystemInfo '{"keys":["modelName","firmwareVersion","sdkVersion"]}' </dev/null 2>/dev/null | tr -d '\n ' | cut -c1-160)"
echo "== root and persistence"
[ "$(id -u)" = 0 ] && R=1 || R=0; say "running as root" "$R"
say "Homebrew init.d" "$([ -d /var/lib/webosbrew/init.d ] && echo present || echo MISSING)"
say "root filesystem" "$(grep ' / ' /proc/mounts | head -1 | awk '{print $3, $4}' | cut -c1-30)"
say "/media/developer writable" "$(touch /media/developer/.w 2>/dev/null && rm -f /media/developer/.w && echo yes || echo NO)"
say "init system" "$(command -v initctl >/dev/null 2>&1 && echo 'Upstart (initctl)' || { command -v systemctl >/dev/null 2>&1 && echo 'systemd (systemctl)' || echo unknown; })"
echo "== tools the scripts need (BusyBox)"
for t in tcpsvd usleep timeout python curl awk sed od mount pgrep pkill luna-send; do say "$t" "$(command -v $t >/dev/null 2>&1 && echo yes || echo NO)"; done
echo "== Home"
say "defaultApps.home" "$(luna-send -n 1 -w 4000 luna://com.webos.settingsservice/getSystemSettings '{"category":"general","keys":["defaultApps"]}' </dev/null 2>/dev/null | tr -d '\n ' | grep -o '"defaultApps":"[^"]*"\|"defaultApps":{[^}]*}' | head -1)"
say "Home programs" "$(ls /usr/bin 2>/dev/null | grep -E '^com\.webos\.app\.(full)?home$' | tr '\n' ' ')"
say "Home appinfo" "$(ls -d /usr/palm/applications/com.webos.app.fullhome /usr/palm/applications/com.webos.app.home 2>/dev/null | tr '\n' ' ')"
echo "== services the features use"
LS=$(ls-monitor -l 2>/dev/null)
for s in com.webos.service.update com.webos.appUpdateService com.webos.appInstallService com.webos.service.mrcu com.webos.settingsservice com.webos.service.activitymanager com.webos.service.systemUIManager com.webos.surfacemanager com.palm.webappmanager; do say "$s" "$(echo "$LS" | grep -q "$s" && echo registered || echo not-seen)"; done
echo "== LG settings keys (description.json)"
for k in appUpdateMode automaticUpdate pointerShape cursorAutoRemover sleepTimer aspectRatio soundOutput pictureMode backlight; do say "$k" "$(grep -c "\"key\": \"$k\"" /etc/palm/description.json 2>/dev/null)"; done
echo "== verdict"
[ $R = 1 ] && [ -d /var/lib/webosbrew/init.d ] && verdict OK "rooted with the Homebrew init hook: the full feature set can be installed" || verdict NO "no root / Homebrew hook: use the rootless pack (rootless/README.md)"
command -v tcpsvd >/dev/null && command -v usleep >/dev/null && command -v timeout >/dev/null && verdict OK "BusyBox tools for the local API are present" || verdict NO "tcpsvd/usleep/timeout missing: api.sh cannot run"
command -v python >/dev/null && verdict OK "python present (app list, pointer and key watchers)" || verdict WARN "no python: Back-chain, app-update list and parts of the API will not work"
command -v initctl >/dev/null && verdict OK "Upstart: debloat.sh works as written" || verdict WARN "systemd TV (webOS 5+): service stops go through tv/init.sh + tv/systemd-units.tsv (unverified: run tools/list-services.sh), the compositor key patch is skipped (AGENTS.md section 8)"
[ -x /usr/bin/com.webos.app.fullhome ] && verdict OK "Home program com.webos.app.fullhome found (default HOME_ID)" || verdict WARN "no com.webos.app.fullhome: set HOME_ID/HOME_EXE in tv/common.sh (see Home programs above)"
case "$(cat /etc/starfish-release 2>/dev/null)" in *"webOS TV"*4*|*4.*) verdict OK "webOS 4.x: the combination this repo was built and tested on";; *) verdict WARN "not the tested webOS version: read AGENTS.md section 8 before installing";; esac
