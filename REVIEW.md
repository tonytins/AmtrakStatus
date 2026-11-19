# Review Guide

Use this checklist when reviewing a change to AmtrakStatus or its local
`AmtrakClient` package. It is adapted from the contributor and review practices in
[NVIDIA FLARE's contribution guide](https://github.com/NVIDIA/NVFlare/blob/main/CONTRIBUTING.md),
by way of [Hudini](https://github.com/tonytins/Hudini), with checks tailored to
this Swift package and split-flap train status display. The rules it checks
against are in [AGENTS.md](AGENTS.md).

## Before Reviewing

- Read the change description and the relevant code, tests, and interface documents.
- Identify the user-visible behavior the change is intended to address, including
  station selection, timetable look-ahead, error recovery, or split-flap presentation.
- Check available build and test results. Run `swift build` and `swift test` when
  the change or its verification warrants it. For changes touching the Raylib
  window, user input, or split-flap drawing, perform a runtime visual check
  (`swift run AmtrakStatus`). Report checks that could not be run.

## Review Checklist

- Does the entry point remain synchronous and the render loop on the main thread?
  Are `@MainActor`, `await`, and `AsyncParsableCommand` avoided in the loop so
  OpenGL contexts never desync or cause window flickering on Linux?
- Are background data fetches executed strictly off the main thread and passed
  back safely via `Mailbox`?
- Can user input, station codes, or malformed API responses reach a trap (`!`,
  `try!`, `as!`, string indexing, out-of-range slice, or unchecked integer math)?
  Are errors caught and handled gracefully without crashing the application?
- Does `AmtrakClient` own API requests, response decoding, and disk caching
  without leaking networking logic into the executable?
- Are stale, delayed, or unavailable train data communicated accurately rather
  than presented as current status?
- Are dates, estimates, and midnight rollovers calculated in the station's time
  zone rather than the local machine's time zone?
- Is split-flap text correctly uppercased, clipped, padded, and restricted to
  glyphs supported by the board font?
- Do flip animations transition smoothly across full durations without jitter,
  unwanted resets on unchanged text, or orphaned tile states during window resize?
- Are layout, colors, and margins defined in UIScript documents
  (`Sources/AmtrakStatus/Interface`) instead of hardcoded in Swift?
- Do focused tests in `AmtrakStatusTests` cover changed model, formatting, or
  caching behavior?
- If runtime assets or package dependencies changed, are `packaging/env.sh`,
  `README.md`, and `changelog.md` updated?

## Writing Review Comments

- Report concrete correctness, stability, compatibility, or missing-test
  concerns; do not block changes on personal style preferences.
- Make each comment specific, constructive, and actionable. Point to the
  smallest relevant location and explain the impact and a useful next step.
- Prioritize findings by impact:
  - **Blocking**: prevents the package from building, causes traps or crashes,
    breaks the main-thread render loop, or presents inaccurate train status
    as current.
  - **High**: breaks an existing user flow, CLI option, station refresh mechanism,
    or leaves an input boundary unvalidated.
  - **Medium**: causes a limited visual glitch, animation hiccup, formatting
    irregularity, or leaves docs describing something that isn't true.
  - **Low**: a small edge case or non-blocking improvement.
- If no actionable issues remain, say so and note any important checks that
  were not run.
