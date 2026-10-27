# Audit (2026-10-26): performance, safety, UI and what to build next

Dev TV: LG 55UM7300PUA, webOS TV 4.10.2 ("webOS 4.5"), firmware 05.40.97, armv7l, kernel 4.4.84, **964 MB RAM**, 4 cores, rooted with the Homebrew Channel.
Everything below was measured or read on that TV in this session unless it says *untested*. Raw numbers for the earlier rounds are in `results/`.

## 1. Performance analysis

### 1.1 What the numbers say (same `bench.sh` / `bench-quick.sh`, medians of 3)

| | Stock | Debloat only | Round 1 (launcher) | Round 3 |
|---|---:|---:|---:|---:|
| Home cold start | 7.5 s | 7.5 s | 1.1 s | 1.2 s |
| YouTube opens | 1.8 s | 1.9 s | 1.2 s | 1.3 s (was 2.5 s in the same-day "before") |
| Netflix opens | 2.5 s | 1.9 s | 1.2 s | 1.1-1.7 s (noisy) |
| Swap in use | 428 MB | 308 MB | 253 MB | 218-229 MB |
| Context switches / s | 29.9k | 31.0k | 24.7k | 23.8k |
| 300 fork+exec | 3.1 s | 1.25 s | 1.14 s | 1.19 s |
| LG ad impressions logged | dozens | 0 | 0 | 0 |

Honest reading: the big, certain wins are **cold Home (7x)**, **zero ad traffic** and **less swap**. App launches are mostly dominated by the apps themselves; the +-0.3 s noise is larger than most differences.

### 1.2 Where the TV is actually limited: memory, not CPU
Snapshot taken with the launcher running, nobody using the TV (`tools/quick.sh`, `/proc`):

| Item | Value |
|---|---|
| RAM total / available | 964 MB / 180-285 MB (free 33-62 MB; the rest is cache that can be dropped) |
| Swap used | 220-300 MB of 699 MB, **with 47 KB/s in and 55 KB/s out while idle** |
| CPU | 84-94 % idle |
| `WebAppMgr` browser process | 263-270 MB RSS |
| `WebAppMgr` renderer (Home + overlays) | 87 MB right after a fresh Home, 147-151 MB after several hours |
| `surface-manager` (compositor + LG's QML panels) | 51 MB RSS, 17 MB swapped |
| `com.webos.app.inputcommon` (the HDMI 1 input app, kept resident by LG's preload manager) | 46 MB RSS, 25 MB swapped |
| Everything else | each under 10 MB (`pbs` 9.5, `mojodb` 6, `ss.gateway` 6, `SettingsService` 6, `MaliitServer` 5) |

So: the TV is slightly short of RAM, swaps constantly at a low rate, and the biggest single user is LG's web runtime (two processes, about 260 MB together for Home alone). Our own code is small (launcher files 5 MB in tmpfs, shell scripts, a few KB of RAM).

### 1.3 Findings

**P1. The load average (about 31) is an artifact, ignore it.** 29 kernel threads (`film_mode_detec`, workqueues and others) sit in uninterruptible sleep permanently and each counts 1 toward the load average; `top` shows 84 % CPU idle and 0.2 % iowait. Do not chase it. (Already true in every state, see `results/`.)

**P2. Home renderer memory grows over hours (87 -> about 150 MB).** Measured: fresh Home 87 MB renderer, the same renderer after about three hours of use (Settings opened many times, saver cycles, app list reloads) 147 MB; killing and relaunching Home brought it back to 87 MB. The cause is not isolated (the renderer is shared with the Settings overlay and photo decode caches). *Suggested fix:* reload the Home page when the user wakes from the screensaver if the page is older than 6 hours (one flash of about 1 s, saves 60 MB). Effort: S.

**P3. LG keeps HDMI input apps resident.** `inputcommon` for HDMI 1 holds 46 MB (25 MB of it already swapped). The preload manager has `criu` pre-loading enabled for hdmi1-4, Live TV and the Live Menu. This round already disables the unused stock Home (`com.webos.app.home`). *Option:* a switch "Pre-load HDMI inputs" in Services; off frees about 45 MB per resident input at the cost of about 1 s slower switching to that input. Effort: S.

**P4. Every luna call costs 15 ms idle and up to about 1 s under swap.** The Settings-key hook was losing about 1 s per press to process starts. This round it was restructured (earliest log signal, no round trips, state from the log). Further saving would need a long-lived helper instead of `luna-send` per call. Effort: M.

**P5. `/etc/hosts` with 4,400 names costs about 6 ms per lookup** (glibc scans linearly). Fine for now; a local DNS sinkhole (dnsmasq/unbound) would be O(1) and allow wildcards, but adds a network-critical service (risk). Effort: L, risk: high. Not recommended unless lookups become a measured problem.

**P6. App updates: could not be proven to install.** `option.appUpdateMode` is `auto` and the check request is accepted, but Peacock (6.4.202) and Prime Video (4.5.25) stay in `appUpdateService/statusAll` with `status:"Y"` and unchanged versions 90 s after a check, with and without our host blocks. Either `Y` does not mean "update waiting" or the store does not serve this TV. *Next step:* leave it running for a day and compare versions in Settings -> App updates; if still unchanged, capture the store traffic (needs `tcpdump`, not on the TV: run it from a router / PC mirror).

### 1.4 Things tried that did **not** help (kept as a record)
`vm.swappiness` 30 (no change), stopping the voice/ThinQ/HomeKit helpers (a few MB each), hiding the pointer with `activateMotionSensor` alone.

## 2. Safety and security review

| # | Finding | Severity | Recommendation |
|---|---|---|---|
| S1 | **Telnet (port 23) is open with no password** on the LAN. It is the owner's deliberate way back in. | High on a shared network | Keep while you test; then turn it off in the Homebrew Channel settings and rely on SSH keys (root's password hash is `*`, key login only). |
| S2 | **Port 9998 (Chrome DevTools) is listening on all interfaces** even with our `DEBUG` flag removed (LG's developer mode exposes it). Anyone on the LAN can inspect running web apps. | Medium | Disable Developer Mode's inspector when not developing, or firewall the port; not caused by this repo. |
| S3 | Our API on 8765: loopback = full control; LAN = phone page and photo/settings routes only, with a 96-bit token (plain HTTP). | Low | Treat the QR code like a house key; "Reset phone link" rotates it. No change needed. |
| S4 | Firmware updates: five independent layers (LG switch, hosts, Upstart job stopped, program replaced by a stub, API refuses the keys, 5-minute sweep). `com.webos.service.update` no longer registers at all (`diagnose.sh` shows `not-seen`). The over-the-air update through the TV tuner (`com.webos.service.tv.swupdate` inside `tvservice`) is a separate path that cannot be stopped from here; it only matters with an antenna/cable connected. | Low | Do not connect an antenna on a TV you want to keep rooted, or leave auto-update off in Live TV settings. |
| S5 | `install.sh`/`revert.sh` are destructive by design. | Info | `revert.sh` treats **any** argument as "go on": never call it with `--help`. (The installer was fixed not to.) |

Recovery layers are unchanged and tested (`tools/safety-test.sh`): `./revert.sh`, `DISABLE` flag, 30 s ready check, crash-loop guard, API watchdog, Telnet.

## 3. Findings about the remote (so nobody repeats the experiments)

* The Magic Remote's buttons, pointer and scroll wheel all arrive through **uinput devices created by `lginput2`** (`LGE M-RCU - Builtin [0]/[1]`, `LGE RCU`, `LGE Simple Premium`). The M-RCU devices carry arrows/OK/digits **and** the pointer axes (`ABS_X/Y`, `REL_WHEEL`) on the same device, so the pointer cannot be filtered out by grabbing a device without also losing those keys. KEY_BACK (158) arrives on `LGE RCU` (`/dev/input/event1`).
* **Reading** those devices is safe and gives us the Back key early (`keywatch.py`). **Writing** a 16-byte `input_event` to `/dev/input/event1` injects a key as if pressed: this is how `tools/keys-test.sh` tests without the remote.
* `lginput2`'s luna service (`com.webos.service.mrcu`) has `activateMotionSensor`, `/cursor/setWakeUpCondition {motion|shake}`, `/cursor/setPosition`, `/sensor/setCursorBounds`, `setHotkeyCursorPolicy` (button index + policy). They answer **only while the remote is awake** (`Magic Remote is not Ready` otherwise) and a reconnect resets them. None of them is a documented "hide the pointer". The current attempt (wake on shake + sensor off + parking the arrow in the bottom-right corner) is **unverified**.
* Surface-manager has no luna method for cursor visibility (it has a Wayland `set_cursor_visibility` request used by clients).
* **Round 7 additions (unverified, the agent cannot see the screen or turn the wheel):** `qspatch.sh` also makes `systemUi.js` run `compositor.mouseEventEnabled = false` at start (the compositor object is global in LG's QML, `YSM/StarfishKeyFilter.qml` reads `compositor.cursorVisible`; both are inside try/catch) and swallow `Key_webOS_CursorShow` in three handlers. LG's own comment says cursor keys are handled in the C++ compositor, so the swallow may be too late; the property is the stronger attempt. A test that injected wheel/move/click events into the M-RCU uinput devices reached the Home page neither with the patch nor without it, so it proves nothing either way.
* *Remaining ideas, none done:* a uinput proxy that re-emits only keys (high risk: if it dies the remote is dead until the process ends).

## 4. The Settings key and LG's quick panel

* The gear key logs `lginput2 NL_BUTTON_CLICK ... KEY_SETTINGS`; about 0.5 s later `KeyFilters/appLaunch.js` (JavaScript loaded by surface-manager) calls `systemUIManager /launch com.webos.app.quicksettings`, and the QML panel (`/usr/lib/qt5/qml/QuickSettings/`, preloaded at boot) appears. The panel offers exactly: **Picture mode, Aspect ratio, Sound mode (+ Sound effect), Sound out (+ device), Sleep timer, Network, All settings.** The new **Quick settings** category contains all of those.
* Our hook now opens our overlay from the first log line and closes LG's panel with `systemUIManager/closeByAppId {"appId":...}` (the `surfacemanager/closeByAppId` call used before is refused). On this TV LG's panel is still visible for about 1 s, because every process start costs about 100-300 ms while the TV swaps.
* **Done in round 7 (`tv/qspatch.sh`, Services switch, on by default).** A copy of `appLaunch.js` whose `openSettings()` returns at once (plus `systemUi.js` with the pointer changes, section 3) is generated on the TV from LG's own files, validated, bind-mounted from RAM, and the compositor is restarted once. Upstart restarts WebAppMgr and SAM by itself (`WebAppMgr` is `stop on stopping surface-manager`, `start on lsm-ready`); the script waits for all of them and for our launcher.
  * **What it buys:** LG's QML panel is never created, so there is no flash and no competing CPU/memory use while our overlay starts (the overlay was taking about 1.5 s from the key against about 1.0 s on its own: the difference is that contention).
  * **What it costs:** about 10 s of black screen and all open apps closed, once per apply/undo and once per cold boot (the hook runs after the compositor is up). The picture/aspect/sleep hotkeys no longer open LG's panel either.
  * **Risk and reversal:** nothing on the read-only partition changes. Failure modes and their handling: generated files fail the checks (marker count, brace balance, size) -> refused; compositor or WebAppMgr not back -> `wam-start` emitted, then rollback (unmount, restart); launcher not ready after the restart -> rollback; the script hangs -> a RAM watchdog unmounts and reboots after 180 s; a reboot is always stock; `state/qspatch.trying` stops a boot from repeating an attempt that never finished (it switches the item off). Reverse by hand: `sh qspatch.sh undo`, the Services switch, or `./revert.sh`. Tested on the dev TV: apply, undo and re-apply through the Settings API, about 10 s each, UI healthy every time, `tools/check.sh` and `tools/keys-test.sh` pass with it active.
  * **Failure it cannot cover by itself:** a patched file that loads but misbehaves (keys wrong). The key-filter edits are one inserted `return`, one `try/catch` in `init()` and three `if (key === CursorShow)` lines; SSH/Telnet keep working regardless, and `qspatch.sh undo` or a reboot removes them.

## 5. UI and feature backlog (not built yet)

Ranked by value for effort. S = under a day, M = a few days, L = a week or more.

| # | Idea | Why | Effort |
|---|---|---|---|
| 1 | **Reload Home after 6 h on wake** (P2) | Saves about 60 MB of a 964 MB TV | S |
| 2 | **Health page** in Settings: uptime, memory/swap, update-lock status (4/4), ad counts, last app-update check, watcher status | One place to see that everything is still in force; `tools/check.sh` already computes most of it | S |
| 3 | **Recent apps row** on Home (from the history `lastapp.sh` already keeps) | Faster than the grid for the 3-4 apps you really use | S |
| 4 | **Input names** (HDMI 1 = "PlayStation") | The Inputs button lists HDMI 1-4 only | S |
| 5 | **Night-time dimming**: saver backlight/dim follows the clock (the real backlight dim itself exists since round 7) | Darker at night, brighter by day | S |
| 6 | **Hide / reorder apps on the TV** (today via the phone page / settings.json) | Needs only list UI + the existing `hide`/`dock` settings | S |
| 7 | **Phone as remote** (D-pad, Back, Home, volume) over the LAN, token protected, using the evdev injection found above | Replaces a lost remote; the injection is already proven | M |
| 8 | **Settings backup / restore** (our settings + about 90 LG keys) to one JSON file | Makes a new TV or a factory reset a 1-minute job | M |
| 9 | **Self-update** (`git pull`-style check against the repo, deploy, run `tools/check.sh`, roll back on failure) | Like Homebrew's own updater | M |
| 10 | **Notifications API** (POST a message, shown as a toast on Home): doorbell, laundry, backups | cleanyourtv offers it; trivial with the existing toast | S |
| 11 | **Pre-load HDMI inputs switch** (P3) | Frees 45 MB per input | S |
| 12 | **Scheduled app-update check status on Home** (small badge when `statusAll` is not empty) | Makes the unproven update path visible | S |
| 13 | **Weather: hourly strip and alerts** | Open-Meteo already supplies them | S |
| 14 | **systemd port** (webOS 5+): `do_upstart` -> `systemctl --no-block stop`, `diagnose.sh` already says which one the TV uses | The main blocker for other TVs | L |
| 15 | **Translations** (strings are in `app.js`, ES5) | Anyone not reading English | M |
| 16 | **Fix the pointer for real** (section 3) or drop the option | Currently experimental and unverified | ? |
| 17 | ~~Remove LG's panel flash~~ done in round 7 (section 4) | | |

## 6. Test coverage

| Test | What it proves |
|---|---|
| `tools/check.sh` | Settings, Home, Netflix, HDMI 1 open after any change |
| `tools/safety-test.sh` | Recovery paths: ready check, crash-loop guard, API watchdog |
| `tools/keys-test.sh` (new) | Settings key opens ours and closes LG's, toggles; Back chain; Back on Home (API) |
| `tools/lg-settings-test.sh` | Every LG key our screens write is accepted |
| `tools/diagnose.sh` (new) | Read-only compatibility report for a new TV |
| `bench.sh`, `tools/bench-quick.sh` | Launch latency, memory, swap |

Gaps: physical Back key on Home, the pointer setting, an actual app update installing, the rootless IPK on a real TV, and `install.sh` end to end on a clean TV. These need a person or a second TV.

## 7. Round 8: snappiness, memory, and what the compositor will not let us do (2026-10-27)

All numbers from the dev TV, raw output in `results/r8-*.txt`; tools: `tools/settings-latency.sh`, `tools/loaded-test.sh`.

### 7.1 Why the Settings key felt slow

| Part | Before | Now |
|---|---|---|
| Key reaches our code | **0.6-0.9 s late**: the hook followed the system log with BusyBox `tail -F`, which polls once a second | **about 90 ms**: the patched compositor script launches the page itself (`lunaCall` -> WebAppMgr `launchApp`) |
| Page creation + first paint | about 1.05 s: about 450 ms is WebAppMgr creating the page before our HTML even arrives, 65 ms is our JavaScript, the rest is HTML/CSS parse and first frame | unchanged (the QR library is loaded on demand: no measurable gain, kept anyway because Home and Settings parse 57 KB less) |
| Total, key to visible | 1.2-2.3 s idle, 2.8 s when the TV was short of RAM | about 1.2-1.4 s expected (the physical key itself could not be tested without the remote) |

What is left is WebAppMgr's page creation. Keeping a hidden page alive is not possible (pages have no `webOSSystem`, there is no hide call); LG's CRIU quick-start (`supportQuickStart`, `/var/log/*_criu_*.log`) is an untested lead.

### 7.2 Memory

* The TV swaps to an **encrypted eMMC partition** with `vm.swappiness=100`; after 4.5 h it had written 965k pages (3.7 GB). `vmtune` (swappiness 20): for the same cycle swap-ins 6972 -> 4025 (-42 %), swap-outs 20192 -> 12538 (-38 %), major faults 7490 -> 4387 (-41 %) at swappiness 15; 40 gave -23 %, -37 %, -24 %. Fewer flash writes, fewer stalls.
* Who holds the RAM: WebAppMgr main process about 290 MB RSS, one renderer about 130 MB, Netflix kept resident about 125 MB (RSS+swap), the HDMI input app about 65 MB. No daemon is above 8 MB, so stopping more services saves almost nothing.

### 7.3 The pointer: what was tried and what is left

Tested from inside the compositor (QML probe, then removed): `compositor.cursorVisible` is **read-only**; `mouseEventEnabled` is already false and does not gate the Magic Remote pointer; the object only offers `setEnableCursorChange`, `setMouseFocus`, `updateCursorFocus`. In `KeyFilters/*.js` the `compositor` object does not exist at all, so the Round 7c lines there never did anything. LG's `cursorAutoRemover` is already on.

Leads that are left (all need the remote awake, so they could not be tested alone):
1. lginput2's mrcu methods found with `strings`: `cursor/setSensitivity`, `setHotkeyCursorPolicy{button,cursorPolicy}` (maybe a policy for the wheel), `setCursorBounds` (a 1 x 1 area in a corner), `setSlideMode`, `setAutoAlign`. Cheap to try with a watcher like `pointer.sh`, no restart.
2. A grab-and-re-emit evdev proxy that drops the pointer axes: kernel releases a grab when the process dies, but the Magic Remote's keys share those devices, so a bug could leave the remote dead (ssh and the phone page would remain). Not built.
3. Not recommended: `enableMrcu` / `activateMrcu` (they disable the whole remote), injecting into lginput2 like cleanyourtv-WebOS does (their issue 23: it broke HDMI-CEC / eARC).
