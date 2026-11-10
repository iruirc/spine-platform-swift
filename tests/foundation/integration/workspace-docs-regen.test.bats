#!/usr/bin/env bats
# fixtures/docs-regen/expected is the format of every section and workspace file the script writes;
# a change to that format changes the golden files in the same commit.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
  PARENT="$(ws_mktemp_dir)"
  "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/docs-regen.yml)" "$PARENT" >/dev/null 2>&1
  # The meta repo is the workspace root: workspace.yml, the docs and the packages share one folder.
  META="$PARENT"
  REGEN="$(ws_repo_root)/scripts/workspace-docs-regen.zsh"
  GOLDEN="$(ws_fixture_path docs-regen/expected)"
}
teardown() { ws_cleanup_tmpdirs; }

tree_hash() { find "$PARENT" -type f -not -path '*/.git/*' -exec md5 -q {} + | md5 -q; }

# The tools version of a manifest comes from the machine that generated it, so the golden files hold
# one value and both sides are read with it masked; the test below asserts the real one.
norm() { sed 's|^// swift-tools-version: .*|// swift-tools-version: <toolchain>|'; }

@test "a new workspace matches the golden files" {
  n=0
  while IFS= read -r f; do
    n=$((n + 1))
    diff -u <(norm < "$GOLDEN/$f") <(norm < "$PARENT/$f") || return 1
  done < <(cd "$GOLDEN" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
  [ "$n" -eq 17 ] || { echo "compared $n golden files; the scan went vacuous"; return 1; }
}

@test "a generated manifest names this machine's toolchain" {
  local tools
  tools="$(zsh -c "for f in workspace-yml-parser workspace-doc-markers workspace-docs workspace-package; do source '$(ws_repo_root)/templates/workspace/lib/'\$f.zsh; done; wsyml::load '$META/workspace.yml'; wspkg::tools_version")"
  [[ "$tools" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "no toolchain version: $tools"; return 1; }
  grep -Fxq "// swift-tools-version: $tools" "$PARENT/sharedPackages/AKit/Package.swift"
}

@test "a second run and --check change nothing" {
  before="$(tree_hash)"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=0" ]
  run "$REGEN" --check
  [ "$status" -eq 0 ]
  [ "$(tree_hash)" = "$before" ]
}

@test "--check shows a new public declaration, exits 1 and writes nothing" {
  printf '%s\n' 'public struct Engine {' '}' > "$PARENT/sharedPackages/BEngine/Sources/BEngine/Engine.swift"
  cd "$META"
  run "$REGEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'+- `public struct Engine`'* ]]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=1 malformed=0 missing=0 pending=0" ]
  cmp "$GOLDEN/sharedPackages/BEngine/CLAUDE.md" "$PARENT/sharedPackages/BEngine/CLAUDE.md"
  run "$REGEN"
  [ "$status" -eq 0 ]
  grep -Fxq -- '- `public struct Engine`' "$PARENT/sharedPackages/BEngine/CLAUDE.md"
}

@test "text outside the markers survives; a stale section does not" {
  printf '%s\n' '- stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$META/README.md' PKG_LIST"
  echo "MANUAL_OUTSIDE_MARKERS" >> "$META/README.md"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  run grep -Fxq -- '- stale' "$META/README.md"
  [ "$status" -ne 0 ]
  grep -Fxq -- '- AKit (api-contract) — common' "$META/README.md"
  grep -Fxq 'MANUAL_OUTSIDE_MARKERS' "$META/README.md"
}

@test "runs from a package repository inside the workspace; --pkg keeps to that package" {
  for p in sharedPackages/AKit domainPackages/CFeature; do
    printf '%s\n' '# stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$PARENT/$p/README.md' PKG_HEADER"
  done
  printf '%s\n' '- stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$META/README.md' PKG_LIST"
  cd "$PARENT/domainPackages/CFeature"
  run "$REGEN" --pkg CFeature
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/domainPackages/CFeature/README.md" "$PARENT/domainPackages/CFeature/README.md"
  cmp "$GOLDEN/README.md" "$META/README.md"
  grep -Fxq '# stale' "$PARENT/sharedPackages/AKit/README.md"
  run "$REGEN" --pkg Nope
  [ "$status" -eq 2 ]
}

@test "an unwritable file does not poison the scratch path for the next file of the same basename" {
  local target="$PARENT/sharedPackages/AKit/Package.swift"
  cp "$(ws_fixture_path docs-regen/pre-markers/sharedPackages/BEngine/Package.swift)" "$target"
  chmod 444 "$target"
  cd "$META"
  run "$REGEN"
  local rc="$status"
  chmod 644 "$target"
  [ "$rc" -eq 0 ]
  cmp "$GOLDEN/sharedPackages/BEngine/Package.swift" "$PARENT/sharedPackages/BEngine/Package.swift"
  cmp "$GOLDEN/domainPackages/CFeature/Package.swift" "$PARENT/domainPackages/CFeature/Package.swift"
}

@test "--check names a .code-workspace it would create" {
  rm -f "$META/RegenWS.code-workspace"
  cd "$META"
  run "$REGEN" --check
  [ "$status" -eq 1 ]
  # bash 3.2's `set -e` does not act on a [[ ]] mid-body; `|| return 1` makes the check bite.
  [[ "$output" == *"RegenWS.code-workspace: would be created"* ]] || return 1
  [ ! -e "$META/RegenWS.code-workspace" ]
}

@test "a regenerated contents.xcworkspacedata is world-readable" {
  rm -rf "$META/RegenWS.xcworkspace"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$META/RegenWS.xcworkspace/contents.xcworkspacedata")" = 644 ]
}

@test "a newly created .code-workspace is world-readable" {
  rm -f "$META/RegenWS.code-workspace"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$META/RegenWS.code-workspace")" = 644 ] || return 1
}

@test "malformed markers exit 2 and leave the rest regenerated; --repair waits for --yes" {
  printf '%s\n' '<!-- WORKSPACE_LAYERS_BEGIN -->' >> "$META/ARCHITECTURE.md"
  printf '%s\n' '- stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$META/README.md' PKG_LIST"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing WORKSPACE_LAYERS_END"* ]]
  cmp "$GOLDEN/README.md" "$META/README.md"
  cp "$META/ARCHITECTURE.md" "$BATS_TEST_TMPDIR/broken.md"
  run "$REGEN" --repair
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=1" ]
  cmp "$BATS_TEST_TMPDIR/broken.md" "$META/ARCHITECTURE.md"
  run "$REGEN" --repair --yes
  [ "$status" -eq 0 ]
  run "$REGEN" --check
  [ "$status" -eq 0 ]
}

@test "a preview reports what it cannot repair instead of silently skipping it" {
  # A cross-nested pair (WORKSPACE_GRAPH_BEGIN sits inside the LAYERS pair) is a boundary
  # wsmark::repair_to refuses to auto-fix, not just a lint error --repair can propose past.
  awk '/<!-- WORKSPACE_LAYERS_END -->/ { print "<!-- WORKSPACE_GRAPH_BEGIN -->" } { print }' \
    "$META/ARCHITECTURE.md" > "$BATS_TEST_TMPDIR/cross-nested.md"
  cp "$BATS_TEST_TMPDIR/cross-nested.md" "$META/ARCHITECTURE.md"
  cd "$META"
  run "$REGEN" --repair
  [ "$status" -eq 2 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=1 missing=0 pending=0" ]
  cmp "$BATS_TEST_TMPDIR/cross-nested.md" "$META/ARCHITECTURE.md"
}

@test "--repair --yes rebuilds a manifest whose target-deps END was deleted, without truncating the file" {
  local m="$PARENT/domainPackages/CFeature/Package.swift"
  grep -v 'WORKSPACE_PKG_TARGET_DEPS_END' "$m" > "$BATS_TEST_TMPDIR/truncated-source.swift"
  cp "$BATS_TEST_TMPDIR/truncated-source.swift" "$m"
  cd "$META"
  run "$REGEN" --repair --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"CFeature/Package.swift: PKG_TARGET_DEPS — "*" line(s) left below the restored _END; check for duplicates"* ]] || return 1
  grep -Fq '.testTarget(name: "CFeatureTests"' "$m"
  [ "$(tail -n 1 "$m")" = ")" ]
  # Repair keeps what the lost END swallowed below the restored pair and says so; regen fills the pair again.
  [ "$(grep -Fxc '            .product(name: "AKit", package: "AKit"),' "$m")" -eq 2 ]
  run "$REGEN" --check
  [ "$status" -eq 0 ]
}

@test "--repair prints why a file is malformed" {
  printf '%s\n' '<!-- WORKSPACE_LAYERS_BEGIN -->' >> "$META/ARCHITECTURE.md"
  cd "$META"
  run "$REGEN" --repair
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing WORKSPACE_LAYERS_END"* ]]
}

@test "runs from a folder deep inside a package and finds the root workspace.yml" {
  printf '%s\n' '# stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$PARENT/sharedPackages/AKit/README.md' PKG_HEADER"
  cd "$PARENT/sharedPackages/AKit/Sources/AKit"
  run "$REGEN"
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/sharedPackages/AKit/README.md" "$PARENT/sharedPackages/AKit/README.md"
  [ ! -e "$PARENT/sharedPackages/AKit/Sources/workspace.yml" ]
}

# The old layout: <ws>/RegenWS-meta holds workspace.yml, the packages sit beside it in <ws>.
old_layout() {
  OLD="$(ws_mktemp_dir)"
  mkdir -p "$OLD/RegenWS-meta" "$OLD/sharedPackages/AKit/Sources" "$OLD/domainPackages/CFeature"
  cp "$META/workspace.yml" "$OLD/RegenWS-meta/workspace.yml"
  OLD_HASH="$(find "$OLD" -type f -exec md5 -q {} + | md5 -q)"
}

@test "the old layout, run from a package beside the *-meta folder, exits 4 and points at the migration guide" {
  old_layout
  cd "$OLD/sharedPackages/AKit/Sources"
  run "$REGEN"
  [ "$status" -eq 4 ]
  [[ "$output" == *"docs/migrations/workspace-nested-layout.md"* ]] || return 1
  [ "$(find "$OLD" -type f -exec md5 -q {} + | md5 -q)" = "$OLD_HASH" ]
}

@test "the old layout, run from the folder that holds the *-meta folder, exits 4 and points at the migration guide" {
  old_layout
  cd "$OLD"
  run "$REGEN"
  [ "$status" -eq 4 ]
  [[ "$output" == *"docs/migrations/workspace-nested-layout.md"* ]] || return 1
  [ "$(find "$OLD" -type f -exec md5 -q {} + | md5 -q)" = "$OLD_HASH" ]
}

@test "the old layout, run from inside the *-meta folder, exits 4 and rewrites nothing" {
  old_layout
  cd "$OLD/RegenWS-meta"
  run "$REGEN"
  [ "$status" -eq 4 ]
  [[ "$output" == *"docs/migrations/workspace-nested-layout.md"* ]] || return 1
  [ "$(find "$OLD" -type f -exec md5 -q {} + | md5 -q)" = "$OLD_HASH" ]
  [ ! -e "$OLD/RegenWS-meta/RegenWS.xcworkspace" ]
  [ ! -e "$OLD/RegenWS-meta/RegenWS.code-workspace" ]
}

@test "the old layout is reported before a schema error an old workspace.yml carries" {
  old_layout
  yq -i '.packages[0].allowed_deps = ["library"]' "$OLD/RegenWS-meta/workspace.yml"
  cd "$OLD/RegenWS-meta"
  run "$REGEN" --check
  [ "$status" -eq 4 ] || { echo "$output"; return 1; }
  [[ "$output" == *"docs/migrations/workspace-nested-layout.md"* ]]
}

@test "a new root that happens to be named <ws>-meta and holds its packages is still a root" {
  local root="$(ws_mktemp_dir)/RegenWS-meta"
  mkdir -p "$root/sharedPackages/AKit"
  cp "$META/workspace.yml" "$root/workspace.yml"
  cd "$root"
  run "$REGEN" --check
  [ "$status" -ne 4 ]
}

@test "regen fills .gitignore, bootstrap.sh and SPINE.md, and --check passes afterwards" {
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  grep -Fxq '# WORKSPACE_REPOS_BEGIN' "$META/.gitignore"
  grep -Fxq '/sharedPackages/AKit/' "$META/.gitignore"
  grep -Fxq '/domainPackages/CFeature/' "$META/.gitignore"
  grep -Fxq $'sharedPackages/AKit\tgit@github.com:user/AKit.git' "$META/bootstrap.sh"
  grep -Fxq -- '- sharedPackages/BEngine — engine package' "$META/SPINE.md"
  run "$REGEN" --check
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh is still executable after a regen that rewrites it" {
  [ -x "$META/bootstrap.sh" ] || { echo "the generated bootstrap.sh is not executable"; return 1; }
  printf '%s\n' 'stale-path	stale-url' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$META/bootstrap.sh' REPOS"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$META/bootstrap.sh")" = 755 ] || return 1
  run grep -c 'stale-path' "$META/bootstrap.sh"
  [ "$output" = "0" ]
  grep -Fxq $'sharedPackages/BEngine\tgit@github.com:user/BEngine.git' "$META/bootstrap.sh"
}

@test "the same REPOS marker takes each file's own generator" {
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  run grep -c $'\t' "$META/.gitignore"
  [ "$output" = "0" ]
  run grep -c '^/' "$META/bootstrap.sh"
  [ "$output" = "0" ]
}

@test "a registered file that is not there is counted as missing; one without the pair is left alone" {
  rm "$META/SPINE.md"
  grep -v 'WORKSPACE_REPOS_' "$META/.gitignore" > "$BATS_TEST_TMPDIR/plain.gitignore"
  cp "$BATS_TEST_TMPDIR/plain.gitignore" "$META/.gitignore"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=1 pending=0" ]
  cmp "$BATS_TEST_TMPDIR/plain.gitignore" "$META/.gitignore"
  [ ! -e "$META/SPINE.md" ]
}

@test "--adopt brings 1.12 docs under the markers and keeps what the user wrote" {
  local pre="$(ws_fixture_path docs-regen/pre-markers)" f
  local -a files=(README.md CONTRIBUTING.md sharedPackages/BEngine/CLAUDE.md)
  for f in "${files[@]}"; do cp "$pre/$f" "$PARENT/$f"; done
  cd "$META"
  run "$REGEN" --adopt
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=3" ]
  for f in "${files[@]}"; do cmp "$pre/$f" "$PARENT/$f"; done
  run "$REGEN" --adopt --yes
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/README.md" "$META/README.md"
  run grep -c 'WORKSPACE_PROJECT_RULES\|workspace-check\|Cluster 2' "$META/README.md" "$META/CONTRIBUTING.md" "$PARENT/sharedPackages/BEngine/CLAUDE.md"
  [ "$output" = "$META/README.md:0
$META/CONTRIBUTING.md:0
$PARENT/sharedPackages/BEngine/CLAUDE.md:0" ]
  grep -Fxq 'Keep UI state out of packages.' "$META/CONTRIBUTING.md"
  grep -Fxq 'Never import UIKit.' "$PARENT/sharedPackages/BEngine/CLAUDE.md"
  for m in ARCHETYPE_RULES:CONTRIBUTING.md PKG_BOUNDARY:sharedPackages/BEngine/CLAUDE.md PKG_PUBLIC_API:sharedPackages/BEngine/CLAUDE.md PKG_META:sharedPackages/BEngine/CLAUDE.md; do
    [ "$(zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::read '$PARENT/${m#*:}' ${m%%:*}")" \
      = "$(zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::read '$GOLDEN/${m#*:}' ${m%%:*}")" ] || { echo "$m differs"; return 1; }
  done
  run "$REGEN" --check
  [ "$status" -eq 0 ]
}

@test "--adopt without --yes writes nothing even when there is nothing to adopt" {
  printf '%s\n' 'public struct Engine {' '}' > "$PARENT/sharedPackages/BEngine/Sources/BEngine/Engine.swift"
  cd "$META"
  run "$REGEN" --adopt
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=0" ]
  cmp "$GOLDEN/sharedPackages/BEngine/CLAUDE.md" "$PARENT/sharedPackages/BEngine/CLAUDE.md"
  run "$REGEN" --repair
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/sharedPackages/BEngine/CLAUDE.md" "$PARENT/sharedPackages/BEngine/CLAUDE.md"
}

@test "the .code-workspace keeps numbers regen does not change, byte for byte" {
  local cw="$META/RegenWS.code-workspace"
  yq -i -p=json -o=json -I=2 'del(.folders[1])' "$cw"
  # yq would print 1.5 and round the integer; write the literals in by hand.
  sed -i '' 's|"settings": {}|"settings": { "zoom": 1.50, "big": 100000000000000000001 }|' "$cw"
  grep -qF '1.50' "$cw" || { echo "setup did not place the literals"; return 1; }
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  grep -qF '"zoom": 1.50' "$cw"
  grep -qF '"big": 100000000000000000001' "$cw"
  [ "$(yq -p=json -o=json -I=0 '.folders' "$cw")" = "$(yq -p=json -o=json -I=0 '.folders' "$GOLDEN/RegenWS.code-workspace")" ]
}

@test "regen refuses a jq older than 1.7 instead of rewriting numbers" {
  local bin="$(ws_mktemp_dir)"
  printf '#!/bin/sh\necho jq-1.6\n' > "$bin/jq"; chmod +x "$bin/jq"
  cd "$META"
  PATH="$bin:$PATH" run "$REGEN"
  [ "$status" -eq 3 ]
  [[ "$output" == *"jq 1.7 or newer is required"*"found: jq-1.6"* ]]
}

@test "regen rejects a jq pre-release version without a bad math expression" {
  local bin="$(ws_mktemp_dir)"
  printf '#!/bin/sh\necho jq-1.6rc2\n' > "$bin/jq"; chmod +x "$bin/jq"
  cd "$META"
  PATH="$bin:$PATH" run "$REGEN"
  [ "$status" -eq 3 ]
  [[ "$output" == *"jq 1.7 or newer is required"*"found: jq-1.6rc2"* ]] || return 1
  [[ "$output" != *"bad math expression"* ]]
}

@test "--check exits 0 with a jq older than 1.7 on a clean workspace" {
  local bin="$(ws_mktemp_dir)"
  printf '#!/bin/sh\necho jq-1.6\n' > "$bin/jq"; chmod +x "$bin/jq"
  cd "$META"
  PATH="$bin:$PATH" run "$REGEN" --check
  [ "$status" -eq 0 ]
}

@test "regen accepts a jq older than 1.7 when workspace.code_workspace is false" {
  yq -i '.workspace.code_workspace = false' "$META/workspace.yml"
  local bin="$(ws_mktemp_dir)"
  printf '#!/bin/sh\necho jq-1.6\n' > "$bin/jq"; chmod +x "$bin/jq"
  cd "$META"
  PATH="$bin:$PATH" run "$REGEN"
  [ "$status" -eq 0 ]
}

@test "the .code-workspace keeps its settings; one that is not plain JSON is reported" {
  local cw="$META/RegenWS.code-workspace"
  yq -i -p=json -o=json -I=2 '.settings."editor.tabSize" = 4 | del(.folders[1])' "$cw"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "$(yq -p=json -o=json -I=0 '.folders' "$cw")" = "$(yq -p=json -o=json -I=0 '.folders' "$GOLDEN/RegenWS.code-workspace")" ]
  [ "$(yq -p=json '.settings."editor.tabSize"' "$cw")" = 4 ]
  printf '// a comment VS Code allows\n' >> "$cw"
  run "$REGEN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not plain JSON"* ]]
}

@test "outside a workspace the script exits 4" {
  cd "$(ws_mktemp_dir)"
  run "$REGEN"
  [ "$status" -eq 4 ]
  [[ "$output" == *"no workspace.yml"* ]]
}

@test "--check shows a manifest that lost a dependency and writes nothing" {
  local m="$PARENT/domainPackages/CFeature/Package.swift"
  grep -v '.package(path: "../../sharedPackages/BEngine")' "$m" > "$BATS_TEST_TMPDIR/stale.swift"
  cp "$BATS_TEST_TMPDIR/stale.swift" "$m"
  cd "$META"
  run "$REGEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *'+        .package(path: "../../sharedPackages/BEngine"),'* ]] || return 1
  cmp "$BATS_TEST_TMPDIR/stale.swift" "$m"
  run "$REGEN"
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/domainPackages/CFeature/Package.swift" "$m"
}

@test "an external dep with no version requirement is reported and left out of the manifest" {
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sharedPackages/AKit/Package.swift: external dep https://github.com/apple/swift-algorithms.git has no version requirement"* ]] || return 1
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=0" ]
  run grep -c 'swift-algorithms' "$PARENT/sharedPackages/AKit/Package.swift"
  [ "$output" = "0" ]
}

@test "a manifest below the stack is named on every run and never rewritten" {
  local m="$PARENT/sharedPackages/BEngine/Package.swift"
  sed -i '' -e 's|^// swift-tools-version: .*|// swift-tools-version: 5.9|' \
            -e 's|\[\.iOS(\.v17), \.macOS(\.v14)\]|[.iOS(.v15), .macOS(.v14)]|' "$m"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sharedPackages/BEngine/Package.swift: swift-tools-version 5.9 < 6.0 (fix by hand)"* ]] || return 1
  [[ "$output" == *"sharedPackages/BEngine/Package.swift: platforms .iOS(.v15) below defaults.platforms ios 17.0 (fix by hand)"* ]] || return 1
  grep -Fxq '// swift-tools-version: 5.9' "$m"
  grep -Fq '[.iOS(.v15), .macOS(.v14)]' "$m"
}

@test "--adopt brings a 1.14 manifest under the markers and fills it" {
  local m="$PARENT/sharedPackages/BEngine/Package.swift"
  cp "$(ws_fixture_path docs-regen/pre-markers/sharedPackages/BEngine/Package.swift)" "$m"
  cd "$META"
  run "$REGEN" --adopt
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=1" ]
  cmp "$(ws_fixture_path docs-regen/pre-markers/sharedPackages/BEngine/Package.swift)" "$m"
  run "$REGEN" --adopt --yes
  [ "$status" -eq 0 ]
  grep -Fxq '        .package(path: "../AKit"),' "$m"
  grep -Fxq '            .product(name: "AKit", package: "AKit"),' "$m"
  run grep -c 'Filled by' "$m"
  [ "$output" = "0" ]
  # The stack it was adopted with stays 1.14's, and saying so does not colour the exit code.
  run "$REGEN" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"swift-tools-version 5.9 < 6.0"* ]] || return 1
}

@test "--adopt reports a manifest whose arrays are the user's and changes nothing" {
  local m="$PARENT/sharedPackages/BEngine/Package.swift"
  cp "$(ws_fixture_path docs-regen/pre-markers/sharedPackages/BEngine/Package.swift)" "$m"
  sed -i '' -e 's|// Filled by.*|.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),|' "$m"
  cp "$m" "$BATS_TEST_TMPDIR/hand-written.swift"
  cd "$META"
  run "$REGEN" --adopt --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Package.swift: not the shape the package template renders; add both marker pairs by hand"* ]] || return 1
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=1" ]
  cmp "$BATS_TEST_TMPDIR/hand-written.swift" "$m"
}
