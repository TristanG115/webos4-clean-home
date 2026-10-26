# Upstream drafts (NOT posted - needs Tristan's OK first)

## Draft 1: issue for lasharor/cleanyourtv-WebOS - "webOS 4.x (webOS TV Lite 4.10.2 / "webOS 4.5") works with a different approach"

**Title:** webOS 4.5 (LG UM7300PUA, firmware 05.40.97) - stand-in method works; report + findings

**Body:**
Tested on an LG UM7300PUA (2019), `Rockhopper release 4.10.2-29 (goldilocks2-grampians)`, rooted with the Homebrew Channel.
I did not run `install.sh` (it correctly refuses webOS < 5: no systemd, Node 0.12). Instead I reproduced the same idea with shell only:

- Home is native (`com.webos.app.fullhome`, `defaultApps.home` in `/var/luna/preferences/general`; `com.webos.app.home` also exists).
- `scripts/home-standin.sh` logic works unchanged in spirit: bind-mount a stand-in over `/usr/bin/com.webos.app.fullhome`, kill LG's Home once,
  SAM starts the stand-in, which calls `luna://com.palm.webappmanager/launchApp` with the launcher's app description.
- Differences found on 4.x:
  1. Init is Upstart: `initctl stop remotelogger|nudge|contentminer` instead of `systemctl`; `admanager` is an on-demand luna service (stub bind-mount works).
  2. SAM refuses `registerNativeApp` for this Home ("unmatched method with nativeLifeCycleInterfaceVersion"); `registerApp` works (see the launch args: `"interfaceMethod":"registerApp"`).
  3. WAM's `launchApp` appDesc is an **object** (string form → "Miss launch parameter(s)"); `defaultWindowType` accepts `card`/`overlay` but not `home`, so the launcher is a `card`.
  4. Pages opened this way get no luna bridge (`PalmServiceBridge` calls never answer); a loopback helper is needed. BusyBox `tcpsvd` + a shell script is enough (no Node).
  5. The page can only read files inside its own folder; `"inspectable": true` in the appDesc exposes DevTools on port 9998.
  6. Chromium 53: no async/await, no flex `gap`, no CSS grid.
- Result on this TV: cold Home start 7.5 s → ~1.1 s, swap in use down by ~X MB, LG Home's 100-130 MB process gone (numbers in the repo).

Offer: I can open a PR that adds a `webos4` profile (Upstart + shell helper) if that fits the project, or publish it separately and link it.

## Draft 2: PR to Gathin23/cleanyourtv SHOWCASE.md ("Other platforms")

One line: `- [<repo name>](<repo url>) - Apple-TV-style Home, photo screensaver and debloat for **LG webOS 4.x** (Upstart, Chromium 53), shell only, one-line revert.`
