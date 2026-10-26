# LG TV debloat + clean launcher (handoff from a cloud session)

## Goal (from Tristan)
Make his LG TV look like cleanyourtv (Apple TV-style Home: dock of 4 apps, top shelf with glow, app grid,
Inputs/Wi-Fi/Settings buttons, clock + date + weather), add a photo screensaver (his own pictures, low resource
use), remove LG ads/telemetry, and make the TV as responsive as possible. He has lifted all earlier rules except
one: **don't break the TV, and always keep a way to recover/access it.**

## TV
- LG UM7300PUA (2019), webOS TV Lite 4.10.2 ("webOS 4.5"), firmware 05.40.97, armv7, 987 MB RAM (heavy swap use)
- IP 10.0.0.63 (Ethernet). Rooted, Homebrew Channel installed (root status ok), SSH (dropbear) on, Telnet on,
  "block system updates" on. Auto updates off - keep it that way.
- SSH: `ssh root@10.0.0.63`. Default password `alpine` until an authorized_keys file exists; setup was in progress
  to install ~/.ssh/id_ed25519.pub (check with `ssh -o BatchMode=yes root@10.0.0.63 echo key-ok`).
  After a key is installed and the TV reboots, `alpine` stops working. Telnet (no password) is the fallback.

## Findings (tv-report/ has raw evidence; tv-report/PLAN.md has the full plan)
- Root FS is read-only squashfs + ro overlay: everything must be runtime (initctl stop, bind mounts from /tmp).
- Init is Upstart (`initctl`), no systemd. This is why github.com/lasharor/cleanyourtv-WebOS refuses webOS 4
  (it also needs a Node.js 8 root service). Don't run its install.sh; reading its scripts is fine (MIT).
- Homebrew startup.sh runs `/var/lib/webosbrew/init.d/*` via run-parts AFTER its own hosts update-block,
  telnet/ssh start, and telemetry spool ro-mounts. init.d was empty (nothing customised before us).
- LG Home is native: `/usr/bin/com.webos.app.fullhome` (launched by sam). Port's "standin" method
  (scripts/home-standin.sh: bind-mount a shell stand-in over the Home exe, ask com.palm.webappmanager/launchApp
  to open a web launcher as com.webos.app.home, register with sam for relaunch, 30 s fallback) should apply.
- Ad/telemetry candidates running: admanager (luna on-demand, parent ls-hubd -> stub bind-mount needed),
  remotelogger, nudge, contentminer (Upstart). acr2 (LivePlus) present, not running. Leave pacrunner, crashd,
  update, networking, inputs alone.
- luna-send produced empty output in the first inspection; tv-inspect-2.sh checks this plus Home manifests,
  WAM Chromium version, Node version. RUN IT FIRST (read-only).

## Plan
1. Run tv-inspect-2.sh, write revert.sh (+ copy at /media/developer/tv-debloat/revert.sh), test it as a no-op.
2. Debloat one item at a time at runtime: hosts block (confirmed domains only), remotelogger, nudge,
   contentminer, admanager stub. Check Home, apps, HDMI after each.
3. Launcher: own single-file web app (no Node service), targeting the TV's old Chromium (likely 53: no async/await,
   no flex gap). Calls luna directly. Weather: Open-Meteo, West Lafayette IN, Fahrenheit. Screensaver: photos
   resized to 1920x1080 JPEG, cross-fade, only while Home is idle.
4. Persist only via `/var/lib/webosbrew/init.d/zz-debloat`, with a DISABLE flag file and the 30 s Home fallback.
5. Keep CHANGES.md with every command run on the TV and how to undo it.
Defaults (unless he says otherwise): keep AirPlay/casting and voice; stop ThinQ/IoT (iot-client, ocf-onboarding)
and HomeKit; dock = Netflix, YouTube, Hulu, Disney+.

## Upstream
If it works well: fork lasharor/cleanyourtv-WebOS and open an issue/PR for webOS 4 support (or publish a separate
repo and PR it into Gathin23/cleanyourtv SHOWCASE.md "Other platforms"). Ask Tristan before pushing anything public.

---

## Status (updated 2026-10-26 by the local session) - the plan above is DONE and installed

- Installed and persistent via `/var/lib/webosbrew/init.d/zz-debloat`; reboot-tested (launcher up 57 s after boot start).
- Debloat items 1-5 and 7 applied; Home replaced by `tv/launcher/index.html`; screensaver works (placeholder photos so far).
- Recovery paths all tested: `./revert.sh` (no-op tested before the first change), 30 s launcher-ready fallback to LG Home,
  crash-loop guard (4 unfinished boots -> `DISABLE`), API self-heal (`results/safety-test.txt`).
- Docs: `README.md` (design + usage), `CHANGES.md` (every change + undo), `results/` + `tools/bench-compare.js` (before/after numbers),
  `UPSTREAM-DRAFT.md` (issue/PR text, NOT posted - ask Tristan first).
- Open items for Tristan: real photos (`tools/prep-photos.ps1`, then `sh tools/deploy.sh`), a physical-remote check (Home key from an app,
  Back key on Home, magic-remote click), whether to turn Telnet off, and whether to publish upstream.
- Gotchas worth knowing before touching the TV again: see the README "findings" list and the `lg-tv-debloat-state` memory (luna-send needs
  `</dev/null`; never `pkill -f`/`pgrep -f` a pattern that is in your own ssh command line; files must be root-owned and not world-writable).
