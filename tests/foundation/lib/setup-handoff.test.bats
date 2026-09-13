#!/usr/bin/env bats
# The config writers here hand everything to spine-toolkit:setup through its
# `## Input`. No zsh driver can run that call, so these pin what each one passes.

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
  for want in 'spine-toolkit:setup' '`platform = spine-platform-swift`' '`stack = —`' \
              '`tasks = skip`' '`docs_map = skip`' '`wsyml::toolkit`' \
              '`wsproj::append_workspace_meta <meta> meta`'; do
    grep -qF -- "$want" <<<"$row" || { echo "s02b row lacks: $want"; return 1; }
  done
}

@test "the meta-repo config step calls setup only while no config exists" {
  step_row s02b_meta_config | grep -qF 'Only if `<meta>/CLAUDE-spine-toolkit.md` is absent'
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
  row="$(step_row 's06b_project_<app>')"
  [ -n "$row" ] || { echo "no s06b row"; return 1; }
  [ "$(grep -oF -- '--tasks=skip' <<<"$row" | wc -l | tr -d ' ')" -eq 2 ] \
    || { echo "--tasks=skip is not in both invocations"; return 1; }
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
  step_row s02b_meta_config | grep -qF 'with `<meta>` as the working directory'
}

@test "swift-init names the directory setup runs in" {
  grep -qF 'as the working directory, and fill its `## Input`' "$INIT"
}

@test "s06b counts swift-init done by its project and config, not by a marker" {
  step_row 's06b_project_<app>' \
    | grep -qF "\`[[ -f <repo>/project.yml ]] && grep -q '^## Platform\$' <repo>/CLAUDE-spine-toolkit.md\`"
}

@test "no file names the marker swift-init never wrote" {
  all="$(grep -rlF --exclude-dir=.git --exclude-dir=.superpowers '.swift-init.done' "$ROOT" || true)"
  grep -qF 'setup-handoff.test.bats' <<<"$all" || { echo "the scan did not reach this file"; return 1; }
  hits="$(grep -vF 'setup-handoff.test.bats' <<<"$all" || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}
