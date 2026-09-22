#!/usr/bin/env bats
# A spine-toolkit workflow calls the security agent two ways besides the user's audit, and in
# neither may it write or patch: the lens returns findings another agent folds in.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  F="$ROOT/agents/swift-security.md"
}

section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "swift-security names the three ways it is called, and writes nothing in a workflow" {
  s="$(section "$F" 'Invocation Context')"
  for token in '**triage**' '**lens**' '**audit**' '**write no artifact and apply no patch**'; do
    grep -qF "$token" <<<"$s" || { echo "## Invocation Context does not say $token"; return 1; }
  done
}

@test "swift-security no longer describes a Research consilium" {
  ! grep -qi 'consilium' "$F" || { echo "swift-security.md still describes a consilium"; return 1; }
}

@test "swift-security scopes its output layout to an audit" {
  s="$(section "$F" 'Output Structure')"
  grep -qF "As triage or lens, return only what the brief's schema asks for. In an audit, your response MUST be structured" <<<"$s" \
    || { echo "## Output Structure still binds the triage and the lens to the audit layout"; return 1; }
}
