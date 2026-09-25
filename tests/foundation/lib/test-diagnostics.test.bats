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

# The flag also stops a green run's diagnose, but a direct run without it still goes silent
# after its summary line; the verdict is already in the log, so the run must not read as hung.
@test "the validator says the collection runs on a green run too" {
  v="$AGENTS/swift-validator.md"
  ! grep -qF 'one failing test makes `xcodebuild` collect' "$v" \
    || { echo "the validator still ties the collection to a failing test"; return 1; }
  grep -qF 'on a green run too' "$v" || { echo "the validator does not say a green run collects too"; return 1; }
}

@test "the validator ends a direct run stalled on simctl diagnose with the verdict it already has" {
  v="$AGENTS/swift-validator.md"
  for phrase in '`stalled`' '`simctl diagnose`' '`long-run.sh stop`' 'not as hung' 'Do not rerun the tests'; do
    grep -qF -- "$phrase" "$v" || { echo "the fallback lacks: $phrase"; return 1; }
  done
}

@test "the other runners point at the rule and its fallback" {
  for f in "$AGENTS"/*.md; do
    [ "$(basename "$f")" = swift-validator.md ] && continue
    grep -qF -- "$FLAG" "$f" || continue
    ! grep -qF -- '(why: `swift-validator` → Tooling Procedure)' "$f" \
      || { echo "$(basename "$f") still points at the reason only"; return 1; }
    grep -qF -- '(rule and fallback: `swift-validator` → Tooling Procedure)' "$f" \
      || { echo "$(basename "$f") does not point at the fallback"; return 1; }
  done
}

# A test_sim went silent after "Writing result bundle" and held a stage for fifteen minutes: an MCP
# call has no --stall and no --max, so a long run goes where long-run.sh can watch it.
@test "a build of the app and a whole-suite run go through long-run.sh, test_sim only for one class" {
  v="$AGENTS/swift-validator.md"
  for phrase in 'go through `long-run.sh`' 'Long-running commands' 'no `--stall` and no `--max`' \
                '`test_sim` itself stays for one class or target' '-only-testing:'; do
    grep -qF -- "$phrase" "$v" || { echo "the validator lacks: $phrase"; return 1; }
  done
  ! grep -qF 'primary tool for running tests' "$AGENTS/swift-tester.md" \
    || { echo "the tester still sends every test run through XcodeBuildMCP"; return 1; }
}
