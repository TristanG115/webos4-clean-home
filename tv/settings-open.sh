#!/bin/sh
# settings-open.sh open|toggle|close|status - our Settings as a transparent overlay web page (a second WAM page, like LG's own Settings app).
# The remote's Settings key is routed here by settings-hook.sh. The page is killed again when it closes, so it costs no memory while unused.
. /media/developer/tv-debloat/common.sh
is_open() { lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | grep -q "\"appId\": *\"$SET_ID\"" ||
            lun luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' | grep -q "\"appId\": *\"$SET_ID\""; }
do_open() {
  DIR=$(launcher_dir); [ "$DIR" = "$D/launcher" ] && ensure_settings_html
  APP="{\"id\":\"$SET_ID\",\"version\":\"1.0.0\",\"vendor\":\"tv-debloat\",\"type\":\"web\",\"main\":\"settings.html\",\"title\":\"Settings\",\"visible\":false,\"transparent\":true,\"bgColor\":\"#00000000\",\"disableBackHistoryAPI\":true,\"lockable\":false,\"supportQuickStart\":false,\"defaultWindowType\":\"overlay\",\"trustLevel\":\"trusted\",\"folderPath\":\"$DIR\""
  [ -e "$D/DEBUG" ] && APP="$APP,\"inspectable\":true"
  APP="$APP}"
  r=$(LW=8000 lun luna://com.palm.webappmanager/launchApp "{\"appDesc\":$APP,\"parameters\":{},\"launchingAppId\":\"\",\"launchingProcId\":\"\",\"instanceId\":\"tv-debloat-settings\"}" | tr -d '\n')
  case $r in *'"returnValue": *true'*|*true*) log "settings overlay opened ($DIR)";; *) log "settings overlay refused: $(echo "$r" | cut -c1-160)";; esac
  echo "$r"
}
do_close() { lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$SET_ID\"}" >/dev/null; }
case ${1:-toggle} in
  open)   is_open || do_open;;
  close)  do_close;;
  toggle) if is_open; then do_close; else do_open; fi;;
  status) is_open && echo open || echo closed;;
esac
