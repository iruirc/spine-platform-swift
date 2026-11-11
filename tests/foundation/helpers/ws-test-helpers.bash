#!/usr/bin/env bash
# Shared bats helpers for Foundation tests.
# Source from each .bats file via:
#   load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

# Absolute path to the toolkit repo root, regardless of cwd.
ws_repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd
}

# Path to a Foundation lib script.
ws_lib_path() {
  echo "$(ws_repo_root)/templates/workspace/lib/$1"
}

# Path to a Foundation fixture directory or file.
ws_fixture_path() {
  echo "$(ws_repo_root)/tests/foundation/fixtures/$1"
}

# Create a temp directory; trap-cleaned at end of test.
ws_mktemp_dir() {
  local d
  d="$(mktemp -d -t wsfound.XXXXXX)"
  WS_TEST_TMPDIRS+=("$d")
  echo "$d"
}

# Hook to invoke from `teardown` for cleanup.
ws_cleanup_tmpdirs() {
  local d
  for d in "${WS_TEST_TMPDIRS[@]:-}"; do
    [[ -d "$d" ]] && rm -rf -- "$d"
  done
  WS_TEST_TMPDIRS=()
}

# Builds the workspace of a fixture once per test file; call from `setup_file`. A build takes
# seconds and a copy a fraction of one, and a built workspace holds no absolute path and no
# symlink, so each test's copy is the workspace the driver would have built in its place.
# Usage: ws_build_template workspace-yml/<name>.yml
ws_build_template() {
  local out
  out="$("$(ws_repo_root)/tests/foundation/helpers/ws-init-driver.zsh" \
    "$(ws_fixture_path "$1")" "$BATS_FILE_TMPDIR/template" 2>&1)" || {
    echo "ws_build_template: ws-init-driver failed on $1"; echo "$out"; return 1; }
}

# Gives a test its own copy of the workspace ws_build_template built; <dest> may exist and be empty.
ws_copy_template() {
  mkdir -p -- "$1" && cp -Rp -- "$BATS_FILE_TMPDIR/template/." "$1"
}

# Run a zsh script under test with stdin/stdout captured.
# Usage: ws_run_zsh "$(ws_lib_path workspace-yml-parser.zsh)" wsyml::load /path/to/yml
ws_run_zsh() {
  zsh -c 'source "$1"; shift; "$@"' "ws_run_zsh" "$@"
}

# Runs wsproj::swift_init_flags against a workspace.yml.
# Usage: ws_swift_init_flags <workspace.yml> <ios|macos> <interactive|batch> [config-root, default /r]
ws_swift_init_flags() {
  local lib; lib="$(ws_repo_root)/templates/workspace/lib"
  zsh -c "for f in workspace-yml-parser workspace-package workspace-project; do source '$lib/'\$f.zsh; done
    wsyml::load '$1' || exit 9
    wsproj::swift_init_flags $2 $3 '${4-/r}'"
}
