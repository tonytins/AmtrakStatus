# Project Guidelines

## Project structure

AmtrakStatus is a Swift executable that presents Amtraker train status. The
local `AmtrakClient` package owns API requests and decoded response models; the
executable owns presentation and application behavior.

The main interface is a Raylib split-flap-style train status display modeled
after public transport timetables, opening on Ashland, Virginia (ASD). Hudini's
UIScript documents in `Sources/AmtrakStatus/Interface` describe its layout,
colors, and text. Keep these responsibilities separate: API data belongs in
`AmtrakClient`, while display and interaction logic belongs in the executable.
Put design values in the documents rather than in Swift. The one exception is
fonts: UIScript can't name a font yet, so `InterfaceFont.swift` names them until
Hudini can.

## Swift and graphics

- Match the Swift tools version, formatting, and established naming in the
  package and its targets.
- Keep public package APIs clear at the call site and document behavior that
  is not clear from their names.
- Use the APIs from the resolved raylib-swift dependency. Do not assume C
  function names or documentation for a different version match its Swift API.
- Keep data fetching and state updates separate from drawing where practical.
  Perform Raylib drawing only while the graphics context is available.
- Keep the entry point synchronous and the render loop on the main thread. Do not
  use `AsyncParsableCommand`, `@MainActor`, or `await` in the loop: on Linux they
  move frames to threads without the OpenGL context, which makes the window
  flicker. Nothing drains the main actor, so work sent to it never runs. Background
  tasks return results through `Mailbox`.
- Preserve useful existing AmtrakClient behavior while changing the interface.

## Build and review

- Use the package's existing SwiftPM and project commands when validation is
  appropriate. Report checks that were not run.
- Keep logic that does not require graphics headless-testable. Use a runtime or
  visual check for behavior that depends on a Raylib window.
- Update the relevant documentation when user-visible behavior or project
  setup changes.
- The scripts in `packaging` build the release packages, each on its own
  platform. See [packaging/README.md](packaging/README.md). If the app gains
  files it needs at runtime, add them to `stage` in `packaging/env.sh`.

See [REVIEW.md](REVIEW.md) for the review checklist.

## Personal Configuration

Keep personal preferences and machine-specific guidance in git-ignored
`*.local` files or directories, rather than in shared project instructions.
Check for relevant local guidance before environment-specific work. You can
create or update these files for details such as:

- Coding preferences
- Local build and development environment
- Personal shortcuts or workflows
