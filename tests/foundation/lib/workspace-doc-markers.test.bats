#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() { WS_TEST_TMPDIRS=(); }
teardown() { ws_cleanup_tmpdirs; }

@test "wsmark::read returns content between matching markers" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::read '$(ws_fixture_path markers/well-formed.md)' PKG_LIST"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "- A (api-contract)" ]
  [ "${lines[1]}" = "- B (engine)" ]
}

@test "wsmark::write replaces section content, leaves outside intact" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/well-formed.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf '%s\n' '- C (library)' | wsmark::write '$tmp' PKG_LIST"
  [ "$status" -eq 0 ]
  run grep '^- C' "$tmp"
  [ "$status" -eq 0 ]
  run grep '^- A ' "$tmp"
  [ "$status" -eq 1 ]
  run grep '^Manual content' "$tmp"
  [ "$status" -eq 0 ]
  run grep '^More manual content' "$tmp"
  [ "$status" -eq 0 ]
}

@test "wsmark::lint passes well-formed.md" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/well-formed.md)'"
  [ "$status" -eq 0 ]
}

@test "wsmark::lint flags missing END" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/missing-end.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing WORKSPACE_PKG_LIST_END"* ]]
}

@test "wsmark::lint flags orphan END" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/orphan-end.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"orphan WORKSPACE_PKG_LIST_END"* ]]
}

@test "wsmark::lint flags duplicate BEGIN" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/duplicate-begin.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate WORKSPACE_PKG_LIST_BEGIN"* ]]
}

@test "wsmark::lint flags cross-nested pairs" {
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$(ws_fixture_path markers/cross-nested.md)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"crosses"* ]]
}

@test "wsmark::repair fixes missing END (auto-confirm)" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/missing-end.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf 'y\n' | wsmark::repair '$tmp'"
  [ "$status" -eq 0 ]
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$tmp'"
  [ "$status" -eq 0 ]
}

@test "wsmark::repair declines on user 'n'" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/missing-end.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf 'n\n' | wsmark::repair '$tmp'"
  [ "$status" -eq 1 ]
}

@test "wsmark::write refuses on duplicate BEGIN" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/duplicate-begin.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf '%s\n' 'NEW' | wsmark::write '$tmp' PKG_LIST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"multiple"* ]]
}

@test "wsmark::write refuses on missing BEGIN" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '# Hi\nno markers\n' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; printf '%s\n' 'NEW' | wsmark::write '$tmp' PKG_LIST"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no WORKSPACE_PKG_LIST_BEGIN"* ]]
}

@test "wsmark::lint flags a second pair of one marker" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '<!-- WORKSPACE_X_BEGIN -->' one '<!-- WORKSPACE_X_END -->' '<!-- WORKSPACE_X_BEGIN -->' two '<!-- WORKSPACE_X_END -->' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$tmp'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"4: second WORKSPACE_X pair (first closed at line 3)"* ]]
}

@test "wsmark::lint on three pairs of one marker names the first close" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '<!-- WORKSPACE_X_BEGIN -->' one '<!-- WORKSPACE_X_END -->' '<!-- WORKSPACE_X_BEGIN -->' two '<!-- WORKSPACE_X_END -->' '<!-- WORKSPACE_X_BEGIN -->' three '<!-- WORKSPACE_X_END -->' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::lint '$tmp'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"7: second WORKSPACE_X pair (first closed at line 3)"* ]]
}

@test "wsmark::repair_to drops a second pair's markers, keeps its text, and asks nothing" {
  local dir="$(ws_mktemp_dir)"
  printf '%s\n' '<!-- WORKSPACE_X_BEGIN -->' one '<!-- WORKSPACE_X_END -->' '<!-- WORKSPACE_X_BEGIN -->' two > "$dir/in.md"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::repair_to '$dir/in.md' '$dir/out.md' </dev/null"
  [ "$status" -eq 0 ]
  [ "$(cat "$dir/out.md")" = "$(printf '%s\n' '<!-- WORKSPACE_X_BEGIN -->' one '<!-- WORKSPACE_X_END -->' two)" ]
}

@test "wsmark::wrap body wraps a section's body and ignores a heading inside a code fence" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '## Quickstart' '' '```bash' '# clone' 'git clone x' '```' '' '## Next' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '## Quickstart' CLONE body"
  [ "$status" -eq 0 ]
  [ "$(cat "$tmp")" = "$(printf '%s\n' '## Quickstart' '' '<!-- WORKSPACE_CLONE_BEGIN -->' '```bash' '# clone' 'git clone x' '```' '<!-- WORKSPACE_CLONE_END -->' '' '## Next')" ]
}

@test "wsmark::wrap paragraph leaves the text below the first paragraph outside the marker" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '## Boundary contract' '' 'Engine package.' '' 'Also: no UIKit.' '' '<!-- WORKSPACE_PKG_PUBLIC_API_BEGIN -->' '<!-- WORKSPACE_PKG_PUBLIC_API_END -->' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '## Boundary contract' PKG_BOUNDARY paragraph"
  [ "$status" -eq 0 ]
  [ "$(cat "$tmp")" = "$(printf '%s\n' '## Boundary contract' '' '<!-- WORKSPACE_PKG_BOUNDARY_BEGIN -->' 'Engine package.' '<!-- WORKSPACE_PKG_BOUNDARY_END -->' '' 'Also: no UIKit.' '' '<!-- WORKSPACE_PKG_PUBLIC_API_BEGIN -->' '<!-- WORKSPACE_PKG_PUBLIC_API_END -->')" ]
}

@test "wsmark::wrap section takes the heading in, and an empty body gets an empty pair" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '## Public API' '' '- a' '' '## Empty' '' '## Test' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '## Public API' PKG_PUBLIC_API section && wsmark::wrap '$tmp' '## Empty' E body"
  [ "$status" -eq 0 ]
  [ "$(cat "$tmp")" = "$(printf '%s\n' '<!-- WORKSPACE_PKG_PUBLIC_API_BEGIN -->' '## Public API' '' '- a' '<!-- WORKSPACE_PKG_PUBLIC_API_END -->' '' '## Empty' '' '<!-- WORKSPACE_E_BEGIN -->' '<!-- WORKSPACE_E_END -->' '' '## Test')" ]
}

@test "wsmark::wrap section ignores a heading quoted inside a code fence and wraps the real one" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '## Fenced' '```' '## Public API' '```' '' '## Public API' '' '- a' '' '## Test' > "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '## Public API' PKG_PUBLIC_API section"
  [ "$status" -eq 0 ]
  [ "$(cat "$tmp")" = "$(printf '%s\n' '## Fenced' '```' '## Public API' '```' '' '<!-- WORKSPACE_PKG_PUBLIC_API_BEGIN -->' '## Public API' '' '- a' '<!-- WORKSPACE_PKG_PUBLIC_API_END -->' '' '## Test')" ]
}

@test "wsmark::wrap returns 1 and changes nothing when the only heading is inside a code fence" {
  local tmp="$(ws_mktemp_dir)/file.md"
  printf '%s\n' '## Fenced' '```' '## Public API' '```' '' '## Test' > "$tmp"
  cp "$tmp" "$tmp.orig"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '## Public API' PKG_PUBLIC_API section"
  [ "$status" -eq 1 ]
  cmp "$tmp" "$tmp.orig"
}

@test "wsmark::wrap changes nothing when the marker is there, and returns 1 without the heading" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/well-formed.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '# Hello' PKG_LIST body"
  [ "$status" -eq 0 ]
  cmp "$tmp" "$(ws_fixture_path markers/well-formed.md)"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::wrap '$tmp' '## Absent' OTHER body"
  [ "$status" -eq 1 ]
  cmp "$tmp" "$(ws_fixture_path markers/well-formed.md)"
}

@test "wsmark::unwrap removes a pair and keeps what it held" {
  local tmp="$(ws_mktemp_dir)/file.md"
  cp "$(ws_fixture_path markers/well-formed.md)" "$tmp"
  run zsh -c "source '$(ws_lib_path workspace-doc-markers.zsh)'; wsmark::unwrap '$tmp' PKG_LIST"
  [ "$status" -eq 0 ]
  [ "$(cat "$tmp")" = "$(grep -v WORKSPACE_PKG_LIST "$(ws_fixture_path markers/well-formed.md)")" ]
}
