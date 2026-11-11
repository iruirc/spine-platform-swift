#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/test-foundation.sh sha256:11626b8b730021a82aa492e67cfe1b44d67d997726e9ddd27c4b507c820c8493
# Adapted from spine-toolkit's test runner. Plugins share no code; update both or neither.
# Run Foundation bats tests.
# Usage: scripts/test-foundation.sh [unit|integration|all|changed]
#   changed  runs what the branch touches since its merge base with $TEST_BASE (default main),
#            uncommitted and untracked files included; the map is tests/foundation/README.md.
set -euo pipefail

target="${1:-all}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$root/tests/foundation/lib"
integration="$root/tests/foundation/integration"

if ! command -v bats >/dev/null 2>&1; then
  echo "error: bats-core not on PATH. install: brew install bats-core" >&2
  exit 3
fi

# Prints the bats arguments for the changed files, one per line, and why to stderr.
# Keep in step with the table in tests/foundation/README.md.
changed_suites() {
  local base_ref="${TEST_BASE:-main}" base files f need_all=0 need_unit=0 extra=""
  # A fresh clone of a branch has origin/main and no local main.
  git -C "$root" rev-parse -q --verify "$base_ref^{commit}" >/dev/null ||
    base_ref="origin/$base_ref"
  base="$(git -C "$root" merge-base HEAD "$base_ref")" || {
    echo "error: no merge base with '$base_ref'; set TEST_BASE" >&2; exit 2; }
  files="$( { git -C "$root" diff --name-only "$base"
              git -C "$root" ls-files --others --exclude-standard; } | sort -u)"
  if [ -z "$files" ]; then
    echo "changed: nothing differs from $base_ref" >&2
    return 0
  fi
  while IFS= read -r f; do
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
