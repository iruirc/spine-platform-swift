#!/usr/bin/env bats
# README.md restates two facts other files own — the core range in plugin.json and the manifest's
# tables — and nothing moves the copy when the owner changes.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "the README quotes the core range plugin.json declares" {
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["dependencies"]; print([x["version"] for x in d if x["name"]=="spine-toolkit"][0])' "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qF -- "- \`spine-toolkit\` \`$output\`" "$ROOT/README.md" || { echo "README does not quote $output"; return 1; }
}

@test "the README's manifest table names every table the manifest declares" {
  declared="$(grep -E '^## ' "$ROOT/skills/manifest/SKILL.md" | LC_ALL=C sort)"
  listed="$(grep -oE '^\| `## [A-Za-z]+`' "$ROOT/README.md" | sed 's/^| `//; s/`$//' | LC_ALL=C sort)"
  [ "$declared" = "$listed" ] || { printf 'manifest:\n%s\nREADME:\n%s\n' "$declared" "$listed"; return 1; }
}
