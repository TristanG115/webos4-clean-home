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
