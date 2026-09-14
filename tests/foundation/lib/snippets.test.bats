#!/usr/bin/env bats
# A Swift block marked for typecheck compiles under Swift 6 against the iOS simulator SDK.
# The fixtures prove the script tells a block that compiles from one that does not.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TYPECHECK="$ROOT/scripts/typecheck-snippets.sh"
  FX="$ROOT/tests/foundation/fixtures/snippets"
}

@test "marked blocks compile with their prelude, per group, with both test frameworks" {
  run "$TYPECHECK" "$FX/compiles"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qxF 'scanned 2 files, 3 units, 4 blocks, 0 failed' <<<"$output" || { echo "$output"; return 1; }
}

@test "a marked block that does not compile fails at its Markdown line" {
  run "$TYPECHECK" "$FX/fails"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  grep -qF 'skills/demo/SKILL.md:5:' <<<"$output" || { echo "$output"; return 1; }
  grep -qxF 'scanned 1 files, 1 units, 1 blocks, 1 failed' <<<"$output" || { echo "$output"; return 1; }
}

@test "a marked block imports only the allowed Apple SDK modules" {
  run "$TYPECHECK" "$FX/bad-import"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
  grep -qF 'skills/demo/SKILL.md:5: import Swinject' <<<"$output" || { echo "$output"; return 1; }
}

@test "a marker not directly above a swift fence is an error, not a skip" {
  run "$TYPECHECK" "$FX/bad-marker"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
  grep -qF 'skills/demo/SKILL.md:4:' <<<"$output" || { echo "$output"; return 1; }
}

@test "a swiftc older than 6.2 is refused, not skipped" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)"\n' > "$BATS_TEST_TMPDIR/bin/xcrun"
  chmod +x "$BATS_TEST_TMPDIR/bin/xcrun"
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$TYPECHECK" "$FX/compiles"
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
  grep -qF 'older than 6.2' <<<"$output" || { echo "$output"; return 1; }
}

@test "every marked block in the plugin compiles" {
  run "$TYPECHECK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # No floor on marked blocks yet: none is marked. The file count proves the scan ran.
  n="$(ls "$ROOT"/skills/*/SKILL.md "$ROOT"/skills/*/references/detailed-guide.md 2>/dev/null | wc -l | tr -d ' ')"
  grep -qE "^scanned $n files, " <<<"$output" || { echo "want $n files scanned: $output"; return 1; }
}
