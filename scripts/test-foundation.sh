#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/test-foundation.sh sha256:11626b8b730021a82aa492e67cfe1b44d67d997726e9ddd27c4b507c820c8493
# Adapted from spine-toolkit's test runner. Plugins share no code; update both or neither.
# Run Foundation bats tests.
# Usage: scripts/test-foundation.sh [unit|integration|all|changed]
#   changed  runs what the branch touches since its merge base with $TEST_BASE (default main),
#            or on main what is not pushed, uncommitted and untracked files included, plus unit
#            when the spine-toolkit checkout beside it has changes; the map is
#            tests/foundation/README.md.
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

case "$target" in
  unit)        bats "$lib" ;;
  integration) bats "$integration" ;;
  all)         bats "$lib" "$integration" ;;
  changed)
    list="$(changed_suites)"
    [ -n "$list" ] || exit 0
    suites=()
    while IFS= read -r s; do suites+=("$s"); done <<< "$list"
    bats "${suites[@]}" ;;
  *)           echo "usage: $0 [unit|integration|all|changed]" >&2; exit 2 ;;
esac
