#!/bin/sh
# Name: Kindle Music test
# Author: kindle-music contributors
# Harmless download test: only prints a message on screen and writes a one-line log.
MSG="Kindle Music: test OK - .sh download works"
if [ -x /usr/bin/fbink ]; then /usr/bin/fbink -pmh -y 10 "$MSG"; else eips 2 10 "$MSG"; fi
echo "$(date) test ok" > /mnt/us/kindlemusic-test.log
