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

@test "app_dir: the repo under its dir, normalized, default at the root, undeclared key fails" {
  run docs "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsdocs::app_dir ios'
  [ "$output" = 'projects/App' ]
  run docs "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsdocs::app_dir ios'
  [ "$output" = 'SimpleApp-iOS' ]
  run docs "$(ws_fixture_path workspace-yml/with-project-shortform.yml)" 'wsdocs::app_dir ios'
  [ "$output" = 'ShortApp-iOS' ]
  run docs "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsdocs::app_dir macos'
  [ "$status" -eq 2 ]
}

@test "app_dir: ./projects/, projects/ and . normalize without a leading ./ or trailing /" {
  local d f
  f="$(mktemp -d)"; WS_TEST_TMPDIRS+=("$f")
  for d in './projects/' 'projects' 'projects/' '.' './' './a/b/'; do
    sed "s|dir: projects/|dir: $d|" "$(ws_fixture_path workspace-yml/nested-apps.yml)" > "$f/w.yml"
    run docs "$f/w.yml" 'wsdocs::app_dir ios'
    case "$d" in
      .|./) [ "$output" = 'App' ] ;;
      ./a/b/) [ "$output" = 'a/b/App' ] ;;
      *) [ "$output" = 'projects/App' ] ;;
    esac
  done
}

@test "app_url: the url of the first remote, empty when the app has no git" {
  run docs "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsdocs::app_url ios'
  [ "$status" -eq 0 ]
  [ "$output" = 'git@x:o/app.git' ]
  run docs "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsdocs::app_url ios'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an ungrouped package lives under packages/ and sits in the — row" {
  run docs "$(ws_fixture_path workspace-yml/minimal.yml)" 'wsdocs::pkg_dir OnePkg; wsdocs::layers; wsdocs::pkg_meta OnePkg'
  [ "$output" = "packages/OnePkg
| Group | api-contract | engine | library | feature |
|---|---|---|---|---|
| — | OnePkg | — | — | — |
**Archetype**: api-contract
**Group**: —
**Workspace**: minimal-ws (../..)
**Archetype rule exceptions**: —
**External deps**: —
**Version**: 0.1.0" ] || { echo "$output"; return 1; }
}

@test "apps get a project ref and a folder; the clone block is the four lines of a fresh checkout" {
  local yml="$(ws_fixture_path workspace-yml/with-project-full.yml)"
  run docs "$yml" 'wsdocs::clone'
  [ "$output" = '```bash
git clone <meta-repo-url> FullProj
cd FullProj
./bootstrap.sh
open FullProj.xcworkspace
```' ] || { echo "$output"; return 1; }
  run docs "$yml" 'wsdocs::xcworkspace'
  [ "$output" = '<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
<!-- WORKSPACE_PROJECT_REFS_BEGIN -->
   <FileRef location="group:FullApp-iOS/FullApp-iOS.xcodeproj"></FileRef>
   <FileRef location="group:FullApp-macOS/FullApp-macOS.xcodeproj"></FileRef>
<!-- WORKSPACE_PROJECT_REFS_END -->
<!-- WORKSPACE_PKG_REFS_BEGIN -->
   <FileRef location="group:packages/CoreKit"></FileRef>
   <FileRef location="group:packages/Engine"></FileRef>
<!-- WORKSPACE_PKG_REFS_END -->
</Workspace>' ] || { echo "$output"; return 1; }
  run docs "$yml" 'wsdocs::code_workspace_folders'
  [ "$output" = '[{"name": "FullProj", "path": "."},{"name": "FullApp-iOS", "path": "FullApp-iOS"},{"name": "FullApp-macOS", "path": "FullApp-macOS"},{"name": "CoreKit", "path": "packages/CoreKit"},{"name": "Engine", "path": "packages/Engine"},{"name": "Tasks", "path": "Tasks"},{"name": "Docs", "path": "Docs"}]' ] || { echo "$output"; return 1; }
}

@test "an app nested under projects/ keeps its dir in the xcworkspace ref and the folder path" {
  local yml="$(ws_fixture_path workspace-yml/nested-apps.yml)"
  run docs "$yml" 'wsdocs::xcworkspace'
  [[ "$output" == *'<FileRef location="group:projects/App/App.xcodeproj"></FileRef>'* ]]
  [[ "$output" == *'<FileRef location="group:packages/OnePkg"></FileRef>'* ]]
  run docs "$yml" 'wsdocs::code_workspace_folders'
  [[ "$output" == '[{"name": "Nested", "path": "."},'* ]]
  [[ "$output" == *'{"name": "App", "path": "projects/App"}'* ]]
  [[ "$output" == *'{"name": "Tasks", "path": "Tasks"}'* ]]
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
  [ "$output" = '[{"name": "Modes", "path": "."},{"name": "A", "path": "packages/A"},{"name": "Tasks", "path": "work/Tasks"}]
```bash
git clone <meta-repo-url> Modes
cd Modes
./bootstrap.sh
```' ] || { echo "$output"; return 1; }
}

@test "pkg_meta climbs one .. per segment of the package dir, without a trailing slash" {
  run docs "$(ws_fixture_path workspace-yml/grouped.yml)" 'wsdocs::pkg_meta BEngine'
  [[ "$output" == *'**Workspace**: GroupedWS (../..)'* ]]
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

@test "repos: apps first, then packages, as <path><TAB><url>; no url leaves the url empty" {
  run docs "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsdocs::repos'
  [ "$status" -eq 0 ]
  [ "$output" = $'projects/App\tgit@x:o/app.git\npackages/OnePkg\tgit@x:o/one.git' ]
  run docs "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsdocs::repos | head -n 1'
  [ "$output" = $'SimpleApp-iOS\t' ]
}

@test "gitignore_repos: one /<path>/ line per repository, then the Tasks and Docs repos" {
  run docs "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsdocs::gitignore_repos'
  [ "$output" = $'/projects/App/\n/packages/OnePkg/\n/Tasks/\n/Docs/' ] || { echo "$output"; return 1; }
}

@test "gitignore_repos: a Tasks repo in path mode by its path; a symlink and a disabled block are not ignored" {
  local yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: Modes
  tasks: { enabled: true, mode: path, path: ./work/Tasks/ }
  docs: { enabled: true, mode: symlink, symlink_target: ../../Docs }
remotes: [origin]
packages:
  - { name: A, archetype: library, git: { origin: x }, version: 0.1.0 }
YML
  run docs "$yml" 'wsdocs::gitignore_repos'
  [ "$output" = $'/packages/A/\n/work/Tasks/' ] || { echo "$output"; return 1; }
  run docs "$(ws_fixture_path workspace-yml/docs-disabled.yml)" 'wsdocs::gitignore_repos'
  [[ "$output" != *'/Docs/'* ]] || { echo "$output"; return 1; }
  [[ "$output" == *'/Tasks/'* ]] || { echo "$output"; return 1; }
}

@test "repo_map: the workspace line, one line per repository, the commit rule" {
  run docs "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsdocs::repo_map'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '- Workspace: Nested; launch agents from this folder' ]
  [ "${lines[1]}" = '- projects/App — app (ios)' ]
  [ "${lines[2]}" = '- packages/OnePkg — api-contract package' ]
  [ "${lines[3]}" = '- Before editing inside a repository, read its CLAUDE.md when it has one; commit in each repository separately' ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "app_xcodeproj: the one project the app folder holds, else <repo>.xcodeproj" {
  local root; root="$(ws_mktemp_dir)"
  cp "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" "$root/workspace.yml"
  mkdir -p "$root/SimpleApp-iOS"
  run docs "$root/workspace.yml" 'wsdocs::app_xcodeproj ios'
  [ "$output" = 'SimpleApp-iOS/SimpleApp-iOS.xcodeproj' ] || { echo "none: $output"; return 1; }
  mkdir "$root/SimpleApp-iOS/Other.xcodeproj"
  run docs "$root/workspace.yml" 'wsdocs::xcworkspace'
  [[ "$output" == *'<FileRef location="group:SimpleApp-iOS/Other.xcodeproj"></FileRef>'* ]] || { echo "one: $output"; return 1; }
  mkdir "$root/SimpleApp-iOS/Second.xcodeproj"
  run docs "$root/workspace.yml" 'wsdocs::app_xcodeproj ios'
  [ "$output" = 'SimpleApp-iOS/SimpleApp-iOS.xcodeproj' ] || { echo "two: $output"; return 1; }
}

@test "refuse_old_layout: a <name>-meta folder that differs from workspace.name only in case is the old layout" {
  local ws; ws="$(ws_mktemp_dir)"
  mkdir -p "$ws/myapp-meta" "$ws/myapp" "$ws/packages/myapp-core"
  printf '%s\n' 'workspace: { name: MyApp }' 'remotes: [origin]' \
    'project: { name: MyApp, apps: { ios: { repo: myapp } } }' \
    'packages:' '  - { name: myapp-core, archetype: library, git: { origin: git@x:c.git }, version: 0.1.0 }' \
    > "$ws/myapp-meta/workspace.yml"
  run docs "$ws/myapp-meta/workspace.yml" "wsdocs::refuse_old_layout '$ws/myapp-meta/workspace.yml'"
  [ "$status" -eq 4 ] || { echo "$status: $output"; return 1; }
  [[ "$output" == *"docs/migrations/workspace-nested-layout.md"* ]]
}

@test "refuse_old_layout: a new root named <ws>-meta in another case that holds its repositories is a root" {
  local root; root="$(ws_mktemp_dir)/myapp-meta"
  mkdir -p "$root/myapp" "$root/packages/myapp-core"
  printf '%s\n' 'workspace: { name: MyApp }' 'remotes: [origin]' \
    'project: { name: MyApp, apps: { ios: { repo: myapp } } }' \
    'packages:' '  - { name: myapp-core, archetype: library, git: { origin: git@x:c.git }, version: 0.1.0 }' \
    > "$root/workspace.yml"
  run docs "$root/workspace.yml" "wsdocs::refuse_old_layout '$root/workspace.yml'"
  [ "$status" -eq 0 ] || { echo "$status: $output"; return 1; }
}
