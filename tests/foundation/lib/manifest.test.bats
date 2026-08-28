#!/usr/bin/env bats
# swift-platform's manifest is the four-table contract core/tests/fixtures/fixture-platform
# demonstrates: these tests check the real platform manifest against that same contract.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  M="$ROOT/skills/manifest/SKILL.md"
}

@test "manifest declares all four tables" {
  for s in Roles Axes Heuristics Topics; do
    grep -q "^## $s\$" "$M"
  done
}

@test "every role maps to an agent file that exists" {
  while read -r ref; do
    [ -f "$ROOT/agents/${ref#swift-platform:}.md" ]
  done < <(grep -oE 'swift-platform:swift-[a-z]+' "$M" | sort -u)
}

@test "every topic points at a skill that exists" {
  while read -r skill; do
    [ -d "$ROOT/skills/$skill" ]
  done < <(sed -n '/^## Topics/,/^## /p' "$M" | grep -oE '`[a-z][a-z-]+`' | tr -d '`' | sort -u)
}
