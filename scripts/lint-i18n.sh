#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/lint-i18n.sh sha256:ecf307978ed83c9232b0d6ace36a73ad1437dc82117c026c06b9a317de2248b9
# Vendored copy of spine-toolkit's lint. Plugins share no code; update both or neither.
set -euo pipefail

# Paths below are repo-relative: anchor the cwd so a run from elsewhere
# cannot scan the wrong tree and report a pass.
cd "$(dirname "$0")/.."

# Allowed cyrillic locations:
#   skills/*/locales/ru.md           (Russian locale strings; en.md is checked)
#   conventions/i18n.md              (canonical multilingual examples)
#   any *.ru.md anywhere             (Russian-only mirrors)
#   skills/<name>/SKILL.md           (only inside frontmatter description: bilingual triggers)
#   agents/<name>.md                 (only inside frontmatter description: bilingual triggers)
#   commands/<name>.md               (only inside frontmatter description: bilingual one-line)
#
# Anything else with cyrillic chars is a violation. Scanned file types: md, json,
# yml, yaml, js, sh, bats, zsh — an extensionless file is out of scope, since the
# reader here would have to guess whether it is text.

violations=0
while IFS= read -r -d '' f; do
  case "$f" in
    *.ru.md) continue ;;
    ./skills/*/locales/ru.md) continue ;;
    ./conventions/i18n.md) continue ;;
    ./.git/*) continue ;;
    # Defines the cyrillic range it searches for, so it matches itself.
    ./scripts/lint-i18n.sh) continue ;;
  esac

  # For SKILL.md / agents/*.md / commands/*.md, allow cyrillic ONLY inside the
  # frontmatter description block (between the first two --- lines).
  case "$f" in
    ./skills/*/SKILL.md|./agents/*.md|./commands/*.md)
      python3 - "$f" <<'PY' || violations=$((violations + 1))
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
lines = text.split('\n')
fence_count = 0
for i, line in enumerate(lines, 1):
    if line.strip() == '---':
        fence_count += 1
        continue
    if fence_count >= 2 and any('А' <= c <= 'я' or c in 'ёЁ' for c in line):
        print(f'{path}:{i}: cyrillic outside frontmatter: {line.rstrip()}')
        sys.exit(1)
# Under two fences the loop above never enters its body, so a broken frontmatter
# silently exempts the whole file from the check it is the exception to.
if fence_count < 2:
    print(f'{path}:1: malformed frontmatter ({fence_count} `---` fence(s)) — cyrillic here cannot be checked')
    sys.exit(1)
PY
      ;;
    *)
      python3 - "$f" <<'PY' || violations=$((violations + 1))
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
for i, line in enumerate(text.split('\n'), 1):
    if any('А' <= c <= 'я' or c in 'ёЁ' for c in line):
        print(f'{path}:{i}: cyrillic in non-localized file: {line.rstrip()}')
        sys.exit(1)
PY
      ;;
  esac
done < <(find . -type f \( -name '*.md' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' \
  -o -name '*.js' -o -name '*.sh' -o -name '*.bats' -o -name '*.zsh' \) -print0)

if [ "$violations" -gt 0 ]; then
  echo
  echo "i18n lint failed: $violations file(s) with disallowed cyrillic"
  exit 1
fi

echo "i18n lint passed: no disallowed cyrillic"
