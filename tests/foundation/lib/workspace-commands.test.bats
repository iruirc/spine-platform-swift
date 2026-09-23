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

@test "both s06b branches hand the tests axis to swift-init" {
  local s="$(ws_repo_root)/skills/workspace-init/SKILL.md"
  local n; n="$(grep -o -- '--tests=' "$s" | wc -l | tr -d ' ')"
  [ "$n" -ge 2 ] || { echo "s06b names --tests $n time(s); interactive and batch both need it"; return 1; }
}
