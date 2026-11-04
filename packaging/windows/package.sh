#!/usr/bin/env bash
# Builds AmtrakStatus for x86_64 Windows:
#
#   $DIST/amtrakstatus-<version>-windows-x64.zip  the app in a folder; unzip it anywhere
#
# Usage: packaging/windows/package.sh
#
# Runs on Windows, in Git Bash, with the Swift toolchain for Windows: Swift can't build a Windows
# app from another system. The Swift runtime is built in, so users need nothing installed. Not yet
# run on Windows.

# shellcheck source=../env.sh
. "$(dirname "${BASH_SOURCE[0]}")/../env.sh"
parse_options "$@"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) ;;
    *) fail "this script runs on Windows, in Git Bash; Swift can't build a Windows app from $(uname -s)." ;;
esac

build_app --static-swift-stdlib
BASENAME="amtrakstatus-$VERSION-windows-x64"
echo "==> $APP $VERSION for Windows x64"

STAGE="$WORK/windows/$BASENAME"
stage "$STAGE"
smoke_test "$STAGE/$APP.exe"

OUT="$DIST/$BASENAME.zip"
rm -f "$OUT"
# Git Bash has no zip; PowerShell's archiver is on every Windows.
powershell.exe -NoProfile -Command "Compress-Archive -Path '$(cygpath -w "$STAGE")' -DestinationPath '$(cygpath -w "$OUT")'" \
    || fail "couldn't zip the app."
echo "wrote $OUT"
echo "==> done"
