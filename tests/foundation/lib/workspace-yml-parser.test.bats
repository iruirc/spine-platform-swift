#!/usr/bin/env bats

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
}

teardown() {
  ws_cleanup_tmpdirs
}

@test "wsyml::load on minimal.yml succeeds" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)'"
  [ "$status" -eq 0 ]
}

@test "wsyml::get returns workspace.name" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)'; wsyml::get '.workspace.name'"
  [ "$status" -eq 0 ]
  [ "$output" = "minimal-ws" ]
}

@test "wsyml::get returns 1 when key missing" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)'; wsyml::get '.nope.missing'"
  [ "$status" -eq 1 ]
}

@test "wsyml::packages echoes one name per line" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::packages"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "AKit" ]
  [ "${lines[1]}" = "BEngine" ]
  [ "${lines[2]}" = "CFeature" ]
}

@test "wsyml::groups echoes group names" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::groups"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "common" ]
  [ "${lines[1]}" = "domain" ]
}

@test "wsyml::remotes echoes remote names" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::remotes"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "origin" ]
  [ "${lines[1]}" = "mirror" ]
}

@test "wsyml::package_field returns archetype for a package" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)'; wsyml::package_field BEngine archetype"
  [ "$status" -eq 0 ]
  [ "$output" = "engine" ]
}

@test "validate accepts grouped.yml" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/grouped.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate rejects missing workspace.name" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/missing-name.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"workspace.name is required"* ]]
}

@test "validate rejects empty packages" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/empty-packages.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"packages must have"* ]]
}

@test "validate rejects duplicate package name" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/duplicate-pkg.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate package name"* ]]
}

@test "validate rejects unknown group reference" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-group-ref.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown group"* ]]
}

@test "validate rejects unknown deps reference" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-dep-ref.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown package 'Nope'"* ]]
}

@test "validate rejects git remote key not in top-level remotes" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-remote-key.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown remote 'gitolite'"* ]]
}

@test "validate rejects bad archetype" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-archetype.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid archetype 'widget'"* ]]
}

@test "validate rejects non-semver version" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-version.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid version 'v1'"* ]]
}

@test "validate rejects deps not in allowed_deps when allowed_deps non-empty" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/disallowed-deps.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"package 'C' dep 'A' not in allowed_deps"* ]]
}

@test "validate rejects tasks.path that is absolute" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-absolute-path.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.path must be relative"* ]]
}

@test "validate rejects tasks.enabled that is not a boolean" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-bad-enabled.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.enabled must be boolean"* ]]
}

@test "validate accepts tasks.enabled: false" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-disabled.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate rejects tasks.mode that is not sibling|path|symlink" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-bad-mode.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.mode must be one of sibling|path|symlink"* ]]
}

@test "validate rejects tasks.mode=symlink without symlink_target" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-symlink-no-target.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tasks.mode=symlink requires non-empty tasks.symlink_target"* ]]
}

@test "validate rejects docs.path that is absolute" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-absolute-path.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"docs.path must be relative"* ]]
}

@test "validate rejects docs.mode that is not sibling|path|symlink" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-bad-mode.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"docs.mode must be one of sibling|path|symlink"* ]]
}

@test "validate rejects docs.mode=symlink without symlink_target" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-symlink-no-target.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"docs.mode=symlink requires non-empty docs.symlink_target"* ]]
}

@test "validate accepts docs.enabled: false" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/docs-disabled.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate accepts tasks + docs in symlink mode with targets" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/tasks-docs-symlink.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate rejects example_app without example_platform" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/example-app-no-platform.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"example_app: true requires example_platform"* ]]
}

@test "validate rejects malformed git_author" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-author.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git_author"* ]]
}

@test "validate accepts with-project-full.yml" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-full.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate rejects bad app key (watchos)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-bad-app-key.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"apps.watchos rejected (MVP supports ios|macos only)"* ]]
}

@test "validate rejects repo-package collision" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-repo-pkg-collision.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"repo name 'CoreKit' collides with package name 'CoreKit'"* ]]
}

@test "validate rejects duplicate repo names across apps" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-duplicate-repos.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate repo name 'MyApp' in project.apps"* ]]
}

@test "validate rejects bad stack.di" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-bad-stack-di.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"stack.di 'nonexistent'"* ]]
}

@test "validate accepts stack.architecture mvi" {
  local tmp="$(ws_mktemp_dir)/mvi.yml"
  cat > "$tmp" <<'EOF'
workspace:
  name: MviWS
remotes: [origin]
project:
  name: MviApp
  apps:
    ios:
      repo: MviApp-iOS
      stack:
        architecture: mvi
packages:
  - name: A
    archetype: api-contract
    git: { origin: git@github.com:user/A.git }
    version: 0.1.0
EOF
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$tmp' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "validate rejects a stack.architecture no flag spells" {
  local tmp="$(ws_mktemp_dir)/router.yml"
  cat > "$tmp" <<'EOF'
workspace:
  name: RouterWS
remotes: [origin]
project:
  name: RouterApp
  apps:
    ios:
      repo: RouterApp-iOS
      stack:
        architecture: mvvm-router
packages:
  - name: A
    archetype: api-contract
    git: { origin: git@github.com:user/A.git }
    version: 0.1.0
EOF
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$tmp' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"stack.architecture 'mvvm-router'"* ]]
}

@test "validate rejects bad stack.min_platforms.ios (non-semver)" {
  local tmp="$(ws_mktemp_dir)/bad-min.yml"
  cat > "$tmp" <<'EOF'
workspace:
  name: BadMin
remotes: [origin]
project:
  name: BadMinApp
  apps:
    ios:
      repo: BadMin-iOS
      stack:
        min_platforms:
          ios: vBadVersion
packages:
  - name: A
    archetype: api-contract
    git: { origin: git@github.com:user/A.git }
    version: 0.1.0
EOF
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$tmp' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"min_platforms.ios 'vBadVersion'"* ]]
}

@test "validate accepts with-project-shortform.yml (string-form apps.<platform>)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-shortform.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate accepts with-project-mixed.yml (full + empty stack mix)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-mixed.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate accepts with-project-partial-stack.yml (single stack field set)" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/with-project-partial-stack.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "wsarch::boundary_text returns text for engine" {
  run zsh -c "source '$(ws_lib_path workspace-archetypes.zsh)'; wsarch::boundary_text engine"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Engine package"* ]]
}

@test "wsarch::boundary_text errors on unknown archetype" {
  run zsh -c "source '$(ws_lib_path workspace-archetypes.zsh)'; wsarch::boundary_text widget"
  [ "$status" -eq 4 ]
}

@test "validate rejects toolkit.lang that is not en|ru" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/toolkit-bad-lang.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"toolkit.lang must be one of en|ru; got 'de'"* ]]
}

@test "validate rejects toolkit.mode that is not manual|auto" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/toolkit-bad-mode.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"toolkit.mode must be one of manual|auto; got 'semi'"* ]]
}

@test "validate rejects toolkit.progress that is not quiet|normal|live" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/toolkit-bad-progress.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"toolkit.progress must be one of quiet|normal|live; got 'verbose'"* ]]
}

@test "validate accepts a toolkit block that sets only some keys" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/toolkit-ru.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "wsyml::toolkit prints the defaults when the block is absent" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)' && print -r -- \$(wsyml::toolkit lang) \$(wsyml::toolkit mode) \$(wsyml::toolkit progress)"
  [ "$status" -eq 0 ]
  [ "$output" = "en manual normal" ]
}

@test "wsyml::toolkit prints what the yml sets and defaults the rest" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/toolkit-ru.yml)' && print -r -- \$(wsyml::toolkit lang) \$(wsyml::toolkit mode) \$(wsyml::toolkit progress)"
  [ "$status" -eq 0 ]
  [ "$output" = "ru manual normal" ]
}

@test "wsyml::toolkit rejects a key it does not know" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)' && wsyml::toolkit colour"
  [ "$status" -eq 4 ]
  [[ "$output" == *"unknown key 'colour'"* ]]
}

@test "validate rejects a defaults.platforms key it does not support and a version that is not semver" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-defaults-platforms.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"defaults.platforms.watchos rejected"* ]]
  [[ "$output" == *"defaults.platforms.ios 'seventeen' must match semver"* ]]
}

@test "validate rejects a defaults.tests value outside the accepted tokens" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-defaults-tests.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"defaults.tests 'spock' must be swift-testing|xctest|quick-nimble"* ]]

  # A glob is not a token: membership is compared literally, so `*` must not pass as a member.
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-defaults-tests-glob.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"defaults.tests '*' must be swift-testing|xctest|quick-nimble"* ]]
}

@test "validate rejects a defaults.platforms that is not a map" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-defaults-platforms-scalar.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"defaults.platforms must be a map of ios/macos to a version"* ]]
}

@test "validate rejects a defaults.platforms that is an empty map" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-defaults-platforms-empty.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"defaults.platforms must have at least one entry"* ]]
}

@test "validate rejects an external dep's unquoted-float version, an unknown requirement key, and a two-key map" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/bad-external-dep-version.yml)' && wsyml::validate"
  [ "$status" -eq 2 ]
  [[ "$output" == *"external dep https://example.com/one.git version '1' must match M.m.p"* ]] || return 1
  [[ "$output" == *"external dep https://example.com/two.git version key 'range' must be one of from|exact|branch|revision"* ]] || return 1
  [[ "$output" == *"external dep https://example.com/three.git version must have exactly one key (from|exact|branch|revision)"* ]] || return 1
}

@test "validate accepts external_deps with all four requirement kinds, a URL-only map, and a bare URL string" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/pkg-manifest.yml)' && wsyml::validate"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "validate accepts a workspace that declares platforms and tests, and one that declares neither" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; wsyml::load '$(ws_fixture_path workspace-yml/minimal.yml)' && wsyml::validate"
  [ "$status" -eq 0 ]
}

@test "the parser accepts exactly the tokens of the canonical table" {
  local skill="$(ws_repo_root)/skills/test-frameworks/SKILL.md"
  local tokens accepted
  tokens="$(awk -F'|' '$0 ~ /^\| `[a-z][a-z+-]*` \|/ { gsub(/[` ]/, "", $2); print $2 }' "$skill" | sort -u)"
  accepted="$(zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; print -l \$WSYML_TESTS_KINDS" | sort -u)"
  [ -n "$tokens" ] || { echo "no token table in the skill"; return 1; }
  [ "$tokens" = "$accepted" ] || {
    echo "the table and the parser disagree:"
    diff <(printf '%s\n' "$tokens") <(printf '%s\n' "$accepted")
    return 1
  }
}
