#!/usr/bin/env bats
# The axis said which framework a project uses and the tester wrote XCTest regardless — including
# a naming example XCTest never collects. The syntax now lives once, keyed by the axis value, and
# these tests hold the two halves together: every value has a section, every section has a value.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/test-frameworks/SKILL.md"
  MANIFEST="$ROOT/skills/manifest/SKILL.md"
}

# The values of one manifest axis, one per line.
axis_values() { # $1 = axis name
  sed -n "s/^$1 *= *//p" "$MANIFEST" | tr ',' '\n' | sed 's/^ *//; s/ *$//'
}

# The H2s of a file, fences excluded.
h2s() {
  awk '/^[ \t]*(```|~~~)/ {fence = !fence; next} !fence && /^## / {sub(/^## /, ""); print}' "$1"
}

# The canonical token table: token in column 1, axis value in column 2, one row per line.
# Rows of the `## Forced by surface` table do not start with a backticked lowercase cell.
table_rows() {
  awk -F'|' '$0 ~ /^\| `[a-z][a-z+-]*` \|/ {
    gsub(/[` ]/, "", $2); gsub(/^ +| +$/, "", $3); gsub(/`/, "", $3); print $2 "\t" $3
  }' "$SKILL"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/test-frameworks/SKILL.md"; return 1; }
  grep -q '^name: test-frameworks$' "$SKILL" || { echo "frontmatter name is not test-frameworks"; return 1; }
}

@test "every value of the tests axis has a section" {
  n=0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    n=$((n + 1))
    h2s "$SKILL" | grep -qxF -- "$v" || { echo "no '## $v' section for axis value $v"; return 1; }
  done < <(axis_values tests)
  [ "$n" -ge 3 ] || { echo "found $n values of the tests axis; the scan went vacuous"; return 1; }
}

@test "every section of the skill is a value of the tests axis" {
  values="$(axis_values tests)"
  while IFS= read -r h; do
    [ "$h" = "Forced by surface" ] && continue
    [ "$h" = "Spelling" ] && continue
    grep -qxF -- "$h" <<<"$values" || { echo "'## $h' is no value of the tests axis"; return 1; }
  done < <(h2s "$SKILL")
}

@test "every framework section carries all seven subsections" {
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    body="$(awk -v h="## $v" '$0==h{f=1;next} f&&/^## /{exit} f' "$SKILL")"
    for sub in Declaration Assertions Lifecycle Parameterization Async "Failure output" Setup; do
      grep -qxF "### $sub" <<<"$body" || { echo "## $v has no '### $sub'"; return 1; }
    done
  done < <(axis_values tests)
}

@test "the skill lists the surfaces that force a framework" {
  h2s "$SKILL" | grep -qxF 'Forced by surface' || { echo "no '## Forced by surface'"; return 1; }
  body="$(awk '$0=="## Forced by surface"{f=1;next} f&&/^## /{exit} f' "$SKILL")"
  grep -qF 'XCUITest' <<<"$body" || { echo "the UI-test surface is not named"; return 1; }
  grep -qF '`measure`' <<<"$body" || { echo "the performance surface is not named"; return 1; }
}

@test "the manifest answers the testing topic with this skill" {
  grep -qE '^testing[[:space:]]*→[[:space:]]*`test-frameworks`$' "$MANIFEST" \
    || { echo "no testing row in the manifest ## Topics"; return 1; }
}

@test "the tester names no framework construct in its own instructions" {
  tester="$ROOT/agents/swift-tester.md"
  body="$(awk '/^## Skills Reference/{exit} {print}' "$tester")"
  hits="$(grep -oE 'XCTAssert[A-Za-z]*|XCTestCase|XCTUnwrap|setUp|tearDown|#expect|#require|@Suite|@Test\b|QuickSpec' <<<"$body" | sort -u | tr '\n' ' ')"
  [ -z "$hits" ] || { echo "the tester still spells a framework: $hits"; return 1; }
}

@test "the validator extracts failures of every value the axis allows" {
  v="$ROOT/agents/swift-validator.md"
  grep -qF 'XCTAssert' "$v" || { echo "the XCTest failure form is gone"; return 1; }
  grep -qF 'recorded an issue' "$v" || { echo "the validator cannot see a Swift Testing issue"; return 1; }
  grep -qF 'Executed' "$v" || { echo "the run summary is no longer read"; return 1; }
}

@test "the validator knows the Swift Testing summary does not count its own failures" {
  v="$ROOT/agents/swift-validator.md"
  grep -qF 'zero-width space' "$v" || { echo "nothing warns that the issue line may not start with the mark"; return 1; }
  grep -qF 'XCTest only' "$v" || { echo "the validator may report a green run that failed"; return 1; }
}

@test "a regression test and its sketch name the framework they are written in" {
  grep -qF 'test-frameworks' "$ROOT/agents/swift-developer.md" \
    || { echo "the developer's regression test is in no particular framework"; return 1; }
  grep -qF 'test-frameworks' "$ROOT/agents/swift-diagnostics.md" \
    || { echo "the diagnostics sketch is in no particular framework"; return 1; }
}

@test "init asks the tests axis and carries a flag for it" {
  i="$ROOT/agents/swift-init.md"
  grep -qF -- '--tests=' "$i" || { echo "no --tests flag"; return 1; }
  grep -qE '^\| `--tests=' "$i" || { echo "the flag has no row in the flag-to-Stack table"; return 1; }
}

@test "init offers every value of the tests axis and restates none of them" {
  i="$ROOT/agents/swift-init.md"
  grep -qF 'the values `## Axes` lists for `tests`' "$i" \
    || { echo "init does not take its options from the manifest"; return 1; }
}

@test "init writes the first test from the skill, not from its own memory" {
  i="$ROOT/agents/swift-init.md"
  grep -qF '`test-frameworks`' "$i" || { echo "the placeholder test is in no particular framework"; return 1; }
}

@test "every agent that writes test code takes the choice from core and the syntax from the skill" {
  bad=""
  for a in swift-tester swift-developer swift-diagnostics swift-init; do
    f="$ROOT/agents/$a.md"
    grep -qF 'spine-toolkit:test-authoring' "$f" || bad="$bad $a(choice)"
    grep -qF '`test-frameworks`' "$f" || bad="$bad $a(syntax)"
  done
  [ -z "$bad" ] || { echo "agents not bound to the rule:$bad"; return 1; }
}

@test "the token table names every value of the tests axis, and nothing else" {
  rows="$(table_rows)"
  [ -n "$rows" ] || { echo "the skill has no token table"; return 1; }
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    printf '%s\n' "$rows" | cut -f2 | grep -qxF -- "$v" \
      || { echo "no token row for axis value $v"; return 1; }
  done < <(axis_values tests)
  while IFS=$'\t' read -r tok val; do
    axis_values tests | grep -qxF -- "$val" \
      || { echo "token $tok names '$val', which is not a value of the tests axis"; return 1; }
  done <<< "$rows"
  n="$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
  [ "$n" -ge 3 ] || { echo "the table has $n rows; the scan went vacuous"; return 1; }
}

@test "init's --tests flag rows are exactly the table's tokens" {
  flags="$(sed -n 's/^| `--tests=\([a-z][a-z-]*\)`.*/\1/p' "$ROOT/agents/swift-init.md" | sort -u)"
  tokens="$(table_rows | cut -f1 | sort -u)"
  # Both sides empty compares equal: strip the rows and the table together and this would pass.
  [ -n "$flags" ] || { echo "no --tests rows in swift-init.md; the scan went vacuous"; return 1; }
  [ "$flags" = "$tokens" ] || {
    echo "the flag rows and the token table disagree:"
    diff <(printf '%s\n' "$flags") <(printf '%s\n' "$tokens")
    return 1
  }
}

@test "each stub variant declares a test the way its section of the skill does" {
  local dir="$ROOT/templates/workspace/package/Tests/PACKAGE_NAMETests"
  local n=0
  # token | section heading | the fragments that make a test collectable in that framework
  while IFS='|' read -r tok section frags; do
    n=$((n + 1))
    local stub="$dir/PACKAGE_NAMETests.swift.$tok.tmpl"
    [ -f "$stub" ] || { echo "no stub for token $tok"; return 1; }
    local body; body="$(awk -v s="## $section" '$0 == s {on = 1; next} on && /^## / {exit} on' "$SKILL")"
    [ -n "$body" ] || { echo "no '## $section' section in the skill"; return 1; }
    # Split on commas only: unquoted word-splitting would also break on the spaces inside a
    # fragment, turning `override class func spec()` into four needles, one of which (`class`)
    # any Swift class satisfies.
    local -a fl; IFS=, read -ra fl <<< "$frags"
    local f
    for f in "${fl[@]}"; do
      grep -qF -- "$f" "$stub" || { echo "the $tok stub does not use $f"; return 1; }
      printf '%s\n' "$body" | grep -qF -- "$f" || { echo "'## $section' does not declare $f"; return 1; }
    done
  done <<'EOF'
swift-testing|Swift Testing|import Testing,@Test
xctest|XCTest|import XCTest,XCTestCase
quick-nimble|Quick+Nimble|import Quick,QuickSpec,override class func spec()
EOF
  [ "$n" -eq 3 ] || { echo "scanned $n rows instead of 3; the heredoc scan went vacuous"; return 1; }
}
