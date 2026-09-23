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
  grep -qF -- '--tests=<wspkg::tests_kind>' "$s" \
    || { echo "the interactive branch does not pass the workspace default"; return 1; }
  grep -qF -- '--tests=<apps.<key>.stack.tests, else wspkg::tests_kind>' "$s" \
    || { echo "the batch branch does not carry the per-app override"; return 1; }
}

@test "the qa_defaults_tests locale strings enumerate exactly the accepted tests tokens" {
  local locales="$(ws_repo_root)/skills/workspace-init/locales"
  local canonical
  canonical="$(zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; print -l \$WSYML_TESTS_KINDS" | sort -u)"
  # Both sides empty compares equal, so a guard without this passes once the array or the locale
  # block disappears — two guards on this branch were already caught passing that way.
  [ -n "$canonical" ] || { echo "WSYML_TESTS_KINDS is empty; the scan went vacuous"; return 1; }
  local l tokens
  for l in en ru; do
    tokens="$(awk '/^## qa_defaults_tests$/ {on = 1; next} on && /^## / {exit} on' "$locales/$l.md" \
      | grep -oE '\[[^]]*\]' | tr -d '[]' | tr '|' '\n' | sed -E 's/\([^)]*\)//g' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)"
    [ -n "$tokens" ] || { echo "$l.md: no qa_defaults_tests token list; the scan went vacuous"; return 1; }
    [ "$tokens" = "$canonical" ] || {
      echo "$l.md disagrees with the accepted tests tokens:"
      diff <(printf '%s\n' "$tokens") <(printf '%s\n' "$canonical")
      return 1
    }
  done
}
