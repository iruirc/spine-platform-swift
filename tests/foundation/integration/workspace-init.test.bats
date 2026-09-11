#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "ws-init-driver creates meta-repo + per-package dirs from grouped.yml" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  [ -d "$parent/GroupedWS-meta/.git" ]
  [ -f "$parent/GroupedWS-meta/workspace.yml" ]
  [ -f "$parent/GroupedWS-meta/README.md" ]
  # The config's content is spine-toolkit:setup's and the driver stubs it; the
  # workspace's own block is what this plugin still writes.
  grep -Fxq -- '- Workspace name: GroupedWS' "$parent/GroupedWS-meta/CLAUDE-spine-toolkit.md"
  grep -Fxq -- '- This repository is the meta-repo of a multi-package SPM workspace: meta-repo + N package repos + optional project repos' "$parent/GroupedWS-meta/CLAUDE-spine-toolkit.md"
  [ -f "$parent/sharedPackages/AKit/Package.swift" ]
  [ -f "$parent/sharedPackages/AKit/CLAUDE.md" ]
  # NEW: verify nested source/test stubs are rendered
  [ -f "$parent/sharedPackages/AKit/Sources/AKit/AKit.swift" ]
  [ -f "$parent/sharedPackages/AKit/Tests/AKitTests/AKitTests.swift" ]
  # NEW: verify interpolation worked (no raw placeholder remains)
  run grep -F '{{PACKAGE_NAME}}' "$parent/sharedPackages/AKit/Sources/AKit/AKit.swift"
  [ "$status" -eq 1 ]
  [ -f "$parent/domainPackages/CFeature/Package.swift" ]
  [ -d "$parent/sharedPackages/AKit/.git" ]
}

@test "the meta config takes its toolkit answers from workspace.yml" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/toolkit-ru.yml)" "$parent"
  [ "$status" -eq 0 ]
  run awk '/^## (Language|Mode|Progress)$/{f=1;next} f&&NF{print;f=0}' "$parent/ToolkitRu-meta/CLAUDE-spine-toolkit.md"
  [ "$output" = $'ru\nmanual\nnormal' ] || { echo "got: $output"; return 1; }
}

@test "generated package builds with swift build (sanity)" {
  if ! command -v swift >/dev/null 2>&1; then
    skip "swift not on PATH"
  fi
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$parent"
  [ "$status" -eq 0 ]
  cd "$parent/sharedPackages/AKit"
  run swift build
  [ "$status" -eq 0 ]
}

@test "ws-init-driver fails on cyclic.yml" {
  local parent="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/cyclic.yml)" "$parent"
  [ "$status" -ne 0 ]
}
