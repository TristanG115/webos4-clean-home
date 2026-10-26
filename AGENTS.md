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

Results on the dev TV: cold Home start 7.5 s -> 1.1 s, Home process 150 MB -> 54 MB, swap 428 -> 253 MB, ad impressions -> 0 (details: `README.md`, `results/`).

Credit: the idea comes from Gathin23/cleanyourtv (Android) and lasharor/cleanyourtv-WebOS (webOS 5+); see `NOTICE.md`. This project is MIT.

## 2. The owner's one rule

**Never break the TV, and always keep a way back in.** Every change must be reversible, tested, and recorded in `CHANGES.md`. Never touch firmware, bootloader, raw
partitions, or the read-only root FS (it is squashfs; it cannot be remounted anyway). Never disable the Homebrew Channel, SSH, networking, inputs/HDMI, or LG's update-blocking.
Ask the owner before anything outward-facing (pushing, opening issues/PRs, posting). Owner defaults: AirPlay/casting kept, voice off, ThinQ/IoT/HomeKit off,
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
tv.sh                 ssh helper: ./tv.sh 'cmd'   or   ./tv.sh -s < script.sh     (root@10.0.0.63, key auth)
revert.sh             PC wrapper that runs the TV's own revert.sh over ssh
tv-inspect*.sh        the original read-only inspection scripts
tv/                   everything deployed to /media/developer/tv-debloat on the TV
  common.sh           shared helpers: paths, log(), lun() (luna-send with stdin closed), api_start/api_ok, HOME_ID/HOME_EXE
  boot.sh             started detached by the init hook; crash-loop guard; waits for SAM; applies debloat + home-on; 5-min sweep for late-starting services
  zz-debloat          the ONE Homebrew init.d hook (copied to /var/lib/webosbrew/init.d/)
  debloat.sh          apply|undo|status <items>: hosts remotelogger nudge contentminer admanager lgsettings voice iot idleapps
  home-on.sh          start API, bind-mount the stand-in over LG's Home, wait <=30 s for the launcher to report ready (else fall back), start the watchdog
  home-off.sh         restore LG's Home (kills stand-in first, then umount, then relaunch)
  home-standin.sh     the program SAM thinks is LG's Home: asks WAM to open the launcher, registers with SAM, handles relaunch/close
  api.sh              one HTTP request per connection (tcpsvd): loopback = full API for the launcher, LAN = phone page + token-protected photo/settings routes
  revert.sh           undo everything (+ reboot unless --no-reboot)
  launcher/           the web app: index.html (markup+CSS), app.js (logic), qr.js (vendored MIT), phone.html (served to phones), appinfo.json, photos/ (private)
tools/                PC-side tools (Node 20+; run `npm install` in tools/ once)
  deploy.sh           copy tv/ to the TV, force root ownership, remove group/world write
  prep-photos.js      folder of pictures -> 1920x1080 16:9 crops (sharp "attention" crop) + 320x180 thumbs
  check.sh            health check after any change (Settings, Home, Netflix, HDMI 1 all open) - runs on the TV
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

## 6. Safety net (and how to prove it)

| Layer | What | Test |
|---|---|---|
| `./revert.sh` | LG Home back, debloat undone, init hook renamed to `.disabled`, `DISABLE` created, reboot | `sh /media/developer/tv-debloat/revert.sh --no-reboot` then diff against `results/snap-before-revert-test.txt` |
| `DISABLE` flag / rename hook | boot does nothing -> stock TV | create it, reboot |
| 30 s ready check | launcher must call `/api/ready` or LG Home returns | `tools/safety-test.sh` (A) |
| Crash-loop guard | 4 unfinished boots in a row create `DISABLE` | `tools/safety-test.sh` (B) |
| API watchdog | `tcpsvd` restarted if it dies; 3 failures -> LG Home | `tools/safety-test.sh` (C) |
| Telnet (`telnet <tv>`, no password) and Homebrew failsafe | independent way in if SSH ever breaks | keep enabled until the owner decides |

After **every** change run `tools/check.sh` on the TV and look for `RESULT: ALL CHECKS PASSED`. Add the change and its undo to `CHANGES.md`.

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

**Status: design notes only - none of this is implemented or tested here.** The full project depends on root (bind mounts, `initctl`, `/etc/hosts`, replacing the native Home, a
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
- The repo is published on GitHub by the owner's request; pushes need the owner's OK each time unless they said otherwise. Upstream contributions (issues/PRs to the projects in `NOTICE.md`) are drafted in `UPSTREAM-DRAFT.md` - ask first.

## 12. Pre-push privacy audit (run every time)

```
git ls-files | grep -i -E "\.(jpe?g|png|heic)$|photos|tv-report|runner|shots|scratch"     # must print nothing (tools/prep-photos.js is fine)
git grep -n -i -E "advertising|IFA|serial|passw|systemPin|[0-9a-f]{2}(:[0-9a-f]{2}){5}|<your public IP>" -- . ':!AGENTS.md'      # review hits
git log --all --stat --format=%h | grep -i -E "\.(jpe?g|png)$|tv-report"                                              # must print nothing: history must be clean too
```
If anything private ever got committed, do not just delete it in a new commit: rewrite history before publishing (and tell the owner).
