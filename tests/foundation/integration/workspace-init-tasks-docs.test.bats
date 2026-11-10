#!/usr/bin/env bats
# Coverage for the workspace.tasks / workspace.docs mode matrix (sibling / path / symlink)
# plus preservation of pre-existing Docs symlinks across rerun.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "ws-init-driver provisions Docs/ sibling repo by default (no docs block in yml)" {
  local root="$(ws_mktemp_dir)"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ]
  [ -d "$root/Docs" ]
  [ -d "$root/Docs/.git" ]
  [ -f "$root/Docs/README.md" ]
  [ -d "$root/Tasks" ]
  [ -d "$root/Tasks/.git" ]
}

@test "ws-init-driver provisions Tasks/ + Docs/ as symlinks when mode=symlink" {
  local root="$(ws_mktemp_dir)"
  # Create the external targets the symlinks should point at.
  mkdir -p "$root/external-tasks" "$root/external-docs"
  touch "$root/external-tasks/.keep" "$root/external-docs/.keep"

  # Render a workspace.yml that uses absolute symlink targets.
  local yml="$root/workspace.yml"
  cat > "$yml" <<EOF
workspace:
  name: symlink-ws
  tasks:
    enabled: true
    mode: symlink
    symlink_target: $root/external-tasks
  docs:
    enabled: true
    mode: symlink
    symlink_target: $root/external-docs
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: {origin: x}, version: 0.1.0 }
EOF
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$yml" "$root"
  [ "$status" -eq 0 ]
  [ -L "$root/Tasks" ]
  [ -L "$root/Docs" ]
  [ ! -d "$root/Tasks/.git" ]
  [ ! -d "$root/Docs/.git" ]
  # Symlinks resolve to the prepared external targets.
  # `[ ]`, not `[[ ]]`: a failing `[[ ]]` anywhere but a test's last line does not
  # trip bats' set -e, so the first of these two asserted nothing.
  run readlink "$root/Tasks"
  [ "$status" -eq 0 ]
  [ "$output" = "$root/external-tasks" ]
  run readlink "$root/Docs"
  [ "$status" -eq 0 ]
  [ "$output" = "$root/external-docs" ]
}

@test "ws-init-driver preserves a pre-existing Docs symlink (does not overwrite)" {
  local root="$(ws_mktemp_dir)"
  mkdir -p "$root/manual-docs"
  ln -s "$root/manual-docs" "$root/Docs"
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/grouped.yml)" "$root"
  [ "$status" -eq 0 ]
  # Symlink still in place; the driver did NOT mkdir + git init on top of it.
  [ -L "$root/Docs" ]
  [ ! -d "$root/Docs/.git" ]
  run readlink "$root/Docs"
  [ "$status" -eq 0 ]
  [[ "$output" == "$root/manual-docs" ]]
}

@test "ws-init-driver honors docs.enabled=false" {
  local root="$(ws_mktemp_dir)"
  local yml="$root/workspace.yml"
  cat > "$yml" <<'EOF'
workspace:
  name: nodocs-ws
  docs:
    enabled: false
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: {origin: x}, version: 0.1.0 }
EOF
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$yml" "$root"
  [ "$status" -eq 0 ]
  [ ! -e "$root/Docs" ]
  [ -d "$root/Tasks" ]
}

@test "a relative symlink target counts from the root, and the link is committed with the meta repo" {
  local base="$(ws_mktemp_dir)"
  local root="$base/a/b"
  mkdir -p "$base/ext-tasks" "$root"
  touch "$base/ext-tasks/.keep"
  local yml="$base/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: rel-link
  tasks: { enabled: true, mode: symlink, symlink_target: ../../ext-tasks }
  docs: { enabled: false }
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: {origin: x}, version: 0.1.0 }
YML
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$yml" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run readlink "$root/Tasks"
  [ "$output" = ../../ext-tasks ]
  [ -f "$root/Tasks/.keep" ]
  run git -C "$root" ls-files Tasks
  [ "$output" = Tasks ] || { echo "$output"; return 1; }
  run git -C "$root" status --porcelain
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a Tasks repo in path mode sits at its path under the root and is ignored by the meta repo" {
  local root="$(ws_mktemp_dir)"
  local yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: path-ws
  tasks: { enabled: true, mode: path, path: ./work/Tasks }
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: {origin: x}, version: 0.1.0 }
YML
  run "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" "$yml" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -d "$root/work/Tasks/.git" ]
  grep -Fxq -- '/work/Tasks/' "$root/.gitignore"
  grep -Fxq -- '- Roots: /work/Tasks' "$root/SPINE.md"
  run git -C "$root" status --porcelain
  [ -z "$output" ] || { echo "$output"; return 1; }
}
