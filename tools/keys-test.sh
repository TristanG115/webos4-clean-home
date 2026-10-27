#!/bin/sh
# keys-test.sh - end-to-end test of the remote-key features WITHOUT touching the remote. Runs ON the TV:   ./tv.sh -s < tools/keys-test.sh
# It injects the same things the remote produces: a KEY_BACK evdev event pair written to /dev/input/event1 (the IR remote's device, 16-byte input_event,
# code 158) and the lginput2 log line for KEY_SETTINGS (appended to /var/log/messages). It opens HDMI 2 / Netflix, so run it when nobody is watching.
# Covers: Settings key opens our overlay and LG's panel is closed; the key toggles; Back from an app that quits returns to the previous app; Back on Home does too
# (that last one through its API call; the physical Back key on Home is one of the things only a human can check); Back while an app is still on its splash screen cancels the launch;
# the 'keep 2 apps in memory' rule closes the oldest app.
D=/media/developer/tv-debloat; LOG=/var/log/messages; export PATH=/usr/bin:/usr/sbin:/bin:/sbin:$PATH
pass=0; fail=0
ok()  { echo "PASS $*"; pass=$((pass+1)); }
bad() { echo "FAIL $*"; fail=$((fail+1)); }
L()  { luna-send -n 1 -w 8000 luna://com.webos.applicationManager/launch "{\"id\":\"$1\"}" </dev/null >/dev/null 2>&1; }
FG() { luna-send -n 1 luna://com.webos.applicationManager/getForegroundAppInfo '{}' </dev/null | sed -n 's/.*"appId" *: *"\([^"]*\)".*/\1/p'; }
BACK() { printf '\0\0\0\0\0\0\0\0\1\0\236\0\1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\1\0\236\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0' > /dev/input/event1; }
GEAR() { echo '2026-01-01T00:00:00.000000Z [1.1] user.info lginput2 [] lginput2 NL_BUTTON_CLICK {"remote_type":"LGE MR19","button_type":"KEY_SETTINGS"}' >> $LOG; usleep 500000; luna-send -n 1 luna://com.webos.surfacemanager/showQuickSettings '{}' </dev/null >/dev/null; }
last_vis() { grep "NL_VSC" $LOG 2>/dev/null | grep "\"app_id\":\"$1\"" | tail -1 | grep -o '"visible":[a-z]*' | cut -d: -f2; }
wait_vis() { i=0; while [ $i -lt 12 ]; do [ "$(last_vis $1)" = "$2" ] && return 0; sleep 1; i=$((i+1)); done; return 1; }
[ -e $D/state/backchain-off ] && echo "note: Back chain is switched off in Settings; tests B and C will fail"
sh $D/settings-hook.sh status | grep -q running && ok "Settings hook is running" || bad "Settings hook is not running"
sh $D/backchain.sh status | grep -q running && ok "Back-chain watcher is running" || bad "Back-chain watcher is not running"
sh $D/settings-open.sh close >/dev/null 2>&1; sleep 2; rm -f /tmp/gear-claim
echo "== A. Settings key"
GEAR; wait_vis tv.debloat.settings true && ok "our Settings overlay opened" || bad "our Settings overlay did not open"
wait_vis com.webos.app.quicksettings false && ok "LG's quick panel was closed" || bad "LG's quick panel stayed open"
GEAR; wait_vis tv.debloat.settings false && ok "pressing the key again closed our overlay" || bad "second press did not close our overlay"
sleep 2; luna-send -n 1 luna://com.webos.service.systemUIManager/closeByAppId '{"appId":"com.webos.app.quicksettings"}' </dev/null >/dev/null; sleep 2
echo "== B. Back from an app that quits"
L com.webos.app.hdmi2; sleep 4; L netflix; sleep 6
BACK; usleep 300000; L com.webos.app.fullhome; sleep 8
[ "$(FG)" = com.webos.app.hdmi2 ] && ok "Netflix quit with Back -> previous app (HDMI 2) opened" || bad "expected HDMI 2, foreground is $(FG)"
echo "== C. Back on Home"
L com.webos.app.fullhome; sleep 5
# the page turns Back (keyCode 461) into this API call (goBack() in app.js); an evdev-injected key does not reach the Home page reliably, so the call is made directly
curl -s -m 10 http://127.0.0.1:8765/api/back >/dev/null; sleep 6
[ -n "$(FG)" ] && [ "$(FG)" != com.webos.app.fullhome ] && ok "Back on Home (/api/back) -> last app opened ($(FG))" || bad "expected the last app, foreground is $(FG)"
L com.webos.app.fullhome; sleep 3
echo "== D. Back while an app is still loading (splash up) cancels the launch"
luna-send -n 1 luna://com.webos.applicationManager/closeByAppId '{"id":"netflix","forceMode":true}' </dev/null >/dev/null 2>&1; sleep 3      # a resident app comes to the front at once, so it must be cold
L netflix; usleep 300000
[ -s /tmp/launching ] && ok "launch tracked: $(cat /tmp/launching)" || bad "no launch tracked after starting Netflix (lastapp.sh not running?)"
BACK; sleep 3
[ "$(FG)" = com.webos.app.fullhome ] && ok "Back during the splash -> back on Home" || bad "expected Home, foreground is $(FG)"
sleep 3; luna-send -n 1 luna://com.webos.applicationManager/running '{}' </dev/null | grep -q '"id": *"netflix"' && bad "the loading app was not closed" || ok "the loading app was closed"
L com.webos.app.fullhome; sleep 2
echo "== E. Only the app in front and the last one stay in memory (keep 2)"
sh $D/lastapp.sh conf keep 2; sh $D/lastapp.sh clear test
L com.webos.app.hdmi2; sleep 5; L com.webos.app.fullhome; sleep 2; L netflix; sleep 8; L com.webos.app.fullhome; sleep 2; L youtube.leanback.v4; sleep 9
run=$(luna-send -n 1 luna://com.webos.applicationManager/running '{}' </dev/null | tr -d '
 ')
echo "$run" | grep -q '"id":"com.webos.app.hdmi2"' && bad "HDMI 2 (the oldest) is still in memory" || ok "the oldest app (HDMI 2) was closed"
echo "$run" | grep -q '"id":"youtube.leanback.v4"' && ok "the app in front (YouTube) is in memory" || bad "YouTube is not running"
L com.webos.app.fullhome; sleep 3
echo "RESULT: $pass passed, $fail failed"
[ $fail = 0 ] && echo "ALL KEY TESTS PASSED"
