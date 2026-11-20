#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/test-foundation.sh sha256:681560e95d1221606465ccce7616b8d28463873ded88bbf74b99a2fd4158a799
# Adapted from spine-toolkit's test runner. Plugins share no code; update both or neither.
# Run Foundation bats tests.
# Usage: scripts/test-foundation.sh [unit|integration|all|changed|verified|touched [<file>...]]
#   changed  runs what the branch touches since its merge base with $TEST_BASE (default main),
#            or on main what is not pushed, uncommitted and untracked files included, plus unit
#            when the spine-toolkit checkout beside it has changes; the map is
#            tests/foundation/README.md.
#   touched  runs the test files under lib/ that name any of the given repo-relative files, and
#            nothing else: no map, no diff against a base, nothing from integration/. A file under
#            skills/ is named by a test that names its skill. With no files it takes what the
#            next commit would hold, the files that differ from HEAD,
#            staged, unstaged or untracked; none, and it says so and runs nothing. In both forms a
#            changed tests/foundation/lib/*.bats runs itself, a foundation fixture runs the whole
#            lib/ directory, and a helper runs the lib/ tests that load it, directly or through
#            another helper; a helper no lib test loads is reported and runs nothing. It has no
#            --list. Never records the tree.
#            Every lib/ test that mentions SPINE_TOOLKIT_CORE, one that reads the spine-toolkit
#            checkout beside this repository, is added to the selection whatever was touched,
#            because the verified tree does not cover that checkout.
#   verified runs what changed would run for what differs from the verified tree: the newest tree
#            in the history of HEAD that the stamp holds, from all or from verified, to the
#            worktree, untracked files included. The tests that read the spine-toolkit checkout
#            are added whatever changed, as in touched, and a change in that checkout is not
#            looked at. When green and the tree did not change during the run, records
#            '<tree> via <verified tree>' in the stamp, so a tree checked after a full run counts
#            as verified too. With no such tree in the history it says so, runs nothing and exits
#            2; with nothing differing it says so and runs nothing.
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

# The tests that name the skill a file under skills/ belongs to: skills/<name> followed by
# anything but [a-z0-9-], so that task-report does not pick the tests of task-report-x. A test that
# reads "$ROOT/skills/<s>/locales/$l.md" through a variable names the skill, not the file.
skill_tests() {   # <file under skills/>
  local name
  name="${1#skills/}"; name="${name%%/*}"
  name="$(printf '%s' "$name" | sed 's/[][\\.*^$+?(){}|]/\\&/g')"
  grep -lE -- "skills/$name([^a-z0-9-]|\$)" "$lib"/*.bats 2>/dev/null || true
}

# Prints the bats arguments for the changed files, one per line, and why to stderr.
# Keep in step with the table in tests/foundation/README.md.
changed_suites() {   # <label> <toolkit>
  local label="$1" toolkit="$2" files core core_files core_tests f need_all=0 need_unit=0 extra="" where="here"
  files="$(cat)"
  # Tests under lib/ read the spine-toolkit checkout beside this one, so a change there can turn
  # them red with nothing changed here. With <toolkit> core-tests those tests run whatever changed,
  # as in touched: a verified tree does not cover that checkout.
  core="${SPINE_TOOLKIT_CORE:-$root/../spine-toolkit}"
  if [ "$toolkit" = core-tests ]; then
    core_tests="$(grep -lF -- 'SPINE_TOOLKIT_CORE' "$lib"/*.bats 2>/dev/null || true)"
    if [ -n "$core_tests" ]; then
      echo "$label: tests that read the spine-toolkit checkout -> $(printf '%s\n' "$core_tests" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')" >&2
      extra="$extra"$'\n'"$core_tests"
    fi
  elif git -C "$core" rev-parse -q --git-dir >/dev/null 2>&1; then
    where="here or in $core"
    core_files="$(diff_files "$core" main)" || exit 2
    if [ -n "$core_files" ]; then
      echo "$label: $(printf '%s\n' "$core_files" | wc -l | tr -d ' ') file(s) in $core -> unit" >&2
      need_unit=1
    fi
  fi
  if [ -z "$files" ] && [ "$need_unit" -eq 0 ] && [ -z "$extra" ]; then
    echo "$label: nothing differs from main $where" >&2
    return 0
  fi
  [ -n "$files" ] && while IFS= read -r f; do
    case "$f" in
      templates/workspace/*|scripts/workspace-docs-regen.zsh|tests/foundation/helpers/*|tests/foundation/fixtures/*)
        echo "$label: $f -> all" >&2; need_all=1 ;;
      skills/workspace-add/locales/*)
        echo "$label: $f -> unit + workspace-add-incorporate" >&2; need_unit=1
        extra="$extra"$'\n'"$integration/workspace-add-incorporate.test.bats" ;;
      tests/foundation/lib/*.bats|tests/foundation/integration/*.bats)
        [ -f "$root/$f" ] || { echo "$label: $f -> removed, nothing to run" >&2; continue; }
        echo "$label: $f -> itself" >&2
        extra="$extra"$'\n'"$root/$f" ;;
      *)
        echo "$label: $f -> unit" >&2; need_unit=1 ;;
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

# Prints the files of the repo that differ from HEAD - what the next commit would hold: staged,
# unstaged and untracked. A file staged and modified again comes out once. A deleted file stays in
# the list, so the tests that name it are selected. quotePath is off, as in diff_files.
head_files() {
  { git -C "$root" -c core.quotePath=false diff --name-only --no-renames HEAD
    git -C "$root" -c core.quotePath=false ls-files --others --exclude-standard; } | sort -u
}

# Prints the lib/*.bats files that load the helper tests/foundation/helpers/<name>.<ext>: the ones
# holding the text helpers/<name> (that is how load and source spell it), and those holding the
# text of a helper that itself holds it, down the chain. Each helper is read once, so a cycle ends.
helper_loaders() {   # <repo-relative helper path>
  local name todo seen h hn
  name="${1##*/}"; name="${name%.*}"
  seen=" $name "; todo="$name"
  while [ -n "$todo" ]; do
    todo="${todo# }"
    name="${todo%% *}"; todo="${todo#"$name"}"; todo="${todo# }"
    [ -n "$name" ] || continue
    grep -lF -- "helpers/$name" "$lib"/*.bats 2>/dev/null || true
    for h in "$root"/tests/foundation/helpers/*; do
      [ -f "$h" ] && grep -qF -- "helpers/$name" "$h" || continue
      hn="${h##*/}"; hn="${hn%.*}"
      case "$seen" in *" $hn "*) continue ;; esac
      seen="$seen$hn "; todo="$todo $hn"
    done
  done | sort -u
}

# Prints the bats arguments for the given files, one per line, and why to stderr. A file is named
# by a test that holds its path as text, a file under skills/ by a test that names its skill
# (skill_tests); a changed lib/*.bats is its own pick, a foundation
# fixture picks the whole lib/ directory, and a helper picks the tests that load it
# (helper_loaders). The selection is sorted and has no repeats.
# Tests that read the spine-toolkit checkout are always in it.
touched_suites() {   # <file>...
  local f picked core_tests selected="" all=0
  for f in "$@"; do
    case "$f" in
      tests/foundation/fixtures/*)
        echo "touched: $f -> all of tests/foundation/lib" >&2; all=1; continue ;;
      tests/foundation/helpers/*)
        picked="$(helper_loaders "$f")"
        if [ -z "$picked" ]; then
          echo "touched: $f -> no test loads it" >&2
        else
          echo "touched: $f -> $(printf '%s\n' "$picked" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')" >&2
          selected="$selected"$'\n'"$picked"
        fi
        continue ;;
      tests/foundation/lib/*.bats)
        if [ -f "$root/$f" ]; then
          echo "touched: $f -> itself" >&2
          selected="$selected"$'\n'"$root/$f"
        else
          echo "touched: $f -> removed, nothing to run" >&2
        fi
        continue ;;
    esac
    case "$f" in
      skills/*) picked="$(skill_tests "$f")" ;;
      *) picked="$(grep -lF -- "$f" "$lib"/*.bats 2>/dev/null || true)" ;;
    esac
    if [ -z "$picked" ]; then
      echo "touched: $f -> no test names it" >&2
    else
      echo "touched: $f -> $(printf '%s\n' "$picked" | sed 's|.*/||' | tr '\n' ' ' | sed 's/ $//')" >&2
      selected="$selected"$'\n'"$picked"
    fi
  done
  if [ "$all" -eq 1 ]; then
    printf '%s\n' "$lib"
    return 0
  fi
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

# Prints the path of the stamp in the git common dir.
stamp_path() {
  local common
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s\n' "$common/spine-verified-trees"
}

# Appends <line> - a tree, or `<tree> via <base>` - to the stamp and keeps the last 20 lines. The
# new content is written beside the stamp and moved over it, so a reader never sees a half-written
# file.
record_green_tree() {   # <line>
  local entry="$1" stamp tmp
  stamp="$(stamp_path)" || return 1
  [ ! -d "$stamp" ] || return 1   # mv would put the new file inside it
  tmp="$(mktemp "$stamp.XXXXXX" 2>/dev/null)" || return 1
  { { [ ! -e "$stamp" ] || tail -n 19 "$stamp"; printf '%s\n' "$entry"; } >"$tmp" 2>/dev/null &&
      mv "$tmp" "$stamp" 2>/dev/null; } || { rm -f "$tmp"; return 1; }
}

# Prints the newest tree in the history of HEAD that is the first field of a stamp line: the tree
# a verified run takes its difference from. Exits 1 when there is none. awk reads the log to its
# end: stopping at the match would leave git log writing to a closed pipe, and its SIGPIPE would
# fail the pipeline under pipefail.
verified_base() {
  local stamp t
  stamp="$(stamp_path)" || return 1
  [ -f "$stamp" ] || return 1
  t="$(git -C "$root" log --format=%T HEAD 2>/dev/null |
    awk 'NR == FNR { seen[$1] = 1; next } !found && ($1 in seen) { print; found = 1 }' "$stamp" -)" || return 1
  [ -n "$t" ] || return 1
  printf '%s\n' "$t"
}

# Prints the files of the worktree that differ from <tree>, untracked ones included, in the form of
# diff_files.
verified_files() {   # <tree>
  { git -C "$root" -c core.quotePath=false diff --name-only --no-renames "$1"
    git -C "$root" -c core.quotePath=false ls-files --others --exclude-standard; } | sort -u
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
    files="$(diff_files "$root" "${TEST_BASE:-main}")" || exit 2
    list="$(printf '%s\n' "$files" | sed '/^$/d' | changed_suites changed beside)"
    [ -n "$list" ] || exit 0
    suites=()
    while IFS= read -r s; do suites+=("$s"); done <<< "$list"
    bats "${suites[@]}" ;;
  touched)
    shift
    if [ "$#" -eq 0 ]; then
      files=()
      while IFS= read -r f; do [ -z "$f" ] || files+=("$f"); done < <(head_files)
      if [ "${#files[@]}" -eq 0 ]; then
        echo "touched: nothing differs from HEAD" >&2
        exit 0
      fi
      set -- "${files[@]}"
    fi
    list="$(touched_suites "$@")"
    if [ -z "$list" ]; then
      echo "touched: no test names these files" >&2
      exit 0
    fi
    chosen=()
    while IFS= read -r s; do chosen+=("$s"); done <<< "$list"
    bats "${chosen[@]}" ;;
  verified)
    before="$(worktree_tree)" || {
      echo "verified: the script is not at the repository top level" >&2; exit 2; }
    base="$(verified_base)" || {
      echo "verified: no tree in the history of HEAD passed a full run; run all" >&2; exit 2; }
    files="$(verified_files "$base")"
    if [ -z "$files" ]; then
      echo "verified: nothing differs from the verified tree $base" >&2
      exit 0
    fi
    list="$(printf '%s\n' "$files" | changed_suites verified core-tests)"
    rc=0
    if [ -n "$list" ]; then
      chosen=()
      while IFS= read -r s; do chosen+=("$s"); done <<< "$list"
      bats "${chosen[@]}" || rc=$?
    fi
    after="$(worktree_tree || true)"
    if [ "$rc" -eq 0 ] && [ "$before" = "$after" ]; then
      record_green_tree "$before via $base" || echo "test-foundation: could not record the verified tree" >&2
    fi
    exit "$rc" ;;
  *)           echo "usage: $0 [unit|integration|all|changed|verified|touched [<file>...]]" >&2; exit 2 ;;
esac
