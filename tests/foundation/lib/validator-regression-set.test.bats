#!/usr/bin/env bats
# Validation runs the task's regression set, not whatever the scheme holds: the validator finds the
# changed packages, their dependents and the app that ships them, runs each, and records the set in
# Validation.md for core's lint. The reviewer reads that record instead of re-running the suites.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  V="$ROOT/agents/swift-validator.md"
  R="$ROOT/agents/swift-reviewer.md"
}

@test "the validator has a Regression set step before the profiles" {
  grep -qF '### Regression set' "$V" || { echo "no ### Regression set"; return 1; }
  [ "$(grep -n '^### Regression set' "$V" | head -1 | cut -d: -f1)" -lt "$(grep -n '^### FEATURE' "$V" | head -1 | cut -d: -f1)" ] || { echo "the step comes after the profiles"; return 1; }
}

@test "the set is found through local package references, never published ones" {
  grep -qF '.package(path:)' "$V" || { echo "no .package(path:)"; return 1; }
  grep -qF '.package(url:)' "$V" || { echo "no .package(url:) exclusion"; return 1; }
  grep -qF 'swift package dump-package' "$V" || { echo "no dump-package"; return 1; }
}

@test "the validator defers the definition of the set to core" {
  grep -qF "Validation's regression" "$V" || { echo "no pointer to core's section"; return 1; }
  grep -qF 'validation_ranges' "$V" || { echo "no validation_ranges"; return 1; }
  grep -qF 'task-ranges.sh ranges' "$V" || { echo "no fallback to task-ranges.sh"; return 1; }
}

@test "the validator records the set and lints it before returning" {
  grep -qF '## Regression set' "$V" || { echo "no ## Regression set in the template"; return 1; }
  grep -qF 'lint-validation-scope.sh' "$V" || { echo "no lint"; return 1; }
  grep -qF 'carried' "$V" || { echo "no carried rows"; return 1; }
  grep -qF -- '--kind validated' "$V" || { echo "no validated tips in the closing block"; return 1; }
  sed -n '/^## Self-Verification/,/^## What You Never Do/p' "$V" | grep -qF 'lint-validation-scope.sh' || { echo "no checkbox for the lint"; return 1; }
}

@test "no profile rule runs whatever the scheme holds" {
  ! grep -qF 'whatever exists in the scheme' "$V" || { echo "still the whole scheme"; return 1; }
}

@test "the whole-workspace script waits for the owner" {
  grep -qF 'owner asks' "$V" || { echo "no owner rule"; return 1; }
}

@test "the reviewer points at the lint first" {
  grep -qF 'lint-validation-scope.sh' "$R" || { echo "no lint in the reviewer"; return 1; }
}

@test "a re-run still runs the app when a package it runs is among the app's local references" {
  grep -qF 'the app runs too when a package it runs' "$V" || { echo "the app can be carried"; return 1; }
}

@test "the search roots are the brief's, and fetched dependency copies are not packages of the task" {
  grep -qF "brief's \`Search roots:\` line" "$V" || { echo "no Search roots: line"; return 1; }
  for d in '.build/checkouts' 'SourcePackages' 'Pods' 'Carthage'; do
    grep -qF -- "$d" "$V" || { echo "no $d exclusion"; return 1; }
  done
}

@test "the reviewer checks the set against the manifests and re-runs none but to confirm a finding" {
  grep -qF 'swift-validator.md' "$R" || { echo "no pointer to the validator"; return 1; }
  grep -qF 'unless to confirm a specific finding' "$R" || { echo "no confirm exception"; return 1; }
}

@test "a re-run counts uncommitted edits, and a BUG replay is carried only when the commits miss its path" {
  grep -qF 'uncommitted edits reaching their package too' "$V" || { echo "no uncommitted edits on a re-run"; return 1; }
  grep -qF "for BUG a replay is carried when the commits miss the scenario's path" "$V" || { echo "item 5 has no BUG carry"; return 1; }
  local bug
  bug="$(sed -n '/^### BUG/,/^### REFACTOR/p' "$V")"
  grep -qF "the replay is carried from the last green Validation" <<<"$bug" || { echo "the BUG bullet has no carried replay"; return 1; }
  grep -qF 'return its status as it was (`fixed` only if that Validation replayed, otherwise `deferred-manual`)' <<<"$bug" || { echo "the carried status is not its own"; return 1; }
  grep -qF 'under `## Scope`' <<<"$bug" || { echo "the carried Validation is not named under Scope"; return 1; }
}

@test "failures outside the task follow core's rule, and FLAKY stays the TEST profile's" {
  grep -qF '`spine-toolkit:phase-verification`' "$V" || { echo "no pointer to phase-verification"; return 1; }
  grep -qF 'Failures outside the task' "$V" || { echo "no pointer to the subsection"; return 1; }
  grep -qF '## Outside the task' "$V" || { echo "no ## Outside the task"; return 1; }
  grep -qF 'known_failures' "$V" || { echo "no registry field"; return 1; }
  ! grep -qF 'FLAKY — TEST-profile only; one or more new tests showed' "$V" || { echo "FLAKY keeps the old wording"; return 1; }
  grep -qF 'FLAKY** — TEST-profile only; a test the task added' "$V" || { echo "FLAKY is not tied to the tests the task added"; return 1; }
  local flaky
  flaky="$(sed -n '/^- \*\*Flaky detection\*\*/p' "$V")"
  grep -qF 'a test the task added' <<<"$flaky" || { echo "flaky detection is not about the added tests"; return 1; }
  grep -qF 'outside the task' <<<"$flaky" || { echo "flaky detection does not leave outside failures to core's rule"; return 1; }
}

@test "the return carries PASSED_WITH_FLAKES, outside_failures and known_failures_cleared" {
  grep -qxF '[VALIDATION_STATUS] = PASSED_WITH_FLAKES' "$V" || { echo "no PASSED_WITH_FLAKES status line"; return 1; }
  grep -qF '[VALIDATION_STATUS] = PASSED | PASSED_WITH_FLAKES | FAILED | FLAKY' "$V" || { echo "the return line lacks the four values"; return 1; }
  grep -qF 'outside_failures:' "$V" || { echo "no outside_failures"; return 1; }
  grep -qF 'known_failures_cleared:' "$V" || { echo "no known_failures_cleared"; return 1; }
  grep -qF '{repository, module, test, outcome, entry}' "$V" || { echo "no item shape"; return 1; }
  grep -qF 'PASSED_WITH_FLAKES → `continue`' "$V" || { echo "PASSED_WITH_FLAKES does not continue"; return 1; }
  grep -qF 'On PASSED or PASSED_WITH_FLAKES, close the file' "$V" || { echo "tips are written on PASSED only"; return 1; }
}

@test "a re-run carries a green module from a phase or an earlier Validation, and leaves reach lines to Review" {
  grep -qF 'carried <sha> (phase <N>)' "$V" || { echo "no phase source"; return 1; }
  grep -qF 'carried <sha> (validation)' "$V" || { echo "no validation source"; return 1; }
  grep -qF 'ran:' "$V" || { echo "no ran: line"; return 1; }
  grep -qF 'A line of class `reach` is not a finding: leave it for Review.' "$V" || { echo "reach lines are not left for Review"; return 1; }
}

@test "PASSED_WITH_FLAKES names the failures rather than hiding them" {
  local rule2
  rule2="$(grep -F '2. **Never falsify a verdict.**' "$V")"
  grep -qF 'PASSED_WITH_FLAKES names the failures rather than hiding them' <<<"$rule2" || { echo "rule 2 has no such phrase"; return 1; }
}

@test "the toolkit floor is 2.44.0" {
  grep -qF '{ "name": "spine-toolkit", "version": ">=2.44.0 <3" }' "$ROOT/.claude-plugin/plugin.json" \
    || { echo "the spine-toolkit floor is not >=2.44.0 <3"; return 1; }
}

@test "PASSED allows the known failures outside the task, PASSED_WITH_FLAKES needs a flake with no entry" {
  local passed flakes
  passed="$(grep -F -- '- **PASSED** —' "$V")"
  flakes="$(grep -F -- '- **PASSED_WITH_FLAKES** —' "$V")"
  grep -qF 'all tests passed bar the failures outside the task that `### Failures outside the task` gives PASSED' <<<"$passed" || { echo "PASSED still says every test passed"; return 1; }
  grep -qF 'at least one failure outside the task, with no registry entry, failed and then passed on its retry' <<<"$flakes" || { echo "PASSED_WITH_FLAKES is not tied to a no-entry failure that passed on retry"; return 1; }
  grep -qF 'every other failure is `known`' <<<"$flakes" || { echo "no known failures beside the flake"; return 1; }
  grep -qF 'Failures that are all `known` leave PASSED' <<<"$flakes" || { echo "all-known is not PASSED"; return 1; }
}

@test "a failure inside the task is FAILED bar a TEST task's added tests, and the registry is an input" {
  grep -qF "A failure inside the task, a TEST task's added tests aside, is FAILED, whatever the registry says." "$V" || { echo "the inside rule drops the TEST exception"; return 1; }
  grep -qF 'the file the brief gives in `known_failures`' "$V" || { echo "the registry is not the brief's field"; return 1; }
  grep -qF '5. The registry of known failures' "$V" || { echo "the registry is not in the inputs"; return 1; }
}
