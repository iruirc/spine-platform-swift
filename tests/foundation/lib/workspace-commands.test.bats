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

@test "<root> is an absolute path in workspace-init, and swift-init's --config-dir takes an absolute path" {
  local r="$(ws_repo_root)"
  grep -qF -- '`<root>` is an absolute path: resolve it with' "$r/skills/workspace-init/SKILL.md" \
    || { echo "workspace-init never says <root> is absolute"; return 1; }
  grep -qF -- '`${root:A}`' "$r/skills/workspace-init/SKILL.md" \
    || { echo "workspace-init never resolves <root> with \${root:A}"; return 1; }
  grep -qF -- '`<dir>` is an absolute path; a relative one is resolved against the cwd before anything else uses it' "$r/agents/swift-init.md" \
    || { echo "swift-init never says --config-dir is absolute and resolves a relative one"; return 1; }
}

@test "--resume treats an empty .workspace-init.state as valid" {
  grep -qF -- 'An empty file is valid' "$(ws_repo_root)/skills/workspace-init/SKILL.md" \
    || { echo "--resume does not say an empty state file is valid"; return 1; }
}

@test "the migration guide exists, walks the general order and has a section per real workspace" {
  local g="$ROOT/docs/migrations/workspace-nested-layout.md"
  [ -f "$g" ] || { echo "no $g"; return 1; }
  local h
  for h in '## Before you start' '## General order' '## Rollback' '## MyApp' '## OtherApp' '## ThirdApp' '## TeamApp'; do
    grep -qx -- "$h" "$g" || { echo "the guide has no '$h' heading"; return 1; }
  done
  local want
  for want in './bootstrap.sh' 'workspace-docs-regen.zsh" --adopt --yes' 'MyApp/SourceCode/develop' \
              'OtherApp/SourceCode/develop' 'ThirdApp/SourceCode/develop' 'TeamApp/develop'; do
    grep -qF -- "$want" "$g" || { echo "the guide never names $want"; return 1; }
  done
}

@test "the generated sections describe the nested layout: bootstrap in daily ops, dir and git in the schema" {
  local s="$ROOT/templates/workspace/sections"
  grep -qF -- './bootstrap.sh' "$s/DAILY_OPS.md" || { echo "DAILY_OPS.md does not name ./bootstrap.sh"; return 1; }
  local want
  for want in 'apps.<key>.dir' 'apps.<key>.git' 'counted from the root'; do
    grep -qF -- "$want" "$s/SCHEMA.md" || { echo "SCHEMA.md never names $want"; return 1; }
  done
  grep -qF -- 'Launch agents from this folder' "$ROOT/templates/workspace/meta-repo/CLAUDE.md.tmpl" \
    || { echo "the meta CLAUDE.md template does not say agents launch from the root"; return 1; }
  run grep -nF -- '-meta' "$ROOT/templates/workspace/meta-repo/code-workspace.json.tmpl"
  [ "$status" -eq 1 ] || { echo "the .code-workspace template still names the meta folder <name>-meta: $output"; return 1; }
}

@test "the migration guide's shell blocks paste into a zsh with interactivecomments off: no # comment, no backtick" {
  local g="$ROOT/docs/migrations/workspace-nested-layout.md"
  local n; n="$(grep -cE '^ *```(bash|zsh|sh)$' "$g")"
  [ "$n" -ge 10 ] || { echo "found $n shell blocks; the scan went vacuous"; return 1; }
  run awk '/^ *```(bash|zsh|sh)$/ {on = 1; next} on && /^ *```$/ {on = 0; next}
    on && !/^ *#!/ && (/(^|[[:space:]])#/ || /`/) {print NR ": " $0}' "$g"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "comment or backtick in a shell block:"; echo "$output"; return 1; }
}

@test "the migration guide's shell blocks hold no <word> placeholder outside quotes: zsh reads it as a redirection" {
  local g="$ROOT/docs/migrations/workspace-nested-layout.md"
  # Drop what sits inside '...' and "..." on a line, then look for <word> or <two words>.
  run awk '/^ *```(bash|zsh|sh)$/ {on = 1; next} on && /^ *```$/ {on = 0; next}
    on { l = $0; gsub(/"[^"]*"/, "", l); gsub(/\047[^\047]*\047/, "", l)
         if (l ~ /<[A-Za-z][A-Za-z _-]*>/) print NR ": " $0 }' "$g"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "placeholder in a shell block:"; echo "$output"; return 1; }
  # The scan itself must catch what it is for.
  run awk '{ l = $0; gsub(/"[^"]*"/, "", l); gsub(/\047[^\047]*\047/, "", l); if (l ~ /<[A-Za-z][A-Za-z _-]*>/) print "hit" }' <<<'git remote add origin <your private meta url>'
  [ "$output" = hit ] || { echo "the scan misses an unquoted placeholder"; return 1; }
}

@test "the rollback creates the old meta folder with mkdir -p" {
  grep -qF -- 'mkdir -p "$M" && mv .git "$M/"' "$ROOT/docs/migrations/workspace-nested-layout.md" \
    || { echo "the rollback does not mkdir -p"; return 1; }
}
