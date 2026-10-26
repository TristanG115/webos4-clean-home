#!/bin/sh
# api.sh - ONE HTTP request on stdin/stdout, started per connection by:
#     tcpsvd -c 6 0.0.0.0 8765 timeout -t 120 sh api.sh
# Two trust levels (tcpsvd provides TCPREMOTEADDR=ip:port):
#   LOCAL (127.0.0.1, the launcher page on the TV): full whitelist below, no token.
#   LAN   (your phone): ONLY the phone page and the photo/settings routes under / /m/* /photos/*, and only with ?t=<secret token>
#         (the token is in the QR code shown on the TV; Settings -> Gallery -> "Reset phone link" makes a new one).
. /media/developer/tv-debloat/common.sh
PH=$D/launcher/photos
SETF=$STATE/settings.json
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
body_small() { BODY=""; [ "$CL" -gt 0 ] && [ "$CL" -lt 8192 ] && BODY=$(head -c "$CL"); }
ok_id() { printf %s "$1" | grep -Eq '^[A-Za-z0-9._-]{1,80}$'; }
ok_photo() { printf %s "$1" | grep -Eq '^[A-Za-z0-9_-]{1,40}\.jpg$'; }
token() { cat "$STATE/token" 2>/dev/null; }
token_ok() { t=$(token); [ -n "$t" ] && [ "$(qget t)" = "$t" ]; }
serve_file() { # path content-type
  [ -f "$1" ] || { bad "404 Not Found" "not found"; return; }
  printf 'HTTP/1.0 200 OK\r\nContent-Type: %s\r\nContent-Length: %s\r\nCache-Control: max-age=600\r\nConnection: close\r\n\r\n' "$2" "$(wc -c < "$1")"; cat "$1"; }
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
do_delete() { n=$(qget name); ok_photo "$n" || { bad; return; }; rm -f "$PH/$n" "$PH/thumbs/$n"; hdr "200 OK"; echo '{"ok":true}'; }

# ---------------- LAN (phone) ----------------
if [ $LOCAL = 0 ]; then
  case "$P" in
    /)             hdr "200 OK" "text/html; charset=utf-8"; cat "$D/launcher/phone.html";;
    /m/photos)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; hdr "200 OK"; photos_json;;
    /m/upload)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && do_upload || bad;;
    /m/delete)     token_ok || { bad "403 Forbidden" "token"; exit 0; }; [ "$METHOD" = POST ] && do_delete || bad;;
    /m/settings)   token_ok || { bad "403 Forbidden" "token"; exit 0; }; hdr "200 OK"; if [ "$METHOD" = POST ]; then settings_set; else settings_get; fi;;
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
  /api/photos)  hdr "200 OK"; photos_json;;
  /api/delete)  do_delete;;
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
                case "$cat" in picture|sound|time|option|general) ;; *) bad; exit 0;; esac
                printf %s "$keys" | grep -Eq '^[A-Za-z0-9_,]{1,400}$' || { bad; exit 0; }
                kj=$(printf %s "$keys" | sed 's/,/","/g')
                hdr "200 OK"; lun luna://com.webos.settingsservice/getSystemSettings "{\"category\":\"$cat\",\"keys\":[\"$kj\"]}";;
  /api/lg/set)  body_small
                case "$BODY" in *'"category":"picture"'*|*'"category":"sound"'*|*'"category":"time"'*|*'"category":"option"'*|*'"category":"general"'*) ;; *) bad; exit 0;; esac
                case "$BODY" in *[Pp]in*|*[Pp]assword*|*IPControl*|*arental*|*actory*|*eset*|*lock*) bad "403 Forbidden" "key not allowed"; exit 0;; esac
                hdr "200 OK"; lun luna://com.webos.settingsservice/setSystemSettings "$BODY";;
  /api/reboot)  [ "$METHOD" = POST ] && { hdr "200 OK"; echo '{"ok":true}'; ( sleep 2; luna-send -n 1 -w 5000 luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}' </dev/null >/dev/null 2>&1 ) & } || bad;;
  /api/log)     body_small; hdr "200 OK"; echo "$(up) page: $BODY" | cut -c1-600 >> /tmp/launcher-page.log
                [ "$(wc -c < /tmp/launcher-page.log)" -gt 100000 ] && tail -c 50000 /tmp/launcher-page.log > /tmp/launcher-page.log.t && mv /tmp/launcher-page.log.t /tmp/launcher-page.log
                echo '{"ok":true}';;
  *)            bad "404 Not Found" "not found";;
esac
