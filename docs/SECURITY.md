# Security notes

Running this plugin requires a jailbroken Kindle. A jailbreak deliberately weakens the
device's security model. Things worth knowing before you do it:

- **SSH with a default password.** Common jailbreak tooling (e.g. Jobman's dropbear) ships
  with a well-known override password. Anyone on your Wi-Fi can get root while SSH is on.
  Change the password or use key-only auth, and enable SSH only while you need it.
- **Physical access means root.** A jailbroken Kindle accepts dev-key-signed packages and
  boot hooks (`emergency.sh`, `RUNME.sh`) dropped over USB.
- **No OTA security updates** once OTA is blocked.
- **Supply-chain trust.** Hotfix / re-jailbreak scripts typically run `curl … | sh` as root.
  Run them only when you know why, and inspect the script first.
- **Spotify refresh token** is stored in plain text in KOReader's settings directory on the
  Kindle. Treat the device as holding a credential; revoke access in your Spotify account
  settings if the device is lost.
- Consider putting the Kindle and your speakers on an isolated IoT network/VLAN.

The plugin itself talks only to Sonos speakers on your LAN (UPnP/SOAP, port 1400) and, if
configured, to the Spotify Web API.
