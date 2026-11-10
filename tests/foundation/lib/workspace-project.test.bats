#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

# Usage: proj <yml> <zsh commands>
proj() {
  local lib; lib="$(ws_repo_root)/templates/workspace/lib"
  zsh -c "for f in workspace-yml-parser workspace-doc-markers workspace-archetypes workspace-docs workspace-project; do source '$lib/'\$f.zsh; done
    wsyml::load '$1' || exit 9
    $2"
}

@test "wsproj::package_path counts from the app repo: a repo at the root reaches packages/ with one .." {
  run proj "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsproj::package_path ios CoreKit'
  [ "$status" -eq 0 ]
  [ "$output" = "../packages/CoreKit" ]
}

@test "wsproj::package_path returns the grouped path" {
  local yml; yml="$(ws_mktemp_dir)/workspace.yml"
  { cat "$(ws_fixture_path workspace-yml/grouped.yml)"; printf 'project:\n  name: G\n  apps:\n    ios: GApp\n'; } > "$yml"
  run proj "$yml" 'wsproj::package_path ios BEngine'
  [ "$status" -eq 0 ]
  [ "$output" = "../sharedPackages/BEngine" ]
}

@test "wsproj::package_path from an app nested under projects/ climbs one .. per segment" {
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsproj::package_path ios OnePkg'
  [ "$status" -eq 0 ]
  [ "$output" = "../../packages/OnePkg" ]
}

@test "wsproj::package_path drops the head an app and a package share" {
  local yml; yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: Shared
remotes: [origin]
project:
  name: S
  apps:
    ios: { repo: App, dir: packages/ }
packages:
  - { name: P, archetype: library, git: { origin: x }, version: 0.1.0 }
YML
  run proj "$yml" 'wsproj::package_path ios P'
  [ "$status" -eq 0 ]
  [ "$output" = "../P" ]
}

@test "wsproj::package_path fails on an undeclared app key and on a missing argument" {
  run proj "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsproj::package_path macos CoreKit'
  [ "$status" -eq 2 ]
  run proj "$(ws_fixture_path workspace-yml/with-project-minimal.yml)" 'wsproj::package_path ios'
  [ "$status" -eq 4 ]
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
    source '$(ws_lib_path workspace-doc-markers.zsh)'
    source '$(ws_lib_path workspace-archetypes.zsh)'
    source '$(ws_lib_path workspace-docs.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    cd '$tmpd/MyApp-iOS' && wsproj::inject_deps . MyApp-iOS ios
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
    source '$(ws_lib_path workspace-doc-markers.zsh)'
    source '$(ws_lib_path workspace-archetypes.zsh)'
    source '$(ws_lib_path workspace-docs.zsh)'
    source '$(ws_lib_path workspace-project.zsh)'
    wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)'
    cd '$tmpd/MyApp-iOS' && wsproj::inject_deps . MyApp-iOS ios
  "
  [ "$status" -eq 0 ]
  run yq eval '.packages.Alamofire.url' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "https://github.com/Alamofire/Alamofire" ]
  run yq eval '.packages.CoreKit.path' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" = "../packages/CoreKit" ]
  run yq eval '.targets."MyApp-iOS".dependencies | length' "$tmpd/MyApp-iOS/project.yml"
  [ "$output" -eq 3 ]
}

# Usage: cfg <file-body> -> prints the path of a fresh root holding SPINE.md with that body
cfg() {
  local root; root="$(ws_mktemp_dir)"
  printf '%b' "$1" > "$root/SPINE.md"
  printf "%s\n" "$root"
}

@test "wsproj::append_workspace_meta writes one section with an empty marker pair, once" {
  local root; root="$(cfg '# Toolkit\n\n## Stack\n\nmvvm\n')"
  run proj "$(ws_fixture_path workspace-yml/grouped.yml)" "wsproj::append_workspace_meta '$root'; wsproj::append_workspace_meta '$root'"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^## Workspace meta$' "$root/SPINE.md")" -eq 1 ]
  [ "$(grep -c '^<!-- WORKSPACE_META_BEGIN -->$' "$root/SPINE.md")" -eq 1 ]
  [ "$(grep -c '^<!-- WORKSPACE_META_END -->$' "$root/SPINE.md")" -eq 1 ]
  # the pair sits right under the heading, with nothing between the markers
  run awk '/^## Workspace meta$/{f=1;next} f&&NF{print;exit}' "$root/SPINE.md"
  [ "$output" = "<!-- WORKSPACE_META_BEGIN -->" ]
  run awk '/WORKSPACE_META_BEGIN/{getline; print; exit}' "$root/SPINE.md"
  [ "$output" = "<!-- WORKSPACE_META_END -->" ]
  run grep -qF -- '-meta' "$root/SPINE.md"
  [ "$status" -eq 1 ]
}

@test "wsproj::append_workspace_meta falls back to the legacy config name, and prefers SPINE.md" {
  local root; root="$(ws_mktemp_dir)"
  printf '# Toolkit\n' > "$root/CLAUDE-spine-toolkit.md"
  run proj "$(ws_fixture_path workspace-yml/grouped.yml)" "wsproj::append_workspace_meta '$root'"
  [ "$status" -eq 0 ]
  grep -q '^## Workspace meta$' "$root/CLAUDE-spine-toolkit.md"
  printf '# SPINE\n' > "$root/SPINE.md"
  run proj "$(ws_fixture_path workspace-yml/grouped.yml)" "wsproj::append_workspace_meta '$root'"
  [ "$status" -eq 0 ]
  grep -q '^## Workspace meta$' "$root/SPINE.md"
  [ "$(grep -c '^## Workspace meta$' "$root/CLAUDE-spine-toolkit.md")" -eq 1 ]
}

@test "wsproj::append_workspace_meta exits 4 without a root or without a config" {
  run proj "$(ws_fixture_path workspace-yml/grouped.yml)" 'wsproj::append_workspace_meta'
  [ "$status" -eq 4 ]
  run proj "$(ws_fixture_path workspace-yml/grouped.yml)" "wsproj::append_workspace_meta '$(ws_mktemp_dir)'"
  [ "$status" -eq 4 ]
}

@test "wsproj::append_module adds the row to an empty ## Modules section, once" {
  local root; root="$(cfg '# T\n\n## Modules\n\n## Stack\n\nmvvm\n')"
  local args="'$root' ios UI=UIKit DI=Swinject"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module $args; wsproj::append_module $args"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '^- App: /projects/App — UI: UIKit, DI: Swinject$' "$root/SPINE.md")" -eq 1 ]
  [ "$(grep -c '^## Modules$' "$root/SPINE.md")" -eq 1 ]
  # the row stays inside ## Modules, and ## Stack keeps its heading
  run awk '/^## Modules$/{f=1;next} /^## /{f=0} f&&/^- /{print}' "$root/SPINE.md"
  [ "$output" = "- App: /projects/App — UI: UIKit, DI: Swinject" ]
  grep -q '^## Stack$' "$root/SPINE.md"
  grep -qx 'mvvm' "$root/SPINE.md"
}

@test "wsproj::append_module appends after the last line of a section that has text, before the next heading" {
  local root; root="$(cfg '# T\n\n## Modules\n\n(none yet)\n- Other: /other — UI: AppKit\n\n## Stack\n\nmvvm\n')"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module '$root' ios UI=SwiftUI"
  [ "$status" -eq 0 ]
  run sed -n '/^## Modules$/,/^## Stack$/p' "$root/SPINE.md"
  [ "$output" = "$(printf '## Modules\n\n(none yet)\n- Other: /other — UI: AppKit\n- App: /projects/App — UI: SwiftUI\n\n## Stack')" ]
}

@test "wsproj::append_module creates ## Modules at the end of the file when it is absent" {
  local root; root="$(cfg '# T\n\n## Stack\n\nmvvm\n')"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module '$root' ios UI=UIKit"
  [ "$status" -eq 0 ]
  run tail -n 3 "$root/SPINE.md"
  [ "$output" = "$(printf '## Modules\n\n- App: /projects/App — UI: UIKit')" ]
}

@test "wsproj::append_module keeps the file mode and adds a second app beside the first" {
  local root; root="$(cfg '# T\n\n## Modules\n')"
  chmod 640 "$root/SPINE.md"
  run proj "$(ws_fixture_path workspace-yml/with-project-full.yml)" "wsproj::append_module '$root' ios UI=SwiftUI; wsproj::append_module '$root' macos UI=AppKit DI=Factory"
  [ "$status" -eq 0 ]
  grep -qx -- '- FullApp-iOS: /FullApp-iOS — UI: SwiftUI' "$root/SPINE.md"
  grep -qx -- '- FullApp-macOS: /FullApp-macOS — UI: AppKit, DI: Factory' "$root/SPINE.md"
  [ "$(stat -f %Lp "$root/SPINE.md" 2>/dev/null || stat -c %a "$root/SPINE.md")" = 640 ]
}

@test "wsproj::append_module is idempotent by the repo prefix, not by the whole row" {
  local root; root="$(cfg '# T\n\n## Modules\n\n- App: /projects/App — UI: SwiftUI\n')"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module '$root' ios UI=UIKit"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '^- App:' "$root/SPINE.md")" -eq 1 ]
  grep -qx -- '- App: /projects/App — UI: SwiftUI' "$root/SPINE.md"
}

@test "wsproj::append_module rejects a missing argument, an unknown app and a missing config with 4 or 2" {
  local root; root="$(cfg '# T\n')"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module '$root'"
  [ "$status" -eq 4 ]
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module '$root' macos UI=AppKit"
  [ "$status" -eq 2 ]
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_module '$(ws_mktemp_dir)' ios UI=UIKit"
  [ "$status" -eq 4 ]
}

@test "wsproj::append_paths lists every package folder and the roots, once" {
  local root; root="$(cfg '# T\n\n## Paths\n\n## Stack\n\nmvvm\n')"
  run proj "$(ws_fixture_path workspace-yml/grouped.yml)" "wsproj::append_paths '$root'; wsproj::append_paths '$root'"
  [ "$status" -eq 0 ]
  run sed -n '/^## Paths$/,/^## Stack$/p' "$root/SPINE.md"
  [ "$output" = "$(printf '## Paths\n\n- External packages: /sharedPackages/*\n- External packages: /domainPackages/*\n- Roots: /Tasks\n- Roots: /Docs\n\n## Stack')" ]
  [ "$(grep -c '^## Paths$' "$root/SPINE.md")" -eq 1 ]
}

@test "wsproj::append_paths names /packages/* only when a package sits outside every group" {
  local root; root="$(cfg '# T\n')"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_paths '$root'"
  [ "$status" -eq 0 ]
  grep -qx -- '- External packages: /packages/\*' "$root/SPINE.md"
  run grep -q -- '/sharedPackages' "$root/SPINE.md"
  [ "$status" -eq 1 ]
  local yml; yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: Mixed
remotes: [origin]
package_groups:
  - { name: common, dir: sharedPackages }
packages:
  - { name: A, archetype: api-contract, group: common, git: { origin: x }, version: 0.1.0 }
YML
  root="$(cfg '# T\n')"
  run proj "$yml" "wsproj::append_paths '$root'"
  [ "$status" -eq 0 ]
  grep -qx -- '- External packages: /sharedPackages/\*' "$root/SPINE.md"
  run grep -q -- '/packages/\*' "$root/SPINE.md"
  [ "$status" -eq 1 ]
}

@test "wsproj::append_paths leaves out the root of a disabled block and follows a path-mode path" {
  local root; root="$(cfg '# T\n')"
  run proj "$(ws_fixture_path workspace-yml/tasks-disabled.yml)" "wsproj::append_paths '$root'"
  [ "$status" -eq 0 ]
  run grep -q -- '- Roots: /Tasks' "$root/SPINE.md"
  [ "$status" -eq 1 ]
  grep -qx -- '- Roots: /Docs' "$root/SPINE.md"
  root="$(cfg '# T\n')"
  run proj "$(ws_fixture_path workspace-yml/docs-disabled.yml)" "wsproj::append_paths '$root'"
  grep -qx -- '- Roots: /Tasks' "$root/SPINE.md"
  run grep -q -- '- Roots: /Docs' "$root/SPINE.md"
  [ "$status" -eq 1 ]
  local yml; yml="$(ws_mktemp_dir)/workspace.yml"
  cat > "$yml" <<'YML'
workspace:
  name: PathMode
  tasks: { enabled: true, mode: path, path: ./work/Tasks }
  docs: { enabled: true, mode: path, path: Notes }
remotes: [origin]
packages:
  - { name: A, archetype: api-contract, git: { origin: x }, version: 0.1.0 }
YML
  root="$(cfg '# T\n')"
  run proj "$yml" "wsproj::append_paths '$root'"
  grep -qx -- '- Roots: /work/Tasks' "$root/SPINE.md"
  grep -qx -- '- Roots: /Notes' "$root/SPINE.md"
}

@test "wsproj::append_paths in symlink mode names the default folders" {
  local root; root="$(cfg '# T\n')"
  run proj "$(ws_fixture_path workspace-yml/tasks-docs-symlink.yml)" "wsproj::append_paths '$root'"
  [ "$status" -eq 0 ]
  grep -qx -- '- Roots: /Tasks' "$root/SPINE.md"
  grep -qx -- '- Roots: /Docs' "$root/SPINE.md"
}

@test "wsproj::append_paths skips a line that is already there and keeps other text" {
  local root; root="$(cfg '# T\n\n## Paths\n\n- Roots: /Tasks\n- Mine: /custom\n')"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::append_paths '$root'"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '^- Roots: /Tasks$' "$root/SPINE.md")" -eq 1 ]
  grep -qx -- '- Mine: /custom' "$root/SPINE.md"
  grep -qx -- '- External packages: /packages/\*' "$root/SPINE.md"
}

@test "wsproj::append_paths exits 4 without a root" {
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" 'wsproj::append_paths'
  [ "$status" -eq 4 ]
}

@test "batch flags carry every axis the app's stack sets, and nothing it leaves out" {
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" ios batch
  [ "$status" -eq 0 ]
  [ "$output" = "--no-prompt --platform=ios --main-target-name=FullApp-iOS --ui-framework=swiftui --di=factory --architecture=mvvm-coordinator --async=async-await --min-ios=17.0 --tests=swift-testing --lang=en --mode=manual --progress=normal --tasks=skip --config-dir=/r" ]
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" macos batch
  [ "$status" -eq 0 ]
  [ "$output" = "--no-prompt --platform=macos --main-target-name=FullApp-macOS --ui-framework=swiftui --di=factory --architecture=mvvm --async=async-await --min-macos=14.0 --tests=swift-testing --lang=en --mode=manual --progress=normal --tasks=skip --config-dir=/r" ]
}

@test "interactive flags pre-answer only the workspace's own questions" {
  run ws_swift_init_flags "$(ws_fixture_path workspace-yml/with-project-full.yml)" ios interactive
  [ "$status" -eq 0 ]
  [ "$output" = "--platform=ios --main-target-name=FullApp-iOS --tests=swift-testing --lang=en --mode=manual --progress=normal --tasks=skip --config-dir=/r" ]
}

@test "tests: the app's own answer in batch, the workspace's otherwise; short-form repo resolves" {
  local y="$(ws_fixture_path workspace-yml/with-project-stack-tests.yml)"
  run ws_swift_init_flags "$y" ios batch
  [ "$output" = "--no-prompt --platform=ios --main-target-name=ST-ios --di=plain --tests=quick-nimble --lang=ru --mode=auto --progress=quiet --tasks=skip --config-dir=/r" ]
  run ws_swift_init_flags "$y" ios interactive
  [[ "$output" == *"--tests=xctest "* ]] || return 1
  run ws_swift_init_flags "$y" macos batch
  [ "$output" = "--no-prompt --platform=macos --main-target-name=ST-macos --tests=xctest --lang=ru --mode=auto --progress=quiet --tasks=skip --config-dir=/r" ]
}

@test "swift_init_flags hands the config root to swift-init in both modes and refuses to run without one" {
  local y="$(ws_fixture_path workspace-yml/with-project-full.yml)"
  run ws_swift_init_flags "$y" ios batch /some/root
  [[ "$output" == *"--config-dir=/some/root"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"--tasks=skip"* ]] || { echo "$output"; return 1; }
  run ws_swift_init_flags "$y" ios interactive /some/root
  [[ "$output" == *"--config-dir=/some/root"* ]] || { echo "$output"; return 1; }
  run ws_swift_init_flags "$y" ios batch ""
  [ "$status" -eq 4 ]
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

@test "wsproj::inject_deps writes the package paths of an app nested under projects/" {
  local tmpd; tmpd="$(ws_mktemp_dir)"
  mkdir -p "$tmpd/App"
  printf 'name: App\ntargets:\n  App:\n    type: application\n    platform: iOS\n    sources: [Sources]\n    dependencies: []\n' > "$tmpd/App/project.yml"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::inject_deps '$tmpd/App' App ios"
  [ "$status" -eq 0 ]
  run yq eval '.packages.OnePkg.path' "$tmpd/App/project.yml"
  [ "$output" = "../../packages/OnePkg" ]
}

@test "wsproj::inject_deps needs the app key" {
  local tmpd; tmpd="$(ws_mktemp_dir)"
  printf 'targets:\n  App: {}\n' > "$tmpd/project.yml"
  run proj "$(ws_fixture_path workspace-yml/nested-apps.yml)" "wsproj::inject_deps '$tmpd' App"
  [ "$status" -eq 4 ]
}
