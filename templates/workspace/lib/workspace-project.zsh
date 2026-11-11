#!/usr/bin/env zsh
# workspace-project.zsh — project-repo helpers (deps injection) and the edits of the root config.
# Public API: wsproj::package_path, wsproj::inject_deps, wsproj::append_workspace_meta,
#   wsproj::append_module, wsproj::append_paths, wsproj::swift_init_flags
# swift_init_flags needs workspace-package.zsh loaded (wspkg::tests_kind); package_path, append_module
# and append_paths need workspace-docs.zsh; append_workspace_meta needs workspace-doc-markers.zsh.

# The path from the app repo to a package, as project.yml's `packages.<name>.path` needs it. Both
# sit under the workspace root (wsdocs::app_dir, wsdocs::pkg_dir); wsdocs::rel_between does the climb.
# Needs workspace-docs.zsh loaded.
wsproj::package_path() {
  local app="$1" pkg="$2" from to
  if [[ -z "$app" || -z "$pkg" ]]; then
    print -u2 "wsproj::package_path: usage: <app-key> <package>"
    return 4
  fi
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::package_path: no document loaded; call wsyml::load first"
    return 4
  fi
  from="$(wsdocs::app_dir "$app")" || {
    print -u2 "wsproj::package_path: no app '$app' declared"
    return 2
  }
  # wsdocs::pkg_dir names an undeclared package packages/<name>, so declaration is checked first.
  if ! wsyml::packages 2>/dev/null | grep -qxF -- "$pkg"; then
    print -u2 "wsproj::package_path: package '$pkg' is not declared"
    return 2
  fi
  to="$(wsdocs::pkg_dir "$pkg")" || {
    print -u2 "wsproj::package_path: group of '$pkg' has no dir"
    return 2
  }
  wsdocs::rel_between "$from" "$to"
}

wsproj::inject_deps() {
  local repo_dir="$1"
  local main_target="$2"
  local app_key="$3"
  if [[ -z "$repo_dir" || -z "$main_target" || -z "$app_key" ]]; then
    print -u2 "wsproj::inject_deps: usage: <repo-dir> <main-target-name> <app-key>"
    return 4
  fi
  local proj_yml="$repo_dir/project.yml"
  if [[ ! -f "$proj_yml" ]]; then
    print -u2 "wsproj::inject_deps: $proj_yml not found"
    return 4
  fi
  if ! command -v yq >/dev/null 2>&1; then
    print -u2 "wsproj::inject_deps: yq not on PATH"
    return 3
  fi
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::inject_deps: no workspace.yml loaded"
    return 4
  fi
  local has_target
  has_target="$(yq eval ".targets | has(\"$main_target\")" "$proj_yml" 2>/dev/null || echo false)"
  if [[ "$has_target" != "true" ]]; then
    print -u2 "wsproj::inject_deps: target '$main_target' not found in $proj_yml"
    return 2
  fi
  local pkgs
  pkgs="$(wsyml::packages || true)"
  local p path_rel already
  for p in ${(f)pkgs}; do
    [[ -z "$p" ]] && continue
    path_rel="$(wsproj::package_path "$app_key" "$p")" || return $?
    yq eval -i ".packages.\"$p\".path = \"$path_rel\"" "$proj_yml" || return 4
    already="$(yq eval ".targets.\"$main_target\".dependencies[]? | select(.package == \"$p\") | .package" "$proj_yml" 2>/dev/null || true)"
    if [[ -z "$already" ]]; then
      yq eval -i ".targets.\"$main_target\".dependencies += [{\"package\": \"$p\"}]" "$proj_yml" || return 4
    fi
  done
  return 0
}

# The config file of a root: SPINE.md, or the pre-multi-runtime name where the project still carries
# it. Prints the path; exit 4 (with the caller's name in the message) when it cannot be read+written.
_wsproj_config_file() {
  local fn="$1" root="$2" file="$2/SPINE.md"
  if [[ ! -f "$file" && -f "$root/CLAUDE-spine-toolkit.md" ]]; then
    file="$root/CLAUDE-spine-toolkit.md"
  fi
  if [[ ! -f "$file" || ! -w "$file" ]]; then
    print -u2 "$fn: cannot read+write $file"
    return 4
  fi
  print -r -- "$file"
}

# Adds `## Workspace meta` with an empty marker pair to the root's config; workspace-docs-regen fills
# the pair with wsdocs::repo_map. Idempotent by the heading.
wsproj::append_workspace_meta() {
  local root="$1" file
  if [[ -z "$root" ]]; then
    print -u2 "wsproj::append_workspace_meta: usage: <root>"
    return 4
  fi
  file="$(_wsproj_config_file wsproj::append_workspace_meta "$root")" || return $?
  if (( ! $+functions[_wsmark_begin] )); then
    print -u2 "wsproj::append_workspace_meta: workspace-doc-markers.zsh is not sourced; it writes the marker pair"
    return 4
  fi
  grep -q '^## Workspace meta' "$file" && return 0
  printf '\n## Workspace meta\n\n%s\n%s\n' "$(_wsmark_begin "$file" META)" "$(_wsmark_end "$file" META)" >> "$file"
}

# Appends <line> to the `<heading>` section of <file>, after the section's last non-blank line, and
# creates the section at the end of the file when it is absent. A line of the section that starts with
# <prefix> (default: the whole line) counts as already there. The heading is found whatever trailing
# spaces or CR it carries, and the section ends at the next H1 or H2, as wsmark::wrap's does; a file
# whose first line ends in CR gets CR on the lines added. The file is rewritten in place, so its mode
# survives.
_wsproj_section_add() {
  local file="$1" heading="$2" line="$3" prefix="${4:-$3}" scratch rc
  scratch="$(mktemp -t wsproj.XXXXXX)" || return 4
  awk -v heading="$heading" -v line="$line" -v prefix="$prefix" '
    function trim(x) { sub(/[ \t\r]+$/, "", x); return x }
    { a[NR] = $0 }
    END {
      n = NR; s = 0
      cr = (n && a[1] ~ /\r$/) ? "\r" : ""
      for (i = 1; i <= n; i++) if (trim(a[i]) == heading) { s = i; break }
      if (!s) {
        for (i = 1; i <= n; i++) print a[i]
        if (n && trim(a[n]) != "") print cr
        print heading cr; print cr; print line cr
        exit
      }
      e = n + 1
      for (i = s + 1; i <= n; i++) if (a[i] ~ /^##? /) { e = i; break }
      last = s
      for (i = s + 1; i < e; i++) {
        if (trim(a[i]) != "") last = i
        if (index(a[i], prefix) == 1) dup = 1
      }
      if (dup) { for (i = 1; i <= n; i++) print a[i]; exit }
      if (last == s) {
        # empty section: the row goes under the heading, after its blank line
        p = (s + 1 < e && trim(a[s + 1]) == "") ? s + 1 : s
        for (i = 1; i <= p; i++) print a[i]
        if (p == s) print cr
        print line cr
        if (p + 1 == e && e <= n) print cr
        for (i = p + 1; i <= n; i++) print a[i]
      } else {
        for (i = 1; i <= last; i++) print a[i]
        print line cr
        for (i = last + 1; i <= n; i++) print a[i]
      }
    }
  ' "$file" > "$scratch" && cat "$scratch" > "$file"
  rc=$?
  rm -f "$scratch"
  return $rc
}

# Adds the row of one app to `## Modules`: `- <repo>: /<app dir> — <Axis>: <value>, ...`. The axes
# arrive as the capitalised axis names swift-setup writes under `## Stack` (UI=UIKit DI=Swinject). Idempotent by `- <repo>:`.
wsproj::append_module() {
  local root="$1" key="$2" file dir repo k v row=""
  if [[ -z "$root" || -z "$key" ]]; then
    print -u2 "wsproj::append_module: usage: <root> <app-key> <Axis=value>..."
    return 4
  fi
  shift 2
  file="$(_wsproj_config_file wsproj::append_module "$root")" || return $?
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::append_module: no workspace.yml loaded"
    return 4
  fi
  dir="$(wsdocs::app_dir "$key")" || {
    print -u2 "wsproj::append_module: no app '$key' declared"
    return 2
  }
  repo="${dir:t}"
  for v in "$@"; do
    k="${v%%=*}"
    row+="${row:+, }$k: ${v#*=}"
  done
  _wsproj_section_add "$file" "## Modules" "- $repo: /$dir${row:+ — $row}" "- $repo:"
}

# Adds the folders of the workspace to `## Paths`: one `- External packages: /<dir>/*` per package
# folder (`packages` when a package sits outside every group, each group's dir otherwise) and one
# `- Roots: /<dir>` per enabled Tasks/Docs block (its path in path mode, else the default name).
# Idempotent per line.
wsproj::append_paths() {
  local root="$1" file g p dir block def enabled mode bpath
  local -a dirs
  if [[ -z "$root" ]]; then
    print -u2 "wsproj::append_paths: usage: <root>"
    return 4
  fi
  file="$(_wsproj_config_file wsproj::append_paths "$root")" || return $?
  if [[ -z "${_WSYML_STATE[json]:-}" ]]; then
    print -u2 "wsproj::append_paths: no workspace.yml loaded"
    return 4
  fi
  for p in ${(f)"$(wsyml::packages 2>/dev/null)"}; do
    wsyml::package_field "$p" group >/dev/null 2>&1 || { dirs+=(packages); break; }
  done
  for g in ${(f)"$(wsyml::groups 2>/dev/null)"}; do
    dir="$(wsyml::get ".package_groups[] | select(.name == \"$g\") | .dir")" || continue
    dirs+=("$dir")
  done
  for dir in "${dirs[@]}"; do
    dir="${dir%/}"
    _wsproj_section_add "$file" "## Paths" "- External packages: /${dir#./}/*" || return $?
  done
  for block def in tasks Tasks docs Docs; do
    enabled="$(wsyml::get ".workspace.$block.enabled" 2>/dev/null || echo true)"
    [[ "$enabled" == false ]] && continue
    mode="$(wsyml::get ".workspace.$block.mode" 2>/dev/null || echo sibling)"
    bpath="$def"
    [[ "$mode" == path ]] && bpath="$(wsyml::get ".workspace.$block.path" 2>/dev/null || echo "$def")"
    bpath="${bpath#./}"
    _wsproj_section_add "$file" "## Paths" "- Roots: /${bpath%/}" || return $?
  done
}

# The flags s06b invokes swift-init with; --config-dir points swift-init at the workspace root, where
# the one config lives. Interactive pre-answers only what the workspace itself asked;
# batch adds what apps.<key>.stack sets, and swift-init supplies its own defaults for the rest.
wsproj::swift_init_flags() {
  local key="$1" mode="$2" root="$3" repo v ax flag tests
  local -a out
  if [[ ! "$key" =~ ^(ios|macos)$ || ! "$mode" =~ ^(interactive|batch)$ || -z "$root" ]]; then
    print -u2 "wsproj::swift_init_flags: usage: ios|macos interactive|batch <config-root>"
    return 4
  fi
  repo="$(wsyml::get ".project.apps.$key.repo" 2>/dev/null || wsyml::get ".project.apps.$key" 2>/dev/null)" \
    || { print -u2 "wsproj::swift_init_flags: workspace.yml declares no project.apps.$key"; return 4; }
  tests="$(wspkg::tests_kind)"
  [[ "$mode" == batch ]] && out+=(--no-prompt)
  out+=(--platform=$key --main-target-name=$repo)
  if [[ "$mode" == batch ]]; then
    for ax flag in ui_framework ui-framework di di architecture architecture async async; do
      v="$(wsyml::get ".project.apps.$key.stack.$ax" 2>/dev/null)" && out+=(--$flag=$v)
    done
    for ax in ios macos; do
      v="$(wsyml::get ".project.apps.$key.stack.min_platforms.$ax" 2>/dev/null)" && out+=(--min-$ax=$v)
    done
    v="$(wsyml::get ".project.apps.$key.stack.tests" 2>/dev/null)" && tests="$v"
  fi
  out+=(--tests=$tests --lang=$(wsyml::toolkit lang) --mode=$(wsyml::toolkit mode)
        --progress=$(wsyml::toolkit progress) --tasks=skip --config-dir=$root)
  print -r -- "${(j: :)out}"
}
