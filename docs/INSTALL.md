# Install

## From the Kindle (recommended)

On a Kindle jailbroken with [SpiderCat](https://kindlemodding.org/jailbreaking/SpiderCat/), type
these lines into the home-screen search bar, one at a time:

    ;kpm add-repo https://web3ski.github.io/kindle-music/r
    ;kpm update
    ;kpm install koreader
    ;kpm install kindlemusic

Then tap **Kindle Music** in the library. Update later with `;kpm update` and then `;kpm upgrade`. The same steps are on
https://web3ski.github.io/kindle-music/start (step by step, including the jailbreak).

## Manual install (USB / SSH)

Requires a jailbroken Kindle with KOReader installed (tested on Kindle Paperwhite 10, kindlehf firmware).

1. Copy `plugin/kindlemusic.koplugin/` to `/mnt/us/koreader/plugins/` on the Kindle.
2. Optional home-screen launcher: copy `plugin/scriptlet/KindleMusic.sh` to `/mnt/us/documents/`.
   It touches `/tmp/sonos_autostart` and launches KOReader via KPM; the plugin then opens the
   remote directly and offers to exit back to the Kindle UI when closed.
3. Restart KOReader. Open Tools → Sonos (menu entry name). Speakers are discovered automatically
   (known IPs, then a /24 scan for port 1400); you can also enter any speaker's IP manually.

Settings are stored on the Kindle in `koreader/settings/kindlemusic.lua` (speakers, per-household
profiles, visible rooms). Nothing is hardcoded in the plugin. Settings from the older
`sonos.koplugin` (`settings/sonos.lua`) are copied over automatically on first start.

## Spotify (optional)

Create your own app at https://developer.spotify.com/dashboard with redirect URI
`http://127.0.0.1:8888/callback`, then from a computer on the same network:

    python3 tools/link_spotify.py <kindle-ip> --client-id <your-client-id>

This performs Authorization Code + PKCE (no client secret) and writes the refresh token to
`koreader/settings/sonos_spotify_accounts/<user>.lua` on the Kindle over SSH. The token is not
stored on the computer. The client ID is cached locally in `tools/spotify_client_id.txt`
(git-ignored).
