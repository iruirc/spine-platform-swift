#!/usr/bin/env bats
# A deferred check becomes a case in ManualChecks.md only when it needs a person. The criterion
# is core's (spine-toolkit:manual-checks); the validator has to apply it, not restate it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  A="$ROOT/agents/swift-validator.md"
}

@test "the validator applies the criterion before it writes a case" {
  grep -qF '## Does this check need a person?' "$A" || { echo "no pointer to the criterion"; return 1; }
  grep -qF 'no case that needs a person, no file' "$A" || { echo "auto still writes a file for any deferred check"; return 1; }
  ! grep -qF 'Nothing deferred, no file' "$A" || { echo "the old auto rule is still there"; return 1; }
}

@test "the platform requires the core release that carries the criterion" {
  grep -qF '{ "name": "spine-toolkit", "version": ">=2.32.0 <3" }' "$ROOT/.claude-plugin/plugin.json" \
    || { echo "the spine-toolkit floor is not >=2.32.0 <3"; return 1; }
}

@test "the none line names what was covered and each automatable gap" {
  grep -qF 'each automatable gap' "$A" || { echo "gaps are lost when there is no file"; return 1; }
}
