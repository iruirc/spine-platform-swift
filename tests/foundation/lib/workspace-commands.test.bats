#!/usr/bin/env bats
# Templates render into the user's repositories, where an agent reads a named command as one it can run.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every workspace command the plugin's text names is a command it ships" {
  n="$(ls "$ROOT"/commands/workspace-*.md | wc -l | tr -d ' ')"
  [ "$n" -ge 3 ] || { echo "found $n workspace commands; the scan went vacuous"; return 1; }
  named="$(cd "$ROOT" && grep -rhoE '`workspace-[a-z-]+\\?[` ]' templates skills agents commands README.md \
    | sed -E 's/^`(workspace-[a-z-]+).*/\1/' | LC_ALL=C sort -u)"
  [ -n "$named" ] || { echo "no workspace command named anywhere; the scan went vacuous"; return 1; }
  missing=""
  while IFS= read -r c; do
    [ -f "$ROOT/commands/$c.md" ] || missing="$missing $c"
  done <<<"$named"
  [ -z "$missing" ] || { echo "named but not shipped:$missing"; return 1; }
}

@test "both s06b branches hand the tests axis to swift-init, each with its own precedence" {
  local s="$(ws_repo_root)/skills/workspace-init/SKILL.md"
  # The precedence itself is now pinned by Task 6's wsproj::swift_init_flags tests; this only
  # checks the row still names both calls.
  local row; row="$(grep -E '^\| s06b_project_<app> \|' "$s")"
  grep -qF -- 'wsproj::swift_init_flags <key> interactive <root>' <<<"$row" \
    || { echo "the row does not name the interactive call"; return 1; }
  grep -qF -- 'wsproj::swift_init_flags <key> batch <root>' <<<"$row" \
    || { echo "the row does not name the batch call"; return 1; }
}

@test "the qa_defaults_tests locale strings enumerate exactly the accepted tests tokens" {
  local locales="$(ws_repo_root)/skills/workspace-init/locales"
  local canonical
  canonical="$(zsh -c "source '$(ws_lib_path workspace-yml-parser.zsh)'; print -l \$WSYML_TESTS_KINDS" | sort -u)"
  # Both sides empty compares equal, so a guard without this passes once the array or the locale
  # block disappears — two guards on this branch were already caught passing that way.
  [ -n "$canonical" ] || { echo "WSYML_TESTS_KINDS is empty; the scan went vacuous"; return 1; }
  local l tokens
  for l in en ru; do
    tokens="$(awk '/^## qa_defaults_tests$/ {on = 1; next} on && /^## / {exit} on' "$locales/$l.md" \
      | grep -oE '\[[^]]*\]' | tr -d '[]' | tr '|' '\n' | sed -E 's/\([^)]*\)//g' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)"
    [ -n "$tokens" ] || { echo "$l.md: no qa_defaults_tests token list; the scan went vacuous"; return 1; }
    [ "$tokens" = "$canonical" ] || {
      echo "$l.md disagrees with the accepted tests tokens:"
      diff <(printf '%s\n' "$tokens") <(printf '%s\n' "$canonical")
      return 1
    }
  done
}

@test "swift-init documents --config-dir: the synopsis lists it, an existing config gets a Modules row, the artifact gets no CLAUDE.md" {
  local a="$(ws_repo_root)/agents/swift-init.md"
  local synopsis; synopsis="$(awk '/^swift-init \[--no-prompt\]/ {on = 1} on {print} on && /\[<output-dir>\]/ {exit}' "$a")"
  [ -n "$synopsis" ] || { echo "no swift-init synopsis block; the scan went vacuous"; return 1; }
  grep -qF -- '[--config-dir=<dir>]' <<<"$synopsis" || { echo "the synopsis does not list --config-dir=<dir>"; return 1; }
  grep -qF -- 'wsproj::append_module' "$a" || { echo "swift-init.md does not name wsproj::append_module"; return 1; }
  grep -qF -- 'no CLAUDE.md in the artifact' "$a" || { echo "swift-init.md does not say the artifact gets no CLAUDE.md"; return 1; }
}

@test "workspace-init rows of the nested layout: bootstrap.sh stays executable, s06c injects from the root" {
  local s="$(ws_repo_root)/skills/workspace-init/SKILL.md"
  local row
  row="$(grep -E '^\| s02_meta_files \|' "$s")"
  grep -qF -- 'chmod +x <root>/bootstrap.sh' <<<"$row" || { echo "s02 does not chmod bootstrap.sh"; return 1; }
  row="$(grep -E '^\| s06c_project_inject_<app> \|' "$s")"
  grep -qF -- 'wsproj::inject_deps <root>/<app_dir> <repo> <key>' <<<"$row" \
    || { echo "s06c does not inject from <root>/<app_dir>"; return 1; }
  row="$(grep -E '^\| s10_meta_initial_commit \|' "$s")"
  grep -qF -- 'symlink' <<<"$row" || { echo "s10 does not say the Tasks/Docs symlinks are committed"; return 1; }
}

@test "workspace-init refuses a folder that already holds a workspace, with a key in both locales" {
  local d="$(ws_repo_root)/skills/workspace-init"
  grep -qF -- '`error_root_has_workspace`' "$d/SKILL.md" || { echo "SKILL.md never emits error_root_has_workspace"; return 1; }
  grep -qF -- '`--dir <path>`' "$d/SKILL.md" || { echo "SKILL.md does not document --dir"; return 1; }
  local l
  for l in en ru; do
    grep -qx '## error_root_has_workspace' "$d/locales/$l.md" || { echo "$l.md lacks error_root_has_workspace"; return 1; }
  done
}

@test "workspace-add names the workspace root <root>, places packages by pkg_dir and runs the url check" {
  local s="$ROOT/skills/workspace-add/SKILL.md"
  run grep -nE '<meta>|<workspace-parent>|workspace-parent|-meta/' "$s"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  for want in '`<root>`' 'wsdocs::pkg_dir' 'wsdocs::find_workspace_yml' 'wsdocs::refuse_old_layout' \
              'wspkg::url_matches_name' '`warn_url_name_mismatch`' '`error_old_layout`'; do
    grep -qF -- "$want" "$s" || { echo "workspace-add never names $want"; return 1; }
  done
}
