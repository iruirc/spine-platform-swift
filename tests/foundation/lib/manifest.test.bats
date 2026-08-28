#!/usr/bin/env bats
# swift-platform's manifest is the four-table contract spine-toolkit documents and
# demonstrates with its own reference platform: these tests check the real manifest
# against that same contract.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  M="$ROOT/skills/manifest/SKILL.md"
}

@test "manifest declares all five tables" {
  for s in Roles Axes Heuristics Topics Entrypoints; do
    grep -q "^## $s\$" "$M"
  done
}

@test "the setup entrypoint names a skill that exists" {
  # spine-toolkit:setup finds this platform's half of installation through this
  # row and nothing else; dropping it to `—` silently stops ## Stack being
  # filled on every new project, and the failure looks like a supported shape.
  grep -qE '^setup[[:space:]]*=[[:space:]]*`swift-setup`$' "$M"
  [ -f "$ROOT/skills/swift-setup/SKILL.md" ]
}

@test "every role maps to an agent file that exists" {
  while read -r ref; do
    [ -f "$ROOT/agents/${ref#swift-platform:}.md" ]
  done < <(grep -oE 'swift-platform:swift-[a-z]+' "$M" | sort -u)
}

@test "every topic points at a skill that exists" {
  while read -r skill; do
    [ -d "$ROOT/skills/$skill" ]
  # Rows only: the prose around the table backticks skill and topic names too,
  # and a topic declares nothing outside its `→` row.
  done < <(sed -n '/^## Topics/,/^## /p' "$M" | grep '→' \
             | grep -oE '`[a-z][a-z-]+`' | tr -d '`' | sort -u)
}
