#!/usr/bin/env bats
# Codex and Claude Code share the same skills and release identity. These tests keep the two host
# manifests aligned and reject a host-only runtime path in shared skill instructions.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  CLAUDE_MANIFEST="$ROOT/.claude-plugin/plugin.json"
  CODEX_MANIFEST="$ROOT/.codex-plugin/plugin.json"
}

@test "the Codex plugin manifest has the required native shape" {
  run python3 - "$CODEX_MANIFEST" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1]))
required = ["name", "version", "description", "author", "skills", "interface"]
missing = [key for key in required if key not in manifest]
assert not missing, f"missing fields: {', '.join(missing)}"
assert manifest["skills"] == "./skills/"
assert manifest["author"].get("name")
interface = manifest["interface"]
for key in ("displayName", "shortDescription", "longDescription", "developerName", "category", "capabilities"):
    assert interface.get(key), f"missing interface.{key}"
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the Claude and Codex manifests publish the same identity and version" {
  run python3 - "$CLAUDE_MANIFEST" "$CODEX_MANIFEST" <<'PY'
import json
import sys

claude = json.load(open(sys.argv[1]))
codex = json.load(open(sys.argv[2]))
for path in (("name",), ("version",), ("repository",), ("author", "name")):
    left, right = claude, codex
    for key in path:
        left, right = left[key], right[key]
    assert left == right, f"{'.'.join(path)} differs: {left!r} != {right!r}"
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "shared skills do not depend on Claude-only plugin-root environment" {
  run grep -R -n -F 'CLAUDE_PLUGIN_ROOT' "$ROOT/skills"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "Codex UI metadata exists for every user-facing skill" {
  missing=""
  count=0
  for skill in "$ROOT"/skills/*; do
    [ -d "$skill" ] || continue
    [ "$(basename "$skill")" = manifest ] && continue
    count=$((count + 1))
    [ -f "$skill/agents/openai.yaml" ] || missing="$missing $(basename "$skill")"
  done
  [ "$count" -ge 25 ] || { echo "scan went vacuous: $count user-facing skills"; return 1; }
  [ -z "$missing" ] || { echo "skills missing agents/openai.yaml:$missing"; return 1; }
}

@test "skills only spine-toolkit or Claude Code can drive require explicit Codex invocation" {
  # spine-toolkit ships no Codex manifest, and workspace-init also calls the Claude-only swift-init.
  for skill in manifest swift-setup workspace-init; do
    grep -qx '  allow_implicit_invocation: false' "$ROOT/skills/$skill/agents/openai.yaml" \
      || { echo "$skill: no policy.allow_implicit_invocation: false"; return 1; }
    ! grep -q '^[[:space:]]*default_prompt:' "$ROOT/skills/$skill/agents/openai.yaml" \
      || { echo "$skill: unsupported Codex workflow still advertises a default_prompt"; return 1; }
  done
}

@test "workspace skills load their zsh libraries before using ws namespaces" {
  init="$ROOT/skills/workspace-init/SKILL.md"
  add="$ROOT/skills/workspace-add/SKILL.md"

  for lib in workspace-yml-parser workspace-graph workspace-package workspace-project; do
    grep -qF "source \"<platform-root>/templates/workspace/lib/$lib.zsh\"" "$init" \
      || { echo "workspace-init: $lib is not sourced"; return 1; }
  done
  for lib in workspace-yml-parser workspace-graph workspace-package; do
    grep -qF "source \"<platform-root>/templates/workspace/lib/$lib.zsh\"" "$add" \
      || { echo "workspace-add: $lib is not sourced"; return 1; }
  done
  grep -qF 'wsyml::load "<resolved-workspace.yml>"' "$add" \
    || { echo "workspace-add: workspace.yml is not loaded"; return 1; }
  grep -qF 'wsyml::load "<workspace.yml>"' "$init" \
    || { echo "workspace-init: workspace.yml is not loaded"; return 1; }
}

@test "workspace-add loads workspace.yml again before validating its own edit" {
  # wsyml::validate reads the copy wsyml::load took; a copy taken before the edit checks the old file.
  checks="$(grep -E '^[0-9]+\. .*wsyml::validate' "$ROOT/skills/workspace-add/SKILL.md")"
  [ "$(printf '%s\n' "$checks" | grep -c .)" -ge 2 ] || { echo "scan went vacuous:"; echo "$checks"; return 1; }
  stale="$(printf '%s\n' "$checks" | grep -v 'wsyml::load' || true)"
  [ -z "$stale" ] || { echo "validates without loading the edit:"; echo "$stale"; return 1; }
}
