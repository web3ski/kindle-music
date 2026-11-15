# package/

KPM (KindleModding package manager) packaging of the plugin.

- `manifest.json`: package manifest (bump `version` for every release).
- `install.sh` / `uninstall.sh` / `launch.sh`: KPM hooks, run with `sh` (busybox, not bash).

`tools/build_repo.sh` builds `kindlemusic_<version>_kindle.kpkg` (tar.gz with the manifest, hooks,
`kindlemusic.koplugin/` and `KindleMusic.sh` at its root) and a KPM repository index
`manifest.v2.json` into `_site/`, which GitHub Actions publishes to GitHub Pages together with `web/`.

KOReader is not declared as a KPM dependency (no package in the official repo uses cross-repo
dependencies yet), so `install.sh` checks for `/mnt/us/koreader` and fails with a hint instead.
