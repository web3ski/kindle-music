# kindle-music

A KOReader plugin that turns an old jailbroken Kindle (tested on Paperwhite 10) into an
e-ink remote for Sonos speakers, with optional Spotify browsing/playback (via Sonos or
Spotify Connect).

**Status: alpha.** Expect rough edges. The UI is currently mostly in Polish; an English translation is planned.

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
