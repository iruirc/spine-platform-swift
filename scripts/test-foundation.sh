#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/test-foundation.sh sha256:5d0f4602cca67ab3daaa92007e0163bc24db75fa7eb319be5acf2c5027230a16
# Adapted from spine-toolkit's test runner. Plugins share no code; update both or neither.
# Run Foundation bats tests.
# Usage: scripts/test-foundation.sh [unit|integration|all|changed|touched <file>...]
#   changed  runs what the branch touches since its merge base with $TEST_BASE (default main),
#            or on main what is not pushed, uncommitted and untracked files included, plus unit
#            when the spine-toolkit checkout beside it has changes; the map is
#            tests/foundation/README.md.
#   touched  runs the test files under lib/ that name any of the given repo-relative files, and
#            nothing else: no map, no diff against a base, nothing from integration/. Never
#            records the tree.
#            Every lib/ test that mentions SPINE_TOOLKIT_CORE, one that reads the spine-toolkit
#            checkout beside this repository, is added to the selection whatever was touched,
#            because the verified tree does not cover that checkout.
#   all      when green and the tree did not change during the run, records the tree it verified
#            in .git/spine-verified-trees (the git common dir), the last 20 trees, newest last.
#            `unit` and `integration` record nothing.
set -euo pipefail

target="${1:-all}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/tests/foundation/lib"
integration="$root/tests/foundation/integration"

if ! command -v bats >/dev/null 2>&1; then
  echo "error: bats-core not on PATH. install: brew install bats-core" >&2
  exit 3
fi

# Prints the files of <repo> that differ from <base> — committed since the merge base, uncommitted
# and untracked. On <base> itself the merge base is HEAD and would hide every local commit, so the
# comparison is with origin/<base>: what has not been pushed. A fresh clone of a branch has
# origin/<base> and no local <base>.
diff_files() {   # <repo> <base>
  local repo="$1" base_ref="$2" base
  if [ "$(git -C "$repo" symbolic-ref --short -q HEAD || true)" = "$base_ref" ] ||
     ! git -C "$repo" rev-parse -q --verify "$base_ref^{commit}" >/dev/null; then
    base_ref="origin/$base_ref"
  fi
  base="$(git -C "$repo" merge-base HEAD "$base_ref")" || {
    echo "error: $repo has no merge base with '$base_ref'; set TEST_BASE" >&2; return 2; }
  { git -C "$repo" diff --name-only "$base"
    git -C "$repo" ls-files --others --exclude-standard; } | sort -u
}

# Prints the bats arguments for the changed files, one per line, and why to stderr.
# Keep in step with the table in tests/foundation/README.md.
changed_suites() {
  local files core core_files f need_all=0 need_unit=0 extra="" where="here"
  files="$(diff_files "$root" "${TEST_BASE:-main}")" || exit 2
  # Tests under lib/ read the spine-toolkit checkout beside this one, so a change there can turn
  # them red with nothing changed here.
  core="${SPINE_TOOLKIT_CORE:-$root/../spine-toolkit}"
  if git -C "$core" rev-parse -q --git-dir >/dev/null 2>&1; then
    where="here or in $core"
    core_files="$(diff_files "$core" main)" || exit 2
    if [ -n "$core_files" ]; then
      echo "changed: $(printf '%s\n' "$core_files" | wc -l | tr -d ' ') file(s) in $core -> unit" >&2
      need_unit=1
    fi
  fi
  if [ -z "$files" ] && [ "$need_unit" -eq 0 ]; then
    echo "changed: nothing differs from main $where" >&2
    return 0
  fi
  [ -n "$files" ] && while IFS= read -r f; do
    case "$f" in
      templates/workspace/*|scripts/workspace-docs-regen.zsh|tests/foundation/helpers/*|tests/foundation/fixtures/*)
        echo "changed: $f -> all" >&2; need_all=1 ;;
      skills/workspace-add/locales/*)
        echo "changed: $f -> unit + workspace-add-incorporate" >&2; need_unit=1
        extra="$extra"$'\n'"$integration/workspace-add-incorporate.test.bats" ;;
      tests/foundation/lib/*.bats|tests/foundation/integration/*.bats)
        [ -f "$root/$f" ] || { echo "changed: $f -> removed, nothing to run" >&2; continue; }
        echo "changed: $f -> itself" >&2
        extra="$extra"$'\n'"$root/$f" ;;
      *)
        echo "changed: $f -> unit" >&2; need_unit=1 ;;
    esac
  done <<< "$files"
  if [ "$need_all" -eq 1 ]; then
    printf '%s\n' "$lib" "$integration"
    return 0
  fi
  [ "$need_unit" -eq 1 ] && printf '%s\n' "$lib"
  # A file under lib/ is already in the lib run.
  printf '%s\n' "$extra" | sed '/^$/d' | sort -u |
    { if [ "$need_unit" -eq 1 ]; then grep -v "^$lib/" || true; else cat; fi; }
}

# Prints the bats arguments for the given files, one per line, and why to stderr. A file is named
# by a test that holds its path as text; the selection is sorted and has no repeats. Tests that
# read the spine-toolkit checkout are always in it.
touched_suites() {   # <file>...
  local f picked core_tests selected=""
  for f in "$@"; do
    picked="$(grep -lF -- "$f" "$lib"/*.bats 2>/dev/null || true)"
    if [ -z "$picked" ]; then
      echo "touched: $f -> no test names it" >&2
    else
      echo "touched: $f -> $(printf '%s\n' "$picked" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')" >&2
      selected="$selected"$'\n'"$picked"
    fi
  done
  # Tests that read the spine-toolkit checkout beside this one run whatever was touched: the stamp
  # hashes this tree only, and no file of a release names them.
  core_tests="$(grep -lF -- 'SPINE_TOOLKIT_CORE' "$lib"/*.bats 2>/dev/null || true)"
  if [ -n "$core_tests" ]; then
    echo "touched: tests that read the spine-toolkit checkout -> $(printf '%s\n' "$core_tests" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')" >&2
    selected="$selected"$'\n'"$core_tests"
  fi
  printf '%s\n' "$selected" | sed '/^$/d' | sort -u
}

# Prints the tree hash the worktree would commit - tracked, modified and untracked files, as
# `git add -A` sees them - built in a scratch copy of the index so the real one is not touched.
# Exits 1 outside git or when $root is not the repository top level.
worktree_tree() {
  local top idx tmp tree="" rc=0
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ "$top" = "$(cd -- "$root" && pwd -P)" ] || return 1
  idx="$(git -C "$root" rev-parse --path-format=absolute --git-path index 2>/dev/null)" || return 1
  tmp="$(mktemp)" || return 1
  # An empty file is not an index to git; with no index to copy, let git start a fresh one.
  if [ -f "$idx" ]; then cp "$idx" "$tmp" || rc=1; else rm -f "$tmp"; fi
  if [ "$rc" -eq 0 ]; then
    GIT_INDEX_FILE="$tmp" git -C "$root" add -A >/dev/null 2>&1 &&
      tree="$(GIT_INDEX_FILE="$tmp" git -C "$root" write-tree 2>/dev/null)" || rc=1
  fi
  rm -f "$tmp"
  [ "$rc" -eq 0 ] || return 1
  printf '%s\n' "$tree"
}

# Appends <tree> to the stamp in the git common dir and keeps the last 20 lines. The new content
# is written beside the stamp and moved over it, so a reader never sees a half-written file.
record_green_tree() {   # <tree>
  local tree="$1" stamp tmp
  stamp="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/spine-verified-trees" || return 1
  [ ! -d "$stamp" ] || return 1   # mv would put the new file inside it
  tmp="$(mktemp "$stamp.XXXXXX" 2>/dev/null)" || return 1
  { { [ ! -e "$stamp" ] || tail -n 19 "$stamp"; printf '%s\n' "$tree"; } >"$tmp" 2>/dev/null &&
      mv "$tmp" "$stamp" 2>/dev/null; } || { rm -f "$tmp"; return 1; }
}

case "$target" in
  unit)        bats "$lib" ;;
  integration) bats "$integration" ;;
  all)
    before="$(worktree_tree || true)"
    rc=0
    bats "$lib" "$integration" || rc=$?
    after="$(worktree_tree || true)"
    if [ "$rc" -eq 0 ] && [ -n "$before" ] && [ "$before" = "$after" ]; then
      record_green_tree "$before" || echo "test-foundation: could not record the verified tree" >&2
    fi
    exit "$rc" ;;
  changed)
    list="$(changed_suites)"
    [ -n "$list" ] || exit 0
    suites=()
    while IFS= read -r s; do suites+=("$s"); done <<< "$list"
    bats "${suites[@]}" ;;
  touched)
    shift
    [ "$#" -gt 0 ] || { echo "usage: $0 [unit|integration|all|changed|touched <file>...]" >&2; exit 2; }
    list="$(touched_suites "$@")"
    if [ -z "$list" ]; then
      echo "touched: no test names these files" >&2
      exit 0
    fi
    chosen=()
    while IFS= read -r s; do chosen+=("$s"); done <<< "$list"
    bats "${chosen[@]}" ;;
  *)           echo "usage: $0 [unit|integration|all|changed|touched <file>...]" >&2; exit 2 ;;
esac
