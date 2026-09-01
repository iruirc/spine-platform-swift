#!/usr/bin/env bats
# A platform plugin ships alone: the only thing it may name across the plugin
# boundary is a namespaced skill or agent (`spine-toolkit:setup`). A bare
# relative path resolves under THIS plugin's root, so one that belongs to core
# finds nothing — and carries no prefix for the cross-plugin grep to catch. That
# is the class this file guards, in both directions: a path that names the core
# tree outright, and one that quietly does not resolve here.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every bare relative path swift-platform names resolves under its own root" {
  missing=""
  for p in $(grep -rhoE '`[A-Za-z_][A-Za-z0-9_.-]*/[^` ]*`' "$ROOT" \
               --include='*.md' --include='*.sh' --include='*.js' \
               --include='*.bats' --include='*.zsh' \
               --exclude-dir=.git \
             | tr -d '`' | sort -u); do
    case "$p" in
      skills/*|agents/*|commands/*|conventions/*|templates/*|hooks/*|scripts/*|tests/*|workflows/*) ;;
      # A monorepo-root prefix is a path this plugin does not have: it resolves
      # nowhere once the platform is a repo of its own, and nowhere here either.
      platform/*) ;;
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
  offenders="$(grep -rl --exclude-dir=.git 'CLAUDE-swift-toolkit' "$ROOT" \
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

@test "no file in swift-platform names the core tree by a filesystem path" {
  # The mirror of core's guard: `../core` has no trailing slash and slips past a
  # `core/` grep, and every such path dangles the moment this plugin is extracted.
  # Both namings are wrong to write: the pre-split directory, and the published
  # repo name that the first pattern's `[^A-Za-z0-9_.-]` class swallows. This
  # plugin's own repo name is a monorepo-root prefix and equally wrong, but a
  # leading slash is spared so installed-plugin cache paths stay legal.
  pat='(\.\./(core|spine-toolkit|swift-platform)([^A-Za-z0-9_-]|$)'
  pat="$pat"'|(^|[^A-Za-z0-9_.-])core/'
  pat="$pat"'|(^|[^A-Za-z0-9_./-])(spine-toolkit|swift-platform)/)'
  hits="$(grep -rnE --exclude-dir=.git "$pat" "$ROOT" || true)"
  offenders="$(grep -vF 'self-containment.test.bats' <<<"$hits" || true)"
  [ -z "$offenders" ] || { echo "swift-platform reference(s) to the core tree:"; echo "$offenders"; return 1; }
  # The self-exclusion is otherwise unbounded — a violation added to this file
  # would be invisible. Pin the count: a change here must be re-read.
  n="$(grep -cF 'self-containment.test.bats' <<<"$hits" || true)"
  [ "$n" -eq 3 ] || { echo "self-excluded lines in this file: $n, expected 3"; return 1; }
}

@test "the shipped workspace config template declares every block core reads" {
  # workspace-init renders this instead of going through spine-toolkit:setup, so
  # core's own template guard never sees it. Same block list, checked here.
  tpl="$ROOT/templates/workspace/meta-repo/CLAUDE-spine-toolkit.md.tmpl"
  [ -f "$tpl" ] || { echo "no workspace config template at $tpl"; return 1; }
  for block in Language Platform Agents Stack Mode Progress Modules EstimationDeltas; do
    grep -q "^## $block\$" "$tpl" || { echo "missing block: ## $block"; return 1; }
  done
}
