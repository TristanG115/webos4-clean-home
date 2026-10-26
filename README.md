# Clean Home for LG webOS 4.x (rooted)

A fast Apple-TV-style Home screen, a photo gallery you manage from your phone, a faster Settings screen, and an LG ads/telemetry cleanup for an
**LG UM7300PUA (2019, webOS TV Lite 4.10.2 "webOS 4.5", Chromium 53)**. Everything is shell + plain HTML/JS: no Node service, nothing written to
system partitions, and one command undoes it all.

Inspired by [Gathin23/cleanyourtv](https://github.com/Gathin23/cleanyourtv) (Android) and [lasharor/cleanyourtv-WebOS](https://github.com/lasharor/cleanyourtv-WebOS),
which both refuse webOS 4 (Upstart instead of systemd, no usable Node). See [NOTICE.md](NOTICE.md) for exactly what is borrowed.

## What you get

- **Home** - clock, date, weather (with the date next to it), Inputs / Network / Settings buttons, a favorites row (Netflix, YouTube, Hulu, Disney+) with a
  colour glow, a grid of every other app, and your photos as a slowly rotating background (a different photo every launch, then every 10 min).
- **Screensaver / AFK screen** - after idle time: clock + date + weather over a gallery photo (or a dark screen if you turn photos off; the text drifts to avoid burn-in).
- **Gallery you manage from the TV and your phone** - *Settings -> Photo gallery* shows your photos. "Add photos from your phone" shows a QR code; the phone page uploads the
  whole photo (shrunk to screen size) with an automatic framing. **Framing editor** (TV remote or phone): move / zoom the photo, see a see-through copy of Home on top, and where the photo no
  longer reaches the screen edge the edge colours of the photo fade out. Saved framing is used by Home and the screensaver.
- **Settings** - the remote's Settings (gear) button opens this instead of LG's panel (it is a transparent overlay, so you see the picture while adjusting it). Home & Screensaver, Weather,
  Photo gallery, **Picture**, **Sound**, **Power & timers** (Quick Start, sleep timers, clock), **Inputs & HDMI**, **Remote & pointer**, **Accessibility**, **Network**, **Ad blocking**,
  **Services & privacy**, **About & updates**, plus a legacy link to LG's own Settings (Wi-Fi setup, accounts, channels). Values and option lists come from LG's own settings schema.
- **Ad blocking (Pi-hole style)** - built-in lists (LG, ad networks, analytics, streaming-app ads) plus downloadable lists (Peter Lowe, Perflyst SmartTV, AdAway), your own block and allow lists
  (edit them on the phone page), an always-allowed list for streaming/CDN names. Applied to the TV's RAM hosts file (capped at 9,000 names).
- **Services & privacy** - every LG background service we stop is a switch with a plain description: ad service, nudge, content miner, remote logging, voice, ThinQ/IoT, app pre-loading,
  idle LG apps, TV guide downloader. **LG system and app updates are blocked and locked** (settings, hosts, `update` service, re-checked every 5 minutes).
- **Faster** - the launcher code runs from RAM (tmpfs), LG's app pre-loading is trimmed to Home/favorites/inputs, idle LG apps are closed.
- **Always recoverable** - see [CHANGES.md](CHANGES.md): `./revert.sh`, one init file, automatic fallback to LG's Home, crash-loop guard.

## Results (same TV, same `bench.sh`, medians of 3; raw data in `results/`)

| Metric | Before | Debloat only | Everything |
|---|---:|---:|---:|
| Home, cold start | 7.5 s | 7.5 s | **1.1 s** |
| YouTube / Netflix open | 1.8 s / 2.5 s | 1.9 s / 1.9 s | 1.2 s / 1.2 s |
| Settings opens | 1.5 s (LG app) | 1.1 s | 1.0 s (LG app) - ours is instant |
| Swap in use | 428 MB | 308 MB | 253 MB |
| Home process memory | 150 MB (LG) | 150 MB | 54 MB |
| System snappiness (300 fork+exec) | 3.1 s | 1.25 s | 1.14 s |
| CPU idle | 86 % | 89 % | 94 % |
| Context switches / s | 29.9k | 31.0k | 24.7k |
| LG ad impressions logged | dozens, even with Home hidden | 0 | 0 |

Honest caveats: the "before" run was at 39 min uptime, "everything" at 71 min (later usually means *more* swap, so the comparison is not flattering the new setup).
App-open gains are modest and noisy (about +-0.3 s); the clear wins are cold Home (7x), ~95 MB less memory for Home, and zero ad traffic. Stopping the voice/ThinQ/HomeKit
helpers freed very little RAM (each is a few MB). Things that did **not** help and were dropped: lowering `vm.swappiness` (no measurable change; `results/exp-swp30.txt`).
The ~14k interrupts/s are mostly the kernel timer tick on 4 cores, not a misbehaving driver. Load average sits near 30 in every state and is not a useful metric on this TV.

## How it works

```
Homebrew init.d/zz-debloat -> boot.sh -> debloat.sh apply ...   (hosts, initctl stop, stub bind-mounts, LG toggles)
                                    \-> home-on.sh
                                          |- api.sh via tcpsvd on 0.0.0.0:8765   (loopback = full API for the launcher; LAN = phone page + photo/settings routes, token only)
                                          |- bind-mount home-standin.sh over /usr/bin/com.webos.app.fullhome
                                          '- the stand-in asks WebAppMgr (luna://com.palm.webappmanager/launchApp) to open launcher/index.html as
                                             com.webos.app.fullhome and registers with SAM so the Home key re-shows it.
                                             30 s ready check + watchdog fall back to LG's Home.
```

Findings that shaped the design (all verified on this TV):
- Root FS is read-only; everything is a runtime change (initctl, bind mounts, tmpfs hosts).
- A page launched through WAM gets **no luna access**, so the launcher talks to a small shell API over loopback.
- WAM only lets the page read files **inside its own folder** (photos live in `launcher/photos`; app icons under `/usr` and `/media/cryptofs` are allowed).
- WAM knows `defaultWindowType` values such as `card`/`overlay`, not `home`, so the launcher is a full-screen `card`.
- SAM wants `registerApp` (not `registerNativeApp`) for the lifecycle-v2 Home app; bind-mounted scripts that are running keep the mount busy (kill first, then umount).
- `"inspectable": true` in the app description exposes the page to Chrome DevTools on port 9998 (only while the `DEBUG` flag file exists).
- LG's preload manager relaunches some apps (e.g. the Assistant web app) within seconds, so killing them is pointless.
- Chromium 53: no async/await, no flex `gap`, no CSS grid, no canvas export from `file://` images - the page is ES5-style.

### Security model of the phone link
The TV listens on port 8765 on your LAN. From the LAN **only** these routes work, and only with the secret token from the QR code (`?t=...`, 96 bits, stored in
`state/token`): the phone page, list/upload/delete photos (JPEG magic bytes checked, size-limited, server-chosen file names, no path traversal), read/write the
launcher settings. Everything that can launch apps or change LG settings is loopback-only. It is plain HTTP on your home network, so treat the QR code like a
house key; *Settings -> Photo gallery -> Reset phone link* makes a new token.

## Layout

```
tv/                 deployed to /media/developer/tv-debloat on the TV
  boot.sh debloat.sh home-on.sh home-off.sh home-standin.sh api.sh common.sh revert.sh zz-debloat
  launcher/         index.html (markup+CSS), app.js (logic), qr.js (vendored), phone.html (the phone page), appinfo.json, photos/ (private, git-ignored)
tools/
  deploy.sh         copy tv/ to the TV (forces root ownership, no world-writable files)
  prep-photos.js    resize/crop a folder of pictures to 1920x1080 + thumbnails (sharp; "attention" crop)
  check.sh          post-change health check (runs on TV)        safety-test.sh   proves the recovery paths (runs on TV)
  quick.sh          10 s memory/CPU snapshot                      bench-compare.js before/after table
  cdp.js            DevTools client: list | eval | shot | logs | key | reload
  preview.js        render the launcher on the PC (headless Edge/Chrome) with real icons
bench.sh            performance benchmark (runs on the TV)        results/  raw numbers
tv.sh               ssh helper         revert.sh  PC wrapper for the TV's revert        CHANGES.md  every change + undo
```

## Use

```
sh tools/deploy.sh                                      # install / update the files on the TV
./tv.sh 'sh /media/developer/tv-debloat/debloat.sh status'
./tv.sh 'sh /media/developer/tv-debloat/home-on.sh'     # start now (RAM only);  home-off.sh temp to stop
cp /media/developer/tv-debloat/zz-debloat /var/lib/webosbrew/init.d/   # persist (done once; revert.sh renames it)

cd tools && npm install && node prep-photos.js "C:\path\to\your\photos"   # then: sh deploy.sh   (or just use the phone page)
node tools/cdp.js shot Home shots/now.jpg               # screenshot of the real TV Home (needs: touch /media/developer/tv-debloat/DEBUG, restart Home)
node tools/preview.js home "mock=1"                     # PC preview (also: "mock=1&saver=1", "mock=1&settings=picture&row=1")
```

Your photos are private: `photos-trist/`, `tv/launcher/photos/` and image files are git-ignored; the raw device reports in `tv-report/` (serials, ad ID, network info) are ignored too.

## Compatibility

Written for webOS 4.x (Chromium 53). On other 4.x sets the Home app id (`com.webos.app.fullhome` vs `com.webos.app.home`, see `defaultApps.home` in
`/var/luna/preferences/general`), the `registerApp`/`registerNativeApp` method and the settings keys may differ. The LG settings items only expose keys that were
verified on this TV; invalid values are rejected by LG and shown as a toast.

## Only a human with the remote can check
Home key from inside an app; Back key on Home (it is a full-screen "card": Back should do nothing or return to the previous app); magic-remote click; wake from standby;
the phone page on your own phone (it was tested with a headless desktop browser acting as a phone). If anything feels wrong: `./revert.sh`.
