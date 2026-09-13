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

@test "every stack value swift-init spells a flag into is in the catalog" {
  n=0
  while IFS= read -r row; do
    axis="$(cell 2 <<<"$row" | ticks)"; value="$(cell 3 <<<"$row" | ticks)"
    [ "$value" = "—" ] && continue
    in_axis "$axis" "$value" || { echo "$(cell 1 <<<"$row") → $axis=$value, which ## Axes does not list"; return 1; }
    n=$((n + 1))
  done < <(table_rows '| Flag | Axis | `## Stack` value |' "$INIT")
  [ "$n" -ge 15 ] || { echo "checked $n rows; the table went missing"; return 1; }
}

@test "swift-init, its flag table and workspace.yml accept the same architecture flags" {
  list="$(grep -oE '\[--architecture=[a-z|-]+\]' "$INIT" | tr -d '[]' | sed 's/^--architecture=//' | tr '|' '\n' | sort)"
  table="$(table_rows '| Flag | Axis | `## Stack` value |' "$INIT" | grep -oE '`--architecture=[a-z-]+`' \
    | tr -d '`' | sed 's/^--architecture=//' | sort)"
  yml="$(grep -F -A2 'stack.architecture" 2>/dev/null' "$PARSER" | grep -oE '\^\([a-z|-]+\)\$' | tr -d '^()$' | tr '|' '\n' | sort)"
  [ -n "$list" ] || { echo "no --architecture entry in the flag list"; return 1; }
  [ "$list" = "$table" ] || { printf 'flag list:\n%s\ntable:\n%s\n' "$list" "$table"; return 1; }
  [ "$list" = "$yml" ] || { printf 'flag list:\n%s\nworkspace.yml rule:\n%s\n' "$list" "$yml"; return 1; }
}

@test "swift-init takes the architecture options from the catalog" {
  grep -qF 'the options are the values `## Axes` lists for `architecture`' "$INIT"
}

@test "swift-init writes no retired architecture value" {
  grep -qF '| Flag | Axis | `## Stack` value |' "$INIT" || { echo "the scan did not reach swift-init"; return 1; }
  ! grep -qF 'MVVM+Coordinator' "$INIT"
}

@test "every line architecture-choice writes into ## Stack is a catalog value" {
  n=0
  while IFS= read -r row; do
    arch="$(cell 2 <<<"$row" | ticks)"; ui="$(cell 3 <<<"$row")"
    in_axis architecture "$arch" || { echo "$(cell 1 <<<"$row") writes Architecture: $arch"; return 1; }
    [ "$ui" = "from the answer" ] || in_axis ui "$(ticks <<<"$ui")" || { echo "$(cell 1 <<<"$row") writes UI: $ui"; return 1; }
    n=$((n + 1))
  done < <(table_rows '| Stack | `- Architecture:` | `- UI:` |' "$CHOICE")
  [ "$n" -ge 8 ] || { echo "checked $n stacks; the table went missing"; return 1; }
}

@test "architecture-choice writes no comment, objection or core artifact into the config" {
  grep -qF '| Stack | `- Architecture:` | `- UI:` |' "$CHOICE" || { echo "the scan did not reach architecture-choice"; return 1; }
  for gone in '<!-- Chosen' '`Objection:' 'Done.md'; do
    ! grep -qF -- "$gone" "$CHOICE" || { echo "still there: $gone"; return 1; }
  done
}

@test "architecture-choice asks @Observable of iOS 17, not 16" {
  grep -qF 'SwiftUI iOS 17+ | **MVVM + Router**' "$CHOICE"
}
