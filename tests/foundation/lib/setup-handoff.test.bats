#!/usr/bin/env bats
# The config writers here hand everything to spine-toolkit:setup through its
# `## Input`. No zsh driver can run that call, so these pin what each one passes.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  WS="$ROOT/skills/workspace-init/SKILL.md"
  INIT="$ROOT/agents/swift-init.md"
}

# The row of workspace-init's step table whose first cell is the given step id.
step_row() { grep -E "^\| $1 \|" "$WS"; }

@test "the meta-repo config step hands every answer to setup" {
  row="$(step_row s02b_meta_config)"
  [ -n "$row" ] || { echo "no s02b_meta_config row"; return 1; }
  for want in 'spine-toolkit:setup' '`platform = spine-platform-swift`' '`defaults.tests`' \
              '`defaults.platforms`' '`tasks = skip`' '`docs_map = skip`' '`wsyml::toolkit`' \
              '`wsproj::append_workspace_meta <root>`' '`wsproj::append_paths <root>`'; do
    grep -qF -- "$want" <<<"$row" || { echo "s02b row lacks: $want"; return 1; }
  done
}

@test "the meta-repo config step calls setup only while no config exists" {
  step_row s02b_meta_config | grep -qF 'Only if `<root>/SPINE.md` is absent'
}

@test "the meta-repo config step never hands setup the template's placeholder stack" {
  run step_row s02b_meta_config
  [ -n "$output" ] || { echo "no s02b_meta_config row"; return 1; }
  [[ "$output" != *'`stack = —`'* ]] || { echo "s02b still passes an empty stack"; return 1; }
}

@test "the meta-repo config step runs after the apps: its row follows the last per-app step" {
  local ids; ids="$(grep -oE '^\| s[0-9a-z_<>]+ \|' "$WS" | tr -d '| ')"
  local after; after="$(grep -A1 -xF 's06e_project_git_<app>' <<<"$ids" | tail -n 1)"
  [ "$after" = s02b_meta_config ] || { echo "after s06e comes: $after"; return 1; }
}

@test "the app repo gets no Workspace meta of its own: no s06d step anywhere in the skill" {
  run grep -c 's06d' "$WS"
  [ "$output" = 0 ] || { grep -n 's06d' "$WS"; return 1; }
}

@test "the skill names the workspace root <root>, never <meta> or <workspace-parent>" {
  run grep -nE '<meta>|<workspace-parent>|-meta/' "$WS"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "the dialog asks the three toolkit answers" {
  for key in qa_toolkit_lang qa_toolkit_mode qa_toolkit_progress; do
    grep -qF "\`$key\`" "$WS" || { echo "SKILL.md never asks $key"; return 1; }
  done
}

@test "swift-init offers all five setup answers as flags" {
  for flag in '--lang=en|ru' '--mode=manual|auto' '--progress=quiet|normal|live' \
              '--tasks=create|skip' '--docs-map=create|skip'; do
    grep -qF -- "[$flag]" "$INIT" || { echo "flag list lacks [$flag]"; return 1; }
  done
}

@test "under --no-prompt an absent answer takes its default, not a question" {
  grep -qF '`en`, `manual`, `normal`, `skip`, `skip`' "$INIT"
}

@test "workspace-init keeps Tasks/ out of the project repo in both modes" {
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" ios interactive
  [[ "$output" == *"--tasks=skip"* ]] || { echo "interactive flags lack --tasks=skip"; return 1; }
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" ios batch
  [[ "$output" == *"--tasks=skip"* ]] || { echo "batch flags lack --tasks=skip"; return 1; }
}

@test "no file names the flag that --tasks replaced" {
  all="$(grep -rlF --exclude-dir=.git --exclude-dir=.superpowers -- '--with-tasks' "$ROOT" || true)"
  grep -qF 'setup-handoff.test.bats' <<<"$all" || { echo "the scan did not reach this file"; return 1; }
  hits="$(grep -vF 'setup-handoff.test.bats' <<<"$all" || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

@test "swift-init leaves Tasks/ to setup" {
  grep -qF -- '- A `Tasks/` folder' "$INIT" || { echo "What NOT to Generate does not name Tasks/"; return 1; }
  ! grep -qF 'subfolders `TODO/`, `ACTIVE/`, `DONE/`' "$INIT"
}

@test "the meta-repo config step names the directory setup runs in" {
  step_row s02b_meta_config | grep -qF 'with `<root>` as the working directory'
}

@test "swift-init names the directory setup runs in" {
  grep -qF 'as the working directory, and fill its `## Input`' "$INIT"
}

@test "s06b counts swift-init done by its project and config, not by a marker" {
  step_row 's06b_project_<app>' \
    | grep -qF "\`[[ -f <root>/<app_dir>/project.yml ]] && grep -q '^## Platform\$' <root>/SPINE.md\`"
}

@test "s06_pkg recovers its own interrupted render on --resume" {
  step_row 's06_pkg_<name>' | grep -qF "own interrupted render" || { echo "s06_pkg row lacks recovery clause"; return 1; }
}

@test "no file names the marker swift-init never wrote" {
  all="$(grep -rlF --exclude-dir=.git --exclude-dir=.superpowers '.swift-init.done' "$ROOT" || true)"
  grep -qF 'setup-handoff.test.bats' <<<"$all" || { echo "the scan did not reach this file"; return 1; }
  hits="$(grep -vF 'setup-handoff.test.bats' <<<"$all" || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}
