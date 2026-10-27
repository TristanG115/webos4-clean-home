# AGENTS.md - read this first (for any coding agent working on this repo)

This file is the single source of truth for agents (Claude Code, Codex, etc.). `CLAUDE.md` just points here. Humans: start with `README.md`.

## 1. What this project is

A shell + plain-HTML/JS replacement for the **LG webOS 4.x Home screen**, plus an LG ads/telemetry cleanup, for a **rooted** LG TV
(developed on an LG UM7300PUA 55", 2019, webOS TV Lite 4.10.2 "webOS 4.5", firmware 05.40.97, armv7, 987 MB RAM, Chromium 53).

| Feature | Where it lives |
|---|---|
| Apple-TV-style Home (clock, date, weather, favorites, app grid, photo background) | `tv/launcher/index.html` + `app.js` |
| Screensaver / AFK screen (clock + date + weather over gallery photos) | `app.js` (saver section) |
| Photo gallery managed from the TV and from a phone (QR code) | `app.js` (gallery), `phone.html`, `tv/api.sh` (LAN routes) |
| Settings screen (launcher options + LG picture/sound/power via LG's settings service) | `app.js` (Settings section) |
| Debloat (ad hosts blocked, ad/telemetry/voice/IoT services stopped) | `tv/debloat.sh` |
| Replacing LG's native Home with the web launcher ("stand-in" method) | `tv/home-on.sh`, `home-off.sh`, `home-standin.sh` |
| Persistence, recovery, undo | `tv/boot.sh`, `tv/zz-debloat`, `tv/revert.sh`, `revert.sh` |
| Measuring and testing | `bench.sh`, `tools/*` |
| App updates (auto) and the firmware-update lock | `tv/appupdate.sh`, `do_updates` in `tv/debloat.sh` |
| Self-update of this project from GitHub (check, change notes, install with safety copy and automatic roll-back, Home note when an update is ready) | `tv/selfupdate.sh`, `tv/VERSION`, `tv/notes.json`, `tools/release-check.js`; Settings -> Software updates in `app.js` |
| Installing on another TV (rooted) / without root | `install.sh`, `tools/diagnose.sh`, `tv.conf`; `rootless/README.md`, `tools/export-blocklist.js`, `tools/make-ipk.js`, `tv/launcher/rootless.js` |

Results on the dev TV: cold Home start 7.5 s -> 1.1 s, Home process 150 MB -> 54 MB, swap 428 -> 253 MB, ad impressions -> 0 (details: `README.md`, `results/`).

Credit: the idea comes from Gathin23/cleanyourtv (Android) and lasharor/cleanyourtv-WebOS (webOS 5+); see `NOTICE.md`. This project is MIT.

## 2. The owner's one rule

**Never break the TV, and always keep a way back in.** Every change must be reversible, tested, and recorded in `CHANGES.md`. Never touch firmware, bootloader, raw
partitions, or the read-only root FS (it is squashfs; it cannot be remounted anyway). Never disable the Homebrew Channel, SSH, networking, inputs/HDMI, or LG's update-blocking.
Ask the owner before anything outward-facing (opening issues/PRs, posting). Pushing the owner's own repo is pre-authorized at the end of a task (section 11). **End-of-work state (standing rule, owner 2026-10-27): unless the owner has said otherwise for that task, always leave our project fully enabled on the TV when you finish.** Experiments, benchmarks, safety tests and `home-off.sh temp` all end with everything back ON. Before reporting done, verify on the TV: `sh home-on.sh` says active (our launcher mounted over Home, `state/launcher.ready` present); `sh debloat.sh status` shows every switch the owner has on as applied (admanager STUBBED, `updates` BLOCKED 4/4, `qspatch` ACTIVE, cursorclear on, vmtune 20); the watchers run (settings-hook, lastapp, backchain, pointerhide); no `DISABLE` and no `DEBUG` flag; `update.conf` has no `local=` test line and `state/update-failed` is not left over from a test; `tools/check.sh` passes. If the TV rebooted during the work and `qspatch.sh status` says `off`, run `sh qspatch.sh apply` once from ssh. If you had to leave something off (for example because it is unproven), say so explicitly in the final message.
Owner defaults: AirPlay/casting kept, voice off, ThinQ/IoT/HomeKit off,
dock = Netflix/YouTube/Hulu/Disney+, weather in Fahrenheit.

## 3. Privacy rules (important)

- The owner's personal photos are **private**: `photos-trist/` (originals) and `tv/launcher/photos/` (processed). They are git-ignored. Never commit, upload, paste, or describe them
  beyond what is needed to verify layout. Do not publish screenshots that contain them (`shots/` is ignored; keep it that way).
- `tv-report/`, `tv-report.txt` (raw device dumps: serials, advertising ID, network info) and `runner/` are git-ignored. Never commit them.
- Do not write secrets into the repo: the phone-link token is in `state/token` on the TV; SSH keys stay in `~/.ssh`.
- Before every push run the audit in section 12.

## 4. Repository layout

```
AGENTS.md  CLAUDE.md  README.md  CHANGES.md  NOTICE.md  LICENSE  UPSTREAM-DRAFT.md
bench.sh              performance benchmark; runs ON the TV via ./tv.sh -s <label> <reps> < bench.sh
tv.sh                 ssh helper: ./tv.sh 'cmd'   or   ./tv.sh -s < script.sh     (the TV comes from tv.conf: TV_IP=..., see tv-env.sh / tv.conf.example; git-ignored)
install.sh            guided installer for a rooted TV: ./install.sh <ip> [--check] [--yes]   (stages, each with its undo; --check changes nothing)
docs/                 AUDIT.md (measured findings, risks, ranked backlog) and images/ (README pictures, made with PV_PUBLIC=1 node tools/preview.js)
rootless/             guide for TVs that cannot be rooted
revert.sh             PC wrapper that runs the TV's own revert.sh over ssh
tv-inspect*.sh        the original read-only inspection scripts
tv/                   everything deployed to /media/developer/tv-debloat on the TV
  common.sh           shared helpers: paths, log(), lun() (luna-send with stdin closed), api_start/api_ok, HOME_ID/HOME_EXE
  boot.sh             started detached by the init hook; crash-loop guard; waits for SAM; applies debloat + home-on; 5-min sweep for late-starting services
  zz-debloat          the ONE Homebrew init.d hook (copied to /var/lib/webosbrew/init.d/)
  debloat.sh          apply|undo|status|state|sweep [items]: hosts remotelogger nudge contentminer admanager lgsettings voice iot preload idleapps epg updates (catalog: services.tsv, state: state/svc.conf)
  services.tsv        catalog behind Settings -> Services & privacy (id|group|default|locked|name|description)
  blocklist.sh        Pi-hole style ad blocking: builds the "# tv-debloat begin/end" block in /etc/hosts from blocklists/ + state/lists/ + custom/allow lists
  blocklists/         lists.tsv (catalog), lg/ads/trackers/streaming.txt (built-in), allow.txt (never blocked)
  settings-hook.sh    makes the remote's Settings (gear) key open OUR Settings: watches the log for LG's quick panel / Settings app, closes it, opens the overlay
  lastapp.sh          start|stop|top|before: history of apps/inputs in /tmp/appstack (closed apps skipped); api.sh /api/back launches the newest (Back on Home)
  backchain.sh        start|stop: Back from an app returns to the previous app (keywatch.py reads KEY_BACK from /dev/input/event* of the LGE remotes; history from lastapp.sh)
  keywatch.py         read-only evdev Back-key reporter (Python 2.7; struct input_event is 16 bytes). Test without the remote: write a 16-byte KEY_BACK (code 158) down+up event pair to /dev/input/event1
  pointer.sh          off|on|apply|watch|stop: EXPERIMENTAL Magic Remote pointer switch (wake-on-shake + motion sensor off), re-applied by a watcher when the remote reconnects
  selfupdate.sh       check|apply [force]|auto|due|rollback|json|conf: pulls this project's tv/ tree from GitHub (VERSION + notes.json first, tarball on apply), vets it (sh -n, key files), backs up the running code to backup/code-<v>.tgz, installs file by file (mv, new inode), restarts what changed, waits for a healthy launcher, else rolls back and remembers state/update-failed. Settings in state/update.conf (mode notify|auto|off, every, startup, repo, branch, local= for tests)
  VERSION, notes.json the version (YYYY.MM.DD.N) and the plain-language change notes the TVs read from GitHub: see section 11 (every push that changes tv/ needs an entry)
  appupdate.sh        json|mode|check|apply|pending: option.appUpdateMode=auto, waiting updates (appUpdateService/statusAll), "check now" via an activitymanager activity
  settings-open.sh    open|launch|toggle|close our Settings overlay (launch = no is-it-open check, used by the hook) (a second WAM page, settings.html, window type overlay)
  home-on.sh          start API, bind-mount the stand-in over LG's Home, wait <=30 s for the launcher to report ready (else fall back), start the watchdog
  home-off.sh         restore LG's Home (kills stand-in first, then umount, then relaunch)
  home-standin.sh     the program SAM thinks is LG's Home: asks WAM to open the launcher, registers with SAM, handles relaunch/close
  api.sh              one HTTP request per connection (tcpsvd): loopback = full API for the launcher, LAN = phone page + token-protected photo/settings routes
  revert.sh           undo everything (+ reboot unless --no-reboot)
  launcher/           the web app: index.html (markup+CSS), app.js (logic; MODE home|settings), stage.js (photo framing, shared with the phone page), qr.js (vendored MIT), phone.html, appinfo.json, photos/ (private)
tools/                PC-side tools (Node 20+; run `npm install` in tools/ once)
  deploy.sh           copy tv/ to the TV, force root ownership, remove group/world write
  prep-photos.js      folder of pictures -> whole photos (<=2048 px / 2.6 MP) + 480 px previews + automatic framing (state/crops via deploy.sh)
  lg-settings-test.sh sets every LG key our Settings uses back to its own value on the TV: proves the TV accepts it
  bench-quick.sh      3-minute Home / YouTube / Netflix launch benchmark
  pointer-experiment.sh  dead end, kept as a record: mrcu activateMotionSensor is accepted but does not hide the pointer
  diagnose.sh         READ-ONLY compatibility report (webOS, root, init system, tools, Home program, services, LG keys) with OK/WARN/NO verdicts
  keys-test.sh       Settings key + Back chain end to end without the remote (injects evdev KEY_BACK and the lginput2 log line); opens HDMI 2/Netflix
  export-blocklist.js / make-ipk.js   the rootless pack (block lists for a router; experimental developer-mode app)
  check.sh            health check after any change (Settings, Home, Netflix, HDMI 1 all open) - runs on the TV
  release-check.js    PC-side gate before a push: tv/VERSION == newest tv/notes.json entry, notes well formed, app.js and every tv/*.sh pass a syntax check, no CRLF (deploy.sh runs it too)
  safety-test.sh      proves the recovery paths - runs on the TV
  quick.sh            10 s memory/CPU snapshot - runs on the TV
  bench-compare.js    markdown table from results/*.txt
  cdp.js              Chrome DevTools client for the TV: list | eval | shot | logs | key | reload
  preview.js          renders the launcher on the PC with mock data (headless Edge/Chrome)
results/              raw benchmark and test output (no private data)
```
On the TV: `/media/developer/tv-debloat/` holds the deployed tree plus `state/` (log, `settings.json`, `token`, flags), `backup/` (original configs), flags `DISABLE`
(everything off) and `DEBUG` (launcher inspectable on DevTools port 9998).

## 5. How it works (the parts that are not obvious)

```
init hook -> boot.sh -> debloat.sh apply ... -> home-on.sh
home-on.sh: api.sh (tcpsvd :8765) ; mount --bind home-standin.sh /usr/bin/com.webos.app.fullhome ; kill LG's Home once
SAM starts the stand-in as "Home"; it calls luna://com.palm.webappmanager/launchApp with launcher/appinfo.json (+folderPath) -> WAM renders index.html as app id com.webos.app.fullhome
stand-in registers with SAM (registerApp) so the Home key sends "relaunch" -> it re-shows the launcher
```
Facts verified on webOS 4.5 (re-verify on other versions):

- Root FS is read-only; every change is runtime-only (initctl, bind mounts, tmpfs `/etc/hosts`). A reboot without the init hook is stock.
- Init system is Upstart (`initctl`), not systemd. Homebrew's `startup.sh` runs `/var/lib/webosbrew/init.d/*` after its own setup; it has a failsafe flag, so the hook must return instantly (boot.sh is detached).
- `luna-send` prints nothing unless stdin is `</dev/null`.
- A page launched via WAM `launchApp` gets **no luna bridge**; that is why the launcher talks to `api.sh` on 127.0.0.1:8765. The page can only read files **inside its own folder** (photos live in `launcher/photos`;
  app icons under `/usr`, `/media/cryptofs`, `/media/system` are readable).
- `launchApp` takes `appDesc` as a JSON **object** (string -> "Miss launch parameter(s)"). `defaultWindowType` accepts `card`/`overlay` but not `home`, so the launcher is a `card`. `"inspectable": true` exposes DevTools (port 9998).
- SAM refuses `registerNativeApp` for this Home ("unmatched method with nativeLifeCycleInterfaceVersion"); the launch arguments carry `"interfaceMethod":"registerApp"` - home-standin.sh picks the method from them.
- Closing the launcher through SAM kills only the stand-in; the page stays alive in WAM. Kill it in WAM too (`killApp`) when you need a cold start (bench.sh does).
- A bind-mounted script that is still running keeps the mount busy: kill it, then `umount` (home-off.sh does it in that order; `umount -l` as a fallback).
- On-demand luna services (admanager, nlpmanager, iot-client, ...) are neutralised by bind-mounting a do-nothing stub over `/usr/sbin/<name>`. Upstart jobs use `initctl stop`.
  LG's own Home needs `admanager`, so home-off.sh lifts that stub.
- LG's preload manager (`webos-preload-manager`) relaunches some apps within ~20 s (e.g. the Assistant web app): do not "kill" those in a loop.
- `tcpsvd` exports `TCPREMOTEADDR=ip:port` (not TCPREMOTEIP). Loopback = trusted; LAN needs `?t=<token>` and only reaches `/`, `/m/*`, `/photos/*`.
- BusyBox only: no `httpd`, no `jq`, minimal Python 2.7 (no BaseHTTPServer/threading). Use sh, awk, sed, od, tcpsvd, `timeout -t N`, `usleep`.
- Latency is measured from `/var/log/messages` (SAM `NL_APP_LAUNCH_BEGIN` -> surface-manager `NL_VSC visible:true`). The log rotates; `getForegroundAppInfo` does not report overlays/home.
- Chromium 53 in the page: ES5 style, no async/await, no flex `gap`, no CSS grid, no `padStart`, canvas export of `file://` images is blocked.

### Round 3 facts (verified on the dev TV, webOS 4.5)

- **LG settings schema** is `/etc/palm/description.json` (array of `{category,key,values,dimension}`): use it for valid values. `sound.clearVoice` = `off|level1|level2|level3`, `option.logoLight` = `off|low|medium|high`,
  `sound.soundMode` = `standard|movie|news|sports|music|game`, `option.pointerShape` = `a-d`. `tools/lg-settings-test.sh` re-validates. Picture keys depend on input / picture mode / dynamic range (a missing key is normal).
- **Settings key**: the gear button opens `com.webos.app.quicksettings`, a QML overlay inside surface-manager (no file to replace, a bind mount only helps after restarting surface-manager). We watch `/var/log/messages`
  (`NL_VSC ... quicksettings visible:true`, `NL_APP_LAUNCH_BEGIN com.palm.app.settings`) with `tail -F | awk`, close it (`luna://com.webos.surfacemanager/closeByAppId`) and open our overlay. Test without the remote:
  `luna-send -n 1 luna://com.webos.surfacemanager/showQuickSettings '{}'`. LG's own Settings stays reachable via `/api/lg/open` (hook lets it through for 25 s) and `state/gear-lg` turns the redirect off.
- **Overlay page**: WAM `launchApp` with `defaultWindowType":"overlay"`, `transparent`, `main` = `settings.html` (a query string in `main` gives about:blank). Visible about 0.8-1 s after launch; `getForegroundAppInfo {"extraInfo":true}` lists it a little later. No `webOSSystem` object in these pages.
- `/var/log/messages` rotates in a small ramfs and briefly does not exist: never assume it (bench/check use stamps or retry).
- **Preload manager** has a runtime API: `luna://com.webos.service.preloadmanager/getPreloadPolicy` and `setPreloadPolicy {"application":{"id":...,"isEnabled":false}}` (originals saved in `state/preload.orig`).
- **Update servers**: `/usr/sbin/update` talks to snu.lge.com, snu-dev.lge.com, su.lge.com, su-ssl.lge.com, nsu.lge.com; Homebrew blocks four. `support.automaticUpdate` and `option.appUpdateMode` are the settings; `updates` item keeps all four layers.
- **Memory**: the launcher page grows with photo size (decoded image, 4 bytes/pixel): stored photos are capped at about the screen size (2048 px, 2.6 MP) and Home frees its background while the screensaver runs. 1.5x that made the TV swap until SSH timed out.
- /etc/hosts lookups cost about 6 ms more with 4.4k names (glibc scans the file per lookup); the cap is 9,000 names.
- `hosts` cannot wildcard. A real Pi-hole (DNS sinkhole with wildcards + query log) would need a local DNS service; not built (risk to networking).
- Do not touch `ss.gateway` / second-screen: Homebrew Channel uses that identity for privileged luna calls.
- The Magic Remote pointer cannot be switched off from the system side (see `tools/pointer-experiment.sh`); our own pages hide it with CSS only. Untested lead (`tv/pointer.sh`): mrcu `/cursor/setWakeUpCondition {"condition":"motion|shake"}`; mrcu calls only work while the remote is awake (`Magic Remote is not Ready` otherwise) and reset on reconnect. Other mrcu methods seen in `lginput2`: `/cursor/setPosition{posX,posY}`, `setSlideMode`, `/sensor/setCursorBounds`, `setHotkeyCursorPolicy{button,cursorPolicy}`, `activateMrcu` (could disable the remote: do not try without a way back). Surface-manager has no luna method for cursor visibility (only a Wayland `set_cursor_visibility` request).
- **Back on Home**: Home gets keyCode 461 like the Settings page; `goBack()` calls `/api/back`, which relaunches `/tmp/lastapp` (kept by `lastapp.sh` from SAM's foreground subscription). Verified with an injected key only.
- Python 2.7 on the TV has `json`: handy for parsing luna replies in scripts.

### Round 7 facts (verified on the dev TV, webOS 4.5)

- **Backlight**: `picture.backlight` is per picture context (the `dimension` in the reply: input `default` = Home, `hdmi2`, picture mode...). `backlight.sh` stores value AND dimension and restores with that dimension; restoring while another input is in front would set the wrong context. Restore paths: page wake, `lastapp.sh`, boot, sweep (`/tmp/saver-on` stale 3 min), home-off, revert.
- **Compositor patch (`qspatch.sh`)**: LG's key filters are plain JS in `/usr/lib/qt5/qml/KeyFilters/` loaded when surface-manager starts. Bind-mount generated copies (never commit LG's files), then `initctl restart surface-manager`: WebAppMgr stops with it and comes back on its own (`start on lsm-ready`; `initctl emit wam-start` if not), SAM relaunches Home through our stand-in. The globals `compositor`, `homeView`, `global`, `lunaCall` exist in that scope; wrap anything new in try/catch. Run `qspatch.sh build` (prints the diff, mounts nothing) before changing the patch logic. A restart takes about 10 s.
- **`compositor`** (LG's C++ object) has properties `cursorVisible` and `mouseEventEnabled`; `YSM/StarfishKeyFilter.qml` and `YSM/YSM.qml` show how they are used. The effect of `mouseEventEnabled=false` on the arrow is UNVERIFIED.
- Running shell loops (`home-on.sh` watchdog, `settings-hook.sh`, `lastapp.sh`, `backchain.sh`) keep their OLD code after a deploy: restart them (`home-off.sh temp` then `home-on.sh`) before testing a change to them.
- App updates: `appupdate.sh due` decides background checks (startup once per boot 30 s after `launcher.ready`, then every N h; `state/appupdate.conf`). The `status:"Y"` list did not change in over four hours: do not present it as "updates waiting".

### Round 5 facts (verified on the dev TV, webOS 4.5)

- **LG's gear panel** is QML inside surface-manager (`/usr/lib/qt5/qml/QuickSettings/`), preloaded at boot. The gear key logs `lginput2 NL_BUTTON_CLICK ... "button_type":"KEY_SETTINGS"` about 0.5 s before the panel shows; `KeyFilters/appLaunch.js` calls `systemUIManager /launch`. Close it with `luna://com.webos.service.systemUIManager/closeByAppId {"appId":"com.webos.app.quicksettings"}` (`surfacemanager/closeByAppId` says "not supported"; `{"id":...}` is ignored). Its items: picture mode, aspect ratio, sound mode (+effect), sound out (+device), sleep timer, network, all settings.
- **App updates**: all user apps have `checkUpdateOnLaunch:true` (the prompt). `option.appUpdateMode=auto` = LG's own background update. `com.webos.appUpdateService/statusAll` lists apps with `status:"Y"`; `check` answers only to `com.webos.service.activitymanager` and needs `$activity.activityId`: create an activity (`luna://com.webos.service.activitymanager/create` with a `callback` to `appUpdateService/check`). `luna-send -a <id>` cannot fake the caller. An update actually installing was NOT observed.
- **Firmware update lock**: `com.webos.service.update` is `/usr/sbin/update`; a bind-mounted no-op over it means the service never registers (`diagnose.sh` shows it as not-seen). `debloat.sh status updates` must say `BLOCKED (4/4)`. Never write `automaticUpdate`/`appUpdateMode`/`softwareUpdate` through `/api/lg/set` (refused on purpose); app mode goes through `/api/appupdates/mode`.
- **Remote input**: keys, pointer and wheel arrive via uinput devices made by `lginput2` (`LGE RCU` = event1 carries KEY_BACK 158; `LGE M-RCU - Builtin [n]` carry arrows/OK/digits AND the pointer axes, so they cannot be grabbed). Writing a 16-byte `input_event` (`  x8, type 1, code 158, value 1`) to `/dev/input/event1` injects Back; `keywatch.py` reads it. An injected Back does not reliably reach the Home page: test Back-on-Home through `/api/back`. The Home page gets keyCode 461 from a real remote (unverified by us).
- **Pointer**: `mrcu` calls only work while the remote is awake and reset on reconnect; `/cursor/setPosition` (park in a corner), `setWakeUpCondition shake`, `activateMotionSensor false` are applied by `pointer.sh`; effect UNVERIFIED. The scroll wheel wakes the arrow.
- `ls-monitor -l` lists luna services; `strings` on a single binary shows method names; `getForegroundAppInfo` does not list overlays; the load average (about 31) is 29 kernel threads in D state, not load.
- **Screenshots for the README** must come from `PV_PUBLIC=1 node tools/preview.js <name> "<query>"` (no photos, generic place/IP, fresh profile); look at every image before committing it.

### Round 8 facts (verified on the dev TV, webOS 4.5; raw output in `results/r8-*.txt`)

- **Swap**: the swap device `/dev/mapper/eswap` (700 MB) is a dm-linear device over **zram0 (600 MB compressed RAM) + a ~100 MB eMMC partition** (checked in `/sys/block/dm-0/slaves`), so swapping is mostly compression in RAM, not flash writes (an earlier version of this note claimed flash wear: wrong). `vm.swappiness` was 100. `vmtune` sets 20 (swap-ins -42 %, swap-outs -38 %, major faults -41 % for the same cycle). Memory is held by WebAppMgr (main process ~290 MB RSS, renderer ~130 MB) and apps kept resident in the background (Netflix ~125 MB, HDMI input app ~65 MB), not by daemons.
- **Settings-key latency** (`tools/settings-latency.sh`, `tools/loaded-test.sh`): the launch is 80-100 ms; the old hook saw the key **0.6-0.9 s late because BusyBox `tail -F` polls once a second**. Now the compositor (patched `appLaunch.js`) calls WebAppMgr `launchApp` itself, key to launch about 90 ms (round 13: it now sends one GET and `api.sh` decides, opening Settings inside Home when Home is in front, else launching the overlay about 80 ms after the key: see Round 13 facts). The page then needs about 1.05 s: about 450 ms is WebAppMgr creating the page (`performance.timing.responseEnd`), 65 ms is `app.js`. A hidden page cannot be kept alive (no `webOSSystem`, no hide call).
- **A second `launchApp` of the running overlay makes WAM send `webOSRelaunch` to the page**: that is how the gear key toggles (the page closes itself). Do not use `overlayView.appId` for state (always empty).
- **In the compositor's JS** (`KeyFilters/*.js`) `lunaCall.send/subscribe(service, method, json, cb)` and `XMLHttpRequest` (GET works; POST bodies never arrived, and request objects must be kept in a global array or they are garbage-collected) are available; **the `compositor` object is NOT visible there** (ReferenceError), only inside the QML files (`YSM/StarfishKeyFilter.qml`). `console.log` goes nowhere we can read: report through `GET /api/qs?m=...` (log line in `state/tv-debloat.log`, `e=loaded` touches `/tmp/qs-loaded-*`).
- **Pointer, tested from QML**: `compositor.cursorVisible` is read-only; `mouseEventEnabled` was already false and does not gate the pointer; the compositor object has `setEnableCursorChange`, `setMouseFocus`, `updateCursorFocus` and signals only. `cursorAutoRemover` is already `on`. lginput2 (`strings`) has the mrcu methods `cursor/setSensitivity`, `setWakeUpCondition`, `setPosition`, `setAutoAlign`, `setSlideMode`, `setHotkeyCursorPolicy{button,cursorPolicy}`, `setCursorBounds`, `activateMotionSensor`; they only answer while the remote is awake. Untested leads: those calls (sensitivity, bounds, hotkey policy for the wheel), or a grab-and-re-emit evdev proxy that drops the pointer axes (risky: the Magic Remote's keys share those devices).
- **Boot order**: `debloat.sh apply` (qspatch included) runs BEFORE `home-on.sh`, so at boot there is no launcher to wait for: `qspatch.sh apply boot` skips that wait and refuses a build that was never proven on a running TV (`state/qspatch.verified`). A syntax error in a patched compositor script does not stop the UI, it silently loses the key filter: that is why every patched script must call `/api/qs?e=loaded` and `qspatch.sh` rolls back when one is silent. Check snippets with `node --check` on the PC first.
- **Deploying launcher code**: the TV serves the page from the RAM copy `/tmp/tv-launcher`; `deploy.sh` does not refresh it. Run `. common.sh; ram_sync` on the TV (or restart Home) before testing `app.js` changes in the Settings overlay.
- **System log**: `/var/log/messages` is only ~8 KB, rotates every minute or two and briefly does not exist; timing scripts should not depend on it (the Settings page reports its own first paint: `/api/qs?m=settings-painted_...`).
- **Windows traps hit this round**: Python `open()` rewrites LF to CRLF and reads UTF-8 as cp1252 (use `io.open(..., newline='', encoding='utf-8')` or the Edit tool); a `#` comment in the middle of a one-line shell function comments out the rest of the line; Git Bash `/tmp` is not visible to Windows Python.

### Round 9 facts (the real remote was recorded with `tools/remote-recorder.py`; verified on the dev TV)

- **Magic Remote key codes** (Linux codes on `LGE M-RCU - Builtin [0]` = event3; the IR remote `LGE RCU` = event1): digits 2-11 (1..9, 0), arrows 103 up / 105 left / 106 right / 108 down, OK 28, **Back 412** (158 on IR), Home 773, gear 139, Input 241, mute 113, vol- 114, vol+ 115, channel 402 / 403, colours 398-401, play 207, pause 119, `-` 771 (LG Live Menu), mic 1083 (LG voice app), `123` 994 (on-screen remote), power 1021 (`KEY_STB_POWER`), click 272 (BTN_LEFT), wheel REL type 2 code 8, pointer ABS type 3 codes 0 / 1, **1198 = pointer show, 1199 = pointer hide** (custom keys from lginput2, sent before motion / on arrow and digit presses). lginput2 only logs names (`NL_BUTTON_CLICK`) for some buttons. The Netflix / Prime shortcut buttons produced no event at all in the recording.
- **Pointer**: `pointerhide.py` writes 1199 into the device the moment it reads 1198 (no grab); the owner sees the arrow flicker for a split second. The compositor still processes the show (a stall on pointer wake is possible; not solved).
- **Injecting keys is unreliable**: writing key events to `/dev/input/eventN` is echoed twice / leaves keys pressed on some paths (a held or double Back cannot be tested that way), and the compositor's handlers only reacted to an injected gear key once. Test key features with the real remote.
- **Back**: apps decide what Back does (Netflix ignores it on its start screen, YouTube steps back then quits and SAM lands on the last input, HDMI ignores it); `backchain.sh` + `keywatch.py` add hold / double-press to leave and move the landing to history / Home.
- **LG's own screensaver** (no signal on an input) is a window of type `_WEBOS_WINDOW_TYPE_SCREENSAVER` for app `com.webos.app.screensaver`; the foreground app stays the input; it is visible in the log as `NL_VSC ... visible:true`. `luna launch com.webos.app.screensaver` stands in for it in tests.
- **Backlight is per input x picture mode** and a partial dimension cannot be read: it has to be read while on that input (`brightness.sh` does it on every foreground change). Mute: `luna://com.webos.service.tv.sound/setMuteStatus {"muteStatus":true}` (`getMuteStatus`, `getVolume`); standby: `luna://com.webos.service.tvpower/power/powerOff`; `turnOffScreen` / `turnOnScreen` blank the panel only (and calling an unknown payload still executes it).
- **LG's input picker and Guide / Live Menu** are launched from `KeyFilters/appLaunch.js` (`systemUIManager /launch quickinputpicker` in two places, `livemenu` in two places): the patch swaps them for our `inputs.html` overlay (`tvdOpenOverlay`). Physical keys untested.
- **Memory**: `eswap` = zram0 (600 MB) + ~100 MB eMMC; the biggest recoverable RAM is idle apps: an HDMI input app 57 MB (reopens in 0.75 s), YouTube 83 MB, Netflix 125 MB. WAM has `pauseApp` but no show / resume: a hidden page cannot be re-shown.

### Round 10 facts (verified on the dev TV, webOS 4.5)

- **The pointer arrow is a picture**: `/usr/share/im/cursorType*.png` (255 files, 16 sizes; read-only squashfs). `tv/cursorclear.sh` bind-mounts a RAM copy with transparent PNGs of the same sizes over `/usr/share/im` (debloat item `cursorclear`, applied before `qspatch`). The TV's Python has NO `zlib`: `cursorclear.py` gets a deflate stream from BusyBox `gzip` and wraps it. Whether the compositor loads the pictures at start or on demand is UNKNOWN (the remote was asleep); if the arrow ever shows again, restart the compositor (`qspatch.sh reapply` does it safely) and check `mount | grep /usr/share/im`.
- **The compositor does not hot-plug input devices**: `surface-manager-starfish` holds `/dev/input/event0-5` (and `/dev/uinput`) from its start and did not open a clone device created later. An evdev grab-and-clone proxy therefore cannot work (the remote would be dead). `lginput2` owns three uinput devices (fds 6-8).
- **SAM's `running` subscription** (`luna-send -i luna://com.webos.applicationManager/running '{"subscribe":true}'`) emits one JSON line per change and lists `{"id":"com.webos.app.screensaver",...,"appType":"native_qml"}` only while LG's saver exists: used by `lastapp.sh` as a log-independent trigger for `saver-take.sh`. LG's saver app is a full QML app with an ad player (`Containers/AdImageView.qml`); `general.noSignalScreenSaver` (`on`) decides whether it starts on a no-signal input, `general.screenSaverEnabled` is off.
- **Boot trap**: after a failed or rolled-back boot-time `qspatch`, the next boots skip it ("this build was never proven on a running TV") until `sh qspatch.sh apply` is run once from a running TV. Check `sh qspatch.sh status` after any unexpected reboot: Settings / Input / Guide keys are stock while it says `off`.
- `mrcu` exposes `getConnectionStatus` (works with the remote asleep: `connected:false`); use it to know whether any mrcu experiment can answer.

### Round 11 facts (verified on the dev TV, webOS 4.5)

- **`luna://com.webos.applicationManager/getAppLifeEvents {"subscribe":true}`** emits one JSON line per event with `event` = `splash` (0.05 s after a launch, `showSplash:true`), `launch`, `foreground` (the app is in front, window visible; Spotify +1.7 s, Netflix +3.3 s), `background`, `close` / `stop` (with `reason`, e.g. `memoryReclaim` when LG's memory manager evicts), `preload`. During the splash the foreground is still the app that started the launch (Home), so keys reach Home. `lastapp.sh` keeps `/tmp/launching` (`app|from|uptime`) and `/tmp/fgnow` from it. An app that is already resident has no splash.
- **`settingsservice/getSystemSettings {"category":"picture","keys":["backlight"],"subscribe":true}` pushes a message the instant the picture context changes** (input, picture mode, HDR) and on every change of the value; messages caused by `luna-send` carry `"caller":"com.webos.lunasend-N"`. A read with an explicit `dimension` (`{"pictureMode":..,"input":..,"_3dStatus":"2d"}`) works for any schema-valid context (invalid input names answer "no matched result"): valid inputs `default hdmi1-4 hdmi1_pc-hdmi4_pc av1 av2 comp1 dtv atv camera`, 28 picture modes (`/etc/palm/description.json`). A write creates the row. Seeding all of them takes 37 s, restoring 13 s.
- **LG's memory manager** is `memchute` (`com.webos.memorymanager`, `/etc/palm/memorymanager-conf.json`: priority groups, `KeepOnLaunch`, `EfsTarget` includes YouTube). It evicts background apps by priority when memory is short; closing is reported as `close ... reason: memoryReclaim`. `/etc/palm/preload` policy: Netflix, Amazon, Browser, Tips, Assistant preload off (our `preload` item), YouTube `semi-full` and the HDMI input apps stay on.
- BusyBox has no `paste`, no `grep --line-buffered`, no `ls --time-style`, no `time` keyword; `nice`, `setsid`, `usleep` exist. In `sh -s < file` tests the pipeline `luna-send -i ... | while read` delivers one compact JSON line per message.

### Round 13 facts (verified on the dev TV, webOS 4.5)

- **Settings key fast path**: the patched compositor now sends ONE fire-and-forget GET (`/api/ui/settings-key`); answers to XHRs made from the compositor's JS never arrived (a callback-based first design silently did nothing, so do not build on responses there). `api.sh` decides: if `/tmp/fgnow` is empty or Home it writes `settings` into `/tmp/tvd-ui.fifo`; the Home page keeps one request open on `/api/ui/wait` (blocked in `cat` of that FIFO, no CPU) and opens ITS OWN Settings in place (second press closes it), acks via `/api/ui/ack`; no ack within 0.4 s, or an app in front, means the API runs `settings-open.sh launch` (the overlay page, as before). Both paths write `/tmp/qs-claim` so `settings-hook.sh` stays quiet. Measured with an injected KEY_SETTINGS (code 139, octal 213, into /dev/input/event3: 4 events = down, SYN, up, SYN; works for the compositor): in Home key -> Settings open about 0.2-0.35 s (log lines 1890.78 key / 1890.99 page); in an app key -> overlay launch call +0.08 s, painted about 1.0-1.3 s later (unchanged).
- **Why Settings is not kept hot in a second page**: the overlay page costs about 42 MB PSS (and about 28 MB of free RAM) while open, roughly 4 % of the TV's RAM, permanently, and a WAM page cannot be hidden and re-shown (no `webOSSystem`, `pauseApp` has no resume). The in-Home fast path costs 0 MB because the Home page already contains the Settings UI.
- **Memory picture (35 min after boot, 964 MB)**: used 611, available about 200, swap 182 MB held in zram (172 MB of pages compressed to 39 MB, 4.4x). Home renderer: 77 MB PSS fresh (JS heap 10 MB, 197 nodes, one 1396x1862 photo), 130 MB after hours, about 31 MB once an app or overlay is in front (Chromium purges a hidden page), so a periodic Home reload would gain little. Big items are LG's: WebAppMgr browser process, surface-manager (23 MB), the HDMI input app kept in memory (27-72 MB, limited by "Apps kept in memory"), MaliitServer (keyboard, 25 MB), tvservice (15 MB RSS and about 10 % of one core on average: inputs and tuner, must not be stopped). Leftover daemons (crashd, crashreportd, rdxd, uploadd, faultmanager, nopd, dpp, criu, miracast, upnpd, dmr, bluetooth x3) are 0.4-2.3 MB each, about 15 MB in all with the Bluetooth ones, which the Magic Remote needs: not worth stopping.
- **LG menus still reachable** (read from `appLaunch.js` / `systemUi.js`): voice key -> `com.webos.app.voice` (native overlay), triple Mute -> `com.webos.app.tvhotkey` (hidden menu), Input Hub key -> `com.webos.app.homeconnect`, long-press accessibility key -> `com.palm.app.settings` (already redirected to ours by settings-hook.sh), Back/Exit launch `voiceagent` (invisible key handler: leave it). Debloat item `lgmenus` (flag `state/lgmenus.on`): `lastapp.sh`'s life-event loop closes voice / tvhotkey / homeconnect on their splash or launch event (`closeByAppId` with forceMode); tested by launching voice and homeconnect directly (Home stayed in front, "closed LG menu" in the log). NOT replaced: LG's Settings app for Wi-Fi setup, accounts, channel tuning (reachable on purpose through our Settings, "LG Settings (legacy)"); the Content Store / Browser / Photo & Video / Music apps in the app grid (apps, hide them with the `hide` setting); system status OSDs drawn by surface-manager itself (volume bar, mute icon, input-change banner, power-off prompt, HDMI-CEC prompts): not menus, and replacing them means editing LG's QML. Trap: `pgrep -f getAppLifeEvents` also matches lastapp.sh's own subscription: never kill by that pattern.

### Round 12 facts (verified on the dev TV, webOS 4.5)

- **Boot bug fixed (why the TV came up on LG's Home once)**: in `qspatch.sh restart_ui` the line meant to skip the "wait for the launcher" step at boot was inverted (`[ "$BOOTMODE" = 1 ] || is_mounted ... || return 0`), so a boot-time apply waited 45 s for a launcher that starts only later, rolled back, rebooted, and every later boot skipped qspatch ("never proven"). Now `[ "$BOOTMODE" = 1 ] && return 0` first. After ANY rollback like that run `sh qspatch.sh apply` once from ssh (writes `state/qspatch.verified`), then reboot-test.
- **Self-update** (`selfupdate.sh`, loopback API `/api/update*`, Settings -> Software updates, Home pill): the TV has curl + HTTPS to raw.githubusercontent.com and github.com, GNU tar (`--strip-components`, `--wildcards`), `sha256sum`, Python 2.7 `json`. `check` reads `tv/VERSION` (20 bytes) then `tv/notes.json`; `apply` downloads the branch tarball (3.7 MB), unpacks only `*/tv/*` into `/tmp/tvd-update/stage`, refuses it unless key files exist and every `.sh`/`zz-debloat`/`.py` parses, backs up the code (three newest kept), installs file by file with `cp` + `mv -f` (a running script keeps its old inode), deletes files the new tree dropped (list in `state/installed.files`), refreshes the init hook copy only if it is installed, then restarts only what changed (`debloat.sh apply`, `qspatch.sh reapply` if qspatch.sh / qs/ changed and it is ACTIVE, Home cycle for launcher/loops/api/common changes). Healthy = stand-in mounted + `launcher.ready` + API answers within 120 s; otherwise it restores the backup and writes `state/update-failed` (not retried automatically). `mode` notify (default) / auto (installs only when `/tmp/saver-on` or no foreground app) / off. Tested with `conf local=<dir>` (a folder holding `tv/`): happy path, syntax error refused, launcher JS error rolled back in about 2 min, removed file cleaned. Reboot with this code: qspatch applied at boot, launcher up at 86 s. A real GitHub download + vet + backup + install (forced reinstall of 2026.10.27.2, 2.4 s download) was tested after the first push. Not tested: installing a version that really differs from GitHub with a Home restart, `mode=auto` over a long period.
- **Trust**: whoever can push to the configured repo/branch runs code as root on every TV that updates from it. Keep the GitHub account protected (2FA); forks set `repo`/`branch` with `selfupdate.sh conf repo owner/name`.

## 6. Safety net (and how to prove it)

| Layer | What | Test |
|---|---|---|
| `./revert.sh` | LG Home back, debloat undone, init hook renamed to `.disabled`, `DISABLE` created, reboot | `sh /media/developer/tv-debloat/revert.sh --no-reboot` then diff against `results/snap-before-revert-test.txt` |
| `DISABLE` flag / rename hook | boot does nothing -> stock TV | create it, reboot |
| 30 s ready check | launcher must call `/api/ready` or LG Home returns | `tools/safety-test.sh` (A) |
| Crash-loop guard | 4 unfinished boots in a row create `DISABLE` | `tools/safety-test.sh` (B) |
| API watchdog | `tcpsvd` restarted if it dies; 3 failures -> LG Home | `tools/safety-test.sh` (C) |
| Telnet (`telnet <tv>`, no password) and Homebrew failsafe | independent way in if SSH ever breaks | keep enabled until the owner decides |

After **every** change run `tools/check.sh` on the TV and look for `RESULT: ALL CHECKS PASSED` (and `tools/keys-test.sh` when you touch the Settings key, Back or the hooks). Add the change and its undo to `CHANGES.md`. `revert.sh` treats ANY argument as "go on": never call it with `--help`.

## 7. Day-to-day workflow

```
cd tools && npm install                         # once (sharp, qrcode-generator)
sh tools/deploy.sh                              # push tv/ to the TV (idempotent)
./tv.sh 'sh /media/developer/tv-debloat/debloat.sh status'
./tv.sh -s < tools/check.sh                     # health check
touch /media/developer/tv-debloat/DEBUG         # then home-off.sh temp; home-on.sh : launcher becomes inspectable
node tools/cdp.js shot Home shots/now.jpg       # screenshot of the REAL TV; also: eval, key <code> [n], reload, logs
node tools/preview.js home "mock=1"             # PC preview; also "mock=1&settings=picture&row=1", "mock=1&saver=1"
node tools/prep-photos.js "<folder>"            # private photos -> tv/launcher/photos, then deploy.sh
./tv.sh "sh -s mylabel 3" < bench.sh > results/mylabel.txt ; node tools/bench-compare.js baseline final mylabel      # label, repetitions; launches/closes apps on screen
```
Remove `DEBUG` (and restart Home) when done: it exposes the page on DevTools port 9998.

Editing rules: keep shell scripts POSIX/BusyBox and **LF** line endings (`.gitattributes` enforces it; Windows tools that add CRLF break `sh` on the TV). Keep the launcher ES5.
Settings schema lives in `DEFAULTS` at the top of `app.js` (and the small copy in `phone.html`); settings are stored on the TV in `state/settings.json`.

### Traps that cost time before (avoid them)
- Never `pkill -f` / `pgrep -f` a pattern that appears in your own ssh command: it kills your ssh session (exit 255) and the rest silently does not run. Put such code in a script and run `./tv.sh -s < file`.
- `tar` prints "time stamp in the future" and may exit non-zero: never chain `&&` after it (deploy.sh learned this the hard way).
- Never edit the bind-mounted `home-standin.sh` while mounted and expect the running copy to change (new inode); cycle `home-off.sh temp` / `home-on.sh`.
- Do not kill a hidden WAM page from DevTools expecting a response: hidden pages do not answer CDP calls.
- Don't run recursive `grep`/`strings` over `/usr/lib` on the TV (it swaps to death); search single files.
- Multi-line source edits via bash heredoc + node/python are fragile (backslashes, `//` comments flattened by `tr`); use the editor tool.
- Blocked/unsafe: do not blanket-kill processes on the PC (`taskkill /IM node.exe`).

## 8. Porting to another TV that you CAN root (full feature set)

Rooting is the owner's decision and only for TVs they own. Many 2018-2022 LG sets can be rooted depending on firmware; start at <https://rootmy.tv> and the
webOS Brew / Homebrew Channel docs (<https://www.webosbrew.org>). Do not attempt exploits without the owner asking. You need: root shell (ssh/telnet), Homebrew
startup hook (`/var/lib/webosbrew/init.d/`), and "block system updates" enabled.

**Step 0 - read-only inspection** (change nothing). Run `tv-inspect.sh` / `tv-inspect-2.sh` style commands and collect:
```
cat /etc/starfish-release; uname -a; free -m; mount | head; initctl list | head -80   (or: systemctl list-units --type=service)
ls /usr/palm/applications | grep -i -E "home|launcher"; cat /usr/palm/applications/com.webos.app.*home*/appinfo.json
luna-send -n 1 -f luna://com.webos.settingsservice/getSystemSettings '{"category":"general","keys":["defaultApps"]}' </dev/null     # which Home is active
luna-send -n 1 luna://com.webos.applicationManager/running '{}' </dev/null; luna-send -n 1 luna://com.webos.applicationManager/listLaunchPoints '{}' </dev/null
(engine version: launch any page through WAM with inspectable on and run  node tools/cdp.js eval Home "navigator.userAgent")
curl -s -m 5 https://api.open-meteo.com/ -o /dev/null -w '%{http_code}\n'                                                   # TLS/DNS sanity
```
Write the findings to `tv-report/` (git-ignored) and a plan to `PLAN.md`-style notes; get the owner's go-ahead per item.

**Step 1 - decide the mapping** (edit these, nothing else, for most TVs):

| Thing | On the dev TV | Where to change |
|---|---|---|
| Home app id and program | `com.webos.app.fullhome`, `/usr/bin/com.webos.app.fullhome` | `tv/common.sh` (`HOME_ID`, `HOME_EXE`), `tv/launcher/appinfo.json` (`id`, folderPath) |
| Which Home | `defaultApps.home` in `/var/luna/preferences/general` (`fullhome` vs `home`) | same |
| Init system | Upstart: `initctl stop <job>` | `tv/debloat.sh` `do_upstart` -> use `systemctl --no-block stop <unit>.service` on webOS 5+ (systemd); see lasharor/cleanyourtv-WebOS `debloat-stop.sh` |
| Services to stop | remotelogger nudge contentminer admanager(stub) voice* iot* | `tv/debloat.sh` (verify each exists and is safe: stop one, run `tools/check.sh`) |
| Ad hosts | `AD_HOSTS` in `debloat.sh` | resolve each name first (`nslookup <host> 127.0.0.1`); regional prefixes differ (us./nl./eic.) |
| SAM registration method | `registerApp` (from launch args) | already auto-selected in `home-standin.sh`; verify in `state/tv-debloat.log` |
| WAM `launchApp` fields | appDesc object, `defaultWindowType` card | `tv/launcher/appinfo.json` (webOS 5+ may accept window type `home`; try it) |
| LG settings keys (Settings screen) | picture/sound/option/general/time keys | `cats` in `app.js` and the key whitelist in `tv/api.sh` (`/api/lg/*`); verify each key with `getSystemSettings` first |
| Web engine limits | Chromium 53 | newer TVs allow modern JS; keep ES5 anyway unless you test |
| Resolution | 1920x1080 (rem = 100vw/120) | untested on 4K/other panels: check `cdp.js eval Home "innerWidth"`; the layout scales with `vw`, so it should adapt |

**Step 2 - install in the same order the dev TV used** (runtime first, persistence last):
1. `tools/deploy.sh` (edit the IP in `tv.sh`/`deploy.sh`), set up an SSH key, test `./tv.sh echo ok`.
2. Write/refresh backups in `/media/developer/tv-debloat/backup/` and run `revert.sh --no-reboot` as a no-op test **before** the first real change.
3. Apply debloat items one at a time (`debloat.sh apply hosts`, then each service), `tools/check.sh` after each.
4. Test the stand-in: `touch DEBUG; sh home-on.sh`; expect "launcher active" and a screenshot via `cdp.js`. Test Home key behaviour from inside an app and an HDMI input.
5. Run `tools/safety-test.sh`, then install the init hook (`cp zz-debloat /var/lib/webosbrew/init.d/`), reboot, and watch `state/tv-debloat.log` until "launcher up".
6. Benchmark before/after with `bench.sh` (take the *before* run first!).

## 9. Porting to a TV you can NOT root (what is realistically possible)

**Status: a rootless pack exists (`rootless/README.md`, `tools/export-blocklist.js`, `tools/make-ipk.js`, `tv/launcher/rootless.js`) but the developer-mode app is UNTESTED on a real TV; the DNS block lists work anywhere.** Original notes: The full project depends on root (bind mounts, `initctl`, `/etc/hosts`, replacing the native Home, a
listening server). Without root you cannot replace Home or stop services. What remains:

1. **LG's own toggles, by hand** (no root): Settings -> General -> About This TV -> User Agreements (Viewing Information, Interest-Based Advertising off), Live Plus off,
   Home Settings (Home Promotion off, Content Recommendation off), disable automatic updates only if you accept the trade-off. Menu names vary by version.
2. **DNS-level ad blocking** (no TV access at all): point the TV's DNS at Pi-hole/AdGuard Home/NextDNS or block these names on the router - the list is `AD_HOSTS` in `tv/debloat.sh`.
   Caveats: some TVs ignore DHCP DNS for a few services; verify with the resolver's query log. Blocking everything LG related can break app stores/updates.
3. **The launcher as an ordinary web app** (developer mode, no root): install `tv/launcher` as an IPK with the LG webOS TV CLI (`ares-package`, `ares-install`; needs the Developer Mode app and a free
   LG developer account; the dev session must be renewed periodically). It then appears in the app list as one more app: clock, weather (Open-Meteo works from any web app), photo slideshow/screensaver
   page, favorites. It cannot be the Home screen, and **our loopback API does not exist there**, so `app.js` would need an adapter: `launch` via `webOS.service.request('luna://com.webos.applicationmanager/launch')`,
   app list via `listLaunchPoints` - *whether a non-root dev app is allowed to call these must be tested first* (try `webOSTV.js` and log the callbacks; a page launched without the right trust level
   gets silence). Photos would have to be bundled in the IPK or served by something else on the LAN (a Pi/NAS/PC running a tiny upload server; `api.sh`'s LAN routes + `phone.html` are the reference for the protocol).
4. **Feasibility check an agent can run**: install a 20-line test app, call `listLaunchPoints`, `getForegroundAppInfo`, `settingsservice/getSystemSettings`; report which succeed. Only build the adapter if `launch` and
   `listLaunchPoints` work.

Be honest with the owner: without root this is a nicer *app* plus DNS blocking, not the same experience.

## 10. Where things are verified vs. assumed

Verified on the dev TV: everything in sections 5-6, `results/`. Assumed / untested: other webOS versions, other models, the non-root path (section 9), the phone page on a real phone (tested with a headless desktop browser),
physical-remote Back/Home key behaviour (injected keys only).

## 11. Git, publishing, releases

- Local repo, branch `main`. Commit messages end with the attribution line required by the environment. Keep commits focused; update `CHANGES.md` for any TV-affecting change.
- **Commit incrementally** (owner's standing instruction, 2026-10-26): after every finished, tested piece of work make a commit whose message is a detailed log of what was done (what changed, where, why, what was tested, what is still unverified). Do not batch a whole task into one commit and do not leave work uncommitted between pieces.
- **Push once, at the end of the task**, after the section 12 privacy audit and after `tools/check.sh` passed. The owner pre-authorized this push for their own repo (`origin`, https://github.com/TristanG115/webos4-clean-home); do not wait to be asked again, and do not push in the middle of a task. Report what was pushed.
- **Change notes are mandatory (owner's standing instruction, 2026-10-27).** The owner's TVs, and friends' and family's TVs, update themselves from this repo and show what changed *before* installing. So every push that changes anything under `tv/` must carry:
  1. a new **first** entry in `tv/notes.json`: `{"v": "YYYY.MM.DD.N", "date": "YYYY-MM-DD", "title": "short", "notes": ["plain-language sentence", ...]}`. Write for a non-technical household: what is new / faster / fixed and what they will notice, no jargon, no file names, no internal round numbers. Say honestly when something is new and not yet proven on a real remote. `N` counts up for several pushes on the same day.
  2. `tv/VERSION` set to the same `v`.
  3. `node tools/release-check.js` passing (also run by `tools/deploy.sh`).
  Do not edit or delete old entries (TVs show the ones newer than what they have). Docs-only or PC-tools-only pushes need no entry. Technical detail still goes to `CHANGES.md` and AGENTS.md; `notes.json` is the user-facing summary.
  **Pushing a tv/ change ships it to every TV that updates from this repo**, so before bumping the version: the exact tree must have been deployed and `tools/check.sh` must have passed on the dev TV, and a risky change (boot path, qspatch, home-on, selfupdate.sh itself) must also have been boot-tested. Never push a half-finished tv/ change in the middle of a task.
- The repo is published on GitHub by the owner's request. Upstream contributions (issues/PRs to the projects in `NOTICE.md`) are drafted in `UPSTREAM-DRAFT.md` - ask first.

## 12. Pre-push privacy audit (run every time)

```
node tools/release-check.js                      # tv/VERSION matches the newest tv/notes.json entry (the TVs read both from GitHub)
git ls-files | grep -i -E "\.(jpe?g|png|heic)$|photos|tv-report|runner|shots|scratch" | grep -v -E "^docs/images/[a-z-]+\.png$|^tools/prep-photos.js$"     # must print nothing
# every file in docs/images/ must have been made with PV_PUBLIC=1 and OPENED AND LOOKED AT before commit: no photo, no real city, no real IP, no names
git grep -n -i -E "advertising|IFA|serial|passw|systemPin|[0-9a-f]{2}(:[0-9a-f]{2}){5}|<your public IP>" -- . ':!AGENTS.md'      # review hits
git log --all --stat --format=%h | grep -i -E "\.(jpe?g|png)$|tv-report"                                              # must print nothing: history must be clean too
```
If anything private ever got committed, do not just delete it in a new commit: rewrite history before publishing (and tell the owner).
