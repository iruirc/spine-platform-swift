#!/usr/bin/env bats
# workspace-add --incorporate, as ws-add-driver.zsh runs it: the package moves under the workspace
# root (the meta repo), and regen lists it in .gitignore and bootstrap.sh.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup_file() { ws_build_template workspace-yml/minimal.yml; }

setup() {
  WS_TEST_TMPDIRS=()
  ROOT="$(ws_mktemp_dir)/ws"
  DRIVER="$(ws_repo_root)/tests/foundation/helpers/ws-add-driver.zsh"
  ws_copy_template "$ROOT"
}
teardown() { ws_cleanup_tmpdirs; }

# The skill's "update workspace.yml" step: declare <name> with its url under the first remote.
declare_pkg() {   # <name> <url> [group]
  yq -i ".packages += [{\"name\": \"$1\", \"archetype\": \"engine\", \"version\": \"0.1.0\", \"git\": {\"origin\": \"$2\"}}]" "$ROOT/workspace.yml"
}

# A standalone package folder outside the workspace.
standalone() {   # <name>
  STANDALONE="$(ws_mktemp_dir)/$1"
  mkdir -p "$STANDALONE/Sources"
  echo "fake Package.swift" > "$STANDALONE/Package.swift"
}

@test "incorporate moves the package to <root>/packages/<pkg>, and .gitignore and bootstrap.sh list it" {
  standalone BareKit
  declare_pkg BareKit git@github.com:user/BareKit.git
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" BareKit
  [ "$status" -eq 0 ]
  [ ! -e "$STANDALONE" ]
  [ -f "$ROOT/packages/BareKit/Package.swift" ]
  grep -Fxq '/packages/BareKit' "$ROOT/.gitignore"
  grep -Fxq $'packages/BareKit\tgit@github.com:user/BareKit.git' "$ROOT/bootstrap.sh"
  grep -Fxq '# Package: BareKit' "$ROOT/packages/BareKit/CLAUDE.md"
  grep -Fxq '<!-- WORKSPACE_PKG_BOUNDARY_BEGIN -->' "$ROOT/packages/BareKit/CLAUDE.md"
}

@test "incorporate finds the root from a folder inside the workspace" {
  standalone BareKit
  declare_pkg BareKit git@github.com:user/BareKit.git
  cd "$ROOT/packages/OnePkg/Sources"
  run "$DRIVER" "$STANDALONE" BareKit
  [ "$status" -eq 0 ]
  [ -f "$ROOT/packages/BareKit/Package.swift" ]
  [ ! -e "$ROOT/packages/OnePkg/Sources/packages" ]
}

@test "incorporate --symlink links the package into place and the symlink is still listed" {
  standalone LinkKit
  declare_pkg LinkKit git@github.com:user/LinkKit.git
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" LinkKit --symlink
  [ "$status" -eq 0 ]
  [ -L "$ROOT/packages/LinkKit" ]
  [ -f "$STANDALONE/Package.swift" ]
  grep -Fxq '/packages/LinkKit' "$ROOT/.gitignore"
  grep -Fxq $'packages/LinkKit\tgit@github.com:user/LinkKit.git' "$ROOT/bootstrap.sh"
}

@test "a package incorporated with --symlink stays out of git status of the meta repo after regen" {
  standalone LinkKit
  declare_pkg LinkKit git@github.com:user/LinkKit.git
  git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qam declare
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" LinkKit --symlink
  [ "$status" -eq 0 ]
  [ -L "$ROOT/packages/LinkKit" ]
  # What regen rewrote is the meta repo's own files; commit those, and nothing is left over: the
  # symlink, which git takes for a file, is ignored only by an entry without a trailing slash.
  git -C "$ROOT" add -u
  git -C "$ROOT" -c user.name=t -c user.email=t@t commit -qm regen
  run git -C "$ROOT" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "incorporate into a package group lands under the group's dir" {
  standalone GroupKit
  declare_pkg GroupKit git@github.com:user/GroupKit.git
  yq -i '.package_groups = [{"name": "common", "dir": "sharedPackages"}] | .packages[].group = "common"' "$ROOT/workspace.yml"
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" GroupKit
  [ "$status" -eq 0 ]
  [ -f "$ROOT/sharedPackages/GroupKit/Package.swift" ]
  grep -Fxq '/sharedPackages/GroupKit' "$ROOT/.gitignore"
}

@test "a url whose last component is not the package name prints warn_url_name_mismatch and still incorporates" {
  standalone Pkg
  declare_pkg Pkg git@github.com:user/pkg-ios.git
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" Pkg
  [ "$status" -eq 0 ]
  [[ "$output" == *"git@github.com:user/pkg-ios.git"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"warning: the last part of Pkg's git url"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"Xcode replaces a remote package with a local folder only when the folder name equals the repository name"* ]] || { echo "$output"; return 1; }
  [ -f "$ROOT/packages/Pkg/Package.swift" ]
}

@test "a url that matches the package name prints no mismatch warning" {
  standalone Pkg
  declare_pkg Pkg https://host/o/Pkg.git
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" Pkg
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning: the last part of"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Xcode replaces"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"https://host/o/Pkg.git"* ]] || { echo "$output"; return 1; }
}

@test "a package with no url for the first remote prints no mismatch warning" {
  standalone Pkg
  yq -i '.remotes = ["origin", "mirror"] | .packages += [{"name": "Pkg", "archetype": "engine", "version": "0.1.0", "git": {"mirror": "git@y:o/other.git"}}]' "$ROOT/workspace.yml"
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" Pkg
  [ "$status" -eq 0 ]
  [[ "$output" != *"warning: the last part of"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Xcode replaces"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"git@y:o/other.git"* ]] || { echo "$output"; return 1; }
}

@test "incorporate package with existing CLAUDE.md: it is preserved + warning emitted" {
  standalone HasCLAUDE
  echo "USER_OWNED_CONTENT" > "$STANDALONE/CLAUDE.md"
  declare_pkg HasCLAUDE git@github.com:user/HasCLAUDE.git
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" HasCLAUDE
  [ "$status" -eq 0 ]
  # The warning is half the test's name and was never asserted: silently keeping
  # the file reads to the caller exactly like having written a new one.
  [ "${output#*not overwritten}" != "$output" ]
  run cat "$ROOT/packages/HasCLAUDE/CLAUDE.md"
  [[ "$output" == *"USER_OWNED_CONTENT"* ]]
}

@test "an occupied target stops the run before workspace.yml, the package or the docs change" {
  standalone BareKit
  declare_pkg BareKit git@github.com:user/BareKit.git
  mkdir -p "$ROOT/packages/BareKit"
  echo mine > "$ROOT/packages/BareKit/keep"
  local before; before="$(md5 -q "$ROOT/workspace.yml")$(md5 -q "$ROOT/.gitignore")"
  cd "$ROOT"
  run "$DRIVER" "$STANDALONE" BareKit
  [ "$status" -eq 3 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"already exists"* ]]
  [ -f "$STANDALONE/Package.swift" ]
  [ "$(cat "$ROOT/packages/BareKit/keep")" = mine ]
  [ ! -e "$ROOT/packages/BareKit/Package.swift" ]
  [ "$(md5 -q "$ROOT/workspace.yml")$(md5 -q "$ROOT/.gitignore")" = "$before" ]
}

@test "outside any workspace the driver stops with exit 1 and moves nothing" {
  standalone BareKit
  cd "$(ws_mktemp_dir)"
  run "$DRIVER" "$STANDALONE" BareKit
  [ "$status" -eq 1 ]
  [ -f "$STANDALONE/Package.swift" ]
}

@test "inside an old-layout *-meta folder the driver refuses, pointing at the migration guide" {
  local old="$(ws_mktemp_dir)"
  mkdir -p "$old/minimal-ws-meta" "$old/packages/OnePkg"
  cp "$(ws_fixture_path workspace-yml/minimal.yml)" "$old/minimal-ws-meta/workspace.yml"
  standalone BareKit
  cd "$old/minimal-ws-meta"
  run "$DRIVER" "$STANDALONE" BareKit
  [ "$status" -eq 1 ]
  local guide; guide="$(cd -P -- "$(ws_repo_root)" && pwd)/docs/migrations/workspace-nested-layout.md"
  [[ "$output" == *"docs/migrations/workspace-nested-layout.md ($guide)"* ]] || { echo "$output"; return 1; }
  [ -f "$STANDALONE/Package.swift" ]
}

@test "warn_url_name_mismatch is in both locales with {pkg} and {url}" {
  local k="$(ws_repo_root)/skills/workspace-add/locales" l
  for l in en ru; do
    run awk '$0 == "## warn_url_name_mismatch" { on = 1; next } /^## / { on = 0 } on' "$k/$l.md"
    [[ "$output" == *"{pkg}"* && "$output" == *"{url}"* ]] || { echo "$l: $output"; return 1; }
  done
}
