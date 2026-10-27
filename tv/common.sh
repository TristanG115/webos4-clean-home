#!/bin/sh
# common.sh - sourced by the other tv-debloat scripts. Runs ON the TV (BusyBox ash).
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
D=/media/developer/tv-debloat
STATE=$D/state
MARK="# tv-debloat"
LOGF=$STATE/tv-debloat.log
mkdir -p "$STATE" 2>/dev/null
up() { cut -d' ' -f1 /proc/uptime; }
log() {
  echo "$(up) $(basename "$0")[$$]: $*" >> "$LOGF" 2>/dev/null
  [ "$(wc -c < "$LOGF" 2>/dev/null || echo 0)" -gt 200000 ] && tail -c 100000 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
  return 0
}
# luna-send needs stdin closed; -w bounds the wait so nothing can hang a boot script
lun() { luna-send -n 1 -w "${LW:-6000}" "$@" </dev/null 2>/dev/null; }
is_mounted() { grep -q " $1 " /proc/mounts; }
HOME_ID=com.webos.app.fullhome
HOME_EXE=/usr/bin/com.webos.app.fullhome
INP_ID=tv.debloat.inputs            # our Inputs overlay (replaces LG's input picker, opened by the compositor patch)
COVER_ID=tv.debloat.cover            # the start-up cover (cover.sh)
SET_ID=tv.debloat.settings          # our Settings overlay (a second WAM page; the remote's Settings key opens it)
RAMDIR=/tmp/tv-launcher             # tmpfs copy of the launcher code (photos stay on flash and are bind-mounted in)

api_start() {
  [ -s "$STATE/token" ] || head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$STATE/token"
  pgrep -f "tcpsvd.* 8765 " >/dev/null || ( setsid tcpsvd -c 6 0.0.0.0 8765 timeout -t 120 sh "$D/api.sh" </dev/null >/dev/null 2>&1 & )
}
api_ok() { curl -s -m 3 -o /dev/null http://127.0.0.1:8765/api/ping; }

# ---- launcher in RAM -------------------------------------------------------------------------------------------------
# The page code (a few hundred KB) is copied to tmpfs so starting Home never waits on the eMMC, even when the TV is swapping.
# Photos stay on flash and are bind-mounted into the RAM tree (a symlink would leave the page's own folder).
# launcher_dir prints the folder WAM should load: the RAM copy when it is complete, the flash copy otherwise.
launcher_dir() { if [ -f "$RAMDIR/index.html" ] && [ -f "$RAMDIR/app.js" ] && [ -f "$RAMDIR/.complete" ]; then echo "$RAMDIR"; else echo "$D/launcher"; fi; }
mkhtml() { # <mode> <title> <out>
  sed "s#<script src=\"app.js\">#<script>window.__MODE__=\"$1\"</script><script src=\"app.js\">#; s#<title>Home</title>#<title>$2</title>#" "$D/launcher/index.html" > "$3"
}
ram_sync() {
  [ -f "$D/launcher/index.html" ] || return 1
  rm -f "$RAMDIR/.complete"; mkdir -p "$RAMDIR/photos" || return 1
  for f in index.html app.js qr.js stage.js appinfo.json; do cp "$D/launcher/$f" "$RAMDIR/$f.new" && mv "$RAMDIR/$f.new" "$RAMDIR/$f" || return 1; done
  # the overlays (Settings, Inputs) are the same page started in another mode (the mode is chosen by the file name: see MODE in app.js)
  mkhtml settings Settings "$RAMDIR/settings.html" || return 1
  mkhtml inputs Inputs "$RAMDIR/inputs.html" || return 1
  is_mounted "$RAMDIR/photos" || mount --bind "$D/launcher/photos" "$RAMDIR/photos" || return 1
  chmod -R go-w "$RAMDIR"; touch "$RAMDIR/.complete"; return 0
}
ram_drop() {
  for m in $(awk -v b="$RAMDIR/photos" '$2==b{print $2}' /proc/mounts | sort -r); do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null; done
  rm -rf "$RAMDIR" 2>/dev/null
}
# appinfo for WAM launchApp, pointed at folder $2, as one JSON line. $1 = appinfo file, $3 = optional id/type overrides for the Settings overlay
app_desc() { # <appinfo.json> <folder>
  tr -d '\n' < "$1" | sed "s#\"folderPath\":\"[^\"]*\"#\"folderPath\":\"$2\"#"
}

# ---- Settings overlay ----------------------------------------------------------------------------------------------------
# settings.html = index.html started in settings mode. ram_sync writes it into the RAM copy; this makes sure the flash copy has one
# too (used when the RAM copy is not available).
ensure_settings_html() {
  for m in settings:Settings inputs:Inputs; do
    f=$D/launcher/${m%%:*}.html
    if [ ! -s "$f" ] || [ "$D/launcher/index.html" -nt "$f" ]; then mkhtml "${m%%:*}" "${m#*:}" "$f.new" && mv "$f.new" "$f"; fi
  done
}
# the WAM appDesc of our Settings overlay as ONE JSON line (settings-open.sh sends it from the shell, qspatch.sh bakes it into the compositor patch)
overlay_appdesc() { # <app id> <html file> <title>
  DIR=$(launcher_dir); [ "$DIR" = "$D/launcher" ] && ensure_settings_html
  printf '{"id":"%s","version":"1.0.0","vendor":"tv-debloat","type":"web","main":"%s","title":"%s","visible":false,"transparent":true,"bgColor":"#00000000","disableBackHistoryAPI":true,"lockable":false,"supportQuickStart":false,"defaultWindowType":"overlay","trustLevel":"trusted","folderPath":"%s"' "$1" "$2" "$3" "$DIR"
  [ -e "$D/DEBUG" ] && printf ',"inspectable":true'
  printf '}'
}
# the boot cover: opaque, from the flash copy of the launcher folder (the RAM copy does not exist yet that early in the boot)
cover_appdesc() { printf '{"id":"%s","version":"1.0.0","vendor":"tv-debloat","type":"web","main":"cover.html","title":"Starting","visible":false,"transparent":false,"bgColor":"#07090d","disableBackHistoryAPI":true,"lockable":false,"supportQuickStart":false,"defaultWindowType":"overlay","trustLevel":"trusted","folderPath":"%s"}' "$COVER_ID" "$D/launcher"; }
settings_appdesc() { overlay_appdesc "$SET_ID" settings.html Settings; }
inputs_appdesc() { overlay_appdesc "$INP_ID" inputs.html Inputs; }
# lgsettings.allow holds the uptime (seconds) until which LG's own Settings app may be opened without being redirected to ours
lg_settings_allowed() { a=$(cat "$STATE/lgsettings.allow" 2>/dev/null); [ -n "$a" ] && [ "$(cut -d. -f1 /proc/uptime)" -lt "$a" ]; }
