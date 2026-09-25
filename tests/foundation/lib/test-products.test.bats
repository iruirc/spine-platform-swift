#!/usr/bin/env bats
# Every test_sim without testProductsPath builds a package of a gigabyte or more, and XcodeBuildMCP
# keeps it for days. The stage that built it reuses it while the code stands still and removes it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS="$ROOT/agents"
}

@test "the validator reuses its stage's package and removes it at the end" {
  v="$AGENTS/swift-validator.md"
  for phrase in '**One `test_sim` package per stage.**' '`Test Products`' '`testProductsPath`' \
                'no source or test file has changed' '`<path>.*-completed`' 'only paths from your own results'; do
    grep -qF -- "$phrase" "$v" || { echo "the validator lacks: $phrase"; return 1; }
  done
}

@test "every other agent that calls test_sim reuses the package and points at the rule" {
  runners="$(grep -lF 'test_sim' "$AGENTS"/*.md | grep -v swift-validator.md)"
  [ -n "$runners" ] || { echo "no agent besides the validator calls test_sim; the guard lost its target"; return 1; }
  for f in $runners; do
    grep -qF -- 'reusing the stage'"'"'s package through `testProductsPath`' "$f" \
      || { echo "$(basename "$f") calls test_sim without reusing the package"; return 1; }
  done
}
