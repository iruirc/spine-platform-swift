#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "the workspace folder is the meta repo: git, workspace.yml, docs and packages share it" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -d "$root/.git" ]
  [ ! -e "$root/GroupedWS-meta" ]
  [ -f "$root/workspace.yml" ]
  [ -f "$root/README.md" ]
  [ -f "$root/CLAUDE.md" ]
  [ -f "$root/GroupedWS.xcworkspace/contents.xcworkspacedata" ]
  # The config's content is spine-toolkit:setup's and the driver stubs it; the
  # workspace's own blocks are what this plugin still writes.
  local config="$root/SPINE.md"
  grep -Fxq -- '## Workspace meta' "$config"
  grep -Fxq -- '<!-- WORKSPACE_META_BEGIN -->' "$config"
  grep -Fxq -- '- sharedPackages/AKit — api-contract package' "$config"
  grep -Fxq -- '<!-- WORKSPACE_META_END -->' "$config"
  grep -Fxq -- '- External packages: /sharedPackages/*' "$config"
  grep -Fxq -- '- External packages: /domainPackages/*' "$config"
  grep -Fxq -- '- Roots: /Tasks' "$config"
  grep -Fxq -- '- Roots: /Docs' "$config"
  run grep -F '<one `' "$config"
  [ "$status" -eq 1 ]
  [ -f "$root/sharedPackages/AKit/Package.swift" ]
  [ -f "$root/sharedPackages/AKit/CLAUDE.md" ]
  [ -f "$root/sharedPackages/AKit/Sources/AKit/AKit.swift" ]
  [ -f "$root/sharedPackages/AKit/Tests/AKitTests/AKitTests.swift" ]
  run grep -F '{{PACKAGE_NAME}}' "$root/sharedPackages/AKit/Sources/AKit/AKit.swift"
  [ "$status" -eq 1 ]
  [ -f "$root/domainPackages/CFeature/Package.swift" ]
  [ -d "$root/sharedPackages/AKit/.git" ]
  # s14 done: the state file is gone.
  [ ! -e "$root/.workspace-init.state" ]
}

@test "a workspace with no app gets its stack from defaults, never the template placeholder" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/defaults-tests-xctest.yml)" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -Fxq -- '- Tests: XCTest' "$root/SPINE.md"
  grep -Fxq -- '- Baseline: iOS+macOS' "$root/SPINE.md"
  run grep -F '<one `' "$root/SPINE.md"
  [ "$status" -eq 1 ]
}

@test "the meta config takes its toolkit answers from workspace.yml" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/toolkit-ru.yml)" "$root"
  [ "$status" -eq 0 ]
  local config="$root/SPINE.md"
  grep -Fxq -- '[LANG] = [ru]' "$config"
  grep -Fxq -- '[WORKFLOW_MODE] = [manual]' "$config"
  grep -Fxq -- '[PROGRESS] = [normal]' "$config"
}

@test "bootstrap.sh is executable after init and reports every repository as already there" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ]
  [ -x "$root/bootstrap.sh" ]
  run "$root/bootstrap.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = $'ok sharedPackages/AKit\nok sharedPackages/BEngine\nok domainPackages/CFeature' ] \
    || { echo "$output"; return 1; }
}

@test "the initial commit leaves the meta repo clean: every repository it holds is ignored" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ]
  run git -C "$root" rev-list --count HEAD
  [ "$output" = 1 ] || { echo "$output"; return 1; }
  run git -C "$root" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; return 1; }
  run git -C "$root" ls-files
  [[ "$output" == *bootstrap.sh* ]] || { echo "$output"; return 1; }
  [[ "$output" != *sharedPackages* ]] || { echo "$output"; return 1; }
  [[ "$output" != *Tasks* ]] || { echo "$output"; return 1; }
  # The mode is committed too: a fresh clone gets a runnable bootstrap.sh.
  run git -C "$root" ls-files -s bootstrap.sh
  [[ "$output" == 100755* ]] || { echo "$output"; return 1; }
}

@test "a folder that already holds a workspace is refused and left as it was" {
  local root="$(ws_mktemp_dir)"
  local driver="$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh"
  run "$driver" "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ]
  local before="$(find "$root" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q)"
  run "$driver" "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 4 ] || { echo "$output"; return 1; }
  [[ "$output" == *"already holds a workspace"* ]] || { echo "$output"; return 1; }
  [ "$before" = "$(find "$root" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q)" ]
}

@test "a workspace.yml staged in an empty folder is the batch source, not a reason to refuse" {
  local root="$(ws_mktemp_dir)"
  cp "$(ws_fixture_path workspace-yml/grouped.yml)" "$root/workspace.yml"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$root/workspace.yml" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$(ws_fixture_path workspace-yml/grouped.yml)" "$root/workspace.yml"
  [ -d "$root/sharedPackages/AKit/.git" ]
}

@test "--dir names a folder that does not exist yet: s01 creates it" {
  local root="$(ws_mktemp_dir)/a/b"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -d "$root/.git" ]
  [ -f "$root/workspace.yml" ]
}

@test "a manifest regen filled builds with swift build (sanity)" {
  if ! command -v swift >/dev/null 2>&1; then
    skip "swift not on PATH"
  fi
  local root="$(ws_mktemp_dir)"
  # docs-regen.yml's BEngine gets a real path dependency + product from regen (a path dep on AKit,
  # which has an external dep of its own); building it is the only proof the filled lines compile.
  # AKit itself is not built directly: its own manifest carries that external dependency, and the
  # suite must not need the network.
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/docs-regen.yml)" "$root"
  [ "$status" -eq 0 ]
  cd "$root/sharedPackages/BEngine"
  run swift build
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "defaults.tests xctest renders the XCTest stub and not the Swift Testing one" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/defaults-tests-xctest.yml)" "$root"
  [ "$status" -eq 0 ]
  local test_file="$root/packages/OnePkg/Tests/OnePkgTests/OnePkgTests.swift"
  [ -f "$test_file" ]
  grep -Fq 'import XCTest' "$test_file"
  run grep -Fq 'import Testing' "$test_file"
  [ "$status" -eq 1 ]
  # A toolchain framework leaves the manifest as it was: no framework lines, no empty placeholder.
  local manifest="$root/packages/OnePkg/Package.swift"
  run grep -Fq 'TEST_FRAMEWORK' "$manifest"
  [ "$status" -eq 1 ]
  run grep -Fq '.package(url:' "$manifest"
  [ "$status" -eq 1 ]
}

@test "defaults.tests quick-nimble renders the spec and puts both packages in the manifest" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/defaults-tests-quick-nimble.yml)" "$root"
  [ "$status" -eq 0 ]
  local test_file="$root/packages/OnePkg/Tests/OnePkgTests/OnePkgTests.swift"
  [ -f "$test_file" ]
  grep -Fq 'import Quick' "$test_file"
  grep -Fq 'QuickSpec' "$test_file"
  run grep -Fq 'import Testing' "$test_file"
  [ "$status" -eq 1 ]
  # Resolving these two needs the network, so the manifest is read, never built.
  local manifest="$root/packages/OnePkg/Package.swift"
  grep -Fq '.package(url: "https://github.com/Quick/Quick.git", from: "7.6.0"),' "$manifest"
  grep -Fq '.package(url: "https://github.com/Quick/Nimble.git", from: "13.8.0"),' "$manifest"
  grep -Fq '.product(name: "Quick", package: "Quick"),' "$manifest"
  grep -Fq '.product(name: "Nimble", package: "Nimble"),' "$manifest"
  run grep -Fq 'TEST_FRAMEWORK' "$manifest"
  [ "$status" -eq 1 ]
}

@test "ws-init-driver fails on cyclic.yml" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/cyclic.yml)" "$root"
  [ "$status" -ne 0 ]
}
