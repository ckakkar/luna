#!/usr/bin/env bash
# Packs Luna.app into a compressed disk image with an Applications shortcut to drag it onto.
#
#   scripts/make-dmg.sh <Luna.app> <Luna.dmg>
set -euo pipefail
app=$1
dmg=$2

stage=$(mktemp -d)
ditto "$app" "$stage/Luna.app"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -volname "Luna" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$dmg" >/dev/null
rm -rf "$stage"
echo "› $dmg"
