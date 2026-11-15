#!/bin/sh
# Build the KPM package and a static KPM repository into _site/ (published to GitHub Pages).
# Usage: tools/build_repo.sh [output_dir]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/_site"}
case "$OUT" in /*) ;; *) OUT="$(pwd)/$OUT" ;; esac
ID=kindlemusic
VERSION=$(python3 -c 'import json,sys; print(".".join(map(str, json.load(open(sys.argv[1]))["version"])))' "$ROOT/package/manifest.json")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/package/manifest.json" "$ROOT/package/install.sh" "$ROOT/package/uninstall.sh" "$ROOT/package/launch.sh" "$STAGE/"
cp -r "$ROOT/plugin/kindlemusic.koplugin" "$STAGE/"
cp "$ROOT/plugin/scriptlet/KindleMusic.sh" "$STAGE/"

ART_DIR="$OUT/packages/$ID/artifacts"
KPKG="${ID}_${VERSION}_kindle.kpkg"
rm -rf "$OUT"
mkdir -p "$ART_DIR"
# Reproducible-ish tarball: fixed owner and mtime, sorted entries.
(cd "$STAGE" && find . -mindepth 1 | LC_ALL=C sort | sed 's|^\./||' > "$STAGE.list" &&
  tar --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00' \
      --no-recursion -czf "$ART_DIR/$KPKG" -T "$STAGE.list")
rm -f "$STAGE.list"

python3 - "$ROOT/package/manifest.json" "$OUT/manifest.v2.json" "packages/$ID/artifacts/$KPKG" <<'PY'
import json, sys
pkg = json.load(open(sys.argv[1]))
repo = {
    "manifest_version": 2,
    "id": "kindlemusic",
    "name": "Kindle Music",
    "description": "Sonos remote for KOReader on jailbroken Kindles (github.com/web3ski/kindle-music).",
    "packages": {
        pkg["id"]: {
            "name": pkg["name"],
            "author": pkg["author"],
            "description": pkg["description"],
            "artifacts": [{
                "url": sys.argv[3],
                "version": pkg["version"],
                "dependencies": pkg["dependencies"],
                "supported_platforms": pkg["supported_platforms"],
            }],
        }
    },
}
json.dump(repo, open(sys.argv[2], "w"), indent=2)
PY

cp -r "$ROOT/web/." "$OUT/"
rm -f "$OUT/README.md"
(cd "$ART_DIR" && sha256sum "$KPKG" > "$KPKG.sha256")
echo "Built $OUT ($KPKG)"
