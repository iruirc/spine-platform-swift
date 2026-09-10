#!/usr/bin/env bats
# The platform half of core's driver contract: what this manifest declares to a
# driver, and the guarantee that no file here decides for the project which MCP
# server drives its app.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  M="$ROOT/skills/manifest/SKILL.md"
}

@test "the manifest declares a Driver block with both rows" {
  block="$(sed -n '/^## Driver$/,/^## /p' "$M")"
  grep -qE '^default[[:space:]]*=[[:space:]]*mobile-driver$' <<<"$block"
  grep -qE '^surfaces[[:space:]]*=' <<<"$block"
}

@test "the declared surfaces are exactly the three Apple projects run on" {
  # The vendored lint rejects a name outside core's eight; this pins which three
  # of the eight we mean, so a silent narrowing to two still fails here.
  block="$(sed -n '/^## Driver$/,/^## /p' "$M")"
  got="$(sed -n 's/^surfaces[[:space:]]*=[[:space:]]*//p' <<<"$block" | tr -d '[:space:]')"
  [ "$got" = "ios-simulator,ios-device,macos" ] || { echo "surfaces: $got"; return 1; }
}

@test "the declared core floor is the one that reads a Driver block" {
  # `surfaces` is read by core from 1.7.1. A floor below it loads and is then
  # misread: core looks for a row this manifest means and never finds it.
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["dependencies"]; print([x["version"] for x in d if x["name"]=="spine-toolkit"][0])' "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = ">=1.7.1 <2" ] || { echo "floor: $output"; return 1; }
}

@test "the vendored manifest lint is the copy that knows the Driver block" {
  # A pre-1.7.0 copy passes this manifest by never parsing the block at all — a
  # green run that checked nothing, which is worse than a red one.
  grep -q '^SURFACES=' "$ROOT/scripts/lint-manifest.sh"
}

@test "the vendored lint rejects a surface outside core's vocabulary" {
  # The negative control for the test above: proves the copy not only carries the
  # list but reaches it. Without this the guard is a grep for a variable name.
  tmp="$BATS_TEST_TMPDIR/plugin"
  mkdir -p "$tmp"
  cp -R "$ROOT/.claude-plugin" "$ROOT/agents" "$ROOT/skills" "$tmp/"
  sed 's/^surfaces[[:space:]]*=.*$/surfaces = ios-simulator, iphone, macos/' "$M" \
    > "$tmp/skills/manifest/SKILL.md"
  run "$ROOT/scripts/lint-manifest.sh" "$tmp"
  [ "$status" -eq 1 ] || { echo "expected exit 1, got $status: $output"; return 1; }
  grep -q "surface outside core's vocabulary: iphone" <<<"$output" || { echo "$output"; return 1; }
}

@test "the validator glosses all four driver states" {
  V="$ROOT/agents/swift-validator.md"
  bad=""
  for s in ok none unavailable incompatible; do
    grep -qF "\`$s\`" "$V" || bad="$bad $s"
  done
  [ -z "$bad" ] || { echo "states not glossed:$bad"; return 1; }
}

@test "the return contract carries driver_status with core's four values" {
  # core's profile scripts declare driver_status with exactly this enum under
  # additionalProperties:false, so a fifth value is a field the orchestrator drops.
  grep -qF 'driver_status: ok | none | unavailable | incompatible' \
    "$ROOT/agents/swift-validator.md"
}

@test "the validator names capabilities from core's vocabulary and no call names" {
  # The contract this replaces was a table of six call names, every one of which
  # had stopped existing at a server release with nothing noticing.
  V="$ROOT/agents/swift-validator.md"
  bad=""
  for c in launch stop ui_tree find assert screenshot tap type swipe reset_state; do
    grep -qF "\`$c\`" "$V" || bad="$bad $c"
  done
  [ -z "$bad" ] || { echo "capabilities not named:$bad"; return 1; }
}

@test "no retired call name survives in the validator" {
  # This contract replaced a table of six call names, every one of which had
  # stopped existing at a server release with nothing noticing.
  V="$ROOT/agents/swift-validator.md"
  grep -qF 'driver_status' "$V" || { echo "not the validator, or it lost driver_status"; return 1; }
  bad=""
  for c in app_launch app_stop input_tap input_text input_swipe ui_assert_visible ui_assert_gone screen_capture; do
    grep -qF "$c" "$V" && bad="$bad $c"
  done
  [ -z "$bad" ] || { echo "retired call names present:$bad"; return 1; }
}
