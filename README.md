# kindle-music

A KOReader plugin that turns an old jailbroken Kindle (tested on Paperwhite 10) into an
e-ink remote for Sonos speakers, with optional Spotify browsing/playback (via Sonos or
Spotify Connect).

**Status: alpha.** Expect rough edges. The UI is in English, with a Polish translation
(Settings → Language: English / Polski / Auto, which follows KOReader's language).

## ⚠️ Warnings

- Requires **jailbreaking** your Kindle. That can brick the device, voids any warranty,
  blocks Amazon security updates and opens attack surface (see [docs/SECURITY.md](docs/SECURITY.md)).
  You do this entirely at your own risk.
- Not affiliated with, endorsed by or sponsored by Amazon, Sonos, Spotify or IKEA.
  All trademarks belong to their respective owners.

## Features

- Local Sonos control over UPnP (no cloud): play/pause/skip, volume, groups/rooms,
  shuffle/repeat, sleep timer; auto-discovery and per-household profiles.
- Spotify: browse library/playlists, search, radio, play on Sonos or any Spotify Connect device.
- Small album-art thumbnail next to the track title on the remote.
- "Now playing" sleep screen: when the Kindle sleeps inside KOReader while music plays (or while
  the remote is open), the sleep screen shows the cover, title, artist, album and room instead of
  the usual KOReader screensaver. While music plays, the Kindle wakes up briefly (RTC alarm) when
  the song should end, reads the new track, redraws the screen and goes back to sleep: at the
  latest every 10 minutes (every minute on the charger, every 5 minutes for internet radio).
  Nothing plays → no wakeups. Both settings can be turned off.
- Translations: strings live in `plugin/kindlemusic.koplugin/l10n.lua` (English keys → translation).

## Layout

```
plugin/kindlemusic.koplugin/   KOReader plugin
plugin/scriptlet/        optional Kindle home-screen launcher
tools/link_spotify.py    one-time Spotify account linking (PKCE)
docs/                    install + security notes
package/                 KPM package (manifest + install hooks)
web/                     install guide at /start and download test (GitHub Pages)
tools/build_repo.sh      builds the .kpkg and the KPM repository index
```

## Install

On a Kindle jailbroken with [SpiderCat](https://kindlemodding.org/jailbreaking/SpiderCat/),
follow **https://web3ski.github.io/kindle-music/start** (step by step, including the jailbreak), or type these lines into
the home-screen search bar:

    ;kpm update
    ;kpm install kindlemusic

(Being submitted to the official KindleModding repository. The Kindle search bar rejects
commands containing `.`, `:` or `/`, so `;kpm add-repo <url>` cannot be typed there. Until the
package is listed, add our repository over SSH:
`kpm add-repo https://web3ski.github.io/kindle-music/r && kpm update && kpm -y install kindlemusic`
with `kpm` at `/var/local/kmc/bin/kpm`.)

Details and the manual (USB/SSH) method: [docs/INSTALL.md](docs/INSTALL.md).

## License

AGPL-3.0 — see [LICENSE](LICENSE).
