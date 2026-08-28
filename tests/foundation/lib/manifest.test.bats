#!/usr/bin/env bats
# swift-platform's manifest is the five-table contract spine-toolkit documents and
# demonstrates with its own reference platform: these tests check the real manifest
# against that same contract. They live here rather than in core because core's
# suite must reach no tree but core's — reaching this one leaves core's tests
# broken the moment core is extracted, with no platform tree left to restore.

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

@test "the manifest passes spine-toolkit's conformance lint" {
  # The whole of what a script can check, run against the real manifest rather
  # than the reference fixture. The lint is vendored, like every other one here.
  run "$ROOT/scripts/lint-manifest.sh" "$ROOT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "every topic spine-toolkit asks for has a row here" {
  # The nine names spine-toolkit's contract publishes, copied the way the lints
  # are: a plugin that ships alone has no core tree to read them from. Core
  # matches literally, so spelling `deep links` as `deeplinks` here reads fine on
  # both sides and quietly resolves to nothing on every task.
  rows="$(sed -n '/^## Topics/,/^## Entrypoints/p' "$M")"
  missing=""
  for t in "state management" "navigation" "networking" "persistence" \
           "dependency graph" "concurrency" "errors" "packaging" "deep links"; do
    grep -qE "^${t}[[:space:]]*→" <<<"$rows" || missing="$missing '$t'"
  done
  [ -z "$missing" ] || { echo "topic spine-toolkit names with no row here:$missing"; return 1; }
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
