---
name: swift-setup
description: |
  Platform half of project setup for Swift/Apple projects. Asks the stack questions of swift-platform's manifest axes and writes the ## Stack and ## Modules blocks of an existing CLAUDE-spine-toolkit.md. Invoked by spine-toolkit:setup, which owns the config file and every other block; not invoked by the user directly.
  Use when (en): spine-toolkit:setup hands the platform its own config blocks
  Use when (ru): spine-toolkit:setup передаёт платформе её блоки конфига
---

# Swift Setup

The platform half of `/setup`. `spine-toolkit:setup` owns the config file — it creates
`CLAUDE-spine-toolkit.md`, writes `## Language`, `## Mode`, `## Progress`, `## Platform` and the
`CLAUDE.md` import line, then hands this skill the two blocks that are the platform's:
**`## Stack` and `## Modules`**. This skill touches nothing else in the file and creates no file
of its own.

It is reached through the `setup` row of swift-platform's manifest `## Entrypoints`. That row is the
whole binding; core never hardcodes this skill's name.

The skill does NOT create an Xcode project, does NOT modify Swift code, and does NOT start any
workflow. To generate a project from scratch, use the `@swift-platform:swift-init` agent (via the
`/swift-init` slash command).

## Language Resolution

Special case for a delegate: `<lang>` arrives in the input from `spine-toolkit:setup`, which
resolved it before the config existed. Use it and skip steps 1-4. Otherwise, before producing any
user-facing string:

1. Read `CLAUDE-spine-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with the key name.

Caching: resolve `<lang>` once per skill invocation.

## Agent Tooling

`AUQ` means the structured question mechanism. If the active host cannot provide a structured
question tool, ask numbered options in a regular message and parse the reply. Locale keys with the
`auq_` prefix remain the canonical prompt/option keys.

## Input

```
lang        = en | ru                       # resolved by spine-toolkit:setup
state       = A | B | C | D | E             # its State Detection branch, informational
config_path = path to CLAUDE-spine-toolkit.md   # already written, core blocks filled
stack       = {axis: value, …}              # answers core's caller already collected; usually empty
```

`stack` is what `/swift-init` gives back: the scaffolding agent has just asked the user for the UI
framework, async approach, DI and architecture, and an axis whose answer arrives here as an `## Axes`
value is not asked about again. Core forwards it without reading it, so the values are checked
here — against `## Axes`, like any other answer, and only for an axis the config has not already
answered.

Nothing below branches on `state`: what matters is whether the config's `## Stack` already carries
axis lines, and the file answers that directly. Keying on the data rather than on the branch is what
keeps a state added later from silently skipping reconciliation.

## Algorithm

```
1. Detect a Swift project:
   Check for .xcodeproj / .xcworkspace / Package.swift in the root.
   ↓ if none → render `error_not_swift_project`. Return without writing. Core reports the
     project as configured with ## Stack left unset — spine-toolkit still works, one AUQ per
     axis per task, and nothing this skill would have written was knowable anyway.

2. Read ## Stack from config_path.
   ↓ it holds only the template's placeholder (states A, B, C) → no axis has a value yet;
     go to the overlay below with all six unresolved.
   ↓ it holds `- <Label>: <value>` lines (states D and E — a config migrated from an older
     layout) → reconcile the labels against the manifest's current ## Axes before asking
     anything (see Axis Reconciliation). A surviving line is that axis's value UNLESS its
     value is still an angle-bracketed option list: the legacy templates shipped ## Stack
     unfilled (`- UI: <SwiftUI | UIKit | AppKit>`), so a project that installed the toolkit
     and never answered the stack questions has lines that parse but hold no answer. Those
     are unresolved — writing one through would put a string no ## Axes value matches into
     the config and announce it as unchanged.
     Only the axes with no surviving answered line are unresolved.

   Then fill the still-unresolved axes — and only those — from the input's `stack`. The config
   wins wherever it holds an answered line: `## Input` is open to any caller, and replacing an
   axis the user once answered with a caller's value, silently and with no report line, is the
   same edit Axis Reconciliation exists to prevent. `/swift-init` loses nothing to that rule — it
   arrives in state A, where every axis is unresolved. Take an input value only if this manifest's
   ## Axes lists it for that axis; one it does not list is ignored and its axis stays unresolved,
   because the caller spelled it in its own vocabulary — `swiftui` for `SwiftUI`, or a deployment
   target that has to be assembled into `iOS 17+` out of two flags — and one re-asked question is
   cheaper than a ## Stack line stack-detect will never match.

3. Ask q1–q6 for every axis still without a value after step 2 (see Stack Questions). Options
   come from the manifest's ## Axes for that axis — the manifest is the source of truth, this
   skill only labels the questions. Every axis already answered is skipped, so a caller that
   supplied five of six asks one question, not six.

4. Write ## Stack: one `- <Axis>: <value>` line per axis, in the manifest's ## Axes order,
   replacing the template's placeholder line or the migrated block — then, beneath them and
   verbatim, the lines step 2 preserved because their label matches no current axis. The
   rewrite is what makes `report_axis_unknown`'s "kept as it is" true; without it the skill
   drops a user's value while reporting that it kept it. `ecosystem` gets no line — it is a
   property of the platform, not of the project, and stack-detect excludes it.

5. Write ## Modules only when the project has local packages whose stack differs from the
   global one; otherwise leave the template's placeholder. A multi-target SPM package is the
   usual case that needs it.

6. Return {stack_lines, notes} to spine-toolkit:setup, which renders the one report. `notes`
   holds the step-2 reconciliation lines already rendered in <lang> — `report_axis_renamed`
   per rewrite, `report_axis_unknown` per line matching no current axis — and is empty when
   there was nothing to reconcile. This return is the only path those lines have to the user.
```

## Axis Reconciliation

Any config carrying `## Stack` lines from an older layout — a legacy single-file `CLAUDE.md`, or a
config core has just migrated off the pre-split name — was written against an older `## Axes`
catalog. An
axis this platform has since renamed leaves a line whose label matches nothing, and `stack-detect`
would silently never resolve that axis again.

Rewrite the label, keep the value:

| Old label | Current axis | Why |
|---|---|---|
| `Platform` | `Baseline` | The old name meant an Apple deployment target, not an ecosystem; `ecosystem` took the word. |

The values are unchanged by the rename (`iOS 17+` is a `baseline` value verbatim), so this is a
label rewrite and never a question: re-asking would spend a user's answer on something the file
already says correctly. Render each rewrite as `report_axis_renamed` and each unmatched label as
`report_axis_unknown`, and return both in `notes` (step 6) — an unreported rewrite is exactly the
silent config edit this table exists to avoid. A line whose label matches no current axis and no row
in the table above is left in place and written back by step 4, not dropped: losing a value the user
wrote is worse than carrying an unread line. A line whose *value* is still an angle-bracketed option
list is neither renamed nor kept — it is unanswered (step 2), so step 3 asks for it and step 4 writes
the answer under the current label.

## Stack Questions (q1–q6)

Labels from locale keys; **options from the manifest's `## Axes`**, never restated here — a second
copy of the catalog is exactly what the split removed.

- q1 — `ui` (`auq_q1_ui_label`)
- q2 — `async` (`auq_q2_async_label`)
- q3 — `di` (`auq_q3_di_label`)
- q4 — `architecture` (`auq_q4_arch_label`)
  - if the user says "I don't know" / "advise me" → run `architecture-choice`, bring its result
    back as q4 plus a one-line justification.
- q5 — `baseline` (`auq_q5_baseline_label`)
- q6 — `tests` (`auq_q6_tests_label`)

Axis values are proper nouns from the catalog and are **never translated**: the answer is matched
back against `## Axes`, so a localized option label resolves nothing.

## Edge cases

- **Not a Swift project** → `error_not_swift_project`. Return without writing.
- **AUQ unavailable** → text fallback with numbered options.
- **Config file absent** → this skill was invoked out of order. Say so and stop; `/setup` creates it.

## What this skill does NOT do

- Does NOT create or rename `CLAUDE-spine-toolkit.md`, `CLAUDE.md`, `Tasks/` or `Docs/` — that is `spine-toolkit:setup`.
- Does NOT write `## Language`, `## Mode`, `## Progress`, `## Platform` or `## Agents`.
- Does NOT create an Xcode project, `Package.swift`, sources, `.swiftlint.yml`, or `README.md` — that is `@swift-platform:swift-init`.
- Does NOT modify Swift code or existing project configs (Info.plist, Build Settings).
- Does NOT start workflows or call `orchestrator`.
- Does NOT init git, make commits, or install dependencies (SPM, CocoaPods, Carthage).
