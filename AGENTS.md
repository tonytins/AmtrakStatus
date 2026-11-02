# Project Guidelines

## Project structure

AmtrakStatus is a Swift executable that presents Amtraker train status. The
local `AmtrakClient` package owns API requests and decoded response models; the
executable owns presentation and application behavior.

The planned main interface is a Raylib split-flap-style train status display modeled after public transport timetables,
initially fixed to Ashland, Virginia (ASD). Hudini will be considered for
additional interface elements in a later phase. Keep these responsibilities
separate: API data belongs in `AmtrakClient`, while display and interaction
logic belongs in the executable.

## Swift and graphics

- Match the Swift tools version, formatting, and established naming in the
  package and its targets.
- Keep public package APIs clear at the call site and document behavior that
  is not clear from their names.
- Use the APIs from the resolved raylib-swift dependency. Do not assume C
  function names or documentation for a different version match its Swift API.
- Keep data fetching and state updates separate from drawing where practical.
  Perform Raylib drawing only while the graphics context is available.
- Preserve useful existing AmtrakClient behavior while changing the interface.

## Build and review

- Use the package's existing SwiftPM and project commands when validation is
  appropriate. Report checks that were not run.
- Keep logic that does not require graphics headless-testable. Use a runtime or
  visual check for behavior that depends on a Raylib window.
- Update the relevant documentation when user-visible behavior or project
  setup changes.

See [REVIEW.md](REVIEW.md) for the review checklist.

## Personal Configuration

Keep personal preferences and machine-specific guidance in git-ignored
`*.local` files or directories, rather than in shared project instructions.
Check for relevant local guidance before environment-specific work. You can
create or update these files for details such as:

- Coding preferences
- Local build and development environment
- Personal shortcuts or workflows
