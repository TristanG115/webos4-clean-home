#!/bin/bash
# install.sh <tv-ip> [--check] [--yes] [--auto-update]   - guided install of the clean Home + debloat on a ROOTED LG webOS TV, from this PC.
#   --check   only look (writes tv.conf, tests SSH, prints the read-only compatibility report) - changes nothing on the TV
#   --yes     do not ask before each stage
#   --auto-update  set Settings -> Software updates to "Install by itself" (default: "Tell me"): good for a TV you set up once for someone else
# Stages: 1 TV address -> 2 SSH key login -> 3 compatibility report -> 4 copy the files -> 5 debloat one item at a time (check after each)
#         -> 6 launcher (stand-in Home) -> 7 optional boot hook. Every stage prints how to undo it. Safe to re-run.
# Not rooted? Use the rootless pack instead: rootless/README.md
set -u
cd "$(dirname "$0")" || exit 1
CHECK=0; YES=0; AUTOUP=0; IP=""
for a in "$@"; do case $a in --check) CHECK=1;; --yes) YES=1;; --auto-update) AUTOUP=1;; -h|--help) sed -n 2,9p "$0"; exit 0;; *) IP=$a;; esac; done
ask() { [ $YES = 1 ] && return 0; read -r -p "$1 [y/N] " r; [ "$r" = y ] || [ "$r" = Y ]; }
step() { echo; echo "=== $*"; }
if [ -n "$IP" ]; then printf 'TV_IP=%s\nTV_USER=root\n' "$IP" > tv.conf; echo "wrote tv.conf (TV_IP=$IP)"; fi
[ -f tv.conf ] || { echo "usage: ./install.sh <tv-ip> [--check] [--yes]"; exit 2; }
. ./tv-env.sh

step "1/7 SSH key login to $TV_TARGET"
if ! ./tv.sh 'echo connected as $(id -un)' 2>/dev/null; then
  echo "No key login yet. On the TV: Homebrew Channel -> Settings (or rootmy.tv guide) enables SSH; the default root password is 'alpine'."
  echo "Create a key if you have none:  ssh-keygen -t ed25519    then install it:  ssh-copy-id $TV_TARGET"
  echo "(Homebrew also offers 'Add SSH key' in its settings.) Then run ./install.sh again."; exit 1
fi

step "2/7 compatibility report (read-only)"
./tv.sh -s < tools/diagnose.sh | tee /tmp/tv-diagnose.txt
if grep -q '\[NO\]' /tmp/tv-diagnose.txt; then echo; echo "A required piece is missing (see [NO] above). Stopping. Rootless TV? -> rootless/README.md"; exit 1; fi
[ $CHECK = 1 ] && { echo; echo "--check: nothing was changed."; exit 0; }
grep -q '\[WARN\]' /tmp/tv-diagnose.txt && { echo; echo "There are [WARN] lines: this TV differs from the tested one. Read AGENTS.md section 8 first."; ask "Continue anyway?" || exit 1; }

step "2b/7 does our remote emulator (key injection) work on this TV? (presses Home once; the Back-key features and the tests depend on it)"
if ask "Run tools/emulator-probe.sh --effect now?"; then ./tools/emulator-probe.sh --effect | tail -12; else echo "skipped: run  ./tools/emulator-probe.sh --effect  any time"; fi

step "3/7 keep a way back: Telnet or SSH must stay enabled, and the undo script is ./revert.sh"
ask "Continue?" || exit 1

step "4/7 copy the files (only writes /media/developer/tv-debloat; undo: delete that folder)"
sh tools/deploy.sh || exit 1
./tv.sh 'test -f /media/developer/tv-debloat/revert.sh && echo "undo script is on the TV (do NOT run it unless you want everything removed)"'

echo; echo "What this TV supports (decided from facts about it, saved in state/caps.conf):"
./tv.sh 'sh /media/developer/tv-debloat/caps.sh write | grep "^feature_"'

step "5/7 debloat, one item at a time (undo: ./revert.sh, or sh debloat.sh undo <item>)"
ITEMS=$(./tv.sh 'grep -v "^#" /media/developer/tv-debloat/services.tsv | cut -d"|" -f1' | tr '\n' ' ')
echo "items: $ITEMS"
ask "Apply them with the default switches?" && for i in $ITEMS; do
  ./tv.sh "sh /media/developer/tv-debloat/debloat.sh apply $i" 2>&1 | head -2
  ./tv.sh -s < tools/check.sh 2>&1 | grep -E "FAIL|RESULT" | head -3
done

step "6/7 the launcher (replaces LG's Home until the next reboot; LG's Home comes back by itself if it fails to start in 30 s)"
if ask "Start it now?"; then ./tv.sh 'sh /media/developer/tv-debloat/home-on.sh'; ./tv.sh -s < tools/check.sh 2>&1 | tail -4; fi

step "7/7 boot hook (makes it survive reboots). Undo: ./revert.sh renames it, or delete /var/lib/webosbrew/init.d/zz-debloat"
if ask "Install the hook?"; then
  ./tv.sh -s < tools/safety-test.sh 2>&1 | tail -6
  ./tv.sh 'cp /media/developer/tv-debloat/zz-debloat /var/lib/webosbrew/init.d/ && chmod 755 /var/lib/webosbrew/init.d/zz-debloat && echo "hook installed"'
fi
[ $AUTOUP = 1 ] && ./tv.sh 'sh /media/developer/tv-debloat/selfupdate.sh conf mode auto'
echo; echo "Updates: this TV checks GitHub for new versions of the project (Settings -> Software updates; mode: $([ $AUTOUP = 1 ] && echo 'install by itself' || echo 'tell me'))"
echo; echo "Done. Add your photos:  node tools/prep-photos.js <folder> && sh tools/deploy.sh   (or scan the QR code in Settings -> Photo gallery)"
