#!/usr/bin/env bats
# In Codex CLI's workspace-write sandbox the simulator is refused over XPC, so every build and test
# asked the user (multi-llm milestone 5). setup copies these rules into the project and approves the
# XcodeBuildMCP server it finds in the user's Codex config by the commands listed here.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RULES="$ROOT/runtimes/codex-cli/rules/swift.rules"
  MCP="$ROOT/runtimes/codex-cli/mcp.json"
}

decision() { codex execpolicy check --resolve-host-executables --rules "$RULES" "$@"; }

@test "the rules let xcodebuild and simctl out of the sandbox and nothing else" {
  command -v codex >/dev/null || skip "codex is not installed"
  for cmd in "xcodebuild test -scheme App" "/usr/bin/xcodebuild -version" "xcrun simctl list devices"; do
    run decision $cmd
    [[ "$output" == *'"decision":"allow"'* ]] || { echo "$cmd: $output"; false; }
  done
  for cmd in "xcrun swift build" "swift test"; do
    run decision $cmd
    [[ "$output" == *'"matchedRules":[]'* ]] || { echo "$cmd: $output"; false; }
  done
}

@test "the rules say who writes them and the risk they take" {
  for s in 'setup' 'Run Script' 'delete'; do
    grep -qiF -- "$s" "$RULES" || { echo "header lacks: $s"; false; }
  done
}

@test "the MCP list names XcodeBuildMCP by both of its commands" {
  run python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["servers"])' "$MCP"
  [ "$output" = "['xcodebuildmcp', 'mobilebuildmcp']" ] || { echo "$output"; false; }
}
