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
