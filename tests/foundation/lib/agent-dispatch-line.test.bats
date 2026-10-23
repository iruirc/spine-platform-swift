#!/usr/bin/env bats
# An agent body is its role, read by Claude Code and Codex alike. How a caller dispatches it is
# the orchestrator's business, resolved through the manifest, so no body tells its caller to use
# `subagent_type=` (spec: multi-llm milestone 6). swift-init's closing note to the user is not a
# role instruction and stays.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "no agent body tells its caller how to dispatch it" {
  offenders="$(grep -ln 'subagent_type=' "$ROOT"/agents/*.md | grep -v '/swift-init.md$' || true)"
  [ -z "$offenders" ] || { echo "$offenders"; return 1; }
}
