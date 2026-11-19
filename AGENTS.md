# Project Guidelines

AmtrakStatus is a Swift executable that presents real-time Amtraker train status.
The local `AmtrakClient` package owns API requests, decoded response models, and
response caching; the executable owns presentation, interface layout, and
application behavior.

The main interface is a Raylib split-flap-style train status display modeled
after public transport timetables, opening by default on Ashland, Virginia (ASD).
Hudini's UIScript documents in `Sources/AmtrakStatus/Interface` describe its
layout, colors, and text.

## Project Structure

| Path                                                    | Contents                                                                                       |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `Sources/AmtrakStatus/AmtrakStatusApp.swift`            | Synchronous entry point, CLI arguments, window setup, and the render loop.                     |
| `Sources/AmtrakStatus/TrainBoardScreen.swift`           | Fills `board.uix`, draws split-flap columns, and handles board input and scrolling.            |
| `Sources/AmtrakStatus/TrainBoardModel.swift`            | Board state, train row collections, look-ahead filter, and refreshes.                          |
| `Sources/AmtrakStatus/TrainStatusLoader.swift`          | Fetches trains off the main thread, drops departed and stale ones, returns rows via `Mailbox`. |
| `Sources/AmtrakStatus/SplitFlapBoard.swift`             | Split-flap character matrix and column animation state.                                        |
| `Sources/AmtrakStatus/SplitFlapRenderer.swift`          | Draws split-flap tiles: rounded corners, the hinge, and falling flaps.                         |
| `Sources/AmtrakStatus/StationPicker.swift`              | Station picker window: a typed station code or preset station buttons.                         |
| `Sources/AmtrakStatus/BoardRowText.swift`               | Formats each column's text for a train row.                                                    |
| `Sources/AmtrakStatus/BoardText.swift`                  | Tab-separated board text for `--print`.                                                        |
| `Sources/AmtrakStatus/BoardDateFormatting.swift`        | Station-local time zone date formatting, weekdays, and midnight tags.                          |
| `Sources/AmtrakStatus/InterfaceDocument.swift`          | Loads and parses UIScript interface documents via Hudini.                                      |
| `Sources/AmtrakStatus/InterfaceFont.swift`              | Loads the Overpass and B612 Mono fonts, ASCII glyphs only.                                     |
| `Sources/AmtrakStatus/Mailbox.swift`                    | Thread-safe FIFO queue passing async fetch results to render loop.                             |
| `Sources/AmtrakStatus/Models.swift`                     | Presentation models (`TrainStatusRow`, `BoardColumn`).                                         |
| `Sources/AmtrakStatus/LateTrain.swift`                  | How early or late a train is.                                                                  |
| `Sources/AmtrakStatus/Interface/`                       | UIScript documents (`board.uix`, `station-picker.uix`) and fonts.                              |
| `AmtrakClient/Sources/AmtrakClient/AmtrakClient.swift`  | HTTP client requesting station train data from the Amtraker API.                               |
| `AmtrakClient/Sources/AmtrakClient/ResponseCache.swift` | Disk cache storing responses and fetch timestamps per station URL.                             |
| `AmtrakClient/Sources/AmtrakClient/Models.swift`        | Decodable Amtraker API station, train, and stop response models.                               |
| `AmtrakClient/Sources/AmtrakClient/FetchRecord.swift`   | Metadata recording fetch outcomes, cache hits, and response ages.                              |
| `Tests/AmtrakStatusTests/`                              | Headless unit tests for board modeling, caching, and text formatting.                          |
| `packaging/`                                            | Multiplatform release packaging scripts and environment setup.                                 |
| `GitVersion.txt`                                        | Baseline semantic version when no Git tag or branch supplies one.                              |
| `changelog.md`                                          | User-facing release notes by version.                                                          |
| `README.md`                                             | User-facing setup, flags, station display, and packaging docs.                                 |

## Build and Test

- Build the executable with `swift build`.
- Run the application with `swift run AmtrakStatus` (or `swift run AmtrakStatus -s <STATION>`).
- Run the test suite with `swift test`.
- Keep logic that does not require graphics headless-testable. Use a runtime or
  visual check for behavior that depends on a Raylib window or user input.
- Release packages are built using the scripts in `packaging/`. If runtime files
  or assets are added, add them to `stage` in `packaging/env.sh`.

## Golden Rules

### Design Process

- **Iterate**. A first design or name is a draft. Rebuild clumsy parts as understanding improves.
- **Ask when a decision is open**, and explain the reasoning behind what you suggest.
- **Keep it simple**. The simplest approach that matches what the application does wins.
- **Say what you're unsure of**: assumptions, unverified behavior, and what needs testing.

### Never Crash (Outranks Feature Work)

AmtrakStatus is a board people leave running: a trap closes the window with no
explanation, and nothing is left on screen to say what went wrong. Stability
outranks features.

- **Treat any trap as a crash**: force unwrapping (`!`), `try!`, `as!`, an
  out-of-range index or slice, an integer overflow, an unchecked division, a
  failed `precondition`, or `fatalError`. None of them may depend on API data,
  cached files, or user input. Hudini and raylib-swift have preconditions of
  their own, such as `WindowManager.open` needing a frame made with
  `WindowFrame(view:)`; meet them in code rather than leaning on them.
- **Validate everything that crosses a boundary**: command-line options (in
  `validate()`), station codes typed into the picker (`StationChoice`),
  Amtraker responses, cached responses read from disk, and the interface
  documents and fonts.
- **Fail clearly, and only before the window opens.** A bad option or a missing
  interface document exits with a message on standard error and a non-zero
  status, as does a failed fetch under `--print`. Once the window is open, only
  the user closes it: a failed refresh, an unknown station, or an unreadable
  cache becomes a message on the board, and a missing font falls back to
  raylib's font with a warning.
- **Keep the entry point synchronous and the render loop on the main thread.**
  A loop that leaves the main thread doesn't trap, but it fails as badly: the
  OpenGL context belongs to one thread, so on Linux the window flickers or draws
  nothing. Do not use `AsyncParsableCommand`, `@MainActor`, or `await` in the
  loop, and nothing drains the main actor, so work sent to it never runs.
  Background tasks return results through `Mailbox`.
- **Make Raylib calls only on the main thread, while the window is open.** Keep
  data fetching and state updates separate from drawing.
- **Use the resolved raylib-swift API.** Don't assume C function names or docs for
  another raylib version match its Swift API.
- **Prefer `guard let`, failable initializers, and thrown errors** over
  assertions. The app's one `precondition` checks the main thread at startup,
  before any window exists.
- **Add a focused regression test** for any crash, malformed data issue, or
  layout edge case.

### Train Status and API Separation

- **Keep `AmtrakClient` strictly separated from presentation.** `AmtrakClient`
  owns network requests, response decoding, and cache policies. `AmtrakStatus`
  consumes these models and handles filtering, timetable windows, and display.
- **Never report stale or missing data as current.** When an API request fails,
  clearly communicate the condition (retaining cached rows with clear stale
  indicators or showing an error banner) rather than silently presenting stale
  or empty data as up to date.
- **Calculate dates in the station's time zone.** Today is the station's day,
  not the local computer's. Format scheduled times, estimates, weekday markers,
  and midnight rollovers according to the station's local time zone.
- **Respect train lifecycles.** A train leaves the board once it departs, and
  stays while arriving or at the platform. Trains silent for more than 48 hours
  count as stale and are excluded.
- **Maintain stable row ordering.** Trains that share a scheduled or estimated
  time keep consistent relative ordering between refreshes.

### Split-Flap and Interface Design

- **Put design values in UIScript documents.** Layout, colors, margins, and
  text belong in `Sources/AmtrakStatus/Interface` documents rather than in Swift.
  Fonts (`InterfaceFont.swift`) and split-flap corner radii (`SplitFlapRenderer.swift`)
  remain in Swift only until Hudini expresses them.
- **Constrain characters to the board font's glyph set.** Split-flap text is
  uppercased, padded or truncated to tile column widths, and characters outside
  the board font's glyphs are mapped or replaced. The fonts load ASCII glyphs only, so text
  the app writes into other controls, such as the footer, stays ASCII too.
- **Keep flip animations smooth and stable.** Tiles flip through full animation
  durations. Unchanged text does not trigger flip restarts, and window resizing
  or station changes must not leave orphaned tile states.

### Build, Packaging, and Releases

- **Keep non-graphics logic headless-testable.** Data loading, response caching,
  timetable look-ahead filtering, and text formatting must be tested in
  `AmtrakStatusTests` without requiring a display context.
- **Match Swift tools version, formatting, and naming.** Follow package tools
  version rules and conventions established in the codebase.
- **Keep documentation and packaging in step.** Update `packaging/env.sh` when
  runtime assets change, and keep `README.md` and `changelog.md` up to date with
  user-visible options or behavioral changes.

## Personal Configuration

Keep personal preferences and machine-specific guidance in git-ignored `*.local`
files or directories (such as `AGENTS.local.md`), rather than in shared project
instructions. Check for relevant local guidance before environment-specific work.
You can create or update these files for details such as:

- Coding preferences
- Local build and development environment
- Personal shortcuts or workflows

See [REVIEW.md](REVIEW.md) for the project's review checklist.
