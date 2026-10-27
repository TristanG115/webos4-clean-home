#!/bin/sh
# list-services.sh - READ-ONLY: which of the services this project stops exist on THIS TV, and what their init-system names are. Run:   ./tv.sh -s < tools/list-services.sh
# Meant for porting to a systemd TV (webOS 5+): it shows the init system, which of our job names exist as units (or are missing), and every service whose name looks related
# to ads / telemetry / voice / updates so you can fill in tv/systemd-units.tsv. It changes nothing.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/tv-debloat
if [ -f "$D/init.sh" ]; then . "$D/init.sh"; else
  INIT=$(command -v initctl >/dev/null 2>&1 && echo upstart || { command -v systemctl >/dev/null 2>&1 && echo systemd || echo none; })
  svc_known() { case $INIT in upstart) initctl status "$1" >/dev/null 2>&1;; systemd) systemctl cat "$1.service" >/dev/null 2>&1;; *) return 1;; esac; }
  svc_running() { case $INIT in upstart) initctl status "$1" 2>/dev/null | grep -q start/running;; systemd) systemctl is-active --quiet "$1.service";; *) return 1;; esac; }
  svc_unit() { echo "$1.service"; }
fi
echo "init system: $INIT"
echo "== jobs this project stops (Upstart names) on this TV"
for j in remotelogger nudge contentminer iepg broadcast-conf-downloader voiceinput voiceconductor update surface-manager WebAppMgr; do
  if svc_known "$j"; then s=stopped; svc_running "$j" && s=RUNNING; printf '  %-28s %-10s %s\n' "$j" "$s" "$([ "$INIT" = systemd ] && svc_unit "$j")"
  else printf '  %-28s %s\n' "$j" "not found (skipped by the scripts)"; fi
done
echo "== services with related names (candidates for tv/systemd-units.tsv)"
case $INIT in
  systemd) systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null | awk '{print $1, $3, $4}' ;;
  upstart) initctl list 2>/dev/null | awk '{print $1, $2}' ;;
esac | grep -i -E "log|nudge|miner|acr|ads?[-_.]|admanager|voice|nlp|iot|thinq|update|epg|guide|telemetry|crash|upload|preload|assistant" | head -60
echo "== the compositor / web app manager names (needed for the key patch, Upstart only today)"
case $INIT in
  systemd) systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null | awk '{print $1}' | grep -i -E "surface|compositor|webapp|wam|sam" | head ;;
  upstart) initctl list 2>/dev/null | awk '{print $1}' | grep -i -E "surface|webapp|sam" | head ;;
esac
