<p align="center">
    <img title="" src="assets/banner.svg" alt="" data-align="center" width="80%">
</p>
          
## 🔍 Background

This was intended to solve a rather awkward dilemma. I turned a bunch of online Amtrak status boards made by [Dixieland Software](http://dixielandsoftware.net/Amtrak/status/StatusMaps/) into PWAs (standalone web apps) for stations that I viewed on Virtual Railfan. While it was convenient - don't get me wrong - I had to create a new web app for each and every station, and it was becoming overwhelming.

So I created simple frontend that mapped to Dixieland Software's API using Tauri. You could type in simple station code and it'd take you their status board from within the app. Simple, right? Unfortunately, I didn't know how to get it go back to change the station, my attempted UI redesigns kept failing, and I accidentally botched a migration to Tauri 2.0. I'm just not that good with Node.

With the aid of AI, the app was rewritten with [raylib-swift](https://github.com/tonytins/raylib-swift) to render a similar Solari board as Dixieland Software. (Admittedly, I wasn't expecting the code to be as simple as it turned out to be.) This new app uses the same Amtraker API from an earlier SwiftUI-like attempt but now with versatility I tried to get from Tauri. I know could have gotten that from the last one but I just wanted the Solari back.

## 🛠️ Building

```sh
swift run AmtrakStatus
swift test
```

On Linux, building needs the X11 and GL development headers, and running needs `libxml2.so.2` for Hudini's XML reader.

Click the station name to change stations. Press Escape to close the picker, or to quit from the board.

To build the packages for Linux, Windows, and macOS, see [`packaging`](packaging/README.md).

## 🎨 Changing the interface

The layout, colors, text, and station presets live in [`Sources/AmtrakStatus/Interface`](Sources/AmtrakStatus/Interface), written in [Hudini's UIScript](https://github.com/tonytins/Hudini/blob/main/doc/UISCRIPT.md):

- [`board.xml`](Sources/AmtrakStatus/Interface/board.xml) is the status board. A column's `<Region>` sets where its split-flap tiles go and how many fit, and its style sets their font size and colors.
- [`station-picker.xml`](Sources/AmtrakStatus/Interface/station-picker.xml) is the picker. A button named `preset.<CODE>` adds a station, and its text can be any label. The board's header uses Amtraker's name for the station once it loads.

SwiftPM copies these files into a resource bundle next to the executable, so keep the two together when moving a build you made yourself. Packages carry them in a plain `Interface` folder instead. `AmtrakStatus --check-interface` checks the documents and prints where it found them, without opening a window.

## ⚖️ License

I license this project under the GPL-3.0 license - see [LICENSE](LICENSE) for details.

## ⚠️ Disclaimer

_This project is not in any way affiliated with Amtrak._
