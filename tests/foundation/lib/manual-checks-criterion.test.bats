#!/usr/bin/env bats
# A deferred check becomes a case in ManualChecks.md only when it needs a person. The criterion
# is core's (spine-toolkit:manual-checks); the validator has to apply it, not restate it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  A="$ROOT/agents/swift-validator.md"
}

# The ManualChecks passage of a validator: from its "### `ManualChecks.md`" heading to the next heading.
manual_checks_passage() {
  awk '/^### `ManualChecks\.md`/ { on = 1; print; next } on && /^##(#)? / { exit } on { print }' "$1"
}

@test "the validator applies the criterion before it writes a case" {
  grep -qF '## Does this check need a person?' "$A" || { echo "no pointer to the criterion"; return 1; }
  grep -qF 'no case that needs a person, no file' "$A" || { echo "auto still writes a file for any deferred check"; return 1; }
  ! grep -qF 'Nothing deferred, no file' "$A" || { echo "the old auto rule is still there"; return 1; }
}

@test "the platform requires the core release that carries the criterion" {
  # 2.44.0 carries the criterion too, and classifies failures outside the task, returns PASSED_WITH_FLAKES and carries green whole-module runs.
  grep -qF '{ "name": "spine-toolkit", "version": ">=2.44.0 <3" }' "$ROOT/.claude-plugin/plugin.json" \
    || { echo "the spine-toolkit floor is not >=2.44.0 <3"; return 1; }
}

@test "the none line names what was covered and each automatable gap" {
  grep -qF 'each automatable gap' "$A" || { echo "gaps are lost when there is no file"; return 1; }
}

@test "the validator writes code references in their own section and leaves measuring to itself" {
  grep -qF '`## Code references`' "$A" || { echo "the validator still puts code in the case"; return 1; }
  ! grep -qF 'live only in `**Code:**`' "$A" || { echo "the old Code field is still named"; return 1; }
  ! grep -qF 'twelve fields' "$A" || { echo "the case still has twelve fields"; return 1; }
  grep -qF '## What a case must prove' "$A" || { echo "no pointer to the writing rules"; return 1; }
  grep -qF 'never an instruction for a person to measure' "$A" || { echo "the validator may still hand measuring to a person"; return 1; }
}

@test "the validator keeps no instrument in the file and sends measuring to Validation.md" {
  ! grep -qF '**By instrument:**' "$A" || { echo "the instrument field is still named"; return 1; }
  ! grep -qF 'exact invocation' "$A" || { echo "the file still carries an instrument invocation"; return 1; }
  ! grep -qF 'the measuring' "$A" || { echo "the measuring is still named"; return 1; }
  grep -qF 'Measurements you can take yourself go to `Validation.md`' "$A" || { echo "measuring does not go to Validation.md"; return 1; }
}

@test "the case form follows manual_checks_style and the validator counts no fields" {
  grep -qF 'manual_checks_style' "$A" || { echo "the style field is not named"; return 1; }
  grep -qF '[STYLE]' "$A" || { echo "the file's style line is not named"; return 1; }
  ! grep -qF 'twelve fields' "$A" || { echo "the case still has twelve fields"; return 1; }
  ! grep -qF 'eleven fields' "$A" || { echo "the case still has eleven fields"; return 1; }
  ! grep -qF 'five-column' "$A" || { echo "the step table is still counted"; return 1; }
}

@test "a deferred check first passes the question about the diff" {
  grep -qF 'Does the diff change this behaviour?' "$A" || { echo "a deferred check skips the diff question"; return 1; }
}

@test "no line outside the criterion pointer routes a deferred check to a case without the criterion" {
  stale="$(grep -n -E 'becomes? (a )?(manual )?cases?|become manual cases' "$A" | grep -vF '## Does this check need a person?' || true)"
  [ -z "$stale" ] || { echo "stale routing: $stale"; return 1; }
}

@test "the closing checklist names the outcome of a check the diff does not change" {
  grep -qE '^- \[ \].*the diff does not change' "$A" || { echo "the closing checklist has no diff-unchanged outcome"; return 1; }
}

@test "the manual-checks paragraph names the skill, not an ambiguous Its" {
  ! grep -qF 'Its `## What a case must prove`' "$A" || { echo "ambiguous Its before the skill's section"; return 1; }
  ! grep -qF 'Its input is' "$A" || { echo "ambiguous Its before the skill's input"; return 1; }
}

@test "a step the validator cannot perform is deferred, not deferred to a human" {
  ! grep -qF 'deferred to a human' "$A" || { echo "the validator still defers to a human"; return 1; }
}

@test "the manual-checks paragraph sends a driver-only deferral to the collective pass by name" {
  p="$(manual_checks_passage "$A")"
  grep -qF '`manual_checks_pass`' <<<"$p" || { echo "the paragraph does not name manual_checks_pass"; return 1; }
  grep -qF '**Runner:** agent' <<<"$p" || { echo "the paragraph does not name the agent runner"; return 1; }
  grep -qF '## Marks for a collective pass' <<<"$p" || { echo "the paragraph does not point at the marks section"; return 1; }
}

@test "a Runner agent check stays a case and counts for writing the file" {
  p="$(manual_checks_passage "$A")"
  grep -qF 'stays a case of the file' <<<"$p" || { echo "the paragraph does not keep the Runner agent check a case"; return 1; }
  grep -qF 'counts as a case when deciding whether the file is written' <<<"$p" || { echo "the paragraph does not count the Runner agent check for writing the file"; return 1; }
}
