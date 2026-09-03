#!/usr/bin/env bats
# The vendored copy of core's lint, run against this repository itself. Core's
# own suite runs its copy against a fixture; a real platform has something
# better to check — its own tree.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-core-refs.sh"
  CORE="${SPINE_TOOLKIT_CORE:-$ROOT/../spine-toolkit}"
}

@test "this platform's core references are clean" {
  [ -d "$CORE/skills" ] || skip "no spine-toolkit checkout beside this one"
  run "$LINT" "$ROOT" --core "$CORE"
  [ "$status" -eq 0 ]
}
