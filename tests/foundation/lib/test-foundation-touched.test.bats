#!/usr/bin/env bats
# `test-foundation.sh touched` picks the lib/ test files that name a file. With no arguments the
# files are the ones that differ from HEAD: what the next commit would hold. Each test builds a
# small repository with a copy of the script and changes one thing in it. `touched` has no `--list`,
# so a stub `bats` first on PATH prints its arguments one per line and the selection is its output.
# The repository path holds a space, so a summary that splits paths on spaces shows. The
# spine-toolkit checkout beside the plugin is an empty directory.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  R="$BATS_TEST_TMPDIR/my repo"
  mkdir -p "$BATS_TEST_TMPDIR/empty-core"
  export SPINE_TOOLKIT_CORE="$BATS_TEST_TMPDIR/empty-core"
  mkdir -p "$R/scripts" "$R/skills/arch-mvvm" "$R/tests/foundation/helpers" "$R/tests/foundation/fixtures" \
           "$R/tests/foundation/lib" "$R/tests/foundation/integration"
  cp "$ROOT/scripts/test-foundation.sh" "$R/scripts/test-foundation.sh"
  echo a >"$R/scripts/a.sh"
  echo o >"$R/scripts/orphan.sh"
  echo c >"$R/scripts/café.sh"
  echo s >"$R/skills/arch-mvvm/SKILL.md"
  echo h >"$R/tests/foundation/helpers/h.bash"
  echo f >"$R/tests/foundation/fixtures/f.txt"
  local lib="$R/tests/foundation/lib"
  printf '# names scripts/a.sh and scripts/café.sh\n' >"$lib/a.test.bats"
  printf '# names skills/arch-mvvm/SKILL.md\n' >"$lib/mvvm.test.bats"
  printf '# names nothing\n' >"$lib/other.test.bats"
  printf '# names scripts/a.sh\n' >"$lib/with space.test.bats"
  printf '# names scripts/a.sh\n' >"$R/tests/foundation/integration/build.test.bats"
  git -C "$R" init -q -b main
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@t commit -qm base
  git -C "$R" checkout -q -b work
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' >"$BATS_TEST_TMPDIR/stub/bats"
  chmod +x "$BATS_TEST_TMPDIR/stub/bats"
  PATH="$BATS_TEST_TMPDIR/stub:$PATH"
}

commit() {
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@t commit -qm "$1"
}

# Runs `touched` with the stub bats; the selection is $output, stderr is $stderr_text.
touched() {
  run --separate-stderr "$R/scripts/test-foundation.sh" touched "$@"
  stderr_text="${stderr:-}"
}

# The selection as file names, one per line, directories left whole.
names() {
  printf '%s\n' "$output" | sed '/^$/d' | while IFS= read -r p; do
    case "$p" in */tests/foundation/lib) echo "DIR" ;; *) basename "$p" ;; esac
  done
}

@test "touched with no arguments selects the tests that name a modified file" {
  echo more >>"$R/scripts/a.sh"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = $'a.test.bats\nwith space.test.bats' ]
}

@test "a staged-only file is selected" {
  echo x >>"$R/scripts/a.sh"
  git -C "$R" add scripts/a.sh
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = $'a.test.bats\nwith space.test.bats' ]
}

@test "a file both staged and modified again is listed once" {
  echo x >>"$R/scripts/orphan.sh"
  git -C "$R" add scripts/orphan.sh
  echo y >>"$R/scripts/orphan.sh"
  touched
  [ "$status" -eq 0 ]
  [ "$(grep -c 'scripts/orphan.sh -> ' <<<"$stderr_text")" -eq 1 ]
}

@test "an untracked file is selected" {
  echo n >"$R/scripts/new.sh"
  printf '# names scripts/new.sh\n' >"$R/tests/foundation/lib/new.test.bats"
  touched
  [ "$status" -eq 0 ]
  grep -qF -- "new.test.bats" <<<"$(names)"
  grep -qF -- "scripts/new.sh -> new.test.bats" <<<"$stderr_text"
}

@test "a non-ASCII path from the worktree is selected" {
  echo more >>"$R/scripts/café.sh"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = "a.test.bats" ]
}

@test "nothing to commit runs nothing" {
  touched
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qF -- "touched: nothing differs from HEAD" <<<"$stderr_text"
}

@test "touched with no arguments: a changed test file selects itself" {
  echo more >>"$R/tests/foundation/lib/other.test.bats"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = "other.test.bats" ]
}

@test "touched with the path as an argument: a changed test file selects itself" {
  touched tests/foundation/lib/other.test.bats
  [ "$status" -eq 0 ]
  [ "$(names)" = "other.test.bats" ]
}

@test "touched with no arguments: a removed test file runs nothing and says so" {
  git -C "$R" rm -q tests/foundation/lib/other.test.bats
  touched
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qF -- "tests/foundation/lib/other.test.bats -> removed, nothing to run" <<<"$stderr_text"
}

@test "touched with the path as an argument: a removed test file runs nothing and says so" {
  git -C "$R" rm -q tests/foundation/lib/other.test.bats
  touched tests/foundation/lib/other.test.bats
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qF -- "tests/foundation/lib/other.test.bats -> removed, nothing to run" <<<"$stderr_text"
}

@test "a helper change selects the lib tests that load it, not integration" {
  printf "load '../helpers/h'\n" >"$R/tests/foundation/lib/uses-h.test.bats"
  printf "load '../helpers/h'\n" >"$R/tests/foundation/integration/uses-h.test.bats"
  commit "tests that load h"
  echo more >>"$R/tests/foundation/helpers/h.bash"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = "uses-h.test.bats" ]
  grep -qF -- "$R/tests/foundation/lib/uses-h.test.bats" <<<"$output"
  [ "$(grep -c 'integration' <<<"$output")" -eq 0 ]
  grep -qF -- "touched: tests/foundation/helpers/h.bash -> uses-h.test.bats" <<<"$stderr_text"
}

@test "touched: a helper loaded through another helper selects that helper's tests" {
  local lib="$R/tests/foundation/lib" hd="$R/tests/foundation/helpers"
  printf 'load "$BATS_TEST_DIRNAME/../helpers/h"\n' >"$hd/outer.bash"
  printf 'source "$ROOT/tests/foundation/helpers/outer.bash"\n' >"$hd/outer2.bash"
  printf "load '../helpers/h'\n" >"$lib/uses-h.test.bats"
  printf "load '../helpers/outer'\n" >"$lib/uses-outer.test.bats"
  printf "load '../helpers/outer2'\n" >"$lib/uses-outer2.test.bats"
  echo z >"$hd/zzz.bash"
  printf "load '../helpers/zzz'\n" >"$lib/uses-zzz.test.bats"
  commit "helpers and the tests that load them"
  echo more >>"$hd/h.bash"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = "uses-h.test.bats
uses-outer.test.bats
uses-outer2.test.bats" ]
  # a test that loads an unrelated helper is not picked by the chain
  [ "$(grep -c 'uses-zzz' <<<"$output")" -eq 0 ]
}

@test "touched: helpers that load each other in a cycle still end" {
  local lib="$R/tests/foundation/lib" hd="$R/tests/foundation/helpers"
  printf 'load "../helpers/h"\n' >"$hd/outer.bash"
  printf 'load "../helpers/outer"\n' >"$hd/h.bash"
  printf "load '../helpers/outer'\n" >"$lib/uses-outer.test.bats"
  commit "helpers that load each other"
  echo more >>"$hd/h.bash"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = "uses-outer.test.bats" ]
}

@test "touched: a helper no lib test loads runs nothing and says so" {
  printf "load '../helpers/h'\n" >"$R/tests/foundation/integration/uses-h.test.bats"
  commit "an integration test that loads h"
  echo more >>"$R/tests/foundation/helpers/h.bash"
  touched
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qF -- "touched: tests/foundation/helpers/h.bash -> no test loads it" <<<"$stderr_text"
}

@test "touched: a helper change given as an argument selects the tests that load it" {
  printf "load '../helpers/h'\n" >"$R/tests/foundation/lib/uses-h.test.bats"
  commit "a test that loads h"
  touched tests/foundation/helpers/h.bash
  [ "$status" -eq 0 ]
  [ "$(names)" = "uses-h.test.bats" ]
}

@test "touched: a fixture change selects the lib directory, never integration, and no per-file pick" {
  echo more >>"$R/tests/foundation/fixtures/f.txt"
  echo more >>"$R/scripts/a.sh"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = "DIR" ]
  [ "$(grep -c 'integration' <<<"$output")" -eq 0 ]
}

@test "explicit files keep their meaning" {
  echo more >>"$R/scripts/a.sh"
  commit change
  touched scripts/orphan.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qF -- "touched: no test names these files" <<<"$stderr_text"
}

@test "touched selects from lib only, never from integration" {
  echo more >>"$R/scripts/a.sh"
  touched
  [ "$status" -eq 0 ]
  [ "$(grep -c 'integration' <<<"$output")" -eq 0 ]
}

@test "touched with no arguments still adds the tests that read the toolkit checkout" {
  printf '# reads SPINE_TOOLKIT_CORE\n' >"$R/tests/foundation/lib/toolkit.test.bats"
  commit core-test
  echo more >>"$R/scripts/a.sh"
  touched
  [ "$status" -eq 0 ]
  [ "$(names)" = $'a.test.bats\ntoolkit.test.bats\nwith space.test.bats' ]
  grep -qF -- "touched: tests that read the spine-toolkit checkout -> toolkit.test.bats" <<<"$stderr_text"
}
