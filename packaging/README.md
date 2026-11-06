# Packaging

Scripts that build AmtrakStatus into the packages people download, one folder for each platform,
after [CityLimits'](https://github.com/tonytins/citylimits/tree/main/packaging) and
[Simburbia's](https://github.com/tonytins/SimsCraft/tree/main/Simburbia/packaging). They write to
`dist/release/` at the repository's root, which git ignores, and put the packages together in
`dist/work/`.

| Script | Builds | Runs on |
| --- | --- | --- |
| `linux/package.sh` | `amtrakstatus-<version>-linux-x86_64.AppImage` and `.tar.gz` | Linux |
| `windows/package.sh` | `amtrakstatus-<version>-windows-x64.zip`, the app in a folder | Windows, in Git Bash |
| `macos/package.sh` | `amtrakstatus-<version>-macos-universal.zip`, holding `AmtrakStatus.app` | macOS |

```sh
packaging/linux/package.sh
```

Swift builds for the machine it runs on, so each script runs on its own platform. Only the Linux
script has been run so far. The Windows and macOS scripts are untested, and raylib-swift and the
other dependencies may need changes to build on those systems.

## What they share

`env.sh` sets up every script. It builds the app in release, reads the version from the built app
(`AmtrakStatus --version`, the major.minor.patch GitVersion works out), and stages a folder with:

- the app;
- `Interface/`, only the files git tracks, which the app finds beside itself (in
  `Contents/Resources` in the Mac app). It holds the interface documents, the fonts, and the
  fonts' licences;
- the readme, the changelog, and the licence (`LICENSE`).

Each script then runs the staged app: its version, and `--check-interface`, which loads the
interface documents and finds the fonts with no window, and prints where it found them. The app falls back to the
`.build` folder it was built in, so the check also fails if the documents came from there. Tools
are downloaded only at pinned versions, and a file whose SHA-256 isn't the published one is refused.

| Variable | Default | Meaning |
| --- | --- | --- |
| `AMTRAKSTATUS_VERSION` | the app's own | The version the packages are named for |
| `DIST` | `dist/release` | Where the packages go |
| `WORK` | `dist/work` | Where they're put together, and the downloaded tools kept |

## Linux

The app is built with the Swift runtime inside it (`--static-swift-stdlib`) and carries libxml2.
A user's system needs glibc, X11, libcurl, zlib, liblzma, and the C++ runtime. libcurl is linked
against the system's `libcurl.so.4`, which every distribution has, so building doesn't need its
development package.

**Which systems it runs on depends on where it's built.** glibc can't be carried in the package, so
a package needs the glibc of the machine that built it, or newer, and the script prints that
version when it finishes. A package built on Fedora 44 needed glibc 2.43, and one built on this
machine in November 2026 needs 2.44; neither starts on Ubuntu 24.04, which has 2.39. To reach more systems, build on an older one.

Building needs the X11 and GL headers raylib compiles against; on an atomic distribution they come
from Homebrew, through `CPATH` and `LIBRARY_PATH`. The script refuses a build that links a library
from Homebrew.

The AppImage carries its own runtime, so it runs without FUSE. It's built with appimagetool 1.9.1
and the type 2 runtime from 2025-11-08, CityLimits' pins, downloaded on the first run. `AppRun`
starts the app from inside the image, `AmtrakStatus.desktop` is its menu entry, and
`assets/icon.png` is its icon.

## Windows

Built on Windows with the Swift toolchain, with the Swift runtime inside the app, and zipped with
PowerShell. `AmtrakStatus.exe` has no icon, because SwiftPM has no step that embeds one, and it
opens a console window beside the board. There's no installer.

## macOS

`AmtrakStatus.app` holds the app in `Contents/MacOS`, and its interface documents, docs, and icon
(`assets/icon.icns`) in `Contents/Resources`, with `Info.plist` made from `Info.plist.in`. It's one
app for Apple silicon and Intel.

The app is signed ad hoc, not with a Developer ID, so Gatekeeper asks before a downloaded copy
first opens: Control-click the app and choose Open. Signing with a Developer ID and notarizing need
an Apple developer account.
