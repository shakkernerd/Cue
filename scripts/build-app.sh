#!/bin/bash
# Builds build/Cue.app from the Swift package and signs it.
#
# Signing identity, in order:
#   1. CUE_SIGN_IDENTITY, if set: a codesign identity name or SHA-1 hash, or "-" for ad-hoc.
#   2. The first valid "Apple Development" identity in the keychain.
#   3. Ad-hoc, with a warning: macOS then forgets the Accessibility permission on every rebuild.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product Cue
bin_dir="$(swift build -c release --show-bin-path)"

app="build/Cue.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/Cue" "$app/Contents/MacOS/Cue"
cp Resources/Info.plist "$app/Contents/Info.plist"

identity="${CUE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Apple Development: / { print $2; exit }')"
fi
if [[ -z "$identity" ]]; then
  identity="-"
fi
if [[ "$identity" == "-" ]]; then
  echo "warning: signing ad-hoc; macOS will ask for the Accessibility permission again after every rebuild." >&2
  echo "         Set CUE_SIGN_IDENTITY or add an Apple Development certificate to keep it." >&2
fi

codesign --force --options runtime --sign "$identity" "$app"
codesign --verify --strict "$app"
authority="$(codesign -dvv "$app" 2>&1 | awk -F= '/^Authority=/ && !seen++ { print $2 }')"
echo "Built $app, signed ${authority:-ad-hoc}"
