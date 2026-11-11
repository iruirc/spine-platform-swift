# Foundation tests

`lib/` holds the unit suite: guards on skill, agent and manifest text, and the zsh libraries of
`templates/workspace/lib/` called one function at a time. `integration/` builds whole workspaces.
`scripts/test-foundation.sh` runs them: `unit`, `integration`, `all`, or `changed`.

## What a run costs

`all` takes about ten minutes, and `integration` is four fifths of it (measured on 1.33.2: 485 s of
594 s, 519 tests). Every integration file builds a temporary workspace through
`helpers/ws-init-driver.zsh`, which sources all of `templates/workspace/lib/`, renders the templates
and runs `scripts/workspace-docs-regen.zsh`; `workspace-docs-regen.test.bats` alone is about five
minutes. `unit` is about a minute and a half.

A change outside that path cannot move an integration test, so a task does not pay for it.

## What to run

Per task and per commit, run what the change touches — `scripts/test-foundation.sh changed` picks it
from the branch's diff against `main` (set `TEST_BASE` for another base), uncommitted and untracked
files included, and prints which file led to which choice:

| The change touches | Run |
|---|---|
| `templates/workspace/`, `scripts/workspace-docs-regen.zsh`, `tests/foundation/helpers/`, `tests/foundation/fixtures/` | `all` |
| `skills/workspace-add/locales/` | `unit` and `integration/workspace-add-incorporate.test.bats`, which reads them |
| a test file under `lib/` or `integration/` | that file |
| anything else | `unit` |

While iterating on one file, run it alone with `bats <file>` and narrow it with
`bats --filter '<regex>'`.

Before merging a branch and before a release, run `all`, whatever the branch touched. The run is
green only with no `not ok`; compare its `ok` count with `main`.
