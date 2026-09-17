#!/usr/bin/env bats
# fixtures/docs-regen/expected is the format of every section and workspace file the script writes;
# a change to that format changes the golden files in the same commit.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
  PARENT="$(ws_mktemp_dir)"
  "$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path workspace-yml/docs-regen.yml)" "$PARENT" >/dev/null 2>&1
  META="$PARENT/RegenWS-meta"
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
  [ "$n" -eq 14 ] || { echo "compared $n golden files; the scan went vacuous"; return 1; }
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
  ! grep -Fxq -- '- stale' "$META/README.md"
  grep -Fxq -- '- AKit (api-contract) — common' "$META/README.md"
  grep -Fxq 'MANUAL_OUTSIDE_MARKERS' "$META/README.md"
}

@test "runs from a package repository beside the meta-repo; --pkg keeps to that package" {
  for p in sharedPackages/AKit domainPackages/CFeature; do
    printf '%s\n' '# stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$PARENT/$p/README.md' PKG_HEADER"
  done
  printf '%s\n' '- stale' | zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::write '$META/README.md' PKG_LIST"
  cd "$PARENT/domainPackages/CFeature"
  run "$REGEN" --pkg CFeature
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/domainPackages/CFeature/README.md" "$PARENT/domainPackages/CFeature/README.md"
  cmp "$GOLDEN/RegenWS-meta/README.md" "$META/README.md"
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
  cmp "$GOLDEN/RegenWS-meta/README.md" "$META/README.md"
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
  grep -Fq '.testTarget(name: "CFeatureTests"' "$m"
  [ "$(tail -n 1 "$m")" = ")" ]
  # Repair displaces what the lost END swallowed, so the line appears twice today:
  # once inside the restored pair, once below it. This is the current behaviour, not the desired one.
  [ "$(grep -Fxc '            .product(name: "AKit", package: "AKit"),' "$m")" -eq 2 ]
  run "$REGEN" --check
  [ "$status" -eq 0 ]
}

@test "a workspace.yml beside the meta-repo does not hijack discovery" {
  cp "$META/workspace.yml" "$PARENT/workspace.yml"
  cd "$PARENT/sharedPackages/AKit"
  run "$REGEN"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RegenWS-meta"* ]]
  [ ! -e "$PARENT/RegenWS.xcworkspace" ]
  [ ! -e "$PARENT/RegenWS.code-workspace" ]
}

@test "--adopt brings 1.12 docs under the markers and keeps what the user wrote" {
  local pre="$(ws_fixture_path docs-regen/pre-markers)" f
  local -a files=(RegenWS-meta/README.md RegenWS-meta/CONTRIBUTING.md sharedPackages/BEngine/CLAUDE.md)
  for f in "${files[@]}"; do cp "$pre/$f" "$PARENT/$f"; done
  cd "$META"
  run "$REGEN" --adopt
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "workspace-docs-regen: regenerated=0 drifted=0 malformed=0 missing=0 pending=3" ]
  for f in "${files[@]}"; do cmp "$pre/$f" "$PARENT/$f"; done
  run "$REGEN" --adopt --yes
  [ "$status" -eq 0 ]
  cmp "$GOLDEN/RegenWS-meta/README.md" "$META/README.md"
  run grep -c 'WORKSPACE_PROJECT_RULES\|workspace-check\|Cluster 2' "$META/README.md" "$META/CONTRIBUTING.md" "$PARENT/sharedPackages/BEngine/CLAUDE.md"
  [ "$output" = "$META/README.md:0
$META/CONTRIBUTING.md:0
$PARENT/sharedPackages/BEngine/CLAUDE.md:0" ]
  grep -Fxq 'Keep UI state out of packages.' "$META/CONTRIBUTING.md"
  grep -Fxq 'Never import UIKit.' "$PARENT/sharedPackages/BEngine/CLAUDE.md"
  for m in ARCHETYPE_RULES:RegenWS-meta/CONTRIBUTING.md PKG_BOUNDARY:sharedPackages/BEngine/CLAUDE.md PKG_PUBLIC_API:sharedPackages/BEngine/CLAUDE.md PKG_META:sharedPackages/BEngine/CLAUDE.md; do
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

@test "the .code-workspace keeps its settings; one that is not plain JSON is reported" {
  local cw="$META/RegenWS.code-workspace"
  yq -i -p=json -o=json -I=2 '.settings."editor.tabSize" = 4 | del(.folders[1])' "$cw"
  cd "$META"
  run "$REGEN"
  [ "$status" -eq 0 ]
  [ "$(yq -p=json -o=json -I=0 '.folders' "$cw")" = "$(yq -p=json -o=json -I=0 '.folders' "$GOLDEN/RegenWS-meta/RegenWS.code-workspace")" ]
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
