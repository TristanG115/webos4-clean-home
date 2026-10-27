#!/bin/bash
# test-init.sh - proves tv/init.sh builds the right commands for Upstart AND systemd, WITHOUT a TV: it puts fake `initctl` / `systemctl` programs on the PATH that record what
# they were asked and answer from a tiny state file, then sources the real init.sh. Run on the PC:  bash tools/test-init.sh
# What this does NOT prove: that the unit names exist on a real webOS 5+ TV, or that stopping them is safe there (see tools/list-services.sh and tv/systemd-units.tsv).
cd "$(dirname "$0")/.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: expected [$3] got [$2]"; fi; }
mkshim() { # <dir> <name> <body>
  mkdir -p "$1"; printf '#!/bin/sh\n%s\n' "$3" > "$1/$2"; chmod +x "$1/$2"
}
run() { # <PATH prefix dir or ""> <script>: run a script that sources init.sh with that shim dir first on the PATH
  env -i PATH="${1:+$1:}$ORIGPATH" UNITMAP="$T/units.tsv" LOG="$T/calls.log" sh -c ". tv/init.sh; $2"
}
ORIGPATH=$PATH
: > "$T/units.tsv"; printf '%s\n' '# a comment' 'nudge|com.webos.nudge' 'update|update-svc.socket' 'voice|voice.service' >> "$T/units.tsv"
# --- Upstart ---
mkshim "$T/up" initctl 'echo "initctl $*" >> "$LOG"; case "$1:$2" in status:nudge) echo "nudge start/running, process 42";; status:update) echo "update stop/waiting";; status:ghost) echo "initctl: Unknown job: ghost" >&2; exit 1;; *) ;; esac'
ok "upstart INIT" "$(run "$T/up" 'echo $INIT')" upstart
ok "upstart running" "$(run "$T/up" 'svc_running nudge && echo yes || echo no')" yes
ok "upstart stopped" "$(run "$T/up" 'svc_running update && echo yes || echo no')" no
ok "upstart known" "$(run "$T/up" 'svc_known update && echo yes || echo no')" yes
ok "upstart unknown job" "$(run "$T/up" 'svc_known ghost && echo yes || echo no')" no
: > "$T/calls.log"; run "$T/up" 'svc_stop nudge; svc_start nudge; svc_restart surface-manager' >/dev/null
ok "upstart commands" "$(grep -v '^initctl status' "$T/calls.log" | tr '\n' ';')" "initctl stop nudge;initctl start nudge;initctl restart surface-manager;"
# --- systemd ---
mkshim "$T/sd" systemctl 'echo "systemctl $*" >> "$LOG"; case "$1" in is-active) [ "$3" = com.webos.nudge.service ] && exit 0 || exit 3;; cat) [ "$2" = ghost.service ] && exit 1 || exit 0;; esac; exit 0'
ok "systemd INIT" "$(run "$T/sd" 'echo $INIT')" systemd
ok "unit: mapped" "$(run "$T/sd" 'svc_unit nudge')" com.webos.nudge.service
ok "unit: mapped keeps suffix" "$(run "$T/sd" 'svc_unit update')" update-svc.socket
ok "unit: default name" "$(run "$T/sd" 'svc_unit remotelogger')" remotelogger.service
ok "unit: comment line ignored" "$(run "$T/sd" 'svc_unit a')" a.service
ok "systemd running" "$(run "$T/sd" 'svc_running nudge && echo yes || echo no')" yes
ok "systemd not running" "$(run "$T/sd" 'svc_running remotelogger && echo yes || echo no')" no
ok "systemd known" "$(run "$T/sd" 'svc_known nudge && echo yes || echo no')" yes
ok "systemd unknown" "$(run "$T/sd" 'svc_known ghost && echo yes || echo no')" no
: > "$T/calls.log"; run "$T/sd" 'svc_stop nudge; svc_start nudge; svc_restart remotelogger' >/dev/null
ok "systemd commands" "$(tr '\n' ';' < "$T/calls.log")" "systemctl --no-block stop com.webos.nudge.service;systemctl --no-block start com.webos.nudge.service;systemctl --no-block restart remotelogger.service;"
# --- neither ---
ok "none INIT" "$(run "" 'echo $INIT')" none
ok "none refuses" "$(run "" 'svc_stop x && echo yes || echo no')" no
echo "init.sh: $pass passed, $fail failed"; [ $fail = 0 ]
