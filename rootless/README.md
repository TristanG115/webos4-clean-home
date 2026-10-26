# Rootless guide - what you can do WITHOUT rooting the TV

The full project (replacing LG's Home, stopping LG's services, local API, Back chain, firmware-update stub) needs **root** because it uses bind mounts,
`initctl`, a boot hook and a listening server. A TV that is not rooted cannot do those things. This is what *is* possible, from most to least useful.
Honest summary: without root you get **ad/telemetry blocking and LG's own privacy toggles**; the launcher is only an experimental extra app.

(If you can root the TV, do: it is the better experience. Start at https://rootmy.tv and https://www.webosbrew.org, then `./install.sh <tv-ip>`.
The clean-your-TV project this one was inspired by, `lasharor/cleanyourtv-WebOS`, also requires root on webOS; its Android sibling `Gathin23/cleanyourtv` uses ADB.)

## 1. LG's own switches (no tools, 5 minutes)
Menu names move between webOS versions; look for them under **Settings -> All Settings -> General / Support**.
- **User Agreements / Advertisement**: turn off *Viewing Information*, *Interest-Based & Cross Device Advertisements*, *Live Plus*.
- **Home Settings**: turn off *Home Promotion* and content recommendations.
- **Software updates**: turn *Allow Automatic Updates* off. Be aware firmware updates can remove root and bring LG's software back; on a non-rooted TV they also fix security problems, so this is your call.
- **App updates**: leave *Update apps automatically* **on** (Settings -> General -> About This TV / Support, wording varies) so LG never prompts you before opening an app.
- Voice / ThinQ / HomeKit: turn off what you do not use.

## 2. DNS-level blocking (the biggest win without root)
Point the TV (or the whole network) at a resolver that can block names: Pi-hole, AdGuard Home, NextDNS, or a router with DNS filtering.
```
node tools/export-blocklist.js
```
creates (in `dist/`, git-ignored): `blocklist-domains.txt` (Pi-hole "Adlists" / plain list), `blocklist-hosts.txt` (hosts format, for dnsmasq `addn-hosts`),
`blocklist-adguard.txt` (AdGuard Home custom filter) and `update-servers.txt` (LG firmware servers, kept apart so you decide).
Host the file on your LAN (or paste it in), then check the resolver's query log while the TV is on Home: ads should show as blocked.
Caveats: the TV may ignore DHCP DNS for some services (hard-coded 8.8.8.8): block outbound port 53 to anything but your resolver on the router;
exact names only (the lists contain hosts, not wildcards, unless your resolver adds them); never block `lgtvonline.lge.com`-style names the TV needs to work if something stops working: check the log first.

## 3. The launcher as an ordinary app (EXPERIMENTAL, untested on a real TV)
`tv/launcher` runs in the TV's browser engine. Without root it cannot be the Home screen: it becomes one more app in the list.
```
cd tools && npm install            # once
npm i -g @webos-tools/cli          # LG's CLI (ares-*)
node tools/make-ipk.js             # -> dist/tv.debloat.launcher_1.0.0_all.ipk
ares-setup-device                  # register the TV (Developer Mode app on the TV, free LG developer account, renew the 50-hour session in the Dev Mode app)
ares-install --device <name> dist/tv.debloat.launcher_1.0.0_all.ipk
ares-launch  --device <name> tv.debloat.launcher
```
What the build does: `tools/make-ipk.js` copies `tv/launcher` and adds `rootless.js`, which answers the page's API calls from luna services (via `PalmServiceBridge`) and `localStorage`.
What you get: clock, date, weather, favourites. What is **unknown**: whether LG lets a non-root app call `listLaunchPoints` / `launch` / `getSystemSettings` (many return nothing for apps without
the right permissions). Test first: install, open it, and look at the app row; an empty row means the TV refused `listLaunchPoints`. No photo gallery (no storage), no Back chain, no services page.
Diagnose from a PC with `ares-inspect --device <name> tv.debloat.launcher --open` and watch the console for refused calls.

## 4. What you cannot do without root
Replace LG's Home, stop LG's telemetry services, block firmware updates beyond LG's own switch and DNS, hide the pointer, intercept the Settings key, keep anything running after a reboot.
