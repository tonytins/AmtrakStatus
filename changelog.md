# Change Log

## 0.3.116

- When Amtraker can't be reached or sends something unreadable, the board shows the last saved data instead, however old, and the footer says so, such as `COULD NOT REACH AMTRAKER  /  SHOWING DATA FROM 17:47`. This works after a restart too. `--print` writes the same note, with the fetch time, to standard error.
- A request the saved data covers is logged as one warning rather than an error.

## 0.3.115

- Amtraker's responses are now kept in your cache folder, such as `~/.cache/AmtrakStatus` on Linux. Starting the app, using `--print`, or switching back to a station within the refresh interval reuses them instead of fetching everything again, and stations share what they have in common. Responses older than two days are deleted at startup.
- `UPDATED` shows when the data was fetched, which is earlier than now when it came from the cache, and the next update is due an interval after that.

## 0.3.113

- Added `--hours`, which shows only trains due within that many hours, such as `--hours 6`. A train counts by Amtraker's estimate when there is one, so a late train is judged by when it is really coming, and a late train stays until it departs. Trains come onto the board as their time nears, without waiting for an update. It also applies to `--print`.
- When `--hours` leaves the board empty, it says so, such as `NO TRAINS IN THE NEXT 6 HOURS`.

## 0.3.112

- Trains leave the board once Amtraker says they have departed the station. Before, a train that left in the morning stayed until midnight. Trains still on their way or at the platform stay.

## 0.3.111

- Times are now 24-hour, such as `19:09`, on the board, the clock, the update line, and `--print`.
- Times on another day than today at the station show the weekday where AM or PM used to be, such as `09:07 FRI`, so tomorrow's trains no longer look like today's. A late train from yesterday shows yesterday's weekday. The weekday follows the clock, so it appears at midnight without waiting for the next update.
- The time column is one tile wider, and the Train column one tile narrower.

## 0.3.110

- The clock's label now reads `STATION TIME` instead of `LOCAL TIME`, since it has always shown the time at the station rather than on your computer.

## 0.3.109

- Updated Hudini to its newer theming. Building now needs Swift 6.3 or later.
- The station code field is ready for typing as soon as the picker opens, so it no longer needs a click first.

## 0.3.108

- Added `--station` (or `-s`) to open the board on a station other than Ashland, such as `--station NYP`. It takes the same codes as the picker.
- Added `--print`, which writes the station's trains to the terminal as tab-separated text, with a header line, and exits without a window.
- The app now only logs warnings and errors, including Raylib's. Add `--verbose` (or `-v`) to see each request and Raylib's startup details again.

## 0.3.107

- Fixed trains vanishing from the board, which could leave it empty until the next update. The check for trains silent for 48 hours read Amtraker's milliseconds as seconds, so it really hid trains after about 3 minutes.

## 0.3.106

- The header now shows the station's real name, such as `NEW YORK PENN, NY`, instead of `STATION NYP` when you type a station code. The name comes from Amtraker and appears once the station loads.

## 0.3.105

- Added packaging scripts for Linux, Windows, and macOS in `packaging`. Only the Linux one has been run so far.
- Added `--version`, and `--check-interface`, which checks the interface documents without opening a window.
- The app now looks for its interface documents in an `Interface` folder beside itself, or in `Contents/Resources` in a Mac app, before SwiftPM's resource bundle.

## 0.3.104

- Fixed the window flickering on Linux. The render loop now stays on the main thread that owns the OpenGL context, and train data loads in the background.
- The board and station picker are now described by XML files in `Sources/AmtrakStatus/Interface`, using Hudini's UIScript.
- The board no longer goes blank when Amtraker has no arrival or departure time for a stop, or when one train can't be read. The footer names what is missing, and says how old the data is when an update fails.
- Times show AM and PM correctly, in a wider column, and the version shows without Git details. Updated GitVersion to 0.2.0.
- Tiles keep their place on the board, so new trains flip over what was there. Flips no longer flash at the end.
- Escape now closes the picker instead of quitting. It still quits from the board.
- Clicking the station code field is now required before typing, because Hudini has no way to focus it yet.

## 0.2.104

- Client now checks for any stale trains that are 48 hours old.
- Finally gave Amtraker credit.

## 0.2.103

- A new column after number has "Enroute," "Station," and "Departed" status. It's left blank since status is already taken.

## 0.2.102

- The status bar at the bottom now shows ``It is <time> at <station> station``.

## 0.2.101

Completely rewrote from scratch (except the ported models) using [SwiftCrossUI](https://github.com/moreSwift/swift-cross-ui). This new version now adopts to whatever system it was compiled for. A huge step above from pointing to a web page. While this did involve a lot of work to get it back up to speed, it was wroth it.

## 0.1.104

- New buttons for major terminals and rail cams.
- Version displayed above credits.

## 0.1.102

- Redesigned icons
- Added banner above form

## 0.1.101

- First public prototype