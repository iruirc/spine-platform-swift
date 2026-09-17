#!/usr/bin/env bats
# The branches the golden workspace of workspace-docs-regen.test.bats does not reach: apps, ungrouped
# packages, switched-off workspace files, Tasks/Docs modes, and public declarations beyond the stub.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

# Usage: docs <yml> <zsh commands>
docs() {
  local lib; lib="$(ws_repo_root)/templates/workspace/lib"
  zsh -c "for f in workspace-yml-parser workspace-doc-markers workspace-archetypes workspace-docs; do source '$lib/'\$f.zsh; done
    wsyml::load '$1' || exit 9
    $2"
}

@test "apps: the long and the short form, ios before macos" {
  run docs "$(ws_fixture_path workspace-yml/with-project-full.yml)" 'wsdocs::apps'
  [ "$output" = $'ios FullApp-iOS\nmacos FullApp-macOS' ]
  run docs "$(ws_fixture_path workspace-yml/with-project-shortform.yml)" 'wsdocs::apps'
  [ "$output" = 'ios ShortApp-iOS' ]
}

@test "an ungrouped package lives under packages/ and sits in the — row" {
  run docs "$(ws_fixture_path workspace-yml/minimal.yml)" 'wsdocs::pkg_dir OnePkg; wsdocs::layers; wsdocs::pkg_meta OnePkg'
  [ "$output" = "packages/OnePkg
| Group | api-contract | engine | library | feature |
|---|---|---|---|---|
| — | OnePkg | — | — | — |
**Archetype**: api-contract
**Group**: —
**Workspace**: minimal-ws (../../minimal-ws-meta)
**Public deps allowed**: —
**External deps**: —
**Version**: 0.1.0" ] || { echo "$output"; return 1; }
}

@test "apps get a clone line, a project ref and a folder" {
  local yml="$(ws_fixture_path workspace-yml/with-project-full.yml)"
  run docs "$yml" 'wsdocs::clone'
  [ "$output" = '```bash
git clone <meta-repo-url> FullProj-meta
cd FullProj-meta
git clone git@github.com:user/CoreKit.git ../packages/CoreKit
git clone git@github.com:user/Engine.git ../packages/Engine
git clone <FullApp-iOS-url> ../FullApp-iOS
git clone <FullApp-macOS-url> ../FullApp-macOS
open FullProj.xcworkspace
```' ] || { echo "$output"; return 1; }
  run docs "$yml" 'wsdocs::xcworkspace'
  [ "$output" = '<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
<!-- WORKSPACE_PROJECT_REFS_BEGIN -->
   <FileRef location="group:../FullApp-iOS/FullApp-iOS.xcodeproj"></FileRef>
   <FileRef location="group:../FullApp-macOS/FullApp-macOS.xcodeproj"></FileRef>
<!-- WORKSPACE_PROJECT_REFS_END -->
<!-- WORKSPACE_PKG_REFS_BEGIN -->
   <FileRef location="group:../packages/CoreKit"></FileRef>
   <FileRef location="group:../packages/Engine"></FileRef>
<!-- WORKSPACE_PKG_REFS_END -->
</Workspace>' ] || { echo "$output"; return 1; }
  run docs "$yml" 'wsdocs::code_workspace_folders'
  [ "$output" = '[{"name": "FullProj-meta", "path": "."},{"name": "FullApp-iOS", "path": "../FullApp-iOS"},{"name": "FullApp-macOS", "path": "../FullApp-macOS"},{"name": "CoreKit", "path": "../packages/CoreKit"},{"name": "Engine", "path": "../packages/Engine"},{"name": "Tasks", "path": "../Tasks"},{"name": "Docs", "path": "../Docs"}]' ] || { echo "$output"; return 1; }
}

@test "Tasks in path mode is named after its last segment; disabled Docs and xcworkspace are left out" {
  local yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: Modes
  xcworkspace: false
  tasks: { enabled: true, mode: path, path: ./work/Tasks }
  docs: { enabled: false }
remotes: [origin]
packages:
  - { name: A, archetype: library, git: { origin: x }, version: 0.1.0 }
YML
  run docs "$yml" 'wsdocs::code_workspace_folders; wsdocs::clone'
  [ "$output" = '[{"name": "Modes-meta", "path": "."},{"name": "A", "path": "../packages/A"},{"name": "Tasks", "path": "../work/Tasks"}]
```bash
git clone <meta-repo-url> Modes-meta
cd Modes-meta
git clone x ../packages/A
```' ] || { echo "$output"; return 1; }
}

@test "external deps: a map version, a bare-string version, a bare-string entry, and no version" {
  local yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: ExtDeps
remotes: [origin]
packages:
  - name: P
    archetype: library
    git: { origin: x }
    version: 0.1.0
    external_deps:
      - url: https://a.git
        version: { from: "1.0.0" }
      - url: https://b.git
        version: "2.0.0"
      - https://c.git
      - url: https://d.git
YML
  run docs "$yml" 'wsdocs::pkg_deps P'
  [ "$output" = '## Dependencies

Workspace packages:

- none

External packages:

- https://a.git (from 1.0.0)
- https://b.git (2.0.0)
- https://c.git
- https://d.git' ] || { echo "$output"; return 1; }
}

@test "public API lists top-level public and open declarations in byte order, cut at the brace; files without any add no line" {
  local pkg="$(ws_mktemp_dir)"
  mkdir -p "$pkg/Sources/OnePkg/Sub"
  printf '%s\n' 'import Foundation' 'public import Other' 'public struct Item: Sendable {' '    public let id: Int' '}' 'open class Base {}' 'struct Hidden {}' > "$pkg/Sources/OnePkg/OnePkg.swift"
  printf '%s\n' 'public func make() -> Int { 1 }' > "$pkg/Sources/OnePkg/Sub/Make.swift"
  : > "$pkg/Sources/OnePkg/P1.swift"
  : > "$pkg/Sources/OnePkg/P2.swift"
  run docs "$(ws_fixture_path workspace-yml/minimal.yml)" "wsdocs::pkg_public_api OnePkg '$pkg'; wsdocs::pkg_public_api OnePkg '$pkg/absent'"
  [ "$output" = '## Public API

- `public struct Item: Sendable`
- `open class Base`
- `public func make() -> Int`
## Public API

- none' ] || { echo "$output"; return 1; }
}
