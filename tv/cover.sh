#!/bin/sh
# cover.sh show|hide|status - our own "starting up" screen while the TV boots, so LG's Home (with its promotions) is not what you see.
# It is a tiny standalone page (launcher/cover.html: no app code, no images) shown as an opaque overlay and killed again the moment our Home is ready (home-on.sh), when
# boot.sh ends, or by the page itself after 80 s. It costs a few MB for under a minute, once per boot.
# It is only shown when LG's Home is what would be on screen (nothing or Home in front): if the TV came up on an HDMI input or an app, the cover stays away.
# Off switch: Settings -> Services & privacy -> "Show our own start-up screen" (flag state/cover-off). Never shown when DISABLE exists.
. /media/developer/tv-debloat/common.sh
ID=$COVER_ID
case ${1:-status} in
  show) [ -e "$STATE/cover-off" ] && exit 0; [ -e "$D/DISABLE" ] && exit 0
        [ -f "$D/launcher/cover.html" ] || exit 0
        fg=$(lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p' | head -1)
        case "$fg" in ''|com.webos.app.fullhome|com.webos.app.home|com.webos.app.splash) ;; *) log "cover: not shown ($fg is in front)"; exit 0;; esac
        printf '{"appDesc":%s,"parameters":{},"launchingAppId":"","launchingProcId":"","instanceId":"tv-debloat-cover"}' "$(cover_appdesc)" > /tmp/cover-launch.json
        r=$(LW=8000 lun luna://com.palm.webappmanager/launchApp "$(cat /tmp/cover-launch.json)" | tr -d '\n'); rm -f /tmp/cover-launch.json
        case $r in *true*) touch /tmp/cover-on; log "cover: shown (uptime $(up))";; *) log "cover: refused $(echo "$r" | cut -c1-120)";; esac;;
  hide) if [ -e /tmp/cover-on ]; then lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$ID\"}" >/dev/null; rm -f /tmp/cover-on; log "cover: hidden (uptime $(up))"; fi;;
  status) [ -e /tmp/cover-on ] && echo shown || echo hidden;;
esac
