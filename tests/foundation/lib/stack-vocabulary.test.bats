#!/usr/bin/env bats
# Every value written into `## Stack` must be one the manifest's `## Axes` lists:
# spine-toolkit:stack-detect discards any other, and the axis is asked on every task.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  M="$ROOT/skills/manifest/SKILL.md"
  SETUP="$ROOT/skills/swift-setup/SKILL.md"
  INIT="$ROOT/agents/swift-init.md"
  PARSER="$ROOT/templates/workspace/lib/workspace-yml-parser.zsh"
  CHOICE="$ROOT/skills/architecture-choice/SKILL.md"
}

axis_values() {
  sed -n '/^## Axes$/,/^## Heuristics$/p' "$M" | grep -E "^$1[[:space:]]*=" \
    | sed 's/^[^=]*=//' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

in_axis() { axis_values "$1" | grep -qxF -- "$2"; }

table_rows() {
  awk -v h="$1" '$0 == h {f = 1; next} f && /^\|[-| ]+\|$/ {next} f && /^\|/ {print; next} f {exit}' "$2"
}

cell() { awk -F'|' -v n="$(( $1 + 1 ))" '{ gsub(/^[ \t]+|[ \t]+$/, "", $n); print $n }'; }

ticks() { tr -d '`'; }

@test "every import row pins a value its axis lists" {
  rows="$(sed -n '/^## Heuristics$/,/^## Topics$/p' "$M" | grep -E '^(import|token|file):.*→ [a-z]+=')"
  n="$(grep -c . <<<"$rows")"
  [ "$n" -ge 10 ] || { echo "found $n pinning rows; the scan went vacuous"; return 1; }
  grep -qF '→ architecture=TCA' <<<"$rows" || { echo "no row pins TCA"; return 1; }
  while IFS= read -r row; do
    pin="${row##*→ }"; axis="${pin%%=*}"; value="$(sed 's/[[:space:]]*$//' <<<"${pin#*=}")"
    in_axis "$axis" "$value" || { echo "pins $axis=$value, which ## Axes does not list"; return 1; }
  done <<<"$rows"
}

@test "swift-setup rewrites a retired value into one the catalog lists" {
  rows="$(table_rows '| Axis | Old value | Current value | Why |' "$SETUP")"
  [ -n "$rows" ] || { echo "no value table in swift-setup"; return 1; }
  while IFS= read -r row; do
    axis="$(cell 1 <<<"$row" | ticks)"; old="$(cell 2 <<<"$row" | ticks)"; new="$(cell 3 <<<"$row" | ticks)"
    ! in_axis "$axis" "$old" || { echo "$old is still a $axis value"; return 1; }
    in_axis "$axis" "$new" || { echo "$new is no $axis value"; return 1; }
  done <<<"$rows"
}

@test "a value rewrite is reported, in both locales" {
  grep -qF '`report_axis_value_renamed`' "$SETUP" || { echo "swift-setup never names the key"; return 1; }
  for l in en ru; do
    grep -qx '## report_axis_value_renamed' "$ROOT/skills/swift-setup/locales/$l.md" \
      || { echo "missing in $l.md"; return 1; }
  done
}
