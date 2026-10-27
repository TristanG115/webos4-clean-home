# CHANGES.md - everything done to the TV (10.0.0.63) and how to undo it

Quick undo, in order of preference:

1. **`./revert.sh`** from this folder (or `ssh root@10.0.0.63 sh /media/developer/tv-debloat/revert.sh`).
   Puts LG's Home back, undoes every debloat item, renames the init hook, creates the `DISABLE` flag, reboots.
   `--no-reboot` skips the reboot. Works the same over Telnet (`telnet 10.0.0.63`, no password).
2. **Delete/rename one file and reboot:** `/var/lib/webosbrew/init.d/zz-debloat`
   (or `touch /media/developer/tv-debloat/DISABLE` - boot then does nothing).
3. **Automatic:** the launcher hands Home back to LG's if it has not reported ready within 30 s of being started, or if its
   local API is dead for 60 s. Four unfinished boots in a row create `DISABLE` by themselves.
4. LG factory reset (last resort; also removes root).

`revert.sh` was tested as a no-op before the first real change: system state (hosts, mounts, Upstart jobs, LG prefs, init.d,
processes) was byte-identical before and after (`results/snap-*-revert-test.txt`).

## What is installed on the TV

| What | Where | Undo |
|---|---|---|
| SSH public key of this PC | `/home/root/.ssh/authorized_keys` (+ dir, mode 700/600) | delete the file, reboot (Homebrew then restores the `alpine` password) |
| All our scripts, the launcher page, photos, backups, logs | `/media/developer/tv-debloat/` | `revert.sh` leaves them (inert); `rm -r` them if you want them gone |
| Boot hook (the ONE init script) | `/var/lib/webosbrew/init.d/zz-debloat` | `revert.sh` renames it to `zz-debloat.disabled` |
| Backups of files a change could touch | `/media/developer/tv-debloat/backup/` (`general`, `option`, `hosts`, 3 Upstart confs) | - |

`/media/developer/tv-debloat/` layout: `boot.sh` (started by the hook), `debloat.sh`, `home-on.sh`, `home-off.sh`,
`home-standin.sh`, `api.sh`, `common.sh`, `revert.sh`, `launcher/` (index.html, appinfo.json, photos/), `state/` (log, flags), flags
`DISABLE` (everything off) and `DEBUG` (launcher page inspectable via DevTools - remove the file to close that).

## Runtime changes (RAM only - a reboot without the init hook removes all of them)

| # | Change | Command (run by `debloat.sh apply <item>` / `home-on.sh`) | Undo (`debloat.sh undo <item>` / `home-off.sh`) |
|---|---|---|---|
| 2 | Ad servers blocked in the RAM hosts file | `echo "127.0.0.1 us.ad.lgsmartad.com us.info.lgsmartad.com nl.ad.lgsmartad.com nl.info.lgsmartad.com eic.ads.lgtvcommon.com media.bidr.io # tv-debloat" >> /etc/hosts` (+ `::1` line) | remove lines containing `# tv-debloat` |
| 3 | `remotelogger` stopped | `initctl stop remotelogger` | `initctl start remotelogger` |
| 4 | `nudge` stopped | `initctl stop nudge` | `initctl start nudge` |
| 5 | `contentminer` stopped | `initctl stop contentminer` | `initctl start contentminer` |
| 7 | `admanager` replaced by a do-nothing stub | `mount --bind /media/developer/tv-debloat/stub-noop /usr/sbin/admanager`, kill running copy | `umount /usr/sbin/admanager` |
| 1 | LG's own toggles (persisted by LG's settings service) | `luna-send .../com.webos.settingsservice/setSystemSettings {"category":"general","settings":{"homePromotion":"off","aiNudge":"off","adCookie":"off","personalRecommend":{"changedByUser":true,"value":"off"}}}` | same call with the originals: `homePromotion on, aiNudge on, adCookie on, personalRecommend {changedByUser:false,value:on}` |
| L | LG's screensaver off while the launcher is Home (ours replaces it) | `setSystemSettings {"category":"general","settings":{"screenSaverEnabled":"off"}}` | `screenSaverEnabled: "on"` (done by `home-off.sh`) |
| H | LG's Home replaced by the launcher | `mount --bind home-standin.sh /usr/bin/com.webos.app.fullhome`; kill LG's Home once; SAM starts the stand-in, which asks the web app manager to open `launcher/` as `com.webos.app.fullhome` (`luna://com.palm.webappmanager/launchApp`) | kill stand-in, `umount /usr/bin/com.webos.app.fullhome`, `killApp`, relaunch LG Home |
| A | Local API for the launcher **and the phone page** | `tcpsvd -c 6 0.0.0.0 8765 timeout -t 120 sh api.sh`. Loopback: apps list, launch by id, network status, LG settings get/set (whitelisted categories), settings/photos/delete, ready/log pings. **LAN: only the phone page and photo/settings routes, only with the secret token** (see README, security model) | kill `tcpsvd` |

Not touched (as agreed): Homebrew Channel, "block system updates", SSH/Telnet settings, networking, inputs, Settings, the remote,
`acr2` (Live Plus was already off), `rdxd`/`uploadd`/`crashreportd` (Homebrew already neuters them), voice, AirPlay, casting.

## Experiments that were cleaned up
- Test web app `com.tristan.hometest` (WAM-launched, folders under `/media/developer/tv-debloat/launcher-test` and
  `/media/developer/apps/usr/palm/applications/com.tristan.hometest`) - both folders removed, app killed.
- A throwaway Python log receiver in `/tmp` (removed).
- Benchmarks and health checks opened and closed Settings, YouTube, Netflix and HDMI 1 several times.

## Read-only things that were run
`tv-inspect.sh`, `tv-inspect-2.sh`, process/mount/log inspection, `listLaunchPoints`, `running`, `getForegroundAppInfo`,
`getSystemSettings`; DNS lookups of the ad hostnames against the TV's resolver.

## Chronology of the real changes
1. Generated `~/.ssh/id_ed25519` on the PC; installed the public key on the TV (one password login with Homebrew's default).
2. Deployed scripts to `/media/developer/tv-debloat/`; saved backups; **tested `revert.sh` as a no-op**.
3. Applied, one at a time, each followed by the health check (`tools/check.sh`: Settings, Home, Netflix, HDMI 1 all open): hosts → remotelogger → nudge → contentminer → admanager stub → LG toggles. All passed.
4. Home takeover test (runtime), cold-start test, Inputs panel, screensaver, Home-key relaunch.
5. Installed `zz-debloat`; rebooted; verified everything came back unattended (launcher ready 57 s after boot start).

## Added in round 2 (gallery, phone page, new Settings, more services)

| What | Where / command | Undo |
|---|---|---|
| Voice stack stopped (remote mic button, voice search) | `initctl stop voiceinput voiceconductor`; stub bind-mount over `/usr/sbin/nlpmanager` (`debloat.sh apply voice`) | `debloat.sh undo voice` |
| ThinQ / IoT and HomeKit helpers stopped | stub bind-mounts over `/usr/sbin/iot-client`, `ocf-onboarding`, `homekit`; kill `ocf_memcheck.sh` (`debloat.sh apply iot`) | `debloat.sh undo iot` |
| Tips app closed (LG keeps it resident) | `closeByAppId` + WAM `killApp` on `com.webos.app.tips` (`debloat.sh apply idleapps`); it starts again if opened | nothing to undo |
| Launcher settings (weather location/ZIP, units, screensaver, background, clock) | `/media/developer/tv-debloat/state/settings.json`, written by the launcher or the phone page | delete the file |
| Photo gallery | `/media/developer/tv-debloat/launcher/photos/` (+ `thumbs/`): your photos, resized on the PC or cropped on the phone | delete the folder contents |
| Phone link token | `state/token` (96-bit random) | *Settings -> Photo gallery -> Reset phone link* or delete the file (a new one is created) |
| LG settings written **only when you change them in our Settings screen** | picture (mode, backlight, contrast, brightness, color, sharpness, energy saving), sound (mode, Clear Voice, auto volume, virtual surround), power (Quick Start, Home on power-on, standby light, logo light, no-signal auto-off) via `com.webos.settingsservice/setSystemSettings` | change them back in our screen or LG's Settings; values are never changed by the install itself |

Tried and **dropped** (no measurable benefit): `sysctl vm.swappiness=30` (reverted to 100); killing the Google Assistant web app (LG's preload manager relaunches it every ~20 s).
Not touched on purpose: AirPlay, casting, the on-screen keyboard (`MaliitServer`), `inputcommon` (the Input key), LG's CRIU app preloading.

Verified for this round: full `revert.sh --no-reboot` returned hosts, mounts, Upstart jobs, LG toggles and init.d to the stock snapshot; reboot with the init hook re-applied everything
unattended (launcher ready 60 s after boot start); `tools/check.sh`, the 30 s ready-timeout fallback, the crash-loop guard and the API self-heal all passed (`results/safety-test-2.txt`).

## Added in round 3 (2026-10-26: speed, services switches, ad lists, our Settings on the remote, photo framing)

| What | Where / command | Undo |
|---|---|---|
| Launcher code runs from RAM | `/tmp/tv-launcher` (copy made by `home-on.sh`; photos bind-mounted in); WAM loads that folder, flash copy is the fallback | `home-off.sh` / reboot (tmpfs); `revert.sh` removes it |
| LG app pre-loading trimmed | `preloadmanager/setPreloadPolicy` isEnabled false for Assistant, Browser, Tips, Vudu, Amazon, Pooq (originals in `state/preload.orig`) | `debloat.sh undo preload` or reboot |
| Idle LG apps closed | Tips / Assistant / Browser killed when resident (`debloat.sh apply idleapps`) | none needed (start on demand) |
| LG updates blocked and locked | `support.automaticUpdate=off`, `option.appUpdateMode=manual`, hosts `snu.lge.com snu-dev.lge.com su.lge.com su-dev.lge.com su-ssl.lge.com nsu.lge.com` (`# tvd-update`), `initctl stop update`; re-checked every 5 min | `debloat.sh undo updates` (revert.sh does it); Homebrew's own hosts block stays |
| Services catalog with switches | `services.tsv`, `state/svc.conf`; Settings -> Services & privacy; `epg` (TV guide downloader) available, off by default | switch off in Settings, or `debloat.sh undo <item>` |
| Pi-hole style ad blocking | `blocklist.sh`: hosts block between `# tv-debloat begin/end` (about 4,400 names by default, cap 9,000), lists in `blocklists/`, downloads in `state/lists/`, your lists `state/block-custom.txt` / `block-allow.txt`; remote lists refresh weekly | `blocklist.sh remove` (also `debloat.sh undo hosts`) |
| Remote Settings key opens our Settings | `settings-hook.sh` (log watcher, started by `home-on.sh`), `settings-open.sh` (overlay page `tv.debloat.settings`) | `settings-hook.sh stop`, or Settings -> Remote -> "Settings button opens: LG's quick panel" (`state/gear-lg`) |
| LG Settings values written from our screens, now with correct value sets | Picture, Sound, Power & timers, Inputs, Accessibility, Network, Remote pages (about 90 keys, all re-tested with `tools/lg-settings-test.sh`: 91 accepted) | change back in our screen |
| Photo framing (x, y, zoom, edge colours) | `state/crops/NAME.json`, edited on the TV or the phone page; photos stored whole | Settings -> Photo -> Adjust framing -> Reset to automatic |

Bug fixes: Clear Voice sent `on` (valid: `off/level1/level2/level3`), Sound mode offered invalid `cinema/clearVoice`, LG logo light sent `on` (valid: `off/low/medium/high`). During the tests Clear Voice was set to level 2 once and put back to Off.
Quick Start was already on (`option.quickStartMode`), left on; it is a normal power state and does not conflict with the init hook (nothing re-runs on wake; RAM-only changes stay).
Tried and dropped: hiding the Magic Remote pointer through `com.webos.service.mrcu/activateMotionSensor {"activate":false}`: the TV accepts it, the arrow still appears (tested with the owner's remote). Not offered in the UI.
A mistake worth remembering: full-size photos (3.6 MP) made the Home page grow to 152 MB and the TV swap until SSH timed out; stored photos are now capped to 2.6 MP and Home frees its background during the screensaver.
Measured (`tools/bench-quick.sh`, 3 reps, `results/before-r3.txt` vs `after-r3.txt`): YouTube cold open median 2512 -> 1284 ms; Netflix 1498 -> 1679 ms (noise); Home 1232 -> 1214 ms; RAM available and swap about the same. The RAM copy gives no measurable Home start gain (flash was already in page cache); the pre-loading trim helps app launches.
`tools/safety-test.sh` (results/safety-test-3.txt): API watchdog and crash-loop guard pass; test A now ends at the "no launcher files" early exit. `tools/check.sh`: ALL CHECKS PASSED (includes our Settings overlay).

## Added in round 4 (2026-10-26: Back on Home, pointer switch)

| What | Where / command | Undo |
|---|---|---|
| Back on Home returns to the last app / input | `lastapp.sh` (subscribes to SAM `getForegroundAppInfo`, keeps the newest non-Home app in `/tmp/lastapp`), `api.sh /api/back`, `goBack()` in `app.js` (keys 461 / Esc / Backspace on Home when nothing is open). Started by `home-on.sh` and the 5-min sweep | `lastapp.sh stop` (also done by `home-off.sh` / `revert.sh`); RAM only |
| Back from an app returns to the previous app (Home if none) | `backchain.sh` + `keywatch.py` (read-only reader of the remote's evdev devices, reports KEY_BACK), history in `/tmp/appstack` kept by `lastapp.sh` (closed apps skipped). After Back, if the app quit and Home is in front 2 s later, the previous entry is launched. Switch: Settings -> Remote & pointer, flag `state/backchain-off`, `/api/backchain` | switch off in Settings, or `backchain.sh stop` (also `home-off.sh` / `revert.sh`); RAM only |
| Experimental pointer switch (Settings -> Remote & pointer -> "Pointer only when I shake the remote") | `pointer.sh off|on`: `mrcu/cursor/setWakeUpCondition {"condition":"shake"}` + `activateMotionSensor {"activate":false}`, re-applied by a 10 s watcher whenever the remote reconnects; flag `state/pointer-off`; `/api/pointer` | switch it off in Settings, or `sh pointer.sh on`; `revert.sh` runs it; a TV restart also resets it |

Verified: foreground tracking (hdmi2 -> Home -> `/api/back` returned to hdmi2), injected Back key (461) on the real Home page returned to hdmi2, `pointer.sh off/on` round trip with the remote asleep (flag + watcher start/stop), `tools/check.sh`: ALL CHECKS PASSED.
**Not verified:** whether the shake setting actually stops the arrow showing (the remote was asleep, so the TV could not accept the request during testing), and the physical remote's Back key (only an injected 461 was tested).

Back chain verified with injected Back key events written to the IR remote's evdev device (`/dev/input/event1`, 16-byte input_event, KEY_BACK=158): app quits to Home -> previous app opens; app keeps the key -> nothing; nothing before it -> stays on Home; switch off -> Home. Pointer switch was turned ON at the owner's request (2026-10-26); applies when the remote wakes. Physical remote not tested by the agent.

## Round 5 (2026-10-26): Settings key speed, icon rail Settings, quick-settings parity, screensaver dimming, pointer parking

| What | Where / command | Undo |
|---|---|---|
| Settings key handled earlier and LG's panel closed with the call that works | `settings-hook.sh` now starts on lginput2's `NL_BUTTON_CLICK KEY_SETTINGS` log line (about 0.5 s before LG's panel is drawn), opens our overlay at once (`settings-open.sh launch`, no "is it open" round trips; `/tmp/set-vis` tracks our overlay from its visible/hidden log events, `/tmp/gear-claim` marks the press) and closes LG's panel with `luna://com.webos.service.systemUIManager/closeByAppId {"appId":"com.webos.app.quicksettings"}`. The old call (`com.webos.surfacemanager/closeByAppId`) answers "This API is not supported", so LG's panel used to stay until our overlay took focus | `settings-hook.sh stop`, or Settings -> Remote -> Settings button opens LG's panel |
| Settings = icon rail | `index.html` (`#settings` is a 10 rem rail, `.open` unfolds the pane), `app.js` (`paneOpen`, `openPane`, `paneSet`, keys: OK/Right unfold, Back folds, Back on the folded rail closes). Mouse hover/click on rail icons and rows | revert the commit |
| "Quick settings" category (first icon) | Same shortcuts as LG's quick panel (read from its QML, `/usr/lib/qt5/qml/QuickSettings/QuickSettings.qml`): picture mode, aspect ratio, sound mode, sound out, sleep timer, network, all settings | - |
| Screensaver dimming | `saver.dim` (0-80 %, default 45), a black layer (`#sdim`) under the clock; Settings -> Home & Screensaver. It dims the picture, not the TV backlight | set it to 0 |
| Pointer parked | `pointer.sh` also calls `mrcu/cursor/setPosition 1919,1079` (arrow cut off in the corner); the scroll wheel wakes the arrow where it last was. UNVERIFIED (remote asleep during tests) | `pointer.sh on` |

Facts: LG's quick panel is not a process; it lives in surface-manager (QML), preloaded at boot by `/usr/lib/qt5/qml/KeyFilters/appLaunch.js`, which launches it through `systemUIManager /launch` on `Key_webOS_Settings`; a QML replacement would need a surface-manager restart (not done on purpose). `getForegroundAppInfo` does not list overlays. Load average on the dev TV is about 30 (swap), which adds about 1 s of latency to every luna call.

## Round 5b (2026-10-26): app updates, system updates locked harder

| What | Where / command | Undo |
|---|---|---|
| Apps update themselves (no "update this app?" prompt) | `appupdate.sh`: sets `option.appUpdateMode=auto` (LG's own auto-update; our old `updates` item forced `manual`), lists installed apps + waiting updates (`com.webos.appUpdateService/statusAll`), "check now" = an activity-manager activity whose callback is `appUpdateService/check` (that method answers only to activitymanager). `home-on.sh` asks 3 min after start and every 6 h; Settings -> **App updates** (toggle, check now, installed apps with versions); API `/api/appupdates[/mode|/check]` | Settings -> App updates -> off, or `sh appupdate.sh mode manual` (remembered in `state/appupdate-manual`) |
| System (firmware) updates: fifth layer | `debloat.sh updates` now also bind-mounts a do-nothing stub over `/usr/sbin/update` (the `com.webos.service.update` program), so nothing can start it; status shows `BLOCKED (4/4)`; the API already refuses `automaticUpdate`/`appUpdateMode`/`softwareUpdate` keys; the 5-min sweep re-applies all of it | `debloat.sh undo updates` (revert.sh does it) |

Verified: mode switch, check request accepted, API routes, stub mounted, `tools/check.sh` ALL CHECKS PASSED. NOT verified: that an update actually installs. On the dev TV two apps (Peacock 6.4.202, Prime Video 4.5.25) stay in `statusAll` with status `Y` and unchanged versions 90 s after a check in auto mode, with and without our hosts block, so either those are not real updates (the meaning of `Y` is unknown) or the store does not deliver to this TV. Facts: all 13 user apps carry `checkUpdateOnLaunch:true` (the source of the prompt); `appUpdateService/check` needs `$activity.activityId`; `luna-send -a` cannot fake the caller id.

## Round 6 (2026-10-26): portability, rootless pack, audit, README

| What | Where / command | Undo |
|---|---|---|
| TV address in one git-ignored file | `tv.conf` (`TV_IP`, `TV_USER`), read by `tv-env.sh`; `tv.sh`, `revert.sh`, `tools/deploy.sh`, `tools/cdp.js`, `tools/preview.js` no longer hard-code an address | PC-side only |
| Guided installer + read-only compatibility report | `install.sh <ip> [--check] [--yes]`, `tools/diagnose.sh` | PC-side; each install stage prints its own undo |
| Rootless pack | `rootless/README.md`, `tools/export-blocklist.js` (dist/ lists for Pi-hole/AdGuard/hosts), `tools/make-ipk.js` + `tv/launcher/rootless.js` (experimental dev-mode app; one hook line in `xhr()` in `app.js`, inactive on the rooted TV) | PC-side only |
| LG's unused stock Home no longer pre-loaded | `debloat.sh` `PRELOAD_OFF` + `com.webos.app.home` (runtime preload policy; original flag saved in `state/preload.orig`) | `debloat.sh undo preload` |
| Key test without the remote | `tools/keys-test.sh` (injects evdev KEY_BACK and the KEY_SETTINGS log line): 7/7 passed | - |
| Audit and README | `docs/AUDIT.md` (measurements, findings, 17-item backlog), `README.md` (summary, pictures, features, performance, install), `docs/images/` (10 pictures made with `PV_PUBLIC=1`, each looked at before committing) | - |
| Agent rules | `AGENTS.md` / `CLAUDE.md`: commit incrementally with a detailed log, push once at the end of a task | - |

TV-side runtime effect of this round: only the preload policy for `com.webos.app.home`. `tools/check.sh`: ALL CHECKS PASSED after it.

## Round 7 (2026-10-26): real backlight dimming in the screensaver

| What | Where / command | Undo |
|---|---|---|
| Screensaver lowers the TV's REAL backlight | `tv/backlight.sh dim <pct>|hold|restore|sweep|status`: sets `picture.backlight` (percent of its value, floor 5) for the picture context active when the screensaver starts (Home = input "default"), remembers value + context in `state/backlight.orig` / `.dim`. Settings -> Home & Screensaver -> **Screensaver backlight** (default 50 %, 100 = off) and **Screensaver dimming** (software layer, default now 30 %). API `/api/backlight` | set the slider to 100; `sh backlight.sh restore` |
| Five independent ways back to full backlight | page on wake (`blRestore`), `lastapp.sh` when anything but Home comes to the front, `boot.sh` at boot, the watchdog sweep (marker `/tmp/saver-on` older than 3 min), `home-off.sh`/`revert.sh` | - |

Verified on the TV: dim 100 -> 40 -> restore; sweep restores when the marker is gone and leaves a fresh dim alone; floor (1 % -> 10 % of 100); switching to HDMI 2 restores Home's own context (LG keeps backlight per input: the first version restored into the wrong context, fixed by storing the dimension). Note: the dim is NOT visible to me; whether it looks right is for you to judge.

## Round 7b: app updates in the background, controlled from Settings

| What | Where / command | Undo |
|---|---|---|
| Quiet background check on start and then every N hours | `appupdate.sh due` (cheap, no luna call) asked by the launcher watchdog every 20 s: once per boot 30 s after the launcher is ready (`startup=on`), then every `every` hours (default 6, 0 = never); manual mode never checks. Settings -> App updates: **Update apps automatically**, **Check when the TV starts**, **Then check every**, **Check for app updates now**. State `state/appupdate.conf`, API `/api/appupdates/conf?k=startup|every&v=` | Settings, or edit `state/appupdate.conf` |

Verified: conf get/set through the API, `due` for boot-like, just-checked, 4 h-ago/3 h and 6 h cases. The list label changed from "Updates waiting" to "Flagged by LG": Peacock and Prime Video have been flagged (`status:"Y"`) for over four hours with unchanged versions, so that list is not proof that an update exists.

## Round 7c: LG's quick panel switched off inside the compositor, pointer attempts, wheel and click support

| What | Where / command | Undo |
|---|---|---|
| LG's quick panel never opens; scroll-wheel pointer key and mouse events switched off (best effort) | `tv/qspatch.sh` (services item `qspatch`, default on, group "Remote & Settings"): patched copies of `/usr/lib/qt5/qml/KeyFilters/appLaunch.js` (`openSettings` returns at once) and `systemUi.js` (`compositor.mouseEventEnabled=false` in `init()`, `Key_webOS_CursorShow` swallowed in three handlers, all try/catch) generated on the TV from its own files into `/tmp/keyfilters-patched`, bind-mounted, `initctl restart surface-manager` (about 10 s black), health check, automatic rollback, 180 s reboot watchdog, `state/qspatch.trying` boot guard | Settings -> Services & privacy switch, `sh qspatch.sh undo`, `./revert.sh`, or a reboot (stock) |
| Pointer: wheel scrolls, hover and click everywhere | `app.js`: `wheel` -> same handler as Up/Down; hover/click on pop-up lists, number pad, QR page, Settings rail/rows, Home tiles | - |

Verified: apply, undo and re-apply through the Settings API (each about 10 s, UI healthy), `tools/check.sh` and `tools/keys-test.sh` pass with the patch active; the build prints exactly the intended diff. NOT verified: that the real gear key shows only our panel, and that the wheel no longer shows the arrow (the agent cannot press the key or see the screen). An injected wheel/move/click test reached the Home page neither with nor without the patch, so it proves nothing.

## Round 8: snappiness and memory (everything measured on the dev TV, raw output in `results/r8-*.txt`)

### 8a: swap less (`vmtune`)

| What | Where / command | Undo |
|---|---|---|
| `vm.swappiness` 100 -> 20 (LG's swap `eswap` is a dm-linear device: the first 600 MB are **zram = compressed RAM**, only the last ~100 MB are eMMC; the first version of this note wrongly claimed 3.7 GB had been written to flash) | `debloat.sh` item `vmtune` (services.tsv, group "Memory & speed", default on), value in `VM_SWAPPINESS`, original kept in `state/vm.orig`, re-applied by the sweep; `/proc/sys` only | Settings -> Services & privacy switch, `sh debloat.sh undo vmtune`, `./revert.sh`, or a reboot (stock) |

Measured with the same cycle (YouTube, Netflix, HDMI 2, Home; `results/r8-swappiness.txt`): swap-ins 6972 / 5347 / 4025, swap-outs 20192 / 12647 / 12538, major faults 7490 / 5705 / 4387 at swappiness 100 / 40 / 15. Fewer flash writes and fewer stalls; the Settings-key latency itself did not change (see 8b). Verified: apply, undo, re-apply, `tools/check.sh` passes. Value 20 chosen as a middle between the measured 40 and 15; not measured on its own.

### 8b: the Settings key opens Settings from inside the compositor

Where the time went (`tools/settings-latency.sh`, key-to-visible 1.2-2.3 s idle, 2.8 s when the TV was short of RAM): the launch itself is only 80-100 ms; the Settings hook saw the key **0.6-0.9 s late** because BusyBox `tail -F` polls the log once a second; then the page needs about 1.05 s (about 450 ms of that is WebAppMgr creating the page before our HTML arrives, 65 ms is our JavaScript).

| What | Where / command | Undo |
|---|---|---|
| `qspatch` now patches two of LG's compositor scripts with our own snippets (`tv/qs/*.js`, inserted by awk on the TV, LG's code is not in the repo): `appLaunch.js` `openSettings()` calls WebAppMgr `launchApp` itself through `lunaCall` (key to launch 90 ms, measured); a second press launches the running page again, WebAppMgr sends it `webOSRelaunch` and the page closes itself; LG's quick panel pre-load at compositor start is removed (never shown); `systemUi.js` reports in | `tv/qspatch.sh`, `tv/qs/`, `app.js` (SETMODE: `webOSRelaunch`), `api.sh` (`/api/qs`, `/api/qsdump`, `/api/settings/launch`) | `sh qspatch.sh undo`, Services switch, `./revert.sh`, reboot (stock) |
| The shell hook is now only the fallback: when the compositor did not "claim" the key within 2 s the hook opens / closes Settings as before | `settings-hook.sh` | - |
| `qspatch.sh` safety: it only reports success when each patched script has run (`/api/qs?e=loaded`), otherwise it rolls back (this saved us once: a typo in a snippet was rolled back automatically); a build is applied at boot only if the very same build already ran on this TV (`state/qspatch.verified`); a failed rollback keeps `qspatch.trying` so the next boot backs off | `qspatch.sh` | - |
| Settings page starts without the 57 KB QR library (loaded when the QR page opens) | `index.html`, `app.js` `withQr()` | - |

Bugs found and fixed on the way: **boot-time apply never worked**: `debloat.sh apply` (which includes qspatch) runs before `home-on.sh`, but `qspatch` waited for the launcher to report ready, so it always rolled back, and after a failed rollback it rebooted without leaving its "tried" mark, which made a boot loop (it ran 3 boots until I stopped it by hand; the crash-loop guard would have ended it at the 4th with `DISABLE`). Boot mode no longer waits for the launcher. The `compositor` object does **not** exist in `systemUi.js` (ReferenceError): the Round 7c pointer lines in that script never did anything; only the "swallow CursorShow" return value ran.

Pointer, tested properly this time (a probe inside the QML file `StarfishKeyFilter.qml`): `compositor.cursorVisible` is **read-only** ("Cannot assign to read-only property") and `compositor.mouseEventEnabled` is already false and does not gate the Magic Remote pointer. The compositor object offers `setEnableCursorChange`, `setMouseFocus`, `updateCursorFocus`, `mouseEventEnabled`; none hides the arrow. The pointer part was removed from the patch. Remaining leads are in docs/AUDIT.md.

### 8c: Back-button history options and the optional background-app closer

| What | Where / command | Undo |
|---|---|---|
| Back history is wiped when the screensaver starts (ours: the page tells `/api/history?v=saver`; LG's own: `lastapp.sh` sees `com.webos.app.screensaver*` in front) so the TV feels freshly turned on; options in Settings -> Remote & pointer: "Forget where I was" (never / screensaver / screensaver or TV off, default screensaver), "Forget apps I left a while ago" (never / 5 min ... 4 h), "How many steps Back can go" (1-8) | `tv/lastapp.sh` (entries are now `id epoch`, `clear`, `why`, `conf`, state in `state/back.conf`), `api.sh` `/api/history`, `/api/gear` returns `back`, `app.js` | set "Forget where I was" to Never, or delete `state/back.conf` |
| "Close apps I left on Home after" 10 min .. 3 h (default **never**): a streaming app that stayed in the background that long is closed (frees its memory, Netflix about 125 MB); LG's apps (`com.webos.*`, `com.palm.*`), inputs, Home, Settings and the app on screen are never touched; checked every 2 minutes | `lastapp.sh reap`, `state/back.conf` `closeidle` | set it to Never |

Verified on the TV with real apps: options and expiry logic (all cases printed), `why saver|standby`, bad values rejected, a real "history cleared (saver)" line when the owner's screensaver started, `closeidle=1` closed Netflix after one minute and left HDMI 2, Home and the foreground app alone. NOT verified: the standby trigger (the power state reports `Active`; the standby values are guessed from the names), the physical gear key.

### 8d: boot test of the patched compositor

Rebooted the TV twice: first boot correctly **refused** a build that had not been proven on a running TV (`qspatch: this build was never proven ...`), after proving it live the second boot applied it at 66 s uptime (7 s), launcher ready at 83 s, boot counter reset, `tools/check.sh` and `tools/keys-test.sh` pass. Compositor memory with LG's quick panel no longer pre-loaded: 56.6 / 56.7 MB (stock, two restarts) vs 52.6 MB (patched), `results/r8-compositor-ab.txt`.

### 8e: acr2 stub, the way back re-proven (two bugs found), final numbers

| What | Where / command | Undo |
|---|---|---|
| `acr2` (LG's viewing recognition, an on-demand service that exists on this firmware) is stubbed with the `contentminer` item, like `admanager`. `adoverlay-service`, `service-logger` and `sportsalarm` (in cleanyourtv-WebOS) do not exist on webOS 4.5 | `debloat.sh` | same switch, `undo`, `./revert.sh` |
| Guide downloader (`iepg`, `broadcast-conf-downloader`) switched off on the dev TV through Settings -> Services (the owner only streams); saves about 7 MB; catalog default stays off for other TVs | `state/svc.conf` `epg=on` | Settings switch |

**`revert.sh` re-proven with the round 8 items, two bugs found and fixed** (`results/r8-revert-test.txt`):
1. `qspatch undo` waited for our launcher to report ready, but `revert.sh` has already given LG's Home back, so the undo "failed", rolled back and **rebooted the TV in the middle of the revert** (it came back stock because `DISABLE` was already set, but the init hook had not been renamed yet). `restart_ui` now only waits for a launcher when ours is the mounted Home.
2. The boot sweep (`debloat.sh sweep` every 20 s for 5 minutes, then every 5 minutes from the Home watchdog) **re-applied the stubs after the revert** when the revert ran in the first minutes after boot. `debloat.sh apply|sweep` now refuse while `DISABLE` exists.
After the fix: no stub mounts, no hosts block, swappiness 100, LG's Home and LG's remotelogger/nudge/contentminer/voice/iepg services running again; then the init hook and boot restored the working state. `tools/safety-test.sh` passes (`results/r8-safety-test.txt`; the first run showed an admanager stub while LG Home was active because the boot sweep of a TV rebooted minutes earlier was still running, the rerun showed 0).

**Before / after** (same `tools/bench-quick.sh`, 3 reps, `results/r8-base-bench.txt` vs `results/r8-after-bench.txt`): YouTube cold launch median 1376 -> 1252 ms, Netflix 1932 -> 1723 ms, Home 1353 -> 1567 ms: all inside the usual +-0.3 s noise, i.e. no change. Swap in use at the end of the same cycle 240 -> 174 MB. Settings key to visible: about 2.0 s (0.6-0.9 s of log-polling lag + 1.05 s page) -> about 1.2 s (90 ms + 1.05 s page), the physical key itself untested.

## Round 9: the real remote recorded, Back and pointer fixed, LG menus replaced (2026-10-27)

The owner pressed every button with `tools/remote-recorder.py` running (read-only evdev + log recorder, `results/` has the decoded table in AGENTS.md). What it showed:
the Magic Remote sends Linux key codes on `LGE M-RCU - Builtin [0]`: digits 2-11, arrows 103/105/106/108, OK 28, **Back 412** (158 is the IR remote), Home 773, gear 139, Input 241, mute/vol 113/114/115, channel 402/403, colours 398-401, play 207, pause 119, `-` 771 (opens LG's Live Menu), mic 1083 (opens LG's voice app), `123` 994 (on-screen remote), power 1021, click 272, wheel = REL 8, pointer = ABS 0/1, and two custom codes from the remote driver: **1198 = show the pointer, 1199 = hide the pointer**.

| What | Where / command | Undo |
|---|---|---|
| **Pointer hidden**: a watcher reads the remote's devices and the moment it sees 1198 it writes 1199 into the same device, so the arrow flickers for a split second instead of staying. No grab, so if it dies nothing breaks. Switch in Settings -> Remote & pointer "Hide the Magic Remote pointer" (default on). Owner confirmed: "the arrow appears but disappears almost instantly" | `tv/pointerhide.py`, `tv/pointerhide.sh`, started by `home-on.sh` and the sweep, `/api/pointerhide`, `state/pointerhide-off` | the Settings switch, `sh pointerhide.sh stop`, `revert.sh`, reboot |
| **Back**: the Back chain only knew the IR code 158, so it never reacted to the Magic Remote (412). `keywatch.py` now listens to both and rescans devices every 3 s; **holding Back (0.8 s) or pressing it twice within 1.2 s leaves the app** (to the previous app of the history, or Home); when an app quits on Back and the TV lands somewhere else (YouTube -> HDMI 2) it is moved to the same target; option "Leave an app with Back" (hold or twice / hold / twice / let the app decide) | `tv/keywatch.py`, `tv/backchain.sh`, `lastapp.sh conf leave`, `app.js` | set the option to "Let the app decide" |
| **LG's screensaver on an input (no signal) is replaced by ours**: the log watcher sees `com.webos.app.screensaver` become visible, closes it, brings Home up and the page starts our screensaver (`/tmp/saver-now` read by `/api/saver/take` when the page is shown). Tested by launching LG's saver on HDMI 1: ours was up 2-9 s later | `tv/saver-take.sh`, `settings-hook.sh` (LGSAVER), `api.sh`, `app.js` `onShow` | `state/saver-lg` keeps LG's, or switch our screensaver off |
| **Same brightness everywhere**: LG keeps `picture.backlight` per input x picture mode, so dimming Home left HDMI bright. `brightness.sh` sets the chosen value in whatever context comes to the front (lastapp calls it on every foreground change) and remembers each context's original (`state/brightness.orig`); Settings -> Picture "Same brightness everywhere" | `tv/brightness.sh`, `lastapp.sh`, `/api/brightness`, `app.js` | set it to Off (restores every remembered original), `revert.sh` |
| **LG's Input picker and Guide / Live Menu are replaced by our Inputs panel** (an overlay page `inputs.html`, same toggle trick as Settings: the second press closes it): the compositor patch swaps LG's `quickinputpicker` launch (2 call sites) and the two Live Menu launches in `appLaunch.js` | `tv/qs/appLaunch.head.js` (`tvdOpenOverlay`), `qspatch.sh` awk (`q == 2, g == 2` or the build is refused), `common.sh` (`overlay_appdesc`, `inputs_appdesc`, `mkhtml`), `settings-open.sh [launch\|close] inputs`, `app.js` (`INPMODE`) | `qspatch.sh undo` |

Verified: pointer watcher counters (32 shows, 32 hides) and the owner's report; Back leave logic reached Home from Netflix through the real code path (the held / double timing could only be exercised with injected keys, which this kernel echoes twice: the owner has to confirm with the real remote); LG saver swap; brightness set in Home, HDMI 1-3 and Live TV contexts; Inputs overlay opens, paints (`inputs-painted`) and closes on a second launch; the patch applies with the replacement counts. NOT verified: the physical Input / Guide keys (injection did not reach the handler), Back hold / double on the real remote.

### 9b: RAM audit (measured on the dev TV, `results/r9-*`)

Memory by process (PSS + swapped, MB): YouTube (`cobalt`) 83 while resident, HDMI input app 57, WebAppMgr 38 + 33 + 13, surface-manager 35, MaliitServer 19, tvservice 20, ss.gateway 20 (Homebrew, kept), pbs 16 (holds a 16 MB EPG database in `/tmp/epg`: left alone, Live TV needs it), SettingsService 14. Kernel: slab 44 MB, page tables 11 MB, CMA 168 MB reserved for video (not usable). **LG's swap `eswap` is zram (600 MB compressed RAM) + about 100 MB of eMMC**, so the claim in 8a that the TV had written 3.7 GB to flash was wrong (corrected everywhere); swappiness 20 still cuts swapping by 40 % (compression work, stalls).

| What | Result | Where | Undo |
|---|---|---|---|
| **Close HDMI input apps left in the background** (default after 5 min, option "Close inputs I left after"): closing hdmi1+hdmi2 while on Home raised MemAvailable 235 -> 326 MB (**+91 MB**); returning to an input takes about 0.75 s instead of 0.3 s (measured 3 rounds) | `lastapp.sh reap` (`closeinputs`), already-running inputs are seeded at start, `app.js` row | set it to Never |
| Streaming apps left in the background are closed after 2 hours (was off; option "Close apps I left on Home after", Never / 30 min / 1 h / 2 h / 5 h); Netflix holds about 125 MB, YouTube 83 MB | `lastapp.sh reap` (`closeidle`, default 120) | set it to Never (use this if you play music in the background) |
| LG's Assistant and Browser apps: already kept closed by `idleapps` (checked: not running) | - | - |

Tried and dropped: keeping a hidden Settings page alive for instant pop-ups: WebAppMgr has `pauseApp` (hides the page, keeps it running) but a later `launchApp` does not show it again and there is no resume / show call, so a paused page cannot be re-shown; the 450 ms of page creation stays. Not touched on purpose: MaliitServer (the on-screen keyboard of LG's web apps), pbs, the WebAppMgr command-line cache sizes (`--skia-image-cache-size-mb=40` etc. are maxima, changing them means restarting every web app and editing the Upstart job).

## Round 10: invisible pointer (picture swap), saver swap no longer depends on the log, compositor patch re-proven (2026-10-27)

| What | Where / command | Undo |
|---|---|---|
| **Pointer made invisible at the source**: the compositor draws the Magic Remote arrow from LG's pictures `/usr/share/im/cursorType*.png` (255 files: arrow, hover, hold, entrance / exit animation, 3 sizes). `cursorclear.py` builds a RAM copy of that folder where every `cursorType*.png` is a fully transparent PNG of the same size (the 3 other files are copied), `cursorclear.sh` bind-mounts it over `/usr/share/im`. Nothing is grabbed or intercepted, the remote, wheel and clicks are untouched, LG's read-only folder is not modified. New debloat item `cursorclear` (Settings -> Services & privacy, group "Remote & Settings", default on), applied BEFORE `qspatch` so the compositor restart at boot already loads the transparent pictures. `pointerhide` (the 1198 / 1199 trick) stays as a second layer | `tv/cursorclear.sh`, `tv/cursorclear.py`, `tv/debloat.sh` (`do_cursorclear`), `tv/services.tsv`, `app.js` text | Settings -> Services & privacy -> switch it off, or `sh debloat.sh undo cursorclear` (a running compositor may keep the pictures it already loaded until its next restart), or reboot without the hook; `revert.sh` runs the same undo |
| **LG's screensaver swap no longer relies on the log**: `lastapp.sh` also subscribes to SAM's `running` list, which names `com.webos.app.screensaver` while it exists, and calls `saver-take.sh` (10 s throttle). Before, only the `tail -F /var/log/messages` watcher in `settings-hook.sh` saw it, and that log is tiny, rotates and sometimes does not exist, so a missed line left LG's saver on screen | `tv/lastapp.sh` (`PIDS`) | `lastapp.sh stop` |
| **Compositor patch (`qspatch`) was OFF after the last reboot**: the boot-time attempt on the previous boot failed and rolled back (the `undo` bug fixed in round 8e), and the boot path refuses a build that was never proven on a running TV, so the Settings / Input / Guide key patches were not active. Applied once from ssh (`qspatch.sh apply`: UI healthy in about 20 s, `state/qspatch.verified` written), so the next boots apply it by themselves | `qspatch.sh apply` | Settings -> Services -> "Hide LG's quick panel" off |

Measured / verified: the generated PNG decodes (sharp) to 90 x 128 x RGBA with all 46,080 bytes zero; 255 pictures cleared, 16 distinct sizes, the RAM copy is about 1 MB; `debloat.sh undo cursorclear` / `apply` / `sweep` / `status` cycle; `tools/check.sh` ALL CHECKS PASSED after the compositor restart; LG's saver launched on HDMI 1 was replaced by Home in about 2 s (LG's saver visible for 0.8 s). NOT verified: that the arrow is really gone on the physical remote (the remote was asleep, `mrcu getConnectionStatus` said not connected; an injected 1198 + move did not read any picture, so it is unknown whether the compositor loads the pictures at start or on demand), the boot order (the next reboot has to show `cursorclear: on` BEFORE `qspatch: restarting surface-manager` in `state/tv-debloat.log`), and LG's real no-signal saver (a 13-minute wait on HDMI 3 did not trigger it).

Tried and dropped: a grab-and-re-emit evdev proxy (clone `LGE M-RCU - Builtin [n]` through /dev/uinput and drop the pointer axes). A harmless probe showed the compositor opens `/dev/input/event0-5` once at start and does NOT open a device created later (only our own watcher did), so a proxy would leave the remote dead unless it also owned the devices before the compositor starts. Other leads: `general.noSignalScreenSaver` is `on` (LG's no-signal saver; left on because its appearance is the signal our swap uses), `other.cursorAutoRemover` already `on`, no LG setting hides the pointer (only `pointerShape/Size/Speed/Alignment`).
