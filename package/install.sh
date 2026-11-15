#!/bin/sh
# Run by KPM from /mnt/us/kmc/kpm/packages/kindlemusic/ after unpacking.
# $1 = "upgrade" when upgrading. Settings live in koreader/settings/ and are kept.
set -e
KOREADER=/mnt/us/koreader
if [ ! -d "$KOREADER/plugins" ]; then
    echo "kindlemusic: KOReader not found in $KOREADER (install it with: ;kpm install koreader)" >&2
    exit 1
fi
rm -rf "$KOREADER/plugins/kindlemusic.koplugin"
cp -r ./kindlemusic.koplugin "$KOREADER/plugins/"
mkdir -p /mnt/us/documents
cp ./KindleMusic.sh /mnt/us/documents/KindleMusic.sh
exit 0
