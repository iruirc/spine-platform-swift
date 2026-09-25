#!/usr/bin/env bats
# XcodeBuildMCP keeps every test_sim package for three days and never sweeps a removed worktree's
# workspace. The hook sweeps what the stage did not remove, once a day, from spine projects only,
# under both the old and the renamed binary, whose confirmation words differ.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; BIN="$TMP/bin"; LOG="$TMP/log"
  mkdir -p "$PROJ" "$BIN" "$LOG"
  export HOME="$TMP/home" LOG
  STAMPS="$HOME/Library/Caches/spine-platform-swift"
}

teardown() { rm -rf "$TMP"; }

stub() { # $1 name, $2 confirmation word ('' for none), $3 exit code of a purge
  cat >"$BIN/$1" <<EOF
#!/bin/bash
if [ "\$2" = --help ]; then
  [ -n "$2" ] && printf '      --confirm   Required for --delete: %s  [string]\n' "$2"
  exit 0
fi
printf '%s\n' "\$*" >>"\$LOG/$1"
exit ${3:-0}
EOF
  chmod +x "$BIN/$1"
}

hook() {
  run env PATH="$BIN:/usr/bin:/bin" bash -c "printf '{\"cwd\":\"$PROJ\"}' | '$ROOT/hooks/session-start'"
}

@test "outside a spine project no binary is called" {
  stub mobilebuildmcp delete-mobilebuildmcp-storage
  hook
  [ "$status" -eq 0 ] || { echo "status $status: $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
  [ ! -e "$LOG/mobilebuildmcp" ] || { cat "$LOG/mobilebuildmcp"; return 1; }
}

@test "in a spine project both binaries sweep test products older than a day" {
  touch "$PROJ/CLAUDE-spine-toolkit.md"
  stub mobilebuildmcp delete-mobilebuildmcp-storage
  stub xcodebuildmcp delete-xcodebuildmcp-storage
  hook
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; return 1; }
  [ "$(cat "$LOG/mobilebuildmcp")" = "purge --scope all --classes testProducts --older-than 1d --delete --confirm delete-mobilebuildmcp-storage" ] \
    || { cat "$LOG/mobilebuildmcp"; return 1; }
  [ "$(cat "$LOG/xcodebuildmcp")" = "purge --scope all --classes testProducts --older-than 1d --delete --confirm delete-xcodebuildmcp-storage" ] \
    || { cat "$LOG/xcodebuildmcp"; return 1; }
}

@test "Tasks/ACTIVE marks a spine project too" {
  mkdir -p "$PROJ/Tasks/ACTIVE"
  stub xcodebuildmcp delete-xcodebuildmcp-storage
  hook
  [ -s "$LOG/xcodebuildmcp" ]
}

@test "a binary whose help names no confirmation word is not asked to delete" {
  touch "$PROJ/CLAUDE-spine-toolkit.md"
  stub mobilebuildmcp ''
  stub xcodebuildmcp delete-xcodebuildmcp-storage
  hook
  [ "$status" -eq 0 ]
  [ ! -e "$LOG/mobilebuildmcp" ] || { cat "$LOG/mobilebuildmcp"; return 1; }
  [ -s "$LOG/xcodebuildmcp" ]
}

@test "a failing purge still exits 0 and stays quiet" {
  touch "$PROJ/CLAUDE-spine-toolkit.md"
  stub xcodebuildmcp delete-xcodebuildmcp-storage 1
  hook
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$status $output"; return 1; }
}

# A sweep walks all of DerivedData, ~12 s of CPU even with nothing to delete.
@test "a second session within a day does not sweep again, one a day later does" {
  touch "$PROJ/CLAUDE-spine-toolkit.md"
  stub xcodebuildmcp delete-xcodebuildmcp-storage
  hook; hook
  [ "$(wc -l <"$LOG/xcodebuildmcp")" -eq 1 ] || { cat "$LOG/xcodebuildmcp"; return 1; }
  touch -t "$(date -v-25H +%Y%m%d%H%M)" "$STAMPS/purge-xcodebuildmcp.stamp"
  hook
  [ "$(wc -l <"$LOG/xcodebuildmcp")" -eq 2 ] || { cat "$LOG/xcodebuildmcp"; return 1; }
}

@test "hooks.json runs the hook asynchronously at SessionStart" {
  run python3 - "$ROOT/hooks/hooks.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
hooks = [h for e in entries for h in e["hooks"]]
assert any(h["command"].endswith('/hooks/session-start"') and h.get("async") is True for h in hooks), hooks
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
