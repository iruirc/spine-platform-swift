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

@test "the reviewer judges tests by the core section, not by a list of its own" {
  r="$AGENTS/swift-reviewer.md"
  grep -qF '`## Review`' "$r" || { echo "the reviewer does not name the core section"; return 1; }
  grep -qF 'spine-toolkit:test-authoring' "$r" || { echo "the reviewer never names the skill"; return 1; }
  # The heading stays — it is the reviewer's own checklist structure — but the four
  # bullets under it were the copy, and "Mock abuse" is the one that cannot be
  # rewritten without saying what a double is for, which is core's sentence now.
  if grep -qF '**Mock abuse**' "$r"; then
    echo "the reviewer still carries its own test criteria"
    return 1
  fi
}

@test "core at the declared floor has the sections the agents point at" {
  # lint-core-refs.sh resolves skill names, not sections, and test-authoring existed
  # a minor before these sections did. Without this test the floor is a claim.
  [ -d "$CORE/.git" ] || skip "no spine-toolkit checkout beside this one"
  floor="$(python3 -c 'import json,sys,re; d=json.load(open(sys.argv[1]))["dependencies"]; v=[x["version"] for x in d if x["name"]=="spine-toolkit"][0]; print(re.search(r">=\s*(\d+\.\d+\.\d+)", v).group(1))' "$ROOT/.claude-plugin/plugin.json")"
  git -C "$CORE" rev-parse -q --verify "$floor^{commit}" >/dev/null || skip "core has no tag $floor"
  skill="$(git -C "$CORE" show "$floor:skills/test-authoring/SKILL.md")"
  for h in '## What a good test is' '## Test doubles' '## Before you deliver' '## Review' '## When the task owes no test'; do
    grep -qF "$h" <<<"$skill" || { echo "core $floor has no $h — the floor is too low"; return 1; }
  done
}

@test "the regression test is owed only when the task owes one" {
  for a in swift-diagnostics swift-developer; do
    grep -qF '`## When the task owes no test`' "$AGENTS/$a.md" \
      || { echo "$a writes a regression test whatever need_test says"; return 1; }
  done
  # The Related Agents roster is prose beside the already-conditional `## Regression Test`
  # bullet; a mention of "regression test" there without the qualifier promises one anyway.
  roster="$(awk '$0=="## Related Agents (spine-platform-swift)"{f=1;next} f&&/^#{2,3} /{exit} f' \
    "$AGENTS/swift-diagnostics.md")"
  [ -n "$roster" ] \
    || { echo "swift-diagnostics has no ## Related Agents (spine-platform-swift) section to check"; return 1; }
  if grep -qi 'regression test' <<<"$roster" && ! grep -qF '`## When the task owes no test`' <<<"$roster"; then
    echo "swift-diagnostics' roster still promises the regression test unconditionally"; return 1
  fi
}
