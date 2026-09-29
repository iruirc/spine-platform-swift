#!/usr/bin/env bats
# The platform half of core's device setting (spine-toolkit conventions/stage-dispatch.md → Device):
# the device a brief names outranks the session's pre-set one and the project's files, for every
# agent that builds or tests, and the validator knows how to hand it to XcodeBuildMCP.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  V="$ROOT/agents/swift-validator.md"
}

@test "the validator takes the brief's device over the session's and the project's" {
  x="$(sed -n '/^### XcodeBuildMCP$/,/^### /p' "$V")"
  grep -qF "The brief's Device line wins over both" <<<"$x" || { echo "step 1"; return 1; }
  for f in 'simulatorId' 'simulatorName' '`platform=iOS` without `Simulator`' 'a bare UDID'; do
    grep -qF -- "$f" <<<"$x" || { echo "step 1 lost: $f"; return 1; }
  done
}

@test "every agent that builds or tests puts the brief's device above its project files" {
  for a in developer tester diagnostics refactorer; do
    f="$ROOT/agents/swift-$a.md"
    sed -n '12p' "$f" | grep -qF "A device the brief's Device line names outranks any these files name." \
      || { echo "swift-$a: First line lost the device rule"; return 1; }
  done
}

@test "the validator drives the device the brief names" {
  x="$(sed -n '/^### Driving the app$/,/^---$/p' "$V")"
  grep -qF "The target the driver selects is the one the brief's Device line names" <<<"$x" \
    || { echo "Driving the app lost the device rule"; return 1; }
}
