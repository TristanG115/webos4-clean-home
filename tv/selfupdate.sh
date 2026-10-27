#!/bin/sh
# selfupdate.sh - keep THIS project's code on the TV current from its GitHub repo (Settings -> Software updates).
#   check          look at tv/VERSION in the repo; when it is newer than the installed one remember it (state/update-available) and fetch tv/notes.json
#   apply [force]  download the repo, check it, back up the running code, install it, restart what changed, prove the TV is healthy, else roll back
#   auto           what the 20 s watchdog runs when `due` says yes: check, and in mode "auto" apply when the TV is idle
#   due            yes|no (cheap, no network): is a background check due
#   rollback       put the code of the last backup back
#   json           one JSON object for the Settings screen and the Home pill
#   conf           print / set  mode notify|auto|off , every <hours> , startup on|off , repo owner/name , branch name , ack (forget the last result)
# Safety: the new tree is only installed after every .sh / .py in it passes a syntax check and the key files exist; the old code is kept in
# backup/code-<version>.tgz; if the launcher does not come back healthy the old code is restored and the failed version is not retried by itself.
# LG's firmware updates are a different thing and stay blocked (debloat.sh updates). Test without GitHub: conf `local=/path` (a folder that has tv/ in it).
. /media/developer/tv-debloat/common.sh
CONF=$STATE/update.conf; LAST=$STATE/update-last; AVAIL=$STATE/update-available; NOTES=$STATE/update-notes.json
STATUS=$STATE/update-status; RESULT=$STATE/update-result; FAILED=$STATE/update-failed; ERR=$STATE/update-error; FILES=$STATE/installed.files
LOCK=/tmp/tvd-update.lock; W=/tmp/tvd-update; HOOK=/var/lib/webosbrew/init.d/zz-debloat
DEF_REPO=TristanG115/webos4-clean-home; DEF_BRANCH=main
conf_get() { v=$(sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -1); echo "${v:-$2}"; }
conf_set() { { grep -v "^$1=" "$CONF" 2>/dev/null; echo "$1=$2"; } > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"; }
installed() { v=$(head -1 "$D/VERSION" 2>/dev/null | tr -d '\r '); echo "${v:-0.0.0.0}"; }
vvalid() { echo "$1" | grep -Eq '^[0-9]+(\.[0-9]+){1,4}$'; }
vnewer() { awk -v a="$1" -v b="$2" 'BEGIN{n=split(a,x,".");m=split(b,y,".");if(m>n)n=m;for(i=1;i<=n;i++){p=x[i]+0;q=y[i]+0;if(q>p)exit 0;if(q<p)exit 1}exit 1}'; }
clean() { tr -d '"\\\r\n' | cut -c1-${2:-160}; }
status() { echo "$1" > "$STATUS"; log "update: $1"; }
say() { echo "$1|$2|$3" > "$RESULT"; }          # ok|failed|rolledback , version , message

# ---- where the code comes from (GitHub, or a local folder for tests) ----
repo() { r=$(conf_get repo $DEF_REPO); echo "$r" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' && echo "$r" || echo $DEF_REPO; }
branch() { b=$(conf_get branch $DEF_BRANCH); echo "$b" | grep -Eq '^[A-Za-z0-9._/-]+$' && echo "$b" || echo $DEF_BRANCH; }
get_file() { # <path in the repo> <out file> <seconds>
  l=$(conf_get local ""); if [ -n "$l" ]; then cp "$l/$1" "$2" 2>/dev/null; return $?; fi
  rm -f "$2"; curl -s -f -L -m "${3:-20}" -o "$2" "https://raw.githubusercontent.com/$(repo)/$(branch)/$1" && [ -s "$2" ]
}
get_tree() { # <dir>: the tv/ folder of the repo, unpacked into <dir>
  l=$(conf_get local ""); if [ -n "$l" ]; then cp -r "$l/tv/." "$1/" 2>/dev/null; return $?; fi
  rm -f $W/src.tgz; curl -s -f -L -m 180 -o $W/src.tgz "https://github.com/$(repo)/archive/refs/heads/$(branch).tar.gz" && [ -s $W/src.tgz ] || return 1
  tar xzf $W/src.tgz -C "$1" --strip-components=2 --wildcards '*/tv/*' 2>/dev/null; rm -f $W/src.tgz
  [ -s "$1/VERSION" ]
}

# ---- check ----
check() {
  mkdir -p $W; up > "$LAST"
  if ! get_file tv/VERSION $W/VERSION 20; then echo "could not reach GitHub" > "$ERR"; log "update: check failed (no answer from GitHub)"; echo "Could not reach GitHub"; return 1; fi
  rv=$(head -1 $W/VERSION | tr -d '\r '); iv=$(installed)
  vvalid "$rv" || { echo "bad version in the repo" > "$ERR"; log "update: check: bad version '$(echo "$rv" | clean x 30)'"; echo "The repo has no valid version"; return 1; }
  rm -f "$ERR"
  if get_file tv/notes.json $W/notes.json 20 && python -c 'import json,sys; json.load(open(sys.argv[1]))' $W/notes.json 2>/dev/null; then cp $W/notes.json "$NOTES"; fi
  if vnewer "$iv" "$rv"; then echo "$rv" > "$AVAIL"; log "update: $rv is available (installed $iv)"; echo "Update $rv is available"
  else rm -f "$AVAIL"; log "update: up to date ($iv)"; echo "Up to date ($iv)"; fi
}

# ---- install pieces ----
needs_cycle() { # the changed files include something the running Home / watchers loaded
  grep -Eq '^\./(launcher/|common\.sh|home-|lastapp|settings-|backchain|pointer|keywatch|boot\.sh|api\.sh|appupdate|selfupdate)' "$W/changed"
}
tree_files() { (cd "$1" && find . -type f | grep -v -E '^\./(state|backup|launcher/photos)/' | sort); }
install_tree() { # <srcdir>: copy every file that differs, atomically (a new inode, so a running script keeps its old text); list them in $W/changed
  : > "$W/changed"
  tree_files "$1" > "$W/newlist"
  while read f; do
    [ -f "$D/$f" ] && cmp -s "$1/$f" "$D/$f" && continue
    mkdir -p "$D/$(dirname "$f")" && cp "$1/$f" "$D/$f.upd" && mv -f "$D/$f.upd" "$D/$f" || return 1
    echo "$f" >> "$W/changed"
  done < "$W/newlist"
  [ -s "$FILES" ] && while read f; do grep -qx -- "$f" "$W/newlist" || rm -f "$D/$f"; done < "$FILES"       # files the new version no longer has
  cp "$W/newlist" "$FILES"
  chown -R root:root "$D" 2>/dev/null; chmod -R go-w "$D" 2>/dev/null; chmod 755 "$D"/*.sh "$D/zz-debloat" 2>/dev/null
  return 0
}
install_hook() { # the Homebrew init hook is a copy of tv/zz-debloat; only refresh it when it is installed (revert.sh renames it) and the new one is sane
  [ -f "$HOOK" ] || return 0; cmp -s "$D/zz-debloat" "$HOOK" && return 0
  sh -n "$D/zz-debloat" 2>/dev/null || return 1
  cp "$D/zz-debloat" /var/lib/webosbrew/init.d/.zz-debloat.new && chmod 755 /var/lib/webosbrew/init.d/.zz-debloat.new && mv -f /var/lib/webosbrew/init.d/.zz-debloat.new "$HOOK"
  log "update: init hook refreshed"
}
vet_tree() { # <srcdir>: refuse anything that would not start
  for f in common.sh boot.sh debloat.sh home-on.sh home-off.sh home-standin.sh api.sh revert.sh selfupdate.sh zz-debloat VERSION launcher/index.html launcher/app.js launcher/appinfo.json; do
    [ -s "$1/$f" ] || { echo "missing $f"; return 1; }
  done
  for f in "$1"/*.sh "$1"/zz-debloat; do sh -n "$f" 2>/dev/null || { echo "syntax error in $(basename "$f")"; return 1; }; done
  for f in "$1"/*.py; do [ -f "$f" ] || continue; python -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$f" 2>/dev/null || { echo "syntax error in $(basename "$f")"; return 1; }; done
  return 0
}
restart_changed() {
  if grep -Eq '^\./(debloat\.sh|services\.tsv|blocklist|stub-noop|cursorclear)' "$W/changed"; then sh "$D/debloat.sh" apply >/dev/null 2>&1; fi
  if grep -Eq '^\./(qspatch\.sh|qs/)' "$W/changed" && [ "$(sh "$D/qspatch.sh" status 2>/dev/null | cut -c1-6)" = ACTIVE ]; then status "restarting the compositor"; sh "$D/qspatch.sh" reapply >/dev/null 2>&1; fi
  if needs_cycle; then
    status "restarting Home"; rm -f "$STATE/launcher.ready"
    sh "$D/home-off.sh" temp >/dev/null 2>&1; sh "$D/home-on.sh" >/dev/null 2>&1
  fi
}
healthy() { # the launcher is ours again, answers, and reported ready
  i=0; while [ $i -lt 60 ]; do
    if is_mounted "$HOME_EXE" && [ -e "$STATE/launcher.ready" ] && api_ok; then return 0; fi
    sleep 2; i=$((i+2))
  done
  return 1
}
backup_code() { # <version>
  mkdir -p "$D/backup"
  tar czf "$D/backup/code-$1.tgz" -C "$D" --exclude=./state --exclude=./backup --exclude=./launcher/photos . 2>/dev/null; [ -s "$D/backup/code-$1.tgz" ] || return 1
  for o in $(ls -t "$D"/backup/code-*.tgz 2>/dev/null | tail -n +4); do rm -f "$o"; done      # keep the three newest
}
last_backup() { ls -t "$D"/backup/code-*.tgz 2>/dev/null | head -1; }
do_rollback() { # <tgz> <why>
  b=$1; log "update: rolling back to $b ($2)"; status "putting the old version back"
  rm -rf $W/rb; mkdir -p $W/rb; tar xzf "$b" -C $W/rb 2>/dev/null
  vet_tree $W/rb >/dev/null && install_tree $W/rb && install_hook && { restart_changed; healthy; }
}

# ---- apply ----
apply() {
  [ -e "$D/DISABLE" ] && { say failed "" "The cleanup is switched off (DISABLE flag)"; echo "refused: DISABLE flag"; return 1; }
  mkdir "$LOCK" 2>/dev/null || { echo "an update is already running"; return 1; }
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT
  mkdir -p $W; rm -rf $W/stage; mkdir -p $W/stage; rm -f "$RESULT"
  iv=$(installed)
  status "downloading"
  get_tree $W/stage || { status "download failed"; say failed "" "Could not download the update"; return 1; }
  sv=$(head -1 $W/stage/VERSION | tr -d '\r '); vvalid "$sv" || { status "bad version"; say failed "" "The download has no valid version"; return 1; }
  [ "$1" = force ] || vnewer "$iv" "$sv" || { status "nothing newer"; say ok "$iv" "Already up to date"; rm -f "$AVAIL"; return 0; }
  status "checking $sv"
  why=$(vet_tree $W/stage) || { status "refused: $why"; say failed "$sv" "Refused: $why"; echo "$sv" > "$FAILED"; return 1; }
  status "backing up $iv"; backup_code "$iv" || { status "backup failed"; say failed "$sv" "Could not back up the current version"; return 1; }
  bk=$(last_backup)
  status "installing $sv"
  if ! install_tree $W/stage || ! install_hook; then
    do_rollback "$bk" "install failed"; echo "$sv" > "$FAILED"; say rolledback "$sv" "Install failed, the old version ($iv) is back"; return 1
  fi
  cp "$W/changed" "$W/changed.keep"
  restart_changed
  if healthy; then
    rm -f "$AVAIL" "$FAILED" "$ERR"; say ok "$sv" "Updated from $iv to $sv"; status "done: $sv"; echo "updated to $sv"; return 0
  fi
  do_rollback "$bk" "the launcher did not come back"
  echo "$sv" > "$FAILED"
  if healthy; then say rolledback "$sv" "The new version did not start, the old one ($iv) is back"; else say failed "$sv" "Roll-back also failed: use revert.sh"; fi
  status "rolled back"; echo "rolled back"; return 1
}
rollback() {
  b=$(last_backup); [ -n "$b" ] || { echo "no backup"; return 1; }
  mkdir "$LOCK" 2>/dev/null || { echo "an update is already running"; return 1; }; trap 'rmdir "$LOCK" 2>/dev/null' EXIT
  mkdir -p $W; v=$(installed); rm -f "$RESULT"
  if do_rollback "$b" "asked by the owner"; then say ok "$(installed)" "Went back from $v to $(installed)"; echo "$v" > "$FAILED"; echo "rolled back"; else say failed "$v" "Roll-back failed: use revert.sh"; echo failed; return 1; fi
}

# ---- when ----
mode() { m=$(conf_get mode notify); case $m in auto|off) echo $m;; *) echo notify;; esac; }
idle() { [ -e /tmp/saver-on ] || [ -z "$(cat /tmp/fgnow 2>/dev/null)" ]; }
due() {
  [ -e "$D/DISABLE" ] && { echo no; return; }
  [ "$(mode)" = off ] && { echo no; return; }
  now=$(cut -d. -f1 /proc/uptime); last=$(cut -d. -f1 "$LAST" 2>/dev/null); ready=$(cut -d. -f1 "$STATE/launcher.ready" 2>/dev/null)
  [ -n "$ready" ] && [ $((now - ready)) -ge 120 ] || { echo no; return; }
  if [ -z "$last" ] || [ "$last" -gt "$now" ]; then [ "$(conf_get startup on)" = on ] && echo yes || echo no; return; fi
  # auto mode: an update is waiting for a quiet moment, look again every 30 minutes
  [ "$(mode)" = auto ] && [ -s "$AVAIL" ] && [ "$(cat "$AVAIL")" != "$(cat "$FAILED" 2>/dev/null)" ] && [ $((now - last)) -ge 1800 ] && { echo yes; return; }
  ev=$(conf_get every 12); [ "$ev" -gt 0 ] 2>/dev/null && [ $((now - last)) -ge $((ev * 3600)) ] && echo yes || echo no
}
auto() {
  check >/dev/null || return 0
  [ "$(mode)" = auto ] && [ -s "$AVAIL" ] || return 0
  [ "$(cat "$AVAIL")" = "$(cat "$FAILED" 2>/dev/null)" ] && return 0       # this version failed here already: only by hand
  idle || { log "update: $(cat "$AVAIL") is waiting for a quiet moment"; return 0; }
  apply
}

# ---- json ----
json() {
  iv=$(installed); av=$(cat "$AVAIL" 2>/dev/null | clean x 30); now=$(cut -d. -f1 /proc/uptime); last=$(cut -d. -f1 "$LAST" 2>/dev/null)
  ago=null; [ -n "$last" ] && [ "$last" -le "$now" ] && ago=$((now - last))
  busy=false; [ -d "$LOCK" ] && busy=true
  res=$(cat "$RESULT" 2>/dev/null); rk=$(echo "$res" | cut -d'|' -f1 | clean x 12); rv=$(echo "$res" | cut -d'|' -f2 | clean x 30); rmsg=$(echo "$res" | cut -d"|" -f3 | clean x 160)
  nf=$NOTES; [ -s "$nf" ] || nf=$D/notes.json; n=$(cat "$nf" 2>/dev/null); case $n in \[*) ;; *) n='[]';; esac
  hb=false; [ -n "$(last_backup)" ] && hb=true
  printf '{"installed":"%s","available":"%s","mode":"%s","startup":"%s","every":%s,"lastAgoSec":%s,"status":"%s","busy":%s,"error":"%s","failed":"%s","resultKind":"%s","resultVersion":"%s","result":"%s","repo":"%s","branch":"%s","hasBackup":%s,"notes":%s}' \
    "$iv" "$av" "$(mode)" "$(conf_get startup on)" "$(conf_get every 12)" "$ago" "$(cat "$STATUS" 2>/dev/null | clean x 100)" "$busy" "$(cat "$ERR" 2>/dev/null | clean x 100)" "$(cat "$FAILED" 2>/dev/null | clean x 30)" "$rk" "$rv" "$rmsg" "$(repo)" "$(branch)" "$hb" "$n"
}

case ${1:-json} in
  check)    check;;
  apply)    apply "$2";;
  auto)     auto;;
  due)      due;;
  rollback) rollback;;
  json)     json;;
  conf)     if [ -n "$2" ]; then
              case $2:$3 in
                mode:notify|mode:auto|mode:off) conf_set mode "$3";;
                startup:on|startup:off) conf_set startup "$3";;
                every:[0-9]|every:[0-9][0-9]|every:[0-9][0-9][0-9]) conf_set every "$3";;
                repo:*/*) echo "$3" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' && conf_set repo "$3";;
                branch:?*) echo "$3" | grep -Eq '^[A-Za-z0-9._/-]+$' && conf_set branch "$3";;
                ack:*) rm -f "$RESULT";;
              esac
            fi
            echo "mode=$(mode) every=$(conf_get every 12) startup=$(conf_get startup on) repo=$(repo) branch=$(branch)";;
esac
