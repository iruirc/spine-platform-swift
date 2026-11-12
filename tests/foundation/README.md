# Foundation tests

`lib/` holds the unit suite: guards on skill, agent and manifest text, and the zsh libraries of
`templates/workspace/lib/` called one function at a time. `integration/` builds whole workspaces.
`scripts/test-foundation.sh` runs them: `unit`, `integration`, `all`, or `changed`.

## What a run costs

`all` takes about four minutes, and `integration` is two thirds of it (measured on 1.33.2: 252 s,
521 tests). Every integration file builds a temporary workspace through
`helpers/ws-init-driver.zsh`, which sources all of `templates/workspace/lib/`, renders the templates
and runs `scripts/workspace-docs-regen.zsh` — a few seconds a build. `unit` is about a minute
and a half.

A change outside that path cannot move an integration test, so a task does not pay for it.

A file whose tests all start from the same workspace builds it once, in `setup_file` with
`ws_build_template`, and gives each test a copy with `ws_copy_template`; `workspace-docs-regen` and
`workspace-add-incorporate` do. A new integration file does the same unless the build itself is
what it tests.

## What to run

Per task and per commit, run what the change touches — `scripts/test-foundation.sh changed` picks it
from the branch's diff against `main` (set `TEST_BASE` for another base) — on `main` itself, from
what is not pushed — uncommitted and untracked files included, and prints which file led to which
choice. With nothing changed it runs nothing.

| The change touches | Run |
|---|---|
| the `spine-toolkit` checkout beside this one (or `$SPINE_TOOLKIT_CORE`), compared the same way | `unit`: tests under `lib/` read core's files |
| `templates/workspace/`, `scripts/workspace-docs-regen.zsh`, `tests/foundation/helpers/`, `tests/foundation/fixtures/` | `all` |
| `skills/workspace-add/locales/` | `unit` and `integration/workspace-add-incorporate.test.bats`, which reads them |
| a test file under `lib/` or `integration/` | that file |
| anything else | `unit` |

While iterating on one file, run it alone with `bats <file>` and narrow it with
`bats --filter '<regex>'`.

Before merging a branch and before a release, run `all`, whatever the branch touched. The run is
green only with no `not ok`; compare its `ok` count with `main`.
