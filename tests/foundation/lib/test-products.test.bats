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
                'no file the build reads has changed' '`<path>.*-completed`' 'only paths from your own results'; do
    grep -qF -- "$phrase" "$v" || { echo "the validator lacks: $phrase"; return 1; }
  done
}

# Under MCP the result prints paths as a tree: the `Test Products` entry is relative to the
# directory line above it, and `rm -rf` of a wrong line takes DerivedData and result bundles with it.
@test "the validator rebuilds the package path and removes only a package" {
  v="$AGENTS/swift-validator.md"
  for phrase in 'joined to the directory line above it' '`~` written as `$HOME`' \
                'ending in `.xctestproducts` whose parent directory is `test-products`'; do
    grep -qF -- "$phrase" "$v" || { echo "the validator lacks: $phrase"; return 1; }
  done
}

# build-for-testing gets the call's -only-testing too, so a package serves that selector only.
@test "the validator reuses a package only for a repeat of the same selector" {
  v="$AGENTS/swift-validator.md"
  for phrase in 'the same selector' 'whose package is gone or which ran no tests'; do
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
