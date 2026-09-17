#!/usr/bin/env bats
# workspace-package.zsh: the stack a generated manifest carries, the two arrays regen owns, and what
# the toolkit reports about a manifest it will not rewrite.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

# Usage: pkg <yml> <zsh commands>
pkg() {
  local lib; lib="$(ws_repo_root)/templates/workspace/lib"
  zsh -c "for f in workspace-yml-parser workspace-doc-markers workspace-docs workspace-package; do source '$lib/'\$f.zsh; done
    wsyml::load '$1' || exit 9
    $2"
}

# A manifest in the shape the 1.14.x template rendered: no markers, no deps, Swift 5.9.
legacy_manifest() {
  cat > "$1" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "Core", targets: ["Core"])
    ],
    dependencies: [
        // Filled by `workspace-init` / `workspace-add` based on deps + external_deps in workspace.yml.
    ],
    targets: [
        .target(name: "Core", dependencies: []),
        .testTarget(name: "CoreTests", dependencies: ["Core"])
    ]
)
SWIFT
}

@test "defaults.platforms and defaults.tests are read, a whole major becomes .vN and a minor a string" {
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" 'wspkg::platforms_inline; wspkg::tests_kind; wspkg::platform_floor ios'
  [ "$output" = '.iOS(.v16), .macOS("13.4")
xctest
16.0' ] || { echo "$output"; return 1; }
}

@test "a workspace that declares no platforms gets the toolkit's own floor and Swift Testing" {
  run pkg "$(ws_fixture_path workspace-yml/minimal.yml)" 'wspkg::platforms_inline; wspkg::tests_kind'
  [ "$output" = '.iOS(.v17), .macOS(.v14)
swift-testing' ] || { echo "$output"; return 1; }
}

@test "rel_path drops the shared head: same group, another group, ungrouped" {
  run pkg "$(ws_fixture_path workspace-yml/docs-regen.yml)" 'wspkg::rel_path BEngine AKit; wspkg::rel_path CFeature AKit'
  [ "$output" = '../AKit
../../sharedPackages/AKit' ] || { echo "$output"; return 1; }
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" 'wspkg::rel_path App Core'
  [ "$output" = '../Core' ]
}

@test "manifest_deps writes workspace deps first, then external ones with their requirement" {
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" 'wspkg::manifest_deps App'
  [ "$output" = '        .package(path: "../Core"),' ]
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" 'wspkg::manifest_deps Core'
  [ "$output" = '        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),' ] || { echo "$output"; return 1; }
}

@test "target_deps names one product per workspace dep and nothing for external ones" {
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" 'wspkg::target_deps App'
  [ "$output" = '            .product(name: "Core", package: "Core"),' ]
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" 'wspkg::target_deps Core'
  [ "$output" = "" ]
}

@test "diagnose names an old tools version, floors below the defaults, and a dep with no requirement" {
  local m="$(ws_mktemp_dir)/Package.swift"
  legacy_manifest "$m"
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" "wspkg::diagnose Core '$m' packages/Core/Package.swift"
  [ "$output" = 'packages/Core/Package.swift: swift-tools-version 5.9 < 6.0 (fix by hand)
packages/Core/Package.swift: platforms .iOS(.v15) below defaults.platforms ios 16.0 (fix by hand)
packages/Core/Package.swift: platforms .macOS(.v12) below defaults.platforms macos 13.4 (fix by hand)
packages/Core/Package.swift: external dep https://github.com/apple/swift-algorithms.git has no version requirement (add version: { from: "x.y.z" })' ] || { echo "$output"; return 1; }
}

@test "diagnose says nothing about a manifest that meets the defaults" {
  local m="$(ws_mktemp_dir)/Package.swift"
  legacy_manifest "$m"
  sed -i '' -e 's|5\.9|6.4|' -e 's|\.iOS(\.v15)|.iOS(.v16)|' -e 's|\.macOS(\.v12)|.macOS("13.4")|' "$m"
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" "wspkg::diagnose App '$m' packages/App/Package.swift"
  [ "$output" = "" ] || { echo "$output"; return 1; }
}

@test "tools_version takes the machine's toolchain and refuses one older than 6.0" {
  local bin="$(ws_mktemp_dir)"
  printf '#!/bin/sh\necho "Apple Swift version 6.2 (swiftlang-6.2.0)"\n' > "$bin/swift"
  chmod +x "$bin/swift"
  run env PATH="$bin:$PATH" zsh -c "source '$(ws_lib_path workspace-package.zsh)'; wspkg::tools_version"
  [ "$status" -eq 0 ]
  [ "$output" = "6.2" ]
  printf '#!/bin/sh\necho "Apple Swift version 5.9 (swiftlang-5.9.0)"\n' > "$bin/swift"
  run env PATH="$bin:$PATH" zsh -c "source '$(ws_lib_path workspace-package.zsh)'; wspkg::tools_version"
  [ "$status" -eq 3 ]
  [[ "$output" == *"older than 6.0"* ]]
}

@test "tools_version exits 3 when no swift is on PATH" {
  local bin="$(ws_mktemp_dir)" zsh_bin
  zsh_bin="$(command -v zsh)"
  run env PATH="$bin" "$zsh_bin" -c "source '$(ws_lib_path workspace-package.zsh)'; wspkg::tools_version"
  [ "$status" -eq 3 ]
  [[ "$output" == *"swift not on PATH"* ]]
}

@test "adopt_to puts both pairs into a template-shaped manifest and runs again without changing it" {
  local dir="$(ws_mktemp_dir)"
  legacy_manifest "$dir/Package.swift"
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" "wspkg::adopt_to '$dir/Package.swift' '$dir/out.swift' Core"
  [ "$status" -eq 0 ]
  run grep -c 'WORKSPACE_PKG_MANIFEST_DEPS_BEGIN\|WORKSPACE_PKG_MANIFEST_DEPS_END\|WORKSPACE_PKG_TARGET_DEPS_BEGIN\|WORKSPACE_PKG_TARGET_DEPS_END' "$dir/out.swift"
  [ "$output" = "4" ]
  run grep -xF '        .target(name: "Core", dependencies: [' "$dir/out.swift"
  [ "$status" -eq 0 ]
  run grep -F 'Filled by' "$dir/out.swift"
  [ "$status" -eq 1 ]
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" "wspkg::adopt_to '$dir/out.swift' '$dir/out2.swift' Core"
  [ "$status" -eq 0 ]
  run diff -q "$dir/out.swift" "$dir/out2.swift"
  [ "$status" -eq 0 ]
}

@test "adopt_to refuses a manifest whose arrays already hold the user's lines" {
  local dir="$(ws_mktemp_dir)"
  legacy_manifest "$dir/Package.swift"
  sed -i '' -e 's|// Filled by.*|.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),|' "$dir/Package.swift"
  run pkg "$(ws_fixture_path workspace-yml/pkg-manifest.yml)" "wspkg::adopt_to '$dir/Package.swift' '$dir/out.swift' Core"
  [ "$status" -eq 1 ]
}
