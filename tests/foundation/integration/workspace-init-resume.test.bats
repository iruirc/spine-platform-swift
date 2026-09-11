#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "rerunning ws-init-driver is a no-op when artifacts exist (idempotent)" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  local before_hash="$(find "$parent" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  local after_hash="$(find "$parent" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q)"
  [ "$before_hash" = "$after_hash" ]
}

@test "a rerun after the config was written but before Workspace meta only appends the block" {
  # Stands in for an interrupted s02b: setup wrote the config, the append never ran.
  # The config differs from the stub's output, so a rerun that rewrote it would fail cmp.
  local parent="$(ws_mktemp_dir)"
  local driver="$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh"
  local yml="$(ws_fixture_path workspace-yml/grouped.yml)"
  run "$driver" "$yml" "$parent"
  [ "$status" -eq 0 ]
  local config="$parent/GroupedWS-meta/CLAUDE-spine-toolkit.md"
  cp "$config" "$BATS_TEST_TMPDIR/full.md"
  sed '/^## Workspace meta$/,$d' "$BATS_TEST_TMPDIR/full.md" | sed '$d' | sed 's/^manual$/auto/' > "$config"
  sed 's/^manual$/auto/' "$BATS_TEST_TMPDIR/full.md" > "$BATS_TEST_TMPDIR/want.md"
  run grep -c '^## Workspace meta$' "$config"
  [ "$output" = "0" ]
  run "$driver" "$yml" "$parent"
  [ "$status" -eq 0 ]
  cmp "$BATS_TEST_TMPDIR/want.md" "$config"
}
