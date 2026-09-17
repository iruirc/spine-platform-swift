#!/usr/bin/env bats
# A marker the templates carry but the script does not fill stays empty forever, and one the skill
# does not name is a section nobody knows the toolkit owns.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "the doc templates, the regen script and its skill name the same markers" {
  tmpl="$(grep -rhoE '<!-- WORKSPACE_[A-Z_]+_BEGIN -->' --include='*.md.tmpl' "$ROOT/templates/workspace" \
    | sed -E 's/<!-- WORKSPACE_(.*)_BEGIN -->/\1/' | LC_ALL=C sort -u)"
  script="$(grep -E '^ *add ' "$ROOT/scripts/workspace-docs-regen.zsh" | grep -oE '"[A-Z][A-Z_ ]*"' \
    | tr -d '"' | tr ' ' '\n' | grep . | LC_ALL=C sort -u)"
  skill="$(awk '/^## What it owns$/{f=1;next} /^## /{f=0} f' "$ROOT/skills/workspace-docs-regen/SKILL.md" \
    | grep -oE '`[A-Z][A-Z_]+`' | tr -d '`' | LC_ALL=C sort -u)"
  [ "$(printf '%s\n' "$tmpl" | wc -l | tr -d ' ')" -ge 10 ] || { echo "templates: $tmpl"; echo "the scan went vacuous"; return 1; }
  [ "$tmpl" = "$script" ] || { printf 'templates:\n%s\nscript:\n%s\n' "$tmpl" "$script"; return 1; }
  [ "$tmpl" = "$skill" ] || { printf 'templates:\n%s\nskill:\n%s\n' "$tmpl" "$skill"; return 1; }
}
