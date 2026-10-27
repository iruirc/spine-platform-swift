#!/usr/bin/env bats
# Acceptance of milestone 6 (EPIC 548): swift-tester wrote its Write report to 2.step/Write.md, an
# artifact no skill knows. An implementing agent's report is its final message, not a stage file.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "implementing agents create no file named after their stage" {
  for a in swift-developer swift-tester swift-refactorer; do
    grep -F 'has no stage file of its own' "$ROOT/agents/$a.md" | grep -qF '`Write.md`' \
      || { echo "$a lacks the rule"; false; }
  done
}

@test "swift-validator runs simctl unwrapped and swiftc with a module cache in /tmp" {
  f="$ROOT/agents/swift-validator.md"
  grep -F 'xcrun simctl' "$f" | grep -qF 'never wrapped' || { echo "no unwrapped simctl rule"; false; }
  grep -qF -- '-module-cache-path /tmp/spine-module-cache' "$f" || { echo "no module cache flag"; false; }
}
