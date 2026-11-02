# Review Guide

Use this checklist when reviewing changes to AmtrakStatus or its local
`AmtrakClient` package.

## Before reviewing

- Read the change description and the affected code and tests.
- Identify the intended user-visible behavior and confirm the change addresses
  it, including any relevant issue or design discussion.
- Check available build, test, and CI results. Run focused checks when
  appropriate, and report checks that could not be run.

## Review checklist

- Does the behavior match the stated intent, including missing, stale, or
  delayed train data and unknown station or status values?
- Does the executable consume API data through `AmtrakClient` rather than
  duplicating networking or response-model logic?
- Are API errors and unavailable data communicated clearly instead of shown as
  valid or current train status?
- Does asynchronous data loading leave the interface responsive and keep the
  displayed status associated with the selected station?
- Is the split-flap display legible and stable for long or short text, changing
  status values, and window resizing?
- Are Raylib calls made only while the required window and graphics context
  are available? Are graphics-dependent behaviors checked at runtime when
  headless tests are insufficient?
- Do focused tests cover changed data or presentation behavior? Are relevant
  setup instructions and documentation updated?

## Writing review comments

- Report concrete correctness, compatibility, reliability, or missing-check
  concerns. Do not block a change on personal style preferences.
- Make each comment specific and actionable. Identify the smallest relevant
  location, explain the impact, and suggest a useful next step.
- Prioritize findings by impact:
  - **Blocking**: prevents the application from building or causes severe,
    unavoidable failure during normal use.
  - **High**: breaks an existing behavior or a common user flow.
  - **Medium**: causes a limited but meaningful behavior or reliability issue.
  - **Low**: identifies a small edge case or non-blocking improvement.
- If no actionable issues remain, say so and note important checks that were
  not run.
