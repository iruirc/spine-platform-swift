#!/usr/bin/env bats
# "Cluster 2" and "P-rule" name stages of this plugin's own planning, which its reader never saw.
# templates/ zsh libraries are excluded outright: they keep their P-rule comments, which address
# the validator's editor, and the exclusion also lets any "Cluster <n>" in those files go unchecked.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "no planning vocabulary reaches a skill, agent, command, template or the README" {
  n="$(ls "$ROOT"/skills/*/SKILL.md | wc -l | tr -d ' ')"
  [ "$n" -ge 25 ] || { echo "found $n SKILL.md files; the scan went vacuous"; return 1; }
  hits="$(cd "$ROOT" && grep -rnE --exclude='*.zsh' 'Cluster [0-9]|P-rule' \
    skills agents commands templates README.md || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}
