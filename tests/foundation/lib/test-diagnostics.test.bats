#!/usr/bin/env bats
# One failing test cost a Validation stage ten silent minutes: xcodebuild collected simulator
# diagnostics after the run. The flag that skips it has to reach every agent that runs tests,
# whatever the XcodeBuildMCP version, and the reason lives once, in the validator.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS="$ROOT/agents"
  FLAG='-collect-test-diagnostics never'
}

@test "every agent that runs tests carries the flag" {
  runners="$(grep -lE 'test_sim|xcodebuild test|test-without-building' "$AGENTS"/*.md)"
  [ -n "$runners" ] || { echo "no agent runs tests; the guard lost its target"; return 1; }
  for f in $runners; do
    grep -qF -- "$FLAG" "$f" || { echo "$(basename "$f") runs tests without $FLAG"; return 1; }
  done
}

@test "the validator passes the flag to test_sim through extraArgs" {
  v="$AGENTS/swift-validator.md"
  grep -qF -- 'extraArgs: ["-collect-test-diagnostics", "never"]' "$v" \
    || { echo "the validator does not hand the flag to test_sim"; return 1; }
}

@test "the other runners send the reason to the validator instead of restating it" {
  for f in "$AGENTS"/*.md; do
    [ "$(basename "$f")" = swift-validator.md ] && continue
    grep -qF -- "$FLAG" "$f" || continue
    grep -qF -- '`swift-validator` → Tooling Procedure' "$f" \
      || { echo "$(basename "$f") names the flag but not where its reason lives"; return 1; }
  done
}
