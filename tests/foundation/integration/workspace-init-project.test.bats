#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
  DRIVER="$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh"
}
teardown() { ws_cleanup_tmpdirs; }

need_xcodegen() { command -v xcodegen >/dev/null 2>&1 || skip "xcodegen not on PATH"; }

@test "two apps under the root: the repos hold the project, the root holds the one config" {
  need_xcodegen
  local root="$(ws_mktemp_dir)"
  run "$DRIVER" "$(ws_fixture_path workspace-yml/with-project-full.yml)" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$root/FullProj-meta" ]
  local app
  for app in FullApp-iOS FullApp-macOS; do
    [ -f "$root/$app/project.yml" ]
    [ -d "$root/$app/$app.xcodeproj" ]
    [ -d "$root/$app/.git" ]
    local f
    for f in SPINE.md CLAUDE.md AGENTS.md DocsMap.md CLAUDE-spine-toolkit.md Tasks Docs; do
      [ ! -e "$root/$app/$f" ] || { echo "$app has its own $f"; return 1; }
    done
  done
  local config="$root/SPINE.md"
  # The first app's stack is the workspace's; the second app is a Modules row.
  grep -Fxq -- '- UI: SwiftUI' "$config"
  grep -Fxq -- '- Baseline: iOS 17+' "$config"
  run grep -F '<one `' "$config"
  [ "$status" -eq 1 ]
  run grep -c '^- FullApp-macOS: /FullApp-macOS — ' "$config"
  [ "$output" = 1 ] || { cat "$config"; return 1; }
  grep -Fq -- '- FullApp-macOS: /FullApp-macOS — UI: SwiftUI, ' "$config"
  grep -Fq -- 'Baseline: macOS 14+' "$config"
  run grep -c '^- FullApp-iOS:' "$config"
  [ "$output" = 0 ]
  run grep -c '^## Workspace meta$' "$config"
  [ "$output" = 1 ]
  grep -Fxq -- '- FullApp-iOS — app (ios)' "$config"
  run yq eval '.packages.CoreKit.path' "$root/FullApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.packages.Engine.path' "$root/FullApp-iOS/project.yml"
  [ "$output" = "../packages/Engine" ]
  run yq eval '.targets."FullApp-iOS".dependencies | length' "$root/FullApp-iOS/project.yml"
  [ "$output" -eq 2 ]
}

@test "xcworkspace contains PROJECT_REFS for both apps" {
  need_xcodegen
  local root="$(ws_mktemp_dir)"
  "$DRIVER" "$(ws_fixture_path workspace-yml/with-project-full.yml)" "$root" >&2
  local xcws="$root/FullProj.xcworkspace/contents.xcworkspacedata"
  [ -f "$xcws" ]
  run grep -F 'group:FullApp-iOS/FullApp-iOS.xcodeproj' "$xcws"
  [ "$status" -eq 0 ]
  run grep -F 'group:FullApp-macOS/FullApp-macOS.xcodeproj' "$xcws"
  [ "$status" -eq 0 ]
}

@test "shortform yml produces same FS shape as long-form" {
  need_xcodegen
  local root="$(ws_mktemp_dir)"
  run "$DRIVER" "$(ws_fixture_path workspace-yml/with-project-shortform.yml)" "$root"
  [ "$status" -eq 0 ]
  [ -f "$root/ShortApp-iOS/project.yml" ]
  [ -d "$root/ShortApp-iOS/ShortApp-iOS.xcodeproj" ]
  [ -d "$root/ShortApp-iOS/.git" ]
  run yq eval '.packages.A.path' "$root/ShortApp-iOS/project.yml"
  [ "$output" = "../packages/A" ]
  run yq eval '.targets."ShortApp-iOS".dependencies | length' "$root/ShortApp-iOS/project.yml"
  [ "$output" -eq 1 ]
}

@test "an app in a dir of its own: the repo under it, the package path climbs out of it" {
  need_xcodegen
  local root="$(ws_mktemp_dir)"
  run "$DRIVER" "$(ws_fixture_path workspace-yml/nested-apps.yml)" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$root/projects/App/project.yml" ]
  [ -d "$root/projects/App/.git" ]
  run yq eval '.packages.OnePkg.path' "$root/projects/App/project.yml"
  [ "$output" = "../../packages/OnePkg" ]
  grep -Fxq -- '/projects/App' "$root/.gitignore"
  run git -C "$root" status --porcelain
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "with apps, the initial commit leaves the meta repo clean and bootstrap.sh finds every repository" {
  need_xcodegen
  local root="$(ws_mktemp_dir)"
  run "$DRIVER" "$(ws_fixture_path workspace-yml/with-project-full.yml)" "$root"
  [ "$status" -eq 0 ]
  run git -C "$root" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; return 1; }
  run "$root/bootstrap.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = $'ok FullApp-iOS\nok FullApp-macOS\nok packages/CoreKit\nok packages/Engine' ] \
    || { echo "$output"; return 1; }
}

@test "a workspace with an app and no packages generates and regenerates cleanly" {
  need_xcodegen
  local root="$(ws_mktemp_dir)"
  run "$DRIVER" "$(ws_fixture_path workspace-yml/with-project-zero-packages.yml)" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$root/workspace.yml" ]
  [ -f "$root/AppOnly-ios/project.yml" ]
  [ ! -d "$root/packages" ]
  xc="$root/AppOnly.xcworkspace/contents.xcworkspacedata"
  # The package pair stays empty: no blank line between its markers.
  awk '/WORKSPACE_PKG_REFS_BEGIN/ {getline n; print n; exit}' "$xc" | grep -q 'WORKSPACE_PKG_REFS_END'
  grep -qF 'AppOnly-ios/AppOnly-ios.xcodeproj' "$xc"
  cd "$root"
  run "$(ws_repo_root)/scripts/workspace-docs-regen.zsh" --check
  [ "$status" -eq 0 ]
}
