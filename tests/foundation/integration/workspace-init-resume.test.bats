#!/usr/bin/env bats
# --resume: the driver keeps <root>/.workspace-init.state like the skill, and WS_DRIVER_STOP_AT=<step>
# stops it just before that step runs (exit 75), the way an interruption would.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
  DRIVER="$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh"
}
teardown() { ws_cleanup_tmpdirs; }

tree_hash() { (cd "$1" && find . -type f -not -path '*/.git/*' -not -name '*.pbxproj' | LC_ALL=C sort | xargs md5 -q | md5 -q); }

@test "--resume after an interruption at the second app's s06b finishes without duplicates" {
  command -v xcodegen >/dev/null 2>&1 || skip "xcodegen not on PATH"
  local yml="$(ws_fixture_path workspace-yml/with-project-full.yml)"
  local clean="$(ws_mktemp_dir)" root="$(ws_mktemp_dir)"
  run "$DRIVER" "$yml" "$clean"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }

  WS_DRIVER_STOP_AT=s06b_project_macos run "$DRIVER" "$yml" "$root"
  [ "$status" -eq 75 ] || { echo "$output"; return 1; }
  grep -qx 's06e_project_git_ios' "$root/.workspace-init.state"
  run grep -qx 's06b_project_macos' "$root/.workspace-init.state"
  [ "$status" -eq 1 ]
  [ -f "$root/SPINE.md" ]
  [ ! -e "$root/FullApp-macOS/project.yml" ]

  run "$DRIVER" "$yml" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ ! -e "$root/.workspace-init.state" ]
  run grep -c '^- FullApp-macOS:' "$root/SPINE.md"
  [ "$output" = 1 ]
  run grep -c '^## Workspace meta$' "$root/SPINE.md"
  [ "$output" = 1 ]
  run yq eval '.targets."FullApp-iOS".dependencies | length' "$root/FullApp-iOS/project.yml"
  [ "$output" -eq 2 ]
  cmp "$clean/SPINE.md" "$root/SPINE.md"
  cmp "$clean/.gitignore" "$root/.gitignore"
  cmp "$clean/bootstrap.sh" "$root/bootstrap.sh"
  [ "$(tree_hash "$clean")" = "$(tree_hash "$root")" ]
  run git -C "$root" status --porcelain
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a resume finds the config setup wrote before the interruption and only appends to it" {
  # Stands in for an interrupted s02b: setup wrote the config, the appends never ran. The config
  # differs from the stub's output, so a resume that rewrote it would fail cmp.
  local yml="$(ws_fixture_path workspace-yml/grouped.yml)"
  local clean="$(ws_mktemp_dir)" root="$(ws_mktemp_dir)"
  run "$DRIVER" "$yml" "$clean"
  [ "$status" -eq 0 ]
  sed 's/^\[WORKFLOW_MODE\] = \[manual\]$/[WORKFLOW_MODE] = [auto]/' "$clean/SPINE.md" > "$BATS_TEST_TMPDIR/want.md"

  WS_DRIVER_STOP_AT=s02b_meta_config run "$DRIVER" "$yml" "$root"
  [ "$status" -eq 75 ]
  [ ! -e "$root/SPINE.md" ]
  sed '/^## Workspace meta$/,$d' "$BATS_TEST_TMPDIR/want.md" | sed '$d' > "$root/SPINE.md"
  run grep -c '^## Workspace meta$' "$root/SPINE.md"
  [ "$output" = 0 ]

  run "$DRIVER" "$yml" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$BATS_TEST_TMPDIR/want.md" "$root/SPINE.md"
}

@test "an interrupted s02 resumes into an executable bootstrap.sh" {
  local yml="$(ws_fixture_path workspace-yml/grouped.yml)" root="$(ws_mktemp_dir)"
  WS_DRIVER_STOP_AT=s03_meta_git run "$DRIVER" "$yml" "$root"
  [ "$status" -eq 75 ]
  # The render landed but the chmod did not.
  chmod -x "$root/bootstrap.sh"
  sed -i '' '/^s02_meta_files$/d' "$root/.workspace-init.state"
  run "$DRIVER" "$yml" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -x "$root/bootstrap.sh" ]
}
