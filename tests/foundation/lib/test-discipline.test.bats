#!/usr/bin/env bats
# What a good test is does not depend on the language, so it lives in core and this
# plugin says only what core cannot: which boundaries an Apple project has, what
# resets state, and how a double is made where the language generates none. These
# tests are what keeps the neutral half from growing back one helpful sentence at a time.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS="$ROOT/agents"
  CORE="${SPINE_TOOLKIT_CORE:-$ROOT/../spine-toolkit}"
}

@test "no agent restates the neutral discipline" {
  # Each pattern is the rule as it was written here before core carried it. They are
  # chosen to sit on one line whatever the wrapping, so a re-wrap cannot hide a copy.
  offenders=""
  for pat in 'Arrange → Act → Assert' 'methodName_condition_expectedResult' \
             'Never mock these' 'Tests are idempotent'; do
    hits="$(grep -rlF "$pat" "$AGENTS" || true)"
    [ -z "$hits" ] || offenders="$offenders$pat: $(echo "$hits" | xargs -n1 basename | tr '\n' ' ')"$'\n'
  done
  [ -z "$offenders" ] || { echo "the neutral discipline is back in an agent:"; echo "$offenders"; return 1; }
}

@test "the tester points at core for the discipline and the doubles" {
  t="$AGENTS/swift-tester.md"
  grep -qF 'spine-toolkit:test-authoring' "$t" || { echo "the tester never names the skill"; return 1; }
  grep -qF '`## Test doubles`' "$t" || { echo "the tester does not send doubles to core"; return 1; }
  grep -qF '`## Before you deliver`' "$t" || { echo "the quality gate does not point at core"; return 1; }
  # The half that stays is the half core cannot know. Losing it would leave a tester
  # that is correct and useless: it would name no Apple boundary at all.
  for apple in 'URLProtocol' 'UserDefaults' 'Mockolo'; do
    grep -qF "$apple" "$t" || { echo "the tester lost its Apple-specific half: $apple"; return 1; }
  done
}
