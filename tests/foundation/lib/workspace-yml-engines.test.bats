#!/usr/bin/env bats
# wsyml::get evaluates its yq expressions with jq where jq is installed and with yq where it is not;
# both must print the same. fixtures/wsyml-engines/calls.tsv holds real calls — up to three for each
# expression shape the full suite makes, on the fixture it made them on.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  local v
  v="$(jq --version 2>/dev/null)" || skip "jq not on PATH: only the yq engine can run"
  v="${v#jq-}"; v="${v%%[!0-9.]*}"
  [ "$(printf '%s\n' 1.7 "$v" | sort -V | head -1)" = 1.7 ] || skip "jq $v is older than 1.7: only the yq engine runs"
  CALLS="$(ws_fixture_path wsyml-engines/calls.tsv)"
}

# Prints, for each call, its line number and what wsyml::get printed, newlines escaped.
evaluate() {   # <engine>
  WSYML_ENGINE="$1" zsh -c '
    source "$1"; fixtures="$2"; loaded=""; n=0
    while IFS=$'"'"'\t'"'"' read -r fx expr; do
      n=$((n + 1))
      if [[ "$fx" != "$loaded" ]]; then wsyml::load "$fixtures/$fx" || exit 9; loaded="$fx"; fi
      [[ "$n" -eq 1 ]] && print -r -- "engine ${_WSYML_STATE[engine]}"
      out="$(wsyml::get "$expr" 2>/dev/null)" || out="<none>"
      print -r -- "$n ${out//$'"'"'\n'"'"'/\\n}"
    done < "$3"' _ "$(ws_lib_path workspace-yml-parser.zsh)" "$(ws_fixture_path workspace-yml)" \
      "$CALLS"
}

@test "jq and yq print the same for every recorded call, except a number's spelling" {
  [ "$(wc -l < "$CALLS")" -ge 190 ] || { echo "calls.tsv shrank: the comparison went thin"; return 1; }
  jq_out="$(evaluate jq)"; yq_out="$(evaluate yq)"
  [ "$(head -1 <<<"$jq_out")" = "engine jq" ] || { echo "jq engine not chosen: $(head -1 <<<"$jq_out")"; return 1; }
  [ "$(head -1 <<<"$yq_out")" = "engine yq" ] || { echo "yq engine not chosen: $(head -1 <<<"$yq_out")"; return 1; }
  d="$(diff <(tail -n +2 <<<"$yq_out") <(tail -n +2 <<<"$jq_out") | grep '^[<>]' || true)"
  # yq reads `version: 1.0` back from JSON as the integer 1; jq 1.7 keeps it as written, so the
  # validation message quotes what the user wrote and `tag` calls it the float YAML says it is.
  # Both callers treat !!int and !!float alike.
  v="$(grep -n 'bad-external-dep-version.yml.*external_deps\[0\]\.version$' "$CALLS" | cut -d: -f1)"
  t="$(grep -n 'bad-external-dep-version.yml.*external_deps\[0\]\.version | tag$' "$CALLS" | cut -d: -f1)"
  [ -n "$v" ] && [ -n "$t" ] || { echo "calls.tsv lost the 1.0 calls"; return 1; }
  [ "$d" = "$(printf '< %s 1\n< %s !!int\n> %s 1.0\n> %s !!float' "$v" "$t" "$v" "$t")" ] || {
    echo "engines differ:"; echo "$d"; return 1; }
}

@test "tag tells an int from a float, and keys keep document order" {
  run zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'
    f=\$(mktemp); print -r -- 'a: 1
b: 1.0
c: 1e3
m: { z: 1, a: 2 }' > \$f
    wsyml::load \$f || exit 9
    for e in '.a | tag' '.b | tag' '.c | tag' '.m | keys | .[]'; do wsyml::get \"\$e\"; done; rm -f \$f"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '!!int\n!!float\n!!float\nz\na')" ] || { echo "$output"; return 1; }
}
