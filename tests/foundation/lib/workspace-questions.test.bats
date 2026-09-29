#!/usr/bin/env bats
# Every question the workspace skills ask comes from a locale key, so a Russian workspace is not
# asked in English and the agent does not word the question itself.

setup() { ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"; }

# Usage: keys_asked <skill> <key>... — the skill names each key and both locales define it.
keys_asked() {
  local skill="$1"; shift
  local k l bad=""
  for k in "$@"; do
    grep -qF "\`$k\`" "$ROOT/skills/$skill/SKILL.md" || bad="$bad $skill/SKILL.md:$k"
    for l in en ru; do
      grep -qx "## $k" "$ROOT/skills/$skill/locales/$l.md" || bad="$bad $skill/$l.md:$k"
    done
  done
  [ -z "$bad" ] || { echo "missing:$bad"; return 1; }
}

@test "workspace-add asks every package question by key" {
  keys_asked workspace-add qa_pkg_git_url qa_pkg_version qa_pkg_deps \
    qa_pkg_external_dep qa_pkg_external_dep_url qa_pkg_external_dep_version
}

@test "workspace-init asks the git URL and external deps by key" {
  keys_asked workspace-init qa_pkg_git_url \
    qa_pkg_external_dep qa_pkg_external_dep_url qa_pkg_external_dep_version
}

@test "no English question hard-codes the article before an archetype" {
  run grep -nE '\ba \{archetype\}' "$ROOT"/skills/workspace-*/locales/en.md
  [ "$status" -eq 1 ]
}
