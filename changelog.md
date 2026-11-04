# Change Log

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