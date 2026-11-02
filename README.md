<p align="center">
    <img title="" src="assets/banner.svg" alt="" data-align="center" width="80%">
</p>
          
## 🖥️ Supported Platforms

| Platform                     | Support |
| ---------------------------- | ------- |
| macOS                        | Supported |
| Linux                        | X11 (including Wayland through XWayland) |
| Windows                      | Not currently verified |

## 🔨 Setup

### Prerequisites

You will need Swift 6.0 or later and Swift Bundler to run and bundle the app.

1. ``brew install mint``
2. ``mint install stackotter/swift-bundler@main``

### Running

```
swift-bundler run
```

### Bundling

```
swift-bundler bundle -c (release|debug)
```

## 🔍 Background

This was intended to solve a rather awkward dilemma. I turned a bunch of online Amtrak status boards made by [Dixieland Software](http://dixielandsoftware.net/Amtrak/status/StatusMaps/) into PWAs (standalone web apps) for stations that I viewed on Virtual Railfan. While it was convenient - don't get me wrong - I had to create a new web app for each and every station, and it was becoming overwhelming.

So I created simple frontend that mapped to Dixieland Software's API using Tauri. You could type in simple station code and it'd take you their status board from within the app. Simple, right? Unfortunately, I didn't know how to get it go back to change the station, my attempted UI redesigns kept failing, and I accidentally botched a migration to Tauri 2.0. I'm just not that good with Node.

The app now uses [raylib-swift](https://github.com/tonytins/raylib-swift) to render an Amtrak split-flap-style status board. It currently shows trains at Ashland, Virginia (ASD), refreshing from [Amtraker](https://amtraker.com/)'s API every ten minutes by default. Use `--refresh-interval <seconds>` to choose a longer interval; values below 600 seconds are rejected. Fetch and refresh results are logged to standard error. The Amtraker client and response models live in the local `AmtrakClient` Swift package so the executable can consume them as a separate module.

On Linux, install the X11 and OpenGL development headers required by raylib; see the [raylib-swift requirements](https://github.com/tonytins/raylib-swift#requirements) for platform-specific packages.

## ⚖️ License

I license this project under the GPL-3.0 license - see [LICENSE](LICENSE) for details.

## ⚠️ Disclaimer

_This project is not in any way affiliated with Amtrak._
