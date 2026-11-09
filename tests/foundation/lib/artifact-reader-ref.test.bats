#!/usr/bin/env bats
# Every agent whose body tells it to keep prose concise also tells it where the
# exception lives: task artifacts follow the core artifact-reader skill. A platform
# names a core skill only by its namespaced name.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every agent that says 'Keep prose concise' names spine-toolkit:artifact-reader" {
  n=0
  for f in "$ROOT"/agents/*.md; do
    grep -qF 'Keep prose concise' "$f" || continue
    n=$((n + 1))
    grep -qF 'spine-toolkit:artifact-reader' "$f" \
      || { echo "$(basename "$f") says 'Keep prose concise' but never names spine-toolkit:artifact-reader"; return 1; }
  done
  # A floor, so an empty glob cannot pass.
  [ "$n" -ge 4 ] || { echo "only $n agent files carry 'Keep prose concise', expected at least 4"; return 1; }
}

@test "the added sentence follows the brevity sentence verbatim" {
  for f in "$ROOT"/agents/*.md; do
    grep -qF 'Keep prose concise' "$f" || continue
    grep -qF 'so the output can be merged or updated across stages. Artifacts named in `spine-toolkit:artifact-reader` follow its Style instead; there, brevity means no padding, not compression.' "$f" \
      || { echo "$(basename "$f"): the artifact-reader sentence is missing or altered"; return 1; }
  done
}

# The Russian lines are spelled as UTF-8 bytes: a test file is not a place the i18n lint lets Cyrillic in.
@test "the i18n example shows an identifier as a reference and names the skill namespaced" {
  f="$ROOT/conventions/i18n.md"
  bad="$(printf '`FooDataProvider` \xd0\xbf\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb2\xd0\xb5\xd0\xb4\xd1\x91\xd0\xbd')"
  line1="$(printf '\xd0\x98\xd1\x81\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xb8\xd0\xba \xd0\xb4\xd0\xb0\xd0\xbd\xd0\xbd\xd1\x8b\xd1\x85 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0 (`FooDataProvider`) \xd1\x82\xd0\xb5\xd0\xbf\xd0\xb5\xd1\x80\xd1\x8c \xd1\x81\xd1\x82\xd1\x80\xd0\xbe\xd0\xb8\xd1\x82\xd1\x81\xd1\x8f \xd0\xb8\xd0\xb7 \xd0\xbc\xd0\xbe\xd0\xb4\xd0\xb5\xd0\xbb\xd0\xb8.')"
  line2="$(printf '\xd0\x9f\xd0\xbe\xd1\x8d\xd1\x82\xd0\xbe\xd0\xbc\xd1\x83 \xd0\xb2\xd1\x8b\xd0\xb4\xd0\xb5\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xbd\xd0\xb5 \xd1\x82\xd0\xb5\xd1\x80\xd1\x8f\xd0\xb5\xd1\x82\xd1\x81\xd1\x8f \xd0\xbf\xd1\x80\xd0\xb8 \xd0\xbe\xd0\xb1\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb8 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0.   <- RU prose (project language)')"
  if grep -qF -- "$bad" "$f"; then echo "i18n.md still makes an identifier the subject"; return 1; fi
  grep -qxF -- "$line1" "$f" || { echo "first example line missing"; return 1; }
  grep -qxF -- "$line2" "$f" || { echo "second example line missing"; return 1; }
  grep -qF '`spine-toolkit:artifact-reader`' "$f" || { echo "i18n.md never names spine-toolkit:artifact-reader"; return 1; }
}

@test "the toolkit floor is the release that ships the Impact line and the closing block" {
  # 2.31.0 shipped them; 2.32.0, the manual-checks criterion, is the floor now and carries them too.
  grep -qF '"version": ">=2.32.0 <3"' "$ROOT/.claude-plugin/plugin.json" \
    || { echo "plugin.json floor is not >=2.32.0 <3"; return 1; }
}

# The ManualChecks passage of a validator: from its "### `ManualChecks.md`" heading to the next heading.
manual_checks_passage() {
  awk '/^### `ManualChecks\.md`/ { on = 1; print; next } on && /^##(#)? / { exit } on { print }' "$1"
}

@test "every validator's ManualChecks passage names the manual-checks skill and its reader, a tester" {
  for f in "$ROOT"/agents/*-validator.md; do
    p="$(manual_checks_passage "$f")"
    [ -n "$p" ] || { echo "$(basename "$f"): no ManualChecks.md passage found"; return 1; }
    grep -qF 'spine-toolkit:manual-checks' <<<"$p" || { echo "$(basename "$f"): the passage does not name spine-toolkit:manual-checks"; return 1; }
    grep -qF 'The reader is a tester who knows the product but not the code and was not on this task' <<<"$p" \
      || { echo "$(basename "$f"): the passage does not state its reader: a tester who knows the product but not the code"; return 1; }
  done
}

@test "every validator's ManualChecks passage says where the visible text of the app lives" {
  for f in "$ROOT"/agents/*-validator.md; do
    p="$(manual_checks_passage "$f")"
    grep -qF 'Localizable.strings' <<<"$p" \
      || { echo "$(basename "$f"): the ManualChecks passage never names Localizable.strings"; return 1; }
  done
}

@test "every validator's ManualChecks passage sends the lint findings back to the writer once" {
  for f in "$ROOT"/agents/*-validator.md; do
    p="$(manual_checks_passage "$f")"
    grep -qF 'lint-manual-checks.sh' <<<"$p" || { echo "$(basename "$f"): the passage never names lint-manual-checks.sh"; return 1; }
    grep -qF 'back to the writer once' <<<"$p" || { echo "$(basename "$f"): the findings do not go back to the writer once"; return 1; }
  done
}

@test "no validator still describes ManualChecks in the old format" {
  for f in "$ROOT"/agents/*-validator.md; do
    p="$(manual_checks_passage "$f")"
    for old in 'two rules that make a case executable' 'two rules that decide' 'By eye' 'Scene' 'code reference per case' 'hand-run script' 'a person runs'; do
      if grep -qF -- "$old" <<<"$p"; then echo "$(basename "$f"): the ManualChecks passage still says '$old'"; return 1; fi
    done
    if grep -qF 'hand-run script' "$f"; then echo "$(basename "$f"): still calls ManualChecks the 'hand-run script'"; return 1; fi
  done
}

@test "no validator names the lint by a bare core path" {
  for f in "$ROOT"/agents/*-validator.md; do
    if grep -qE '(^|[^[:alnum:]_.-])(\.\./)?(scripts|skills)/(lint-manual-checks|manual-checks|artifact-reader)' "$f"; then
      echo "$(basename "$f"): names a core path bare"; return 1
    fi
  done
}

@test "swift-validator names spine-toolkit:artifact-reader" {
  grep -qF 'spine-toolkit:artifact-reader' "$ROOT/agents/swift-validator.md" \
    || { echo "swift-validator.md never names spine-toolkit:artifact-reader"; return 1; }
}

@test "no validator's MANUAL_CHECKS axis row still promises a human a script" {
  for f in "$ROOT"/agents/*-validator.md; do
    grep -qF '| `[MANUAL_CHECKS]` | `auto` | whether a tester gets test cases |' "$f" \
      || { echo "$(basename "$f"): the [MANUAL_CHECKS] axis row does not say 'whether a tester gets test cases'"; return 1; }
  done
  if grep -rqF -e 'gets a script' -e 'hand-run script' "$ROOT/agents" "$ROOT/skills" "$ROOT/README.md"; then
    echo "an agent, skill or the README still says 'gets a script' or 'hand-run script'"; return 1
  fi
}

# A named list, not the "Keep prose concise" loop: these agents write or feed a task artifact.
@test "the agents that write or feed a task artifact name spine-toolkit:artifact-reader" {
  for a in swift-architect swift-developer swift-refactorer swift-tester swift-validator swift-reviewer swift-diagnostics swift-security; do
    grep -qF 'spine-toolkit:artifact-reader' "$ROOT/agents/$a.md" \
      || { echo "$a.md never names spine-toolkit:artifact-reader"; return 1; }
  done
}

@test "swift-reviewer: a finding carries an Impact, and the Self-Verification list checks it" {
  f="$ROOT/agents/swift-reviewer.md"
  grep -qF '**Impact**' "$f" || { echo "no **Impact** in the Findings description"; return 1; }
  grep -qF 'Category, Location (`file:line`), Description, **Impact**, Recommendation' "$f" \
    || { echo "a finding is not described as Category, Location, Description, Impact, Recommendation"; return 1; }
  grep -qiF 'every finding has an Impact' "$f" || { echo "Self-Verification lacks 'every finding has an Impact'"; return 1; }
}

@test "swift-reviewer: Summary and Previous findings name a finding in words, its ID in brackets" {
  f="$ROOT/agents/swift-reviewer.md"
  [ "$(grep -cF 'its ID in brackets' "$f")" -ge 2 ] \
    || { echo "Summary and Previous findings must each say 'its ID in brackets'"; return 1; }
}

@test "swift-reviewer: the output pointer names the Output Structure section that exists" {
  f="$ROOT/agents/swift-reviewer.md"
  grep -qxF '## Output Structure' "$f" || { echo "no ## Output Structure section"; return 1; }
  if grep -qF 'Output Format' "$f"; then echo "still points at a missing Output Format section"; return 1; fi
  grep -qF 'sections described in the "Output Structure" section below' "$f" \
    || { echo "the opening pointer does not name the Output Structure section"; return 1; }
}

@test "swift-reviewer: the reviewed-commit lines are the closing block, the status line stays byte 0" {
  f="$ROOT/agents/swift-reviewer.md"
  grep -qF 'Reviewed-commit lines (mandatory, the closing block of Review.md whenever you have a task folder)' "$f" \
    || { echo "the reviewed-commit heading is not the closing-block heading"; return 1; }
  grep -qF 'byte-position 0' "$f" || { echo "the byte-position-0 status rule is gone"; return 1; }
  p="$(awk '/^### Reviewed-commit lines/ { on = 1; print; next } on && /^### / { exit } on { print }' "$f")"
  grep -qF 'byte 0' <<<"$p" || { echo "the heading body does not say the status line stays byte 0"; return 1; }
  grep -qF 'Closing block' <<<"$p" || { echo "the heading body does not name the Closing block convention"; return 1; }
  grep -qF '`spine-toolkit`' <<<"$p" || { echo "the heading body does not name spine-toolkit"; return 1; }
  grep -qF 'Run line' <<<"$p" && grep -qF 'Device line' <<<"$p" \
    || { echo "the heading body does not order the Run and Device lines after the markers"; return 1; }
  if grep -qF 'directly under the status line' "$f"; then echo "still says the lines go directly under the status line"; return 1; fi
  grep -qF 'Write the Run line and the Device line only when the brief names them.' <<<"$p" \
    || { echo "the heading body does not say the Run and Device lines are written only when the brief names them"; return 1; }
  if grep -qF 'each where the brief names it' "$f"; then echo "still says the Run and Device lines go each where the brief names it"; return 1; fi
}

@test "swift-architect: the headings come from the calling stage, not six fixed sections" {
  f="$ROOT/agents/swift-architect.md"
  if grep -qF 'Your response MUST be structured with these top-level sections' "$f"; then
    echo "the six mandatory top-level sections are still there"; return 1
  fi
  for old in '## Architectural Analysis' '## Proposed Design' '## Alternatives Considered' '## Integration Points' '## Risks & Mitigations' '## Recommendation'; do
    if grep -qF -- "- \`$old\`" "$f"; then echo "still lists the heading $old"; return 1; fi
  done
  grep -qF '## Short answer' "$f" || { echo "no ## Short answer"; return 1; }
  grep -qF 'The headings of the file come from the stage that calls you' "$f" || { echo "the stage-headings sentence is missing"; return 1; }
  grep -qF 'Write `(none)` for what does not apply.' "$f" || { echo "the (none) rule is gone"; return 1; }
}

@test "swift-validator: the Summary is plain language with no contract field names" {
  f="$ROOT/agents/swift-validator.md"
  line="$(awk '/^## Summary$/ { getline; print; exit }' "$f")"
  [ -n "$line" ] || { echo "no ## Summary line found"; return 1; }
  grep -qF '1-2 sentences in plain language: what was validated and the outcome; no contract field names' <<<"$line" \
    || { echo "Summary line is: $line"; return 1; }
  # the whole section body, up to the next heading; the Summary template sits inside the
  # file's own fenced block, so fences are not skipped
  body="$(awk '/^## Summary$/ { on = 1; next } on && /^#/ { exit } on { print }' "$f")"
  [ -n "$body" ] || { echo "the ## Summary section is empty"; return 1; }
  for field in validation_status VALIDATION_STATUS manual_checks_changed; do
    if grep -qF -- "$field" <<<"$body"; then echo "the Summary section names $field"; return 1; fi
  done
}

@test "swift-tester: the output pointer names the Output Structure section that exists" {
  f="$ROOT/agents/swift-tester.md"
  grep -qxF '## Output Structure' "$f" || { echo "no ## Output Structure section"; return 1; }
  if grep -qF 'Output Format' "$f"; then echo "still points at a missing Output Format section"; return 1; fi
  grep -qF 'sections described in the "Output Structure" section below' "$f" \
    || { echo "the opening pointer does not name the Output Structure section"; return 1; }
}
