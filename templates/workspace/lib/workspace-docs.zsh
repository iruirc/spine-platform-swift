#!/usr/bin/env zsh
# workspace-docs.zsh — the content of every toolkit-owned section and workspace file, derived from
# the loaded workspace.yml. Each generator prints its content without the marker lines.
# Public API: wsdocs::pkg_dir, wsdocs::apps, wsdocs::pkg_list, wsdocs::layers, wsdocs::graph,
#   wsdocs::clone, wsdocs::fragment, wsdocs::pkg_header, wsdocs::pkg_deps, wsdocs::pkg_meta,
#   wsdocs::pkg_boundary, wsdocs::pkg_public_api, wsdocs::xcworkspace, wsdocs::code_workspace_folders

typeset -g _WSDOCS_TEMPLATES="${${(%):-%x}:A:h:h}"

# <dir>/<name> relative to the workspace parent.
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

# One "<key> <repo>" line per declared app, ios before macos; the short form `ios: <repo>` counts.
wsdocs::apps() {
  local key repo
  for key in ios macos; do
    repo="$(wsyml::get ".project.apps.$key.repo" 2>/dev/null || wsyml::get ".project.apps.$key | select(tag == \"!!str\")" 2>/dev/null || true)"
    [[ -n "$repo" ]] && print -r -- "$key $repo"
  done
  return 0
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

# workspace.yml records no URL for the meta-repo or an app repo, so those lines keep a placeholder.
wsdocs::clone() {
  local ws remote p url key repo
  ws="$(wsyml::get '.workspace.name')"
  remote="$(wsyml::remotes | head -1)"
  print -r -- '```bash'
  print -r -- "git clone <meta-repo-url> $ws-meta"
  print -r -- "cd $ws-meta"
  for p in ${(f)"$(wsyml::packages)"}; do
    url="$(wsyml::package_field "$p" "git.$remote" 2>/dev/null || print -r -- "<$p-url>")"
    print -r -- "git clone $url ../$(wsdocs::pkg_dir "$p")"
  done
  wsdocs::apps | while read -r key repo; do
    print -r -- "git clone <$repo-url> ../$repo"
  done
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
  repeat ${#${(s:/:)dir}} up+="../"
  allowed="$(wsyml::package_field "$p" 'allowed_deps[]' 2>/dev/null || true)"
  ext="$(wsyml::get ".packages[] | select(.name == \"$p\") | .external_deps[]? | select(tag == \"!!str\") // .url" 2>/dev/null || true)"
  print -r -- "**Archetype**: $(wsyml::package_field "$p" archetype)"
  print -r -- "**Group**: $(wsyml::package_field "$p" group 2>/dev/null || print -- —)"
  print -r -- "**Workspace**: $ws (${up}$ws-meta)"
  print -r -- "**Public deps allowed**: ${${(j:, :)${(f)allowed}}:-—}"
  print -r -- "**External deps**: ${${(j:, :)${(f)ext}}:-—}"
  print -r -- "**Version**: $(wsyml::package_field "$p" version)"
}

wsdocs::pkg_boundary() {
  wsarch::boundary_text "$(wsyml::package_field "$1" archetype)"
}

# Top-level `public` / `open` declarations of Sources/<name>, files in byte order, each cut at its
# first brace. Members inside a type are not listed.
wsdocs::pkg_public_api() {
  local p="$1" src="$2/Sources/$1" f
  local -a decls
  if [[ -d "$src" ]]; then
    for f in ${(f)"$(cd "$src" && find . -type f -name '*.swift' | LC_ALL=C sort)"}; do
      decls+=(${(f)"$(grep -E '^(public|open) ' -- "$src/$f" | grep -vE '^(public|open) import ' | sed -E 's/[[:space:]]*\{.*$//; s/^(.*)$/- `\1`/')"})
    done
  fi
  print -r -- "## Public API"
  print
  if (( ${#decls} )); then print -r -- "${(F)decls}"; else print -r -- "- none"; fi
}

# The whole contents.xcworkspacedata: the template with both ref lists filled.
wsdocs::xcworkspace() {
  local tmp p key repo projects="" pkgs=""
  tmp="$(mktemp -t wsdocs-xcws.XXXXXX)" || return 4
  cp -- "$_WSDOCS_TEMPLATES/meta-repo/xcworkspace-contents.xml.tmpl" "$tmp" || { rm -f -- "$tmp"; return 4; }
  while read -r key repo; do
    [[ -n "$repo" ]] && projects+="   <FileRef location=\"group:../$repo/$repo.xcodeproj\"></FileRef>"$'\n'
  done < <(wsdocs::apps)
  for p in ${(f)"$(wsyml::packages)"}; do
    pkgs+="   <FileRef location=\"group:../$(wsdocs::pkg_dir "$p")\"></FileRef>"$'\n'
  done
  if [[ -n "$projects" ]]; then
    print -r -- "${projects%$'\n'}" | wsmark::write "$tmp" PROJECT_REFS || { rm -f -- "$tmp"; return 4; }
  fi
  print -r -- "${pkgs%$'\n'}" | wsmark::write "$tmp" PKG_REFS || { rm -f -- "$tmp"; return 4; }
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
  items+=("$(_wsdocs_folder "$ws-meta" .)")
  while read -r key repo; do
    [[ -n "$repo" ]] && items+=("$(_wsdocs_folder "$repo" "../$repo")")
  done < <(wsdocs::apps)
  for p in ${(f)"$(wsyml::packages)"}; do
    items+=("$(_wsdocs_folder "$p" "../$(wsdocs::pkg_dir "$p")")")
  done
  for block def in tasks Tasks docs Docs; do
    [[ "$(wsyml::get ".workspace.$block.enabled" 2>/dev/null)" == false ]] && continue
    mode="$(wsyml::get ".workspace.$block.mode" 2>/dev/null || print sibling)"
    bpath="$(wsyml::get ".workspace.$block.path" 2>/dev/null || print "./$def")"
    if [[ "$mode" == path ]]; then
      items+=("$(_wsdocs_folder "${bpath:t}" "../${bpath#./}")")
    else
      items+=("$(_wsdocs_folder "$def" "../$def")")
    fi
  done
  print -r -- "[${(j:,:)items}]"
}
