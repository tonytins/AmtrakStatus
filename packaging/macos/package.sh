#!/usr/bin/env bash
# Builds AmtrakStatus for macOS, for Apple silicon and Intel in one app:
#
#   $DIST/amtrakstatus-<version>-macos-universal.zip  holding AmtrakStatus.app
#
# Usage: packaging/macos/package.sh
#
# Runs on a Mac with Xcode or its command line tools: Swift can't build a Mac app from another
# system. The app is signed ad hoc, not with a Developer ID, so Gatekeeper asks before a downloaded
# copy first opens: Control-click the app and choose Open. Not yet run on a Mac.

# shellcheck source=../env.sh
. "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
parse_options "$@"
HERE="$ROOT/packaging/macos"

[[ "$(uname -s)" == Darwin ]] || fail "this script runs on a Mac; Swift can't build a Mac app from $(uname -s)."

build_app --arch arm64 --arch x86_64
BASENAME="amtrakstatus-$VERSION-macos-universal"
echo "==> $APP $VERSION for macOS (arm64 and x86_64)"

# The app in Contents/MacOS; its interface documents and docs in Contents/Resources, where the app
# looks for them (InterfaceDocument.location), and where signing expects data to be.
STAGE="$WORK/macos/$BASENAME"
stage "$STAGE"
BUNDLE="$WORK/macos/$APP.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
mv "$STAGE/$APP" "$BUNDLE/Contents/MacOS/$APP"
mv "$STAGE"/* "$BUNDLE/Contents/Resources/"
cp "$ROOT/assets/icon.icns" "$BUNDLE/Contents/Resources/$APP.icns"

sed -e "s/@VERSION@/$VERSION/g" -e "s/@BUILD_SHA@/$BUILD_SHA/g" "$HERE/Info.plist.in" >"$BUNDLE/Contents/Info.plist"
plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null || fail "Info.plist isn't valid."

codesign --force --deep --sign - "$BUNDLE" || fail "couldn't sign the app."
codesign --verify --strict --deep "$BUNDLE" || fail "the app's signature isn't valid."
smoke_test "$BUNDLE/Contents/MacOS/$APP"

OUT="$DIST/$BASENAME.zip"
rm -f "$OUT"
ditto -c -k --keepParent "$BUNDLE" "$OUT"
echo "wrote $OUT"
echo "==> done"
