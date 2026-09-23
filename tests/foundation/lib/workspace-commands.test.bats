#!/usr/bin/env bats
# Templates render into the user's repositories, where an agent reads a named command as one it can run.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every workspace command the plugin's text names is a command it ships" {
  n="$(ls "$ROOT"/commands/workspace-*.md | wc -l | tr -d ' ')"
  [ "$n" -ge 3 ] || { echo "found $n workspace commands; the scan went vacuous"; return 1; }
  named="$(cd "$ROOT" && grep -rhoE '`workspace-[a-z-]+\\?[` ]' templates skills agents commands README.md \
    | sed -E 's/^`(workspace-[a-z-]+).*/\1/' | LC_ALL=C sort -u)"
  [ -n "$named" ] || { echo "no workspace command named anywhere; the scan went vacuous"; return 1; }
  missing=""
  while IFS= read -r c; do
    [ -f "$ROOT/commands/$c.md" ] || missing="$missing $c"
  done <<<"$named"
  [ -z "$missing" ] || { echo "named but not shipped:$missing"; return 1; }
}

@test "both s06b branches hand the tests axis to swift-init, each with its own precedence" {
  local s="$(ws_repo_root)/skills/workspace-init/SKILL.md"
  # Counting occurrences would pass on two identical flags. Each branch is pinned to the value it
  # must carry: interactive applies no overlay, so the workspace answer is what swift-init
  # pre-answers with; batch is the only mode that applies one, so it is the only place the per-app
  # override can take effect and the only place it must be named.
  grep -qF -- '--tests=<defaults.tests>' "$s" \
    || { echo "the interactive branch does not pass the workspace default"; return 1; }
  grep -qF -- '--tests=<apps.<key>.stack.tests, else defaults.tests>' "$s" \
    || { echo "the batch branch does not carry the per-app override"; return 1; }
}
