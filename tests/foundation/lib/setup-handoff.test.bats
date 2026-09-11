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
