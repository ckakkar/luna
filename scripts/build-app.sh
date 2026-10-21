#!/usr/bin/env bash
# Builds Luna.app from the Swift package; there is no Xcode project.
#
#   scripts/build-app.sh [--debug] [--universal] [--version X.Y.Z] [--out DIR]
#
# --universal  one binary for Apple Silicon and Intel (each built on its own, then joined with lipo)
# --version    defaults to <major.minor from Resources/Info.plist>.<commits on HEAD>, like Trav
#
# Signing: LUNA_SIGN_IDENTITY if set; otherwise a "Luna Self-Signed" certificate from the keychain if there
# is one (a stable identity keeps the Accessibility permission across updates); otherwise ad-hoc.
# With a Developer ID identity the app is signed with the hardened runtime, ready for notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

config=release
universal=0
version=""
out=build
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) config=debug ;;
        --universal) universal=1 ;;
        --version) version="$2"; shift ;;
        --out) out="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

base=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
build_number=$(git rev-list --count HEAD 2>/dev/null || echo 1)
version=${version:-$base.$build_number}

echo "› Building Luna $version ($config$([[ $universal == 1 ]] && echo ', universal'))"
if [[ $universal == 1 ]]; then
    binaries=()
    for arch in arm64 x86_64; do
        swift build -c "$config" --triple "$arch-apple-macosx14.0" --product Luna
        binaries+=("$(swift build -c "$config" --triple "$arch-apple-macosx14.0" --show-bin-path)/Luna")
    done
    products=$(swift build -c "$config" --triple arm64-apple-macosx14.0 --show-bin-path)
    binary=$(mktemp -d)/Luna
    lipo -create "${binaries[@]}" -output "$binary"
else
    swift build -c "$config" --product Luna
    products=$(swift build -c "$config" --show-bin-path)
    binary="$products/Luna"
fi

app="$out/Luna.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary" "$app/Contents/MacOS/Luna"

plist="$app/Contents/Info.plist"
cp Resources/Info.plist "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build_number" "$plist"
if [[ -s Resources/SparklePublicKey.txt ]]; then
    plutil -replace SUPublicEDKey -string "$(tr -d '[:space:]' < Resources/SparklePublicKey.txt)" "$plist"
fi

if [[ ! -f Resources/AppIcon.icns ]]; then scripts/make-icons.sh; fi
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

sparkle=$(find "$products" .build/artifacts -name Sparkle.framework -maxdepth 6 -type d 2>/dev/null | head -1)
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"

identity=${LUNA_SIGN_IDENTITY:-}
if [[ -z "$identity" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "Luna Self-Signed"; then
    identity="Luna Self-Signed"
fi
identity=${identity:--}
flags=(--force --sign "$identity")
if [[ "$identity" == Developer\ ID* ]]; then flags+=(--options runtime --timestamp); fi

# Inside out: Sparkle's helpers, the framework, then the app.
fw="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$fw/XPCServices/Installer.xpc" "$fw/XPCServices/Downloader.xpc"; do
    [[ -e "$item" ]] && codesign "${flags[@]}" --preserve-metadata=entitlements "$item"
done
for item in "$fw/Autoupdate" "$fw/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"; do
    [[ -e "$item" ]] && codesign "${flags[@]}" "$item"
done
codesign "${flags[@]}" "$app"
codesign --verify --deep --strict "$app"

echo "› $app (signed: $([[ "$identity" == "-" ]] && echo ad-hoc || echo "$identity"))"
