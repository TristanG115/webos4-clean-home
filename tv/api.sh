#!/bin/sh
# api.sh - ONE HTTP request on stdin/stdout, started per connection by:
#     tcpsvd -c 6 0.0.0.0 8765 timeout -t 120 sh api.sh
# Two trust levels (tcpsvd provides TCPREMOTEADDR=ip:port):
#   LOCAL (127.0.0.1, the launcher page on the TV): full whitelist below, no token.
#   LAN   (your phone): ONLY the phone page and the photo / crop / launcher-settings / ad-block-list routes under / /m/* /photos/*,
#         and only with ?t=<secret token> (the token is in the QR code shown on the TV; Settings -> Photo gallery -> "Reset phone link" makes a new one).
#         The phone can NOT change services, LG settings, reboot or launch anything.
. /media/developer/tv-debloat/common.sh
PH=$D/launcher/photos
SETF=$STATE/settings.json
CROPD=$STATE/crops
read -r line || exit 0
line=$(printf %s "$line" | tr -d '\r'); set -- $line; METHOD=$1; URL=$2
CL=0
while read -r h; do h=$(printf %s "$h" | tr -d '\r'); [ -z "$h" ] && break; case "$h" in [Cc]ontent-[Ll]ength:*) CL=$(printf %s "${h#*:}" | tr -d " ");; esac; done
case "$CL" in ''|*[!0-9]*) CL=0;; esac
LOCAL=0; case "$TCPREMOTEADDR" in 127.0.0.1:*) LOCAL=1;; esac
P=${URL%%\?*}; Q=""; case "$URL" in *\?*) Q=${URL#*\?};; esac
qget() { printf '%s' "$Q" | tr '&' '\n' | sed -n "s/^$1=//p" | head -1 | sed 's/%2F/\//g; s/%3A/:/g; s/%2C/,/g'; }
hdr() { printf 'HTTP/1.0 %s\r\nContent-Type: %s\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n' "$1" "${2:-application/json}"; }
bad() { hdr "${1:-400 Bad Request}"; echo "{\"error\":\"${2:-bad request}\"}"; }
body_small() { BODY=""; [ "$CL" -gt 0 ] && [ "$CL" -lt "${1:-8192}" ] && BODY=$(head -c "$CL"); }
ok_id() { printf %s "$1" | grep -Eq '^[A-Za-z0-9._-]{1,80}$'; }
ok_photo() { printf %s "$1" | grep -Eq '^[A-Za-z0-9_-]{1,40}\.jpg$'; }
token() { cat "$STATE/token" 2>/dev/null; }
token_ok() { t=$(token); [ -n "$t" ] && [ "$(qget t)" = "$t" ]; }
serve_file() { # path content-type
  [ -f "$1" ] || { bad "404 Not Found" "not found"; return; }
  printf 'HTTP/1.0 200 OK\r\nContent-Type: %s\r\nContent-Length: %s\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: max-age=600\r\nConnection: close\r\n\r\n' "$2" "$(wc -c < "$1")"; cat "$1"; }
photos_json() { printf '['; n=0
  for f in "$PH"/*.jpg; do [ -f "$f" ] || continue; [ $n -gt 0 ] && printf ','; printf '"%s"' "${f##*/}"; n=$((n+1)); done; printf ']'; }
settings_get() { if [ -s "$SETF" ]; then cat "$SETF"; else echo '{}'; fi; }
settings_set() { body_small
  case "$BODY" in \{*\}) printf %s "$BODY" > "$SETF.tmp" && mv "$SETF.tmp" "$SETF"; echo '{"ok":true}';; *) echo '{"error":"bad json"}';; esac; }
do_upload() {
  id=$(qget id); kind=$(qget kind)
  printf %s "$id" | grep -Eq '^[0-9a-z]{6,24}$' || { bad; return; }
  case $kind in full) max=4194304; dest="$PH/u$id.jpg";; thumb) max=204800; dest="$PH/thumbs/u$id.jpg";; *) bad; return;; esac
  [ "$CL" -gt 1000 ] && [ "$CL" -le $max ] || { bad "413 Payload Too Large" "size"; return; }
  [ "$(ls "$PH" 2>/dev/null | grep -c '\.jpg$')" -lt 300 ] || { bad "507 Insufficient Storage" "gallery full"; return; }
  mkdir -p "$PH/thumbs"; tmp="$STATE/upload.$$"
  head -c "$CL" > "$tmp"
  magic=$(head -c 3 "$tmp" | od -An -tx1 | tr -d ' \n')
  if [ "$magic" = ffd8ff ] && [ "$(wc -c < "$tmp")" -eq "$CL" ]; then chmod 644 "$tmp"; mv "$tmp" "$dest"; hdr "200 OK"; echo '{"ok":true}'
  else rm -f "$tmp"; bad "415 Unsupported Media Type" "not a complete jpeg"; fi
}
do_delete() { n=$(qget name); ok_photo "$n" || { bad; return; }; rm -f "$PH/$n" "$PH/thumbs/$n" "$CROPD/${n%.jpg}.json"; hdr "200 OK"; echo '{"ok":true}'; }

# ---- framing of each photo (focus point, zoom, edge colours): one small JSON file per photo in state/crops/ ----
crops_json() { printf '{'; n=0
  for f in "$CROPD"/*.json; do [ -f "$f" ] || continue; [ $n -gt 0 ] && printf ','; b=${f##*/}; printf '"%s.jpg":' "${b%.json}"; cat "$f"; n=$((n+1)); done; printf '}'; }
crop_set() { n=$(qget name); ok_photo "$n" || { bad; return; }
  [ -f "$PH/$n" ] || { bad "404 Not Found" "no such photo"; return; }
  if [ "$(qget reset)" = 1 ]; then rm -f "$CROPD/${n%.jpg}.json"; hdr "200 OK"; echo '{"ok":true}'; return; fi
  body_small 2000
  case "$BODY" in \{*\}) ;; *) bad; return;; esac
  [ "$(printf %s "$BODY" | tr -d ']\[{}0-9A-Za-z":,. #-' | wc -c)" = 0 ] || { bad 400 "characters"; return; }
  mkdir -p "$CROPD"; printf %s "$BODY" > "$CROPD/${n%.jpg}.tmp" && mv "$CROPD/${n%.jpg}.tmp" "$CROPD/${n%.jpg}.json"; hdr "200 OK"; echo '{"ok":true}'; }

# ---- ad blocking (block lists, your own block / allow lists) ----
clean_domains() { tr 'A-Z,;' 'a-z\n\n' | tr -c 'a-z0-9._=\n-' '\n' | grep -E '^=?[a-z0-9_-]+(\.[a-z0-9_-]+)+$' | head -600 | sort -u; }
domains_json() { printf '['; n=0; if [ -f "$1" ]; then while read -r d; do [ $n -gt 0 ] && printf ','; printf '"%s"' "$d"; n=$((n+1)); done < "$1"; fi; printf ']'; }
block_file() { case "$(qget kind)" in allow) echo "$STATE/block-allow.txt";; *) echo "$STATE/block-custom.txt";; esac; }
block_custom() { f=$(block_file)
  if [ "$METHOD" = POST ]; then body_small 32768; printf %s "$BODY" | clean_domains > "$f.tmp"; mv "$f.tmp" "$f"; timeout -t 40 sh "$D/blocklist.sh" apply </dev/null >/dev/null 2>&1; hdr "200 OK"; domains_json "$f"
  else hdr "200 OK"; domains_json "$f"; fi; }
block_set() { id=$(qget id); v=$(qget v)
  ok_id "$id" && grep -q "^$id|" "$D/blocklists/lists.tsv" && { [ "$v" = on ] || [ "$v" = off ]; } || { bad; return; }
  grep -v "^$id=" "$STATE/block.conf" 2>/dev/null > "$STATE/block.conf.tmp"; echo "$id=$v" >> "$STATE/block.conf.tmp"; mv "$STATE/block.conf.tmp" "$STATE/block.conf"
  if [ "$v" = on ] && [ "$(awk -F'|' -v id="$id" '$1==id{print $2}' "$D/blocklists/lists.tsv")" = remote ] && [ ! -s "$STATE/lists/$id.txt" ]; then
    timeout -t 70 sh "$D/blocklist.sh" update "$id" </dev/null >/dev/null 2>&1
  else timeout -t 40 sh "$D/blocklist.sh" apply </dev/null >/dev/null 2>&1; fi
  hdr "200 OK"; sh "$D/blocklist.sh" json; }
block_update() { ( timeout -t 150 sh "$D/blocklist.sh" update all </dev/null >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 & hdr "200 OK"; echo '{"started":true}'; }

# ---- services & privacy switches (LOCAL only) ----
svc_json() {
  S=$(sh "$D/debloat.sh" state 2>/dev/null | tr '\n' ','); C=$(cat "$STATE/svc.conf" 2>/dev/null | tr '\n' ',')
  awk -F'|' -v S="$S" -v C="$C" 'BEGIN { n = split(S, a, ","); for (i = 1; i <= n; i++) { split(a[i], b, " "); act[b[1]] = b[2] }
      n = split(C, c, ","); for (i = 1; i <= n; i++) { split(c[i], d, "="); cf[d[1]] = d[2] }; printf "[" }
    /^#/ || NF < 6 { next }
    { w = ($1 in cf) ? cf[$1] : $3; if ($4 == 1) w = "on"
      printf "%s{\"id\":\"%s\",\"group\":\"%s\",\"name\":\"%s\",\"desc\":\"%s\",\"locked\":%s,\"on\":%s,\"active\":%s}", (f++ ? "," : ""), $1, $2, $5, $6, $4, (w == "on" ? "true" : "false"), (act[$1] == 1 ? "true" : "false") }
    END { printf "]" }' "$D/services.tsv"; }
svc_set() { id=$(qget id); v=$(qget v)
  ok_id "$id" && grep -q "^$id|" "$D/services.tsv" && { [ "$v" = on ] || [ "$v" = off ]; } || { bad; return; }
  [ "$(awk -F'|' -v id="$id" '$1==id{print $4}' "$D/services.tsv")" = 1 ] && [ "$v" = off ] && { bad "403 Forbidden" "locked"; return; }
  grep -v "^$id=" "$STATE/svc.conf" 2>/dev/null > "$STATE/svc.conf.tmp"; echo "$id=$v" >> "$STATE/svc.conf.tmp"; mv "$STATE/svc.conf.tmp" "$STATE/svc.conf"
  if [ "$v" = on ]; then timeout -t 40 sh "$D/debloat.sh" apply "$id" </dev/null >/dev/null 2>&1; else timeout -t 40 sh "$D/debloat.sh" undo "$id" </dev/null >/dev/null 2>&1; fi
  hdr "200 OK"; svc_json; }

# ---------------- LAN (phone) ----------------
if [ $LOCAL = 0 ]; then
  case "$P" in
    /)             hdr "200 OK" "text/html; charset=utf-8"; cat "$D/launcher/phone.html";;
    /stage.js)     serve_file "$D/launcher/stage.js" "text/javascript; charset=utf-8";;
    /m/photos)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; hdr "200 OK"; photos_json;;
    /m/upload)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && do_upload || bad;;
    /m/delete)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && do_delete || bad;;
    /m/settings)   token_ok || { bad "403 Forbidden" "token"; exit 0; }; hdr "200 OK"; if [ "$METHOD" = POST ]; then settings_set; else settings_get; fi;;
    /m/crops)      token_ok || { bad "403 Forbidden" "token"; exit 0; }; hdr "200 OK"; crops_json;;
    /m/crop)       token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && crop_set || bad;;
    /m/block)      token_ok || { bad "403 Forbidden" "token"; exit 0; }; hdr "200 OK"; sh "$D/blocklist.sh" json;;
    /m/block/set)  token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && block_set || bad;;
    /m/block/custom) token_ok || { bad "403 Forbidden" "token"; exit 0; }; block_custom;;
    /m/block/update) token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && block_update || bad;;
    /photos/thumbs/*) token_ok || { bad "403 Forbidden" "token"; exit 0; }; n=${P#/photos/thumbs/}; ok_photo "$n" && serve_file "$PH/thumbs/$n" image/jpeg || bad;;
    /photos/*)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; n=${P#/photos/}; ok_photo "$n" && serve_file "$PH/$n" image/jpeg || bad;;
    *)             bad "403 Forbidden" "forbidden";;
  esac
  exit 0
fi

# ---------------- LOCAL (launcher page) ----------------
case "$P" in
  /api/ping)    hdr "200 OK"; echo '{"ok":true}';;
  /api/ready)   hdr "200 OK"; up > "$STATE/launcher.ready"; echo '{"ok":true}';;
  /api/apps)    hdr "200 OK"; LW=8000 lun luna://com.webos.applicationManager/listLaunchPoints '{}';;
  /api/running) hdr "200 OK"; lun luna://com.webos.applicationManager/running '{}';;
  /api/net)     hdr "200 OK"; lun luna://com.webos.service.connectionmanager/getStatus '{}';;
  /api/fg)      hdr "200 OK"; lun luna://com.webos.applicationManager/getForegroundAppInfo '{}';;
  /api/launch)  id=$(qget id)
                if ok_id "$id"; then hdr "200 OK"; LW=10000 lun luna://com.webos.applicationManager/launch "{\"id\":\"$id\",\"params\":{}}"
                else bad; fi;;
  /api/back)    # Back on Home: return to the app / input you were in before Home (tracked by lastapp.sh)
                id=$(timeout -t 8 sh "$D/lastapp.sh" top 2>/dev/null)
                if ok_id "$id"; then hdr "200 OK"; LW=10000 lun luna://com.webos.applicationManager/launch "{\"id\":\"$id\",\"params\":{}}" >/dev/null; echo "{\"back\":\"$id\"}"
                else hdr "200 OK"; echo '{"back":""}'; fi;;
  /api/appupdates) hdr "200 OK"; timeout -t 25 sh "$D/appupdate.sh" json </dev/null 2>/dev/null || echo '{"mode":"","pending":[],"apps":[]}';;
  /api/appupdates/mode) case "$(qget v)" in auto|manual) timeout -t 15 sh "$D/appupdate.sh" mode "$(qget v)" </dev/null >/dev/null 2>&1;; esac
                hdr "200 OK"; printf '{"mode":"%s"}' "$(timeout -t 10 sh "$D/appupdate.sh" mode </dev/null 2>/dev/null)";;
  /api/appupdates/conf) case "$(qget k)" in startup|every) timeout -t 10 sh "$D/appupdate.sh" conf "$(qget k)" "$(qget v)" </dev/null >/dev/null 2>&1;; esac
                hdr "200 OK"; timeout -t 10 sh "$D/appupdate.sh" conf </dev/null 2>/dev/null | sed 's/startup=\([a-z]*\) every=\([0-9]*\)/{"startup":"\1","every":\2}/';;
  /api/appupdates/check) m=$(timeout -t 25 sh "$D/appupdate.sh" check </dev/null 2>/dev/null | head -1 | tr -d '"'); hdr "200 OK"; printf '{"msg":"%s"}' "$m";;
  /api/backlight) case "$(qget v)" in
                  dim) pct=$(qget pct); timeout -t 15 sh "$D/backlight.sh" dim "$pct" </dev/null >/dev/null 2>&1;;
                  hold) sh "$D/backlight.sh" hold </dev/null >/dev/null 2>&1;;
                  restore) timeout -t 15 sh "$D/backlight.sh" restore </dev/null >/dev/null 2>&1;; esac
                hdr "200 OK"; printf '{"backlight":"%s"}' "$(sh "$D/backlight.sh" status | cut -d' ' -f1)";;
  /api/history) # Back-button history (lastapp.sh): v=clear | saver | standby forget it (the options decide for saver / standby); k+v set an option; no args = the options
                case "$(qget v)" in clear) sh "$D/lastapp.sh" clear page;; saver|standby) sh "$D/lastapp.sh" why "$(qget v)";; esac
                [ -n "$(qget k)" ] && sh "$D/lastapp.sh" conf "$(qget k)" "$(qget n)"
                hdr "200 OK"; sh "$D/lastapp.sh" conf;;
  /api/backchain) case "$(qget v)" in off) touch "$STATE/backchain-off";; on) rm -f "$STATE/backchain-off";; esac
                hdr "200 OK"; [ -e "$STATE/backchain-off" ] && echo '{"chain":"off"}' || echo '{"chain":"on"}';;
  /api/pointer) case "$(qget v)" in off|on) m=$(timeout -t 20 sh "$D/pointer.sh" "$(qget v)" </dev/null 2>/dev/null | head -1 | tr -d '"\\');; *) m="";; esac
                hdr "200 OK"; printf '{"pointer":"%s","msg":"%s"}' "$(sh "$D/pointer.sh" status)" "$m";;
  /api/photos)  hdr "200 OK"; photos_json;;
  /api/delete)  do_delete;;
  /api/crops)   hdr "200 OK"; crops_json;;
  /api/crop)    [ "$METHOD" = POST ] && crop_set || bad;;
  /photos/thumbs/*) n=${P#/photos/thumbs/}; ok_photo "$n" && serve_file "$PH/thumbs/$n" image/jpeg || bad;;
  /photos/*)    n=${P#/photos/}; ok_photo "$n" && serve_file "$PH/$n" image/jpeg || bad;;
  /api/settings) hdr "200 OK"; if [ "$METHOD" = POST ]; then settings_set; else settings_get; fi;;
  /api/info)    ip=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1)
                [ -s "$STATE/token" ] || head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$STATE/token"
                hdr "200 OK"; printf '{"ip":"%s","port":8765,"token":"%s"}' "$ip" "$(token)";;
  /api/resettoken) head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$STATE/token"; hdr "200 OK"; echo '{"ok":true}';;
  /api/sysinfo) hdr "200 OK"
                printf '{"uptime":%s,"mem":' "$(cut -d. -f1 /proc/uptime)"
                awk '/^MemTotal/{t=$2}/^MemAvailable/{a=$2}/^SwapTotal/{st=$2}/^SwapFree/{sf=$2}END{printf "{\"totalMB\":%d,\"availMB\":%d,\"swapUsedMB\":%d}",t/1024,a/1024,(st-sf)/1024}' /proc/meminfo
                printf ',"procs":%s,"lg":%s}' "$(ls /proc | grep -c '^[0-9]')" "$(lun luna://com.webos.service.tv.systemproperty/getSystemInfo '{"keys":["modelName","firmwareVersion","sdkVersion"]}' || echo '{}')";;
  /api/lg/get)  cat=$(qget cat); keys=$(qget keys)
                case "$cat" in picture|sound|time|option|general|support|network|other|caption) ;; *) bad; exit 0;; esac
                printf %s "$keys" | grep -Eq '^[A-Za-z0-9_,]{1,900}$' || { bad; exit 0; }
                kj=$(printf %s "$keys" | sed 's/,/","/g')
                hdr "200 OK"; lun luna://com.webos.settingsservice/getSystemSettings "{\"category\":\"$cat\",\"keys\":[\"$kj\"]}";;
  /api/lg/set)  body_small
                case "$BODY" in *'"category":"picture"'*|*'"category":"sound"'*|*'"category":"time"'*|*'"category":"option"'*|*'"category":"general"'*|*'"category":"network"'*|*'"category":"other"'*|*'"category":"caption"'*) ;; *) bad; exit 0;; esac
                case "$BODY" in *systemPin*|*PinCode*|*[Pp]assword*|*IPControl*|*arental*|*actory*|*[Rr]eset*|*hotel*|*automaticUpdate*|*softwareUpdate*|*appUpdateMode*|*deviceName*|*screenSaverEnabled*) bad "403 Forbidden" "key not allowed"; exit 0;; esac
                hdr "200 OK"; lun luna://com.webos.settingsservice/setSystemSettings "$BODY";;
  /api/lg/open) # LG's own (legacy) Settings app, for what ours does not cover (Wi-Fi join, accounts). The hook lets it through for 25 s.
                echo $(( $(cut -d. -f1 /proc/uptime) + 25 )) > "$STATE/lgsettings.allow"
                hdr "200 OK"; LW=10000 lun luna://com.webos.applicationManager/launch '{"id":"com.palm.app.settings","params":{}}';;
  /api/settings/close) hdr "200 OK"; echo '{"ok":true}'; ( usleep 300000; sh "$D/settings-open.sh" close ) </dev/null >/dev/null 2>&1 &
                ;;
  /api/settings/launch) hdr "200 OK"; ( sh "$D/settings-open.sh" launch </dev/null >/dev/null 2>&1 & ); echo '{"ok":true}';;
  /api/qs)      # the patched compositor reports in (qspatch.sh): e=claim = "I opened / closed Settings myself", e=fail = it could not, anything else is just logged
                m=$(qget m | sed 's/%20/ /g; s/%3D/=/g' | tr -c 'A-Za-z0-9 _.:=,-' '?' | cut -c1-120)
                case "$(qget e)" in claim) up > /tmp/qs-claim;; loaded) touch "/tmp/qs-loaded-$(qget m | tr -cd 'A-Za-z')"; q=$(qget q | sed 's/%20/ /g; s/%3D/=/g' | tr -c 'A-Za-z0-9 _.:=,-' '?' | cut -c1-120); [ -n "$q" ] && log "qs: $q";; fail) log "qs: compositor launch failed: $m";; *) [ -n "$m" ] && log "qs: $m";; esac
                hdr "200 OK"; echo '{"ok":true}';;
  /api/qsdump)  # what the patched compositor found out about itself (kept in /tmp, read by hand)
                body_small 65536; n=$(qget n | tr -cd 'A-Za-z0-9_' | cut -c1-30); k=$(qget k | tr -cd '0-9' | cut -c1-4)
                if [ -n "$n" ] && [ -n "$k" ]; then printf '%s' "$(qget d)" > "/tmp/qs-dump-$n.$k"; elif [ -n "$n" ]; then printf '%s\n' "$BODY" > "/tmp/qs-dump-$n.txt"; fi
                hdr "200 OK"; echo '{"ok":true}';;
  /api/settings/open)hdr "200 OK"; sh "$D/settings-open.sh" open >/dev/null 2>&1; echo '{"ok":true}';;
  /api/gear)    if [ "$(qget v)" = lg ]; then touch "$STATE/gear-lg"; elif [ "$(qget v)" = ours ]; then rm -f "$STATE/gear-lg"; fi
                hdr "200 OK"; printf '{"gear":"%s","pointer":"%s","chain":"%s","back":%s}' "$([ -e "$STATE/gear-lg" ] && echo lg || echo ours)" "$([ -e "$STATE/pointer-off" ] && echo off || echo on)" "$([ -e "$STATE/backchain-off" ] && echo off || echo on)" "$(sh "$D/lastapp.sh" conf)";;
  /api/svc)     hdr "200 OK"; svc_json;;
  /api/svc/set) svc_set;;
  /api/guard)   hdr "200 OK"; timeout -t 60 sh "$D/debloat.sh" sweep </dev/null >/dev/null 2>&1; echo '{"ok":true}';;
  /api/block)   hdr "200 OK"; sh "$D/blocklist.sh" json;;
  /api/block/set) block_set;;
  /api/block/custom) block_custom;;
  /api/block/update) block_update;;
  /api/block/test) h=$(qget host | tr 'A-Z' 'a-z'); printf %s "$h" | grep -Eq '^[a-z0-9._-]{1,120}$' || { bad; exit 0; }
                hdr "200 OK"; printf '{"host":"%s","blocked":%s}' "$h" "$(grep -q "^0.0.0.0 $h\$" /etc/hosts && echo true || echo false)";;
  /api/reboot)  [ "$METHOD" = POST ] && { hdr "200 OK"; echo '{"ok":true}'; ( sleep 2; luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 ) & } || bad;;
  /api/log)     body_small; hdr "200 OK"; echo "$(up) page: $BODY" | cut -c1-600 >> /tmp/launcher-page.log
                [ "$(wc -c < /tmp/launcher-page.log)" -gt 100000 ] && tail -c 50000 /tmp/launcher-page.log > /tmp/launcher-page.log.t && mv /tmp/launcher-page.log.t /tmp/launcher-page.log
                echo '{"ok":true}';;
  *)            bad "404 Not Found" "not found";;
esac
