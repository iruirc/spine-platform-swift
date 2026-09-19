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

@test "every bare relative path spine-platform-swift names resolves under its own root" {
  missing=""
  for p in $(grep -rhoE '`[A-Za-z_][A-Za-z0-9_.-]*/[^` ]*`' "$ROOT" \
               --include='*.md' --include='*.sh' --include='*.js' \
               --include='*.bats' --include='*.zsh' \
               --exclude-dir=.git --exclude-dir=.superpowers \
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
  [ -z "$missing" ] || { echo "path(s) that do not resolve under spine-platform-swift:$missing"; return 1; }
}

@test "no file names the pre-split project config" {
  # Migrating a pre-split config is core's job; nothing here may still read one.
  offenders="$(grep -rl --exclude-dir=.git --exclude-dir=.superpowers 'CLAUDE-swift-toolkit' "$ROOT" \
    | grep -vF 'self-containment.test.bats' || true)"
  [ -z "$offenders" ] || { echo "$offenders"; return 1; }
}

@test "every project config this plugin writes names its platform" {
  # spine-toolkit:setup writes every real config; a driver stub without ## Platform
  # lets a test pass on a config the orchestrator cannot route. Discovery keys on
  # ## Stack / ## Task defaults: the meta-repo stub has no stack to declare.
  found=0; missing=""
  while IFS= read -r f; do
    found=$((found + 1))
    grep -q '^## Platform$' "$f" || missing="$missing $f"
  done < <(grep -rlE '^## (Stack|Task defaults)$' "$ROOT/templates" "$ROOT/tests/foundation/helpers")
  [ "$found" -ge 2 ] || { echo "discovery matched $found file(s); the scan went vacuous"; return 1; }
  [ -z "$missing" ] || { echo "config template(s) with no ## Platform block:$missing"; return 1; }
}

@test "no file in spine-platform-swift names the core tree by a filesystem path" {
  # The mirror of core's guard: `../core` has no trailing slash and slips past a
  # `core/` grep, and every such path dangles the moment this plugin is extracted.
  # Both namings are wrong to write: the pre-split directory, and the published
  # repo name that the first pattern's `[^A-Za-z0-9_.-]` class swallows. This
  # plugin's own repo name is a monorepo-root prefix and equally wrong; the
  # installed-plugin cache paths a skill may document are excluded by that
  # prefix rather than by sparing a leading dot or slash — which spared every
  # absolute and dot-relative sibling path too.
  pat='(\.\./(core|spine-toolkit|spine-platform-swift)([^A-Za-z0-9_-]|$)'
  # `$` joins the excluded chars: a `$core/`-style dereference names no path.
  pat="$pat"'|(^|[^A-Za-z0-9_.$-])core/'
  pat="$pat"'|(^|[^A-Za-z0-9_-])(spine-toolkit|spine-platform-swift)/)'
  # .superpowers/ is gitignored scratch that never ships, and a review diff there
  # quotes the very files this scan excludes by name. Core excludes it from its
  # own i18n lint for the same reason.
  hits="$(grep -rnE --exclude-dir=.git --exclude-dir=.superpowers "$pat" "$ROOT" \
            | grep -vE '/\.claude/plugins/(cache|marketplaces)/' || true)"
  # The two suites that look for a sibling checkout of core are the other deliberate
  # exceptions: each skips rather than dangles when the checkout is absent.
  offenders="$(grep -vF -e 'self-containment.test.bats' -e 'core-refs.test.bats' -e 'forks.test.bats' <<<"$hits" || true)"
  [ -z "$offenders" ] || { echo "spine-platform-swift reference(s) to the core tree:"; echo "$offenders"; return 1; }
  # The self-exclusion is otherwise unbounded — a violation added to this file
  # would be invisible. Pin the count: a change here must be re-read.
  n="$(grep -cF 'self-containment.test.bats' <<<"$hits" || true)"
  [ "$n" -eq 3 ] || { echo "self-excluded lines in this file: $n, expected 3"; return 1; }
  n2="$(grep -cF 'core-refs.test.bats' <<<"$hits" || true)"
  [ "$n2" -eq 1 ] || { echo "excluded lines for core-refs.test.bats: $n2, expected 1"; return 1; }
  n3="$(grep -cF 'forks.test.bats' <<<"$hits" || true)"
  [ "$n3" -eq 1 ] || { echo "excluded lines for forks.test.bats: $n3, expected 1"; return 1; }
}

@test "no template ships a copy of core's config" {
  # spine-toolkit:setup writes the config; a copy here drifts from core's template
  # unseen. Three blocks only that config has are enough to spot one.
  [ "$(find "$ROOT/templates" -type f | wc -l)" -gt 10 ] || { echo "templates/ scan went vacuous"; return 1; }
  offenders="$(grep -rlE '^## (Platform|Agents|Orchestration)$' "$ROOT/templates" || true)"
  [ -z "$offenders" ] || { echo "core config block(s) in: $offenders"; return 1; }
  # The driver stubs legitimately carry ## Platform; no file in the plugin carries these two.
  offenders="$(grep -rlE --exclude-dir=.git --exclude-dir=.superpowers '^## (Agents|Orchestration)$' "$ROOT" || true)"
  [ -z "$offenders" ] || { echo "core config block(s) in: $offenders"; return 1; }
}
