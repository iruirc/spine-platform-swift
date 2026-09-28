#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "wsproj::package_path returns flat layout path" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; source '$(ws_lib_path workspace-project.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-minimal.yml)'; wsproj::package_path CoreKit"
  [ "$status" -eq 0 ]
  [ "$output" = "../packages/CoreKit" ]
}

@test "wsproj::package_path returns grouped path" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; source '$(ws_lib_path workspace-project.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsproj::package_path BEngine"
  [ "$status" -eq 0 ]
  [ "$output" = "../sharedPackages/BEngine" ]
}

@test "wsproj::inject_deps adds packages: block and target dependencies" {
  local tmpd
  tmpd="$(ws_mktemp_dir)"
  mkdir -p "$tmpd/MyApp-iOS"
  cat > "$tmpd/MyApp-iOS/project.yml" <<'EOF'
name: MyApp-iOS
options:
  bundleIdPrefix: com.example
targets:
  MyApp-iOS:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies: []
EOF
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    cd '$tmpd/MyApp-iOS' && wsproj::inject_deps . MyApp-iOS
  "
  [ "$status" -eq 0 ]
  run yq eval '.packages.CoreKit.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.packages.Engine.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/Engine" ]
  run yq eval '.targets."MyApp-iOS".dependencies | length' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" -eq 2 ]
}

@test "wsproj::inject_deps preserves existing external dependencies" {
  local tmpd
  tmpd="$(ws_mktemp_dir)"
  mkdir -p "$tmpd/MyApp-iOS"
  cat > "$tmpd/MyApp-iOS/project.yml" <<'EOF'
name: MyApp-iOS
packages:
  Alamofire:
    url: https://github.com/Alamofire/Alamofire
    from: 5.0.0
targets:
  MyApp-iOS:
    type: application
    platform: iOS
    sources: [Sources]
    dependencies:
      - package: Alamofire
EOF
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    cd '$tmpd/MyApp-iOS' && wsproj::inject_deps . MyApp-iOS
  "
  [ "$status" -eq 0 ]
  run yq eval '.packages.Alamofire.url' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "https://github.com/Alamofire/Alamofire" ]
  run yq eval '.packages.CoreKit.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.targets."MyApp-iOS".dependencies | length' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" -eq 3 ]
}

@test "wsproj::append_workspace_meta adds Workspace meta section" {
  local tmpd="$(ws_mktemp_dir)/MyApp-iOS"
  mkdir -p "$tmpd"
  cat > "$tmpd/CLAUDE-spine-toolkit.md" <<'EOF'
# Toolkit configuration — MyApp-iOS

## Stack

mvvm-coordinator
EOF
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    wsproj::append_workspace_meta '$tmpd'
  "
  [ "$status" -eq 0 ]
  run grep '^## Workspace meta' "$tmpd/CLAUDE-spine-toolkit.md"
  [ "$status" -eq 0 ]
  run grep -F 'Workspace name: FullProj (../FullProj-meta)' "$tmpd/CLAUDE-spine-toolkit.md"
  [ "$status" -eq 0 ]
}

@test "wsproj::append_workspace_meta is idempotent" {
  local tmpd="$(ws_mktemp_dir)/MyApp-iOS"
  mkdir -p "$tmpd"
  cat > "$tmpd/CLAUDE-spine-toolkit.md" <<'EOF'
# Toolkit configuration — MyApp-iOS
EOF
  zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    wsproj::append_workspace_meta '$tmpd'
  "
  local count_before
  count_before="$(grep -c '^## Workspace meta' "$tmpd/CLAUDE-spine-toolkit.md")"
  zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    wsproj::append_workspace_meta '$tmpd'
  "
  local count_after
  count_after="$(grep -c '^## Workspace meta' "$tmpd/CLAUDE-spine-toolkit.md")"
  [ "$count_before" -eq 1 ]
  [ "$count_after" -eq 1 ]
}

@test "wsproj::append_workspace_meta meta describes the meta-repo" {
  local tmpd="$(ws_mktemp_dir)/GroupedWS-meta"
  mkdir -p "$tmpd"
  printf '# CLAUDE-spine-toolkit.md — Toolkit Configuration\n' > "$tmpd/CLAUDE-spine-toolkit.md"
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'
    wsproj::append_workspace_meta '$tmpd' meta
  "
  [ "$status" -eq 0 ]
  local f="$tmpd/CLAUDE-spine-toolkit.md"
  grep -Fxq -- '- Workspace name: GroupedWS' "$f"
  grep -Fxq -- '- This repository is the meta-repo of a multi-package SPM workspace: meta-repo + N package repos + optional project repos' "$f"
  grep -Fq -- '- Layout: `workspace.yml` (single source of truth)' "$f"
  ! grep -Fq 'Available packages:' "$f"
}

@test "wsproj::append_workspace_meta meta is idempotent" {
  local tmpd="$(ws_mktemp_dir)/GroupedWS-meta"
  mkdir -p "$tmpd"
  printf '# CLAUDE-spine-toolkit.md — Toolkit Configuration\n' > "$tmpd/CLAUDE-spine-toolkit.md"
  for _ in 1 2; do
    zsh -c "
      source '$(ws_lib_path workspace-yml-parser.zsh)'
      source '$(ws_lib_path workspace-project.zsh)'
      wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'
      wsproj::append_workspace_meta '$tmpd' meta
    "
  done
  [ "$(grep -c '^## Workspace meta' "$tmpd/CLAUDE-spine-toolkit.md")" -eq 1 ]
}

@test "wsproj::append_workspace_meta rejects a role it does not know" {
  local tmpd="$(ws_mktemp_dir)/GroupedWS-meta"
  mkdir -p "$tmpd"
  printf '# CLAUDE-spine-toolkit.md — Toolkit Configuration\n' > "$tmpd/CLAUDE-spine-toolkit.md"
  run zsh -c "
    source '$(ws_lib_path workspace-yml-parser.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'
    wsproj::append_workspace_meta '$tmpd' package
  "
  [ "$status" -eq 4 ]
  [[ "$output" == *"role must be project|meta; got 'package'"* ]]
}

@test "batch flags carry every axis the app's stack sets, and nothing it leaves out" {
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" ios batch
  [ "$status" -eq 0 ]
  [ "$output" = "--no-prompt --platform=ios --main-target-name=FullApp-iOS --ui-framework=swiftui --di=factory --architecture=mvvm-coordinator --async=async-await --min-ios=17.0 --tests=swift-testing --lang=en --mode=manual --progress=normal --tasks=skip" ]
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" macos batch
  [ "$status" -eq 0 ]
  [ "$output" = "--no-prompt --platform=macos --main-target-name=FullApp-macOS --ui-framework=swiftui --di=factory --architecture=mvvm --async=async-await --min-macos=14.0 --tests=swift-testing --lang=en --mode=manual --progress=normal --tasks=skip" ]
}

@test "interactive flags pre-answer only the workspace's own questions" {
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" ios interactive
  [ "$status" -eq 0 ]
  [ "$output" = "--platform=ios --main-target-name=FullApp-iOS --tests=swift-testing --lang=en --mode=manual --progress=normal --tasks=skip" ]
}

@test "tests: the app's own answer in batch, the workspace's otherwise; short-form repo resolves" {
  local y="$(ws_fixture_path workspace-yml/with-project-stack-tests.yml)"
  run ws_swift_init_flags "$y" ios batch
  [ "$output" = "--no-prompt --platform=ios --main-target-name=ST-ios --di=plain --tests=quick-nimble --lang=ru --mode=auto --progress=quiet --tasks=skip" ]
  run ws_swift_init_flags "$y" ios interactive
  [[ "$output" == *"--tests=xctest "* ]]
  run ws_swift_init_flags "$y" macos batch
  [ "$output" = "--no-prompt --platform=macos --main-target-name=ST-macos --tests=xctest --lang=ru --mode=auto --progress=quiet --tasks=skip" ]
}

@test "swift_init_flags refuses an app workspace.yml does not declare" {
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" macos batch
  [ "$status" -eq 4 ]
}

@test "every flag swift_init_flags can print is one swift-init accepts" {
  local init="$(ws_repo_root)/agents/swift-init.md" f checked
  for args in "with-project-full.yml ios batch" "with-project-stack-tests.yml ios batch"; do
    set -- $args
    run ws_swift_init_flags "$(ws_fixture_path workspace-yml/$1)" $2 $3
    [ "$status" -eq 0 ] || { echo "$1 $2 $3: exited $status"; return 1; }
    [ -n "$output" ] || { echo "$1 $2 $3: printed nothing"; return 1; }
    checked=0
    for f in $output; do
      grep -qF -- "[${f%%=*}" "$init" || { echo "$f: not in swift-init's flag list"; return 1; }
      checked=$((checked + 1))
    done
    [ "$checked" -gt 0 ] || { echo "$1 $2 $3: checked 0 flags"; return 1; }
  done
}
