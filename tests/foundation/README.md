# Foundation tests

`lib/` holds the unit suite: guards on skill, agent and manifest text, and the zsh libraries of
`templates/workspace/lib/` called one function at a time. `integration/` builds whole workspaces.
`scripts/test-foundation.sh` runs them: `unit`, `integration`, `all`, `changed`, or `verified`.
`touched <file>...` runs the `lib/` tests that name those files (a file under `skills/` is named by a
test that names its skill), and always the ones that read the
spine-toolkit checkout beside this repository. `touched` with no files takes what the next commit
would hold, the files that differ from `HEAD` (staged, unstaged and untracked), and says so and runs
nothing when there are none; a changed `lib/*.bats` runs itself, a fixture runs the whole `lib/`, and
a helper runs the `lib/` tests that load it, directly or through another helper. A green `all` on an
unchanged tree records it in `.git/spine-verified-trees`; so does a green `verified`, which runs the
`changed` selection for what differs from the newest tree there in the history of `HEAD`, plus the
tests that read the spine-toolkit checkout, and records `<tree> via <that tree>`. A release reads the
file to skip a rerun.

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

Inside a plan, before every commit, run `scripts/test-foundation.sh touched` with no files; outside
a plan, run `scripts/test-foundation.sh changed`. `spine-ops/WORKSPACE.md` → Tests says which and why.
`changed` picks the tests from the branch's diff against `main` (set `TEST_BASE` for another base) —
on `main` itself, from what is not pushed — uncommitted and untracked files included, and prints which
file led to which choice. With nothing changed it runs nothing.

| The change touches | Run |
|---|---|
| the `spine-toolkit` checkout beside this one (or `$SPINE_TOOLKIT_CORE`), compared the same way | `unit`: tests under `lib/` read core's files |
| `templates/workspace/`, `scripts/workspace-docs-regen.zsh`, `tests/foundation/helpers/`, `tests/foundation/fixtures/` | `all` |
| `skills/workspace-add/locales/` | `unit` and `integration/workspace-add-incorporate.test.bats`, which reads them |
| a test file under `lib/` or `integration/` | that file |
| anything else | `unit` |

While iterating on one file, run it alone with `bats <file>` and narrow it with
`bats --filter '<regex>'`.

Run `all` once on a branch, at the end of a plan or before merging, whatever the branch touched;
after a green `all`, check each further fix with `verified` (`spine-ops/WORKSPACE.md`). A release
runs the full suite only on a tree neither of them recorded. The run is
green only with no `not ok`; compare its `ok` count with `main`.
