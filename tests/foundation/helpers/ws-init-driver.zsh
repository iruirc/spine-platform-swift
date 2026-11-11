#!/usr/bin/env zsh
# Minimal driver for batch workspace-init, used by integration tests. NOT shipped to users.
# Mirrors the skill's "Shared execution" table in its order: the workspace root is the meta repo.
#
#   ws-init-driver.zsh <workspace.yml> <root>
#
# <root> is what --dir names (created when absent). Keeps <root>/.workspace-init.state like the skill,
# so a second call with the state file present is --resume. WS_DRIVER_STOP_AT=<step-id> stops just
# before that step runs, with exit 75, the way an interruption would. s12-s14 (gh, push, local
# skills) are not driven: they need a network or are off by default.
set -euo pipefail

helpers="${0:A:h}"
lib="$helpers/../../../templates/workspace/lib"
for f in workspace-yml-parser workspace-graph workspace-doc-markers workspace-archetypes workspace-docs workspace-package workspace-project; do
  source "$lib/$f.zsh"
done
source "$helpers/ws-setup-stub.zsh"

ws_yml="${1:?usage: ws-init-driver.zsh <workspace.yml> <root>}"
root="${2:?}"
ws_yml="${ws_yml:A}" root="${root:A}"

wsyml::load "$ws_yml" || exit $?
wsyml::validate >&2 || exit $?
wsgraph::check_acyclic >&2 || exit $?

ws_name="$(wsyml::get '.workspace.name')"
branch="$(wsyml::get '.defaults.default_branch' 2>/dev/null || print main)"
state="$root/.workspace-init.state"
templates_root="$helpers/../../../templates/workspace"

# Pre-flight: a folder that already holds a workspace is refused unless this is a resume. A
# workspace.yml staged in a folder with no meta repo yet, and named as the source, is no workspace.
if [[ -f "$root/workspace.yml" && ! -f "$state" ]] \
   && ! [[ "$ws_yml" == "$root/workspace.yml" && ! -e "$root/.git" ]]; then
  print -u2 "ws-init-driver: $root already holds a workspace (workspace.yml, no .workspace-init.state)"
  exit 4
fi

run_step() {
  local id="$1"
  shift
  [[ -f "$state" ]] && grep -qxF -- "$id" "$state" && return 0
  if [[ "${WS_DRIVER_STOP_AT:-}" == "$id" ]]; then
    print -u2 "ws-init-driver: stopped before $id"
    exit 75
  fi
  "$@" || { print -u2 "ws-init-driver: error at step $id"; exit 1; }
  print -r -- "$id" >> "$state"
}

render() {   # <src.tmpl> <dst>
  mkdir -p "${2:h}"
  sed "s|{{WORKSPACE_NAME}}|$ws_name|g" "$1" > "$2"
}

s01() { mkdir -p "$root"; }

# The meta-repo templates, recursively; bootstrap.sh is chmod +x after the render, since `sed >`
# leaves it with the default mode.
s02() {
  local src rel dst
  while IFS= read -r src; do
    rel="${${src#$templates_root/meta-repo/}%.tmpl}"
    case "$rel" in
      xcworkspace-contents.xml|code-workspace.json) continue ;;
    esac
    dst="$root/$rel"
    [[ -f "$dst" ]] || render "$src" "$dst"
  done < <(find "$templates_root/meta-repo" -type f -name '*.tmpl')
  chmod +x "$root/bootstrap.sh"
}

s03() { [[ -d "$root/.git" ]] || git -C "$root" init -q -b "$branch"; }

s04() { [[ -f "$root/workspace.yml" ]] || cp "$ws_yml" "$root/workspace.yml"; }

s05() {
  local g p
  for g in ${(f)"$(wsyml::groups 2>/dev/null)"}; do
    mkdir -p "$root/$(wsyml::get ".package_groups[] | select(.name == \"$g\") | .dir")"
  done
  if [[ -z "$(wsyml::groups 2>/dev/null)" && -n "$(wsyml::packages 2>/dev/null || true)" ]]; then
    mkdir -p "$root/packages"
  fi
}

# A dir holding a Package.swift but no .git is this step's own interrupted render.
s06_pkg() {
  local d="$root/$(wsdocs::pkg_dir "$1")"
  [[ -d "$d/.git" ]] && return 0
  [[ -f "$d/Package.swift" ]] && rm -rf -- "$d"
  mkdir -p "$d"
  wspkg::render_to "$1" "$d" || return $?
  git -C "$d" init -q -b "$branch"
}

# s06b is done once the app's project.yml is on disk and the root config names its platform; every
# app but the first also needs its `## Modules` row. A project.yml without that config (the first app,
# stopped before setup) or without the row (a later app) is re-entered by ws-project-init-driver.zsh.
s06b_done() {
  local key="$1" dir; dir="$(wsdocs::app_dir "$key")"
  [[ -f "$root/$dir/project.yml" ]] && grep -q '^## Platform$' "$root/SPINE.md" 2>/dev/null || return 1
  [[ "$key" == "${apps[1]}" ]] || grep -qF -- "- ${dir:t}: /$dir" "$root/SPINE.md"
}

s06_app() {   # <key> <s06b|s06c|s06e>
  [[ "$2" == s06b ]] && s06b_done "$1" && return 0
  "$helpers/ws-project-init-driver.zsh" "$root/workspace.yml" "$root" "$1" "$2" >&2
}

# After the apps: the first app's swift-init normally wrote SPINE.md; with no app, setup writes it
# here with the stack of the workspace's own defaults.
s02b() {
  if [[ ! -f "$root/SPINE.md" ]]; then
    local -a stack
    stack=("Tests=$(wsstub::axis_value Tests "$(wspkg::tests_kind)")")
    local base; base="$(wsstub::baseline "$(wspkg::platform_floor ios)" "$(wspkg::platform_floor macos)")"
    [[ -n "$base" ]] && stack=("Baseline=$base" "${stack[@]}")
    wsstub::setup "$root" "$(wsyml::toolkit lang)" "$(wsyml::toolkit mode)" "$(wsyml::toolkit progress)" "${stack[@]}"
  fi
  wsproj::append_workspace_meta "$root" && wsproj::append_paths "$root"
}

s07() { ( cd "$root" && "$helpers/../../../scripts/workspace-docs-regen.zsh" >&2 ); }

# s09 / s09b: <block> <name> <template-subdir>. Everything counts from the root; anything already at
# the target is kept as it is.
s09_block() {
  local block="$1" name="$2" tmpl="$3" mode bpath target dir src rel
  [[ "$(wsyml::get ".workspace.$block.enabled" 2>/dev/null || print true)" == true ]] || return 0
  mode="$(wsyml::get ".workspace.$block.mode" 2>/dev/null || print sibling)"
  bpath="$(wsyml::get ".workspace.$block.path" 2>/dev/null || print "./$name")"
  target="$(wsyml::get ".workspace.$block.symlink_target" 2>/dev/null || print '')"
  case "$mode" in
    path) dir="$root/${${bpath#./}%/}" ;;
    *) dir="$root/$name" ;;
  esac
  [[ -e "$dir" || -L "$dir" ]] && return 0
  if [[ "$mode" == symlink ]]; then
    ln -s "$target" "$dir"
    return 0
  fi
  mkdir -p "$dir"
  while IFS= read -r src; do
    rel="${${src#$templates_root/$tmpl/}%.tmpl}"
    render "$src" "$dir/$rel"
  done < <(find "$templates_root/$tmpl" -type f \( -name '*.tmpl' -o -name '.gitkeep' \))
  [[ "$block" == tasks ]] && mkdir -p "$dir/TODO" "$dir/ACTIVE" "$dir/DONE"
  git -C "$dir" init -q -b "$branch"
}

# The repo dir of a sibling / path block; empty for a disabled or symlink one.
block_repo() {
  local block="$1" name="$2" mode bpath
  [[ "$(wsyml::get ".workspace.$block.enabled" 2>/dev/null || print true)" == true ]] || return 0
  mode="$(wsyml::get ".workspace.$block.mode" 2>/dev/null || print sibling)"
  bpath="$(wsyml::get ".workspace.$block.path" 2>/dev/null || print "./$name")"
  case "$mode" in
    symlink) ;;
    path) print -r -- "$root/${${bpath#./}%/}" ;;
    *) print -r -- "$root/$name" ;;
  esac
}

commit_after_init="$(wsyml::get '.bootstrap.commit_after_init' 2>/dev/null || print true)"
msg="$(wsyml::get '.bootstrap.initial_commit_message' 2>/dev/null || print 'Initial commit')"
author="$(wsyml::get '.bootstrap.git_author' 2>/dev/null || print 'workspace-init <workspace-init@localhost>')"

# s10 / s10b / s10c / s11 / s11b: `git add -A` and commit in <dir>, once.
commit_in() {
  local dir="$1"
  [[ "$commit_after_init" == true && -d "$dir/.git" ]] || return 0
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null && return 0
  git -C "$dir" add -A
  git -C "$dir" -c user.name="${author% <*}" -c user.email="${${author##*<}%>}" commit -q -m "$msg"
}

apps=(${(f)"$(wsdocs::apps | cut -d' ' -f1)"})
pkgs=(${(f)"$(wsyml::packages 2>/dev/null || true)"})

run_step s01_meta_dir s01
run_step s02_meta_files s02
run_step s03_meta_git s03
run_step s04_meta_yml s04
run_step s05_groups s05
for p in "${pkgs[@]}"; do run_step "s06_pkg_$p" s06_pkg "$p"; done
for k in "${apps[@]}"; do
  run_step "s06b_project_$k" s06_app "$k" s06b
  run_step "s06c_project_inject_$k" s06_app "$k" s06c
  run_step "s06e_project_git_$k" s06_app "$k" s06e
done
run_step s02b_meta_config s02b
run_step s07_regen s07
run_step s09_tasks s09_block tasks Tasks tasks-repo
run_step s09b_docs s09_block docs Docs docs-repo
run_step s10_meta_initial_commit commit_in "$root"
run_step s10b_tasks_initial_commit commit_in "$(block_repo tasks Tasks)"
run_step s10c_docs_initial_commit commit_in "$(block_repo docs Docs)"
for p in "${pkgs[@]}"; do run_step "s11_pkg_initial_commit_$p" commit_in "$root/$(wsdocs::pkg_dir "$p")"; done
for k in "${apps[@]}"; do run_step "s11b_project_initial_commit_$k" commit_in "$root/$(wsdocs::app_dir "$k")"; done
rm -f -- "$state"
