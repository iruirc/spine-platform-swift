#!/usr/bin/env bats
# A platform plugin ships alone: the only thing it may name across the plugin
# boundary is a namespaced skill or agent (`spine-toolkit:setup`). A bare
# relative path resolves under THIS plugin's root, so one that belongs to core
# finds nothing — and carries no `core/` prefix for the cross-plugin grep to
# catch. That is the class this file guards.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every bare relative path swift-platform names resolves under its own root" {
  missing=""
  for p in $(grep -rhoE '`[A-Za-z_][A-Za-z0-9_.-]*/[^` ]*`' "$ROOT" \
               --include='*.md' --include='*.sh' --include='*.js' \
             | tr -d '`' | sort -u); do
    case "$p" in
      skills/*|agents/*|commands/*|conventions/*|templates/*|hooks/*|scripts/*|tests/*|workflows/*) ;;
      *) continue ;;
    esac
    # bash 3.2's `compgen -G` succeeds on any pattern ending in `/`, existing or not,
    # so the trailing slash has to go before the glob is what decides.
    q="$(printf '%s' "$p" | sed 's/<[^>]*>/*/g')"
    compgen -G "$ROOT/${q%/}" >/dev/null \
      || missing="$missing $p"
  done
  [ -z "$missing" ] || { echo "path(s) that do not resolve under swift-platform:$missing"; return 1; }
}

@test "no file names the pre-split project config" {
  # Migrating a pre-split config is core's job; nothing here may still read one.
  offenders="$(grep -rl 'CLAUDE-swift-toolkit' "$ROOT" \
    | grep -vF 'self-containment.test.bats' || true)"
  [ -z "$offenders" ] || { echo "$offenders"; return 1; }
}

@test "every project config this plugin writes names its platform" {
  # workspace-init renders a config of its own, so it bypasses spine-toolkit:setup
  # and every guard core puts on the template. Without ## Platform the file still
  # passes the orchestrator's Routing check 4 — the config exists — and dies at
  # step 5.7 with nothing to resolve roles through.
  # Discovery keys on ## Stack / ## Mode, not ## Language: a config written by code
  # (the workspace project-init driver) omits ## Language because core sets it, so
  # anchoring on that heading silently skipped the very file this guard exists for.
  found=0; missing=""
  while IFS= read -r f; do
    found=$((found + 1))
    grep -q '^## Platform$' "$f" || missing="$missing $f"
  done < <(grep -rlE '^## (Stack|Mode)$' "$ROOT/templates" "$ROOT/tests/foundation/helpers")
  [ "$found" -ge 2 ] || { echo "discovery matched $found file(s); the scan went vacuous"; return 1; }
  [ -z "$missing" ] || { echo "config template(s) with no ## Platform block:$missing"; return 1; }
}
