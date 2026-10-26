# Third-party notices

This project is original work except for the following. Everything else (scripts, launcher, phone page, tools) is MIT-licensed, see LICENSE.

- **qrcode-generator** by Kazuhiko Arase - MIT. Vendored unmodified as `tv/launcher/qr.js` (licence header kept in the file). Draws the QR code on the TV.
- **lasharor/cleanyourtv-WebOS** (MIT) and **Gathin23/cleanyourtv** - the *idea* (Apple-TV-style Home replacing LG's, debloat list of LG ad/telemetry services,
  "stand-in" program bind-mounted over LG's native Home that asks the web app manager to open the launcher) comes from those projects. `tv/home-standin.sh`
  follows the structure of `scripts/home-standin.sh` from lasharor/cleanyourtv-WebOS and is adapted for webOS 4.x (different SAM registration method, Upstart,
  shell-only helper). No code from the Android project is used.
- **sharp** (Apache-2.0, installed by `npm install` in `tools/`, not committed) - image processing in `tools/prep-photos.js`.
- Weather data: [Open-Meteo](https://open-meteo.com) (free, no key). Location lookup: [ipwho.is](https://ipwho.is) (automatic) and [zippopotam.us](https://zippopotam.us) (ZIP codes).
- "LG", "webOS", "Netflix", etc. are trademarks of their owners. This project is not affiliated with LG Electronics.
