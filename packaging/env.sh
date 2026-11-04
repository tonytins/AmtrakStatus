# shellcheck shell=bash
# Shared setup for the packaging scripts, after CityLimits' and Simburbia's. Source it:
# `. "$(dirname "${BASH_SOURCE[0]}")/../env.sh"`.
#
# Sets:
#   ROOT         the repository's root
#   APP          AmtrakStatus, the name of the app and its executable
#   DIST         where the packages go (default: $ROOT/dist/release)
#   WORK         where they are put together (default: $ROOT/dist/work)
#   BUILD_SHA    the commit being packaged
#
# VERSION is set by build_app, from the built app's --version (GitVersion's major.minor.patch);
# AMTRAKSTATUS_VERSION overrides it.
#
# Swift builds for the machine it runs on, so each script runs on its own platform: Linux on
# Linux, Windows on Windows (in Git Bash), macOS on a Mac.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=AmtrakStatus
export ROOT APP

fail() {
    echo "packaging: $*" >&2
    exit 1
}

command -v swift >/dev/null || fail "swift isn't installed; a Swift 6.2 or later toolchain is needed to build."
command -v git >/dev/null || fail "git isn't installed; the app's version is counted from its history."

DIST="${DIST:-$ROOT/dist/release}"
WORK="${WORK:-$ROOT/dist/work}"
mkdir -p "$DIST" "$WORK"
DIST="$(cd "$DIST" && pwd)"
WORK="$(cd "$WORK" && pwd)"
export DIST WORK

BUILD_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
export BUILD_SHA

# Builds the app in release, with any extra arguments for swift build, sets BIN to the built
# executable, and VERSION from it.
build_app() {
    swift build --package-path "$ROOT" -c release --product "$APP" "$@" \
        || fail "couldn't build the app."
    BIN="$(swift build --package-path "$ROOT" -c release "$@" --show-bin-path)/$APP"
    [[ -x "$BIN" || -x "$BIN.exe" ]] || fail "the build has no $APP in $(dirname "$BIN")."
    VERSION="${AMTRAKSTATUS_VERSION:-$("$BIN" --version)}"
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || fail "couldn't read the app's version; got '$VERSION'."
    export BIN VERSION
}

# Puts what a user needs in a folder: the app, its interface documents (only the files git tracks,
# so nothing local slips in), the readme, the changelog, and the licences.
stage() {
    local dest="$1" file
    rm -rf "$dest"
    mkdir -p "$dest/Interface"
    if [[ -f "$BIN.exe" ]]; then cp "$BIN.exe" "$dest/"; else cp "$BIN" "$dest/"; fi
    while IFS= read -r file; do
        cp "$ROOT/$file" "$dest/Interface/"
    done < <(git -C "$ROOT" ls-files Sources/AmtrakStatus/Interface)
    for file in README.md changelog.md LICENSE ASSET-LICENSE; do
        cp "$ROOT/$file" "$dest/"
    done
}

# Checks a staged app runs: its version, and its interface documents with no window. If the package
# lost its documents, the app would still find the ones in this machine's build folder, so where
# they were found is checked too.
smoke_test() {
    local exe="$1" found
    "$exe" --version >/dev/null || fail "the packaged app didn't start."
    # stderr stays out of the capture, so a warning about a document isn't taken for its location.
    found="$("$exe" --check-interface)" || fail "the packaged app couldn't load its interface."
    [[ "$found" == *board.xml* && "$found" == *station-picker.xml* ]] \
        || fail "the packaged app didn't report its interface documents:"$'\n'"$found"
    [[ "$found" != */.build/* ]] \
        || fail "the packaged app used the build's interface documents, not its own:"$'\n'"$found"
}

# Prints a file's SHA-256.
sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# Downloads a file once, and refuses it unless its SHA-256 is the one given. A file already there
# is checked too, so a damaged or swapped download is never used.
download_verified() {
    local url="$1" dest="$2" expected="$3" executable="${4:-false}" got
    if [[ ! -f "$dest" ]]; then
        echo "Downloading $url"
        curl -fL --retry 3 -o "$dest.part" "$url" || fail "couldn't download $url."
        mv "$dest.part" "$dest"
    fi
    got="$(sha256 "$dest")"
    if [[ "$got" != "$expected" ]]; then
        rm -f "$dest"
        fail "$(basename "$dest") has SHA-256 $got, not $expected; it was deleted, so the next run downloads it again."
    fi
    if [[ "$executable" = true ]]; then chmod +x "$dest"; fi
}

# The scripts' options: -h or --help.
parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
            *) fail "unknown option '$1'; see --help." ;;
        esac
    done
}
