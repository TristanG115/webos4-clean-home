#!/bin/sh
# settings-open.sh open|toggle|close|status - our Settings as a transparent overlay web page (a second WAM page, like LG's own Settings app).
# The remote's Settings key is routed here by settings-hook.sh. The page is killed again when it closes, so it costs no memory while unused.
. /media/developer/tv-debloat/common.sh
is_open() { lun luna://com.webos.applicationManager/getForegroundAppInfo '{}' | grep -q "\"appId\": *\"$SET_ID\"" ||
            lun luna://com.webos.applicationManager/getForegroundAppInfo '{"extraInfo":true}' | grep -q "\"appId\": *\"$SET_ID\""; }
do_open() {
  APP=$(settings_appdesc); DIR=$(launcher_dir)
  r=$(LW=8000 lun luna://com.palm.webappmanager/launchApp "{\"appDesc\":$APP,\"parameters\":{},\"launchingAppId\":\"\",\"launchingProcId\":\"\",\"instanceId\":\"tv-debloat-settings\"}" | tr -d '\n')
  case $r in *'"returnValue": *true'*|*true*) log "settings overlay opened ($DIR)";; *) log "settings overlay refused: $(echo "$r" | cut -c1-160)";; esac
  echo "$r"
}
do_close() { lun luna://com.palm.webappmanager/killApp "{\"appId\":\"$SET_ID\"}" >/dev/null; }
case ${1:-toggle} in
  launch) do_open >/dev/null;;                       # no "is it open already" check: the hook tracks that itself (fast path)
  open)   is_open || do_open;;
  close)  do_close;;
  toggle) if is_open; then do_close; else do_open; fi;;
  status) is_open && echo open || echo closed;;
esac
