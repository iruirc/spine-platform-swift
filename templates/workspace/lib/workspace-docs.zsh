#!/usr/bin/env zsh
# workspace-docs.zsh — the content of every toolkit-owned section and workspace file, derived from
# the loaded workspace.yml. Each generator prints its content without the marker lines.
# Public API: wsdocs::find_workspace_yml, wsdocs::refuse_old_layout, wsdocs::migration_guide,
#   wsdocs::pkg_dir, wsdocs::rel_between, wsdocs::apps, wsdocs::app_dir, wsdocs::app_xcodeproj, wsdocs::app_url,
#   wsdocs::pkg_list, wsdocs::layers, wsdocs::graph,
#   wsdocs::repos, wsdocs::gitignore_repos, wsdocs::repo_map,
#   wsdocs::clone, wsdocs::fragment, wsdocs::pkg_header, wsdocs::pkg_deps, wsdocs::pkg_meta,
#   wsdocs::pkg_boundary, wsdocs::pkg_public_api, wsdocs::xcworkspace, wsdocs::code_workspace_folders

typeset -g _WSDOCS_TEMPLATES="${${(%):-%x}:A:h:h}"

# The migration guide of the nested layout, as installed with this library: the templates root is
# <plugin>/templates/workspace, so the plugin root is two folders up. Prints the absolute path.
wsdocs::migration_guide() {
  print -r -- "${_WSDOCS_TEMPLATES:h:h}/docs/migrations/workspace-nested-layout.md"
}

# Messages of the two root checks below name the command that asked.
typeset -g WSDOCS_CALLER="${WSDOCS_CALLER:-workspace}"

# The workspace.yml of the nearest ancestor of <dir> (default: the cwd) that holds one; that
# ancestor is the workspace root. A *-meta folder with a workspace.yml beside an ancestor is the old
# layout: it is reported (exit 4), never used. Exit 4 too when there is no workspace.yml at all.
wsdocs::find_workspace_yml() {
  local d="${1:-$PWD}" old_yml="" cands
  while :; do
    if [[ -f "$d/workspace.yml" ]]; then print -r -- "$d/workspace.yml"; return 0; fi
    if [[ -z "$old_yml" ]]; then cands=("$d"/*-meta/workspace.yml(N)); (( ${#cands} )) && old_yml="${cands[1]}"; fi
    [[ "$d" == / ]] && break
    d="${d:h}"
  done
  if [[ -n "$old_yml" ]]; then
    print -u2 "$WSDOCS_CALLER: $old_yml is the old layout, where the meta repo sits beside the packages; see docs/migrations/workspace-nested-layout.md ($(wsdocs::migration_guide))"
  else
    print -u2 "$WSDOCS_CALLER: no workspace.yml in ${1:-$PWD} or its ancestors"
  fi
  return 4
}

# Needs the workspace.yml loaded. Inside an old <ws>-meta folder (any case) workspace.yml is right there, so
# wsdocs::find_workspace_yml took it for a root. It is the old layout when none of the declared
# repositories is under it and one is beside it: exit 4, the same pointer. Otherwise 0.
wsdocs::refuse_old_layout() {
  local yml="$1" meta="${1:h}" ws rpath inside=0 beside=0
  ws="$(wsyml::get '.workspace.name')"
  # Case-insensitive: a folder made by hand often lowercases the workspace name (myapp-meta).
  [[ "${meta:t:l}" == "${ws:l}-meta" ]] || return 0
  for rpath in ${(f)"$(wsdocs::repos | cut -f1)"}; do
    [[ -e "$meta/$rpath" ]] && inside=1
    [[ -e "${meta:h}/$rpath" ]] && beside=1
  done
  if (( ! inside && beside )); then
    print -u2 "$WSDOCS_CALLER: $yml is the old layout, where the meta repo sits beside the packages; see docs/migrations/workspace-nested-layout.md ($(wsdocs::migration_guide))"
    return 4
  fi
  return 0
}

# <dir>/<name> relative to the workspace root.
wsdocs::pkg_dir() {
  local pkg="$1" group dir
  group="$(wsyml::package_field "$pkg" group 2>/dev/null || true)"
  if [[ -z "$group" ]]; then
    print -r -- "packages/$pkg"
    return 0
  fi
  dir="$(wsyml::get ".package_groups[] | select(.name == \"$group\") | .dir")" || return 2
  print -r -- "$dir/$pkg"
}

# The path from the directory <from-dir> to <to-dir>, both counted from the workspace root: the shared
# head is dropped, each segment left on the from side climbs one `../`, and the last segment of either
# side is never dropped. `./`, a trailing `/` and `.` are normalized away.
wsdocs::rel_between() {
  local up=""
  local -a f t
  if [[ -z "$1" || -z "$2" ]]; then
    print -u2 "wsdocs::rel_between: usage: <from-dir> <to-dir>"
    return 4
  fi
  f=(${(s:/:)1}) t=(${(s:/:)2})
  f=(${f:#(.|)}) t=(${t:#(.|)})
  while (( ${#f} > 1 && ${#t} > 1 )) && [[ "${f[1]}" == "${t[1]}" ]]; do
    shift f
    shift t
  done
  repeat ${#f} up+="../"
  print -r -- "${up}${(j:/:)t}"
}

# One "<key> <repo>" line per declared app, ios before macos; the short form `ios: <repo>` counts.
wsdocs::apps() {
  local key repo
  for key in ios macos; do
    repo="$(wsyml::get ".project.apps.$key.repo" 2>/dev/null || wsyml::get ".project.apps.$key | select(tag == \"!!str\")" 2>/dev/null || true)"
    [[ -n "$repo" ]] && print -r -- "$key $repo"
  done
  return 0
}

# The app repo's path from the workspace root: <dir>/<repo>, with no leading ./ and no trailing /;
# `dir` absent or `.` puts the repo directly under the root. Exit 2 when the key declares no app.
wsdocs::app_dir() {
  local key="$1" k repo dir found=0
  while read -r k repo; do
    [[ "$k" == "$key" ]] && { found=1; break; }
  done < <(wsdocs::apps)
  (( found )) || return 2
  dir="$(wsyml::get ".project.apps.$key.dir" 2>/dev/null || true)"
  while [[ "$dir" == ./* ]]; do dir="${dir#./}"; done
  while [[ "$dir" == */ ]]; do dir="${dir%/}"; done
  [[ "$dir" == . ]] && dir=""
  print -r -- "${dir:+$dir/}$repo"
}

# The url of the app under the first top-level remote; empty when the app declares none.
wsdocs::app_url() {
  local key="$1" remote
  remote="$(wsyml::remotes 2>/dev/null | head -n 1)"
  [[ -n "$remote" ]] || return 0
  wsyml::get ".project.apps.$key.git.\"$remote\"" 2>/dev/null || true
  return 0
}

# One "<path><TAB><url>" line per repository: the apps (ios, macos), then the packages in `packages[]`
# order. The url is the one under the first top-level remote; empty when the repository declares none.
wsdocs::repos() {
  local key repo p remote url
  remote="$(wsyml::remotes 2>/dev/null | head -n 1)"
  while read -r key repo; do
    [[ -n "$repo" ]] && print -r -- "$(wsdocs::app_dir "$key")"$'\t'"$(wsdocs::app_url "$key")"
  done < <(wsdocs::apps)
  for p in ${(f)"$(wsyml::packages)"}; do
    url=""
    [[ -n "$remote" ]] && url="$(wsyml::package_field "$p" "git.\"$remote\"" 2>/dev/null || true)"
    print -r -- "$(wsdocs::pkg_dir "$p")"$'\t'"$url"
  done
}

# The .gitignore entries of the repositories under the root: the ones bootstrap.sh clones, then the
# Tasks and Docs repos of sibling and path mode. None is the meta repo's files; a Tasks or Docs
# symlink is, so it is not listed. No trailing slash: `/p/` matches only a directory, and git takes a
# package incorporated with --symlink for a file.
wsdocs::gitignore_repos() {
  local rpath url block def mode   # not `path`: in zsh it is tied to PATH
  while IFS=$'\t' read -r rpath url; do
    [[ -n "$rpath" ]] && print -r -- "/$rpath"
  done < <(wsdocs::repos)
  for block def in tasks Tasks docs Docs; do
    [[ "$(wsyml::get ".workspace.$block.enabled" 2>/dev/null)" == false ]] && continue
    mode="$(wsyml::get ".workspace.$block.mode" 2>/dev/null || print sibling)"
    case "$mode" in
      symlink) continue ;;
      path) rpath="$(wsyml::get ".workspace.$block.path" 2>/dev/null || print "$def")" ;;
      *) rpath="$def" ;;
    esac
    while [[ "$rpath" == ./* ]]; do rpath="${rpath#./}"; done
    print -r -- "/${rpath%/}"
  done
}

# The repo map of `## Workspace meta`: where agents start, what each repository is, how to commit.
wsdocs::repo_map() {
  local key repo p
  print -r -- "- Workspace: $(wsyml::get '.workspace.name'); launch agents from this folder"
  while read -r key repo; do
    [[ -n "$repo" ]] && print -r -- "- $(wsdocs::app_dir "$key") — app ($key)"
  done < <(wsdocs::apps)
  for p in ${(f)"$(wsyml::packages)"}; do
    print -r -- "- $(wsdocs::pkg_dir "$p") — $(wsyml::package_field "$p" archetype) package"
  done
  print -r -- "- Before editing inside a repository, read its CLAUDE.md when it has one; commit in each repository separately"
}

wsdocs::pkg_list() {
  local p
  for p in ${(f)"$(wsyml::packages)"}; do
    print -r -- "- $p ($(wsyml::package_field "$p" archetype)) — $(wsyml::package_field "$p" group 2>/dev/null || print -- —)"
  done
}

# One row per group in declaration order, then `—` for ungrouped packages; a cell lists the group's
# packages of that archetype.
wsdocs::layers() {
  local -a archs=(api-contract engine library feature) groups cell
  local -A arch_of group_of
  local g p a row
  for p in ${(f)"$(wsyml::packages)"}; do
    arch_of[$p]="$(wsyml::package_field "$p" archetype)"
    group_of[$p]="$(wsyml::package_field "$p" group 2>/dev/null || print -- —)"
  done
  groups=(${(f)"$(wsyml::groups 2>/dev/null)"})
  (( ${${(v)group_of}[(Ie)—]} )) && groups+=(—)
  print -r -- "| Group | ${(j: | :)archs} |"
  print -r -- "|---|---|---|---|---|"
  for g in $groups; do
    row="| $g |"
    for a in $archs; do
      cell=()
      for p in ${(f)"$(wsyml::packages)"}; do
        [[ "${arch_of[$p]}" == "$a" && "${group_of[$p]}" == "$g" ]] && cell+=("$p")
      done
      row+=" ${${(j:, :)cell}:-—} |"
    done
    print -r -- "$row"
  done
}

# A node line for a package without deps keeps it on the graph.
wsdocs::graph() {
  local p d deps
  print -r -- '```mermaid'
  print -r -- 'graph TD'
  for p in ${(f)"$(wsyml::packages)"}; do
    deps="$(wsyml::package_field "$p" 'deps[]' 2>/dev/null || true)"
    if [[ -z "$deps" ]]; then
      print -r -- "  $p"
      continue
    fi
    for d in ${(f)deps}; do print -r -- "  $p --> $d"; done
  done
  print -r -- '```'
}

# What a fresh checkout runs: the meta repo is the workspace root, and bootstrap.sh clones the rest.
wsdocs::clone() {
  local ws
  ws="$(wsyml::get '.workspace.name')"
  print -r -- '```bash'
  print -r -- "git clone <meta-repo-url> $ws"
  print -r -- "cd $ws"
  print -r -- "./bootstrap.sh"
  [[ "$(wsyml::get '.workspace.xcworkspace' 2>/dev/null)" == false ]] || print -r -- "open $ws.xcworkspace"
  print -r -- '```'
}

# Static toolkit text: templates/workspace/sections/<NAME>.md.
wsdocs::fragment() {
  local f="$_WSDOCS_TEMPLATES/sections/$1.md"
  [[ -r "$f" ]] || { print -u2 "wsdocs::fragment: no section '$1'"; return 4; }
  cat -- "$f"
}

wsdocs::pkg_header() {
  local p="$1"
  print -r -- "# $p"
  print
  print -r -- "**Archetype:** $(wsyml::package_field "$p" archetype)"
  print -r -- "**Version:** $(wsyml::package_field "$p" version)"
}

# An external dep is a URL or a map with url and an optional version requirement.
_wsdocs_external() {
  wsyml::get ".packages[] | select(.name == \"$1\") | .external_deps[]? | select(tag == \"!!str\") // (.url + ((.version // {}) | (select(tag == \"!!map\") | to_entries | map(\" (\" + .key + \" \" + (.value | tostring) + \")\") | join(\"\")) // (\" (\" + tostring + \")\")))" 2>/dev/null || true
}

_wsdocs_bullets() {
  local item
  [[ -n "$1" ]] || { print -r -- "- none"; return 0; }
  for item in ${(f)1}; do print -r -- "- $item"; done
}

wsdocs::pkg_deps() {
  local p="$1"
  print -r -- "## Dependencies"
  print
  print -r -- "Workspace packages:"
  print
  _wsdocs_bullets "$(wsyml::package_field "$p" 'deps[]' 2>/dev/null || true)"
  print
  print -r -- "External packages:"
  print
  _wsdocs_bullets "$(_wsdocs_external "$p")"
}

wsdocs::pkg_meta() {
  local p="$1" ws dir up="" allowed ext
  ws="$(wsyml::get '.workspace.name')"
  dir="$(wsdocs::pkg_dir "$p")" || return $?
  up="${(j:/:)${(@)${(s:/:)dir}/*/..}}"
  allowed="$(wsyml::package_field "$p" 'allowed_deps[]' 2>/dev/null || true)"
  ext="$(wsyml::get ".packages[] | select(.name == \"$p\") | .external_deps[]? | select(tag == \"!!str\") // .url" 2>/dev/null || true)"
  print -r -- "**Archetype**: $(wsyml::package_field "$p" archetype)"
  print -r -- "**Group**: $(wsyml::package_field "$p" group 2>/dev/null || print -- —)"
  print -r -- "**Workspace**: $ws ($up)"
  print -r -- "**Archetype rule exceptions**: ${${(j:, :)${(f)allowed}}:-—}"
  print -r -- "**External deps**: ${${(j:, :)${(f)ext}}:-—}"
  print -r -- "**Version**: $(wsyml::package_field "$p" version)"
}

wsdocs::pkg_boundary() {
  wsarch::boundary_text "$(wsyml::package_field "$1" archetype)"
}

# `_wsdocs_public_decls <dir>`: top-level `public` / `open` declarations of the Swift files under
# <dir>, files in byte order, each cut at its first brace. Members inside a type are not listed.
_wsdocs_public_decls() {
  local src="$1" f
  local -a decls
  for f in ${(f)"$(cd "$src" && find . -type f -name '*.swift' | LC_ALL=C sort)"}; do
    decls+=(${(f)"$(grep -E '^(public|open) ' -- "$src/$f" | grep -vE '^(public|open) import ' | sed -E 's/[[:space:]]*\{.*$//; s/^(.*)$/- `\1`/')"})
  done
  if (( ${#decls} )); then print -r -- "${(F)decls}"; else print -r -- "- none"; fi
}

# The `## Public API` section: top-level `public` / `open` declarations of the package's sources.
# Sources/<name> when that folder exists; otherwise every folder directly under Sources/ in byte
# order (a target named unlike its package, or several targets): one folder gives the flat list,
# several give a `### <folder>` group each, `- none` for a folder with no declarations; no folder
# gives `- none`. A folder is a directory or a symlink to one (a package may be symlinked, so its
# targets may be too); a name starting with `.`, a file, a symlink to a file and a dangling symlink
# are not target folders. Package.swift is not read, so a target with a custom `path:` outside
# Sources/ is out of scope.
wsdocs::pkg_public_api() {
  local p="$1" root="$2/Sources" d
  local -a dirs
  print -r -- "## Public API"
  print
  if [[ -d "$root/$p" ]]; then
    _wsdocs_public_decls "$root/$p"
    return
  fi
  if [[ -d "$root" ]]; then
    dirs=("$root"/*(N-/:t))
    dirs=(${(f)"$(print -rl -- "${dirs[@]}" | LC_ALL=C sort)"})
  fi
  case ${#dirs} in
    0) print -r -- "- none" ;;
    1) _wsdocs_public_decls "$root/${dirs[1]}" ;;
    *)
      local first=1
      for d in "${dirs[@]}"; do
        (( first )) || print
        first=0
        print -r -- "### $d"
        print
        _wsdocs_public_decls "$root/$d"
      done
      ;;
  esac
}

# The app's project from the workspace root: the one *.xcodeproj its folder holds, whatever it is
# called (an app made before the workspace often names it after the product, not the repo); with none
# or several, <app_dir>/<repo>.xcodeproj. The root is the folder of the loaded workspace.yml.
wsdocs::app_xcodeproj() {
  local key="$1" dir root
  local -a found
  dir="$(wsdocs::app_dir "$key")" || return 2
  root="${${_WSYML_STATE[path]:-.}:A:h}"
  found=("$root/$dir"/*.xcodeproj(N/))
  if (( ${#found} == 1 )); then
    print -r -- "$dir/${found[1]:t}"
  else
    print -r -- "$dir/${dir:t}.xcodeproj"
  fi
}

# The whole contents.xcworkspacedata: the template with both ref lists filled.
wsdocs::xcworkspace() {
  local tmp p key repo projects="" pkgs=""
  tmp="$(mktemp -t wsdocs-xcws.XXXXXX)" || return 4
  cp -- "$_WSDOCS_TEMPLATES/meta-repo/xcworkspace-contents.xml.tmpl" "$tmp" || { rm -f -- "$tmp"; return 4; }
  while read -r key repo; do
    [[ -n "$repo" ]] && projects+="   <FileRef location=\"group:$(wsdocs::app_xcodeproj "$key")\"></FileRef>"$'\n'
  done < <(wsdocs::apps)
  for p in ${(f)"$(wsyml::packages)"}; do
    pkgs+="   <FileRef location=\"group:$(wsdocs::pkg_dir "$p")\"></FileRef>"$'\n'
  done
  if [[ -n "$projects" ]]; then
    print -r -- "${projects%$'\n'}" | wsmark::write "$tmp" PROJECT_REFS || { rm -f -- "$tmp"; return 4; }
  fi
  if [[ -n "$pkgs" ]]; then
    print -r -- "${pkgs%$'\n'}" | wsmark::write "$tmp" PKG_REFS || { rm -f -- "$tmp"; return 4; }
  fi
  cat -- "$tmp"
  rm -f -- "$tmp"
}

_wsdocs_folder() { print -r -- "{\"name\": \"$1\", \"path\": \"$2\"}"; }

# The `folders` array of the .code-workspace, as compact JSON: meta-repo, apps, packages, then the
# Tasks and Docs folders a workspace keeps.
wsdocs::code_workspace_folders() {
  local ws p key repo block def mode bpath
  local -a items
  ws="$(wsyml::get '.workspace.name')"
  items+=("$(_wsdocs_folder "$ws" .)")
  while read -r key repo; do
    [[ -n "$repo" ]] && items+=("$(_wsdocs_folder "$repo" "$(wsdocs::app_dir "$key")")")
  done < <(wsdocs::apps)
  for p in ${(f)"$(wsyml::packages)"}; do
    items+=("$(_wsdocs_folder "$p" "$(wsdocs::pkg_dir "$p")")")
  done
  for block def in tasks Tasks docs Docs; do
    [[ "$(wsyml::get ".workspace.$block.enabled" 2>/dev/null)" == false ]] && continue
    mode="$(wsyml::get ".workspace.$block.mode" 2>/dev/null || print sibling)"
    bpath="$(wsyml::get ".workspace.$block.path" 2>/dev/null || print "./$def")"
    if [[ "$mode" == path ]]; then
      items+=("$(_wsdocs_folder "${bpath:t}" "${bpath#./}")")
    else
      items+=("$(_wsdocs_folder "$def" "$def")")
    fi
  done
  print -r -- "[${(j:,:)items}]"
}
