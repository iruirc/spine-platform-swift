#!/usr/bin/env zsh
# Minimal driver for workspace-add --incorporate, used by integration tests. NOT shipped to users.
# Mirrors the skill's steps after the Q&A, which a script cannot answer: the package is already
# declared in workspace.yml (the skill's "update workspace.yml" step), and the caller runs inside the
# workspace.
#
#   ws-add-driver.zsh <package-dir> <name> [--symlink]
#
# Exit: 1 no workspace.yml above the cwd, the old layout, or a failed regen; 2 workspace.yml invalid or
# <name> not declared in it; 3 the target folder already exists.
set -euo pipefail

helpers="${0:A:h}"
platform_root="$helpers/../../.."
lib="$platform_root/templates/workspace/lib"
for f in workspace-yml-parser workspace-graph workspace-doc-markers workspace-archetypes workspace-docs workspace-package; do
  source "$lib/$f.zsh"
done

symlink=0
args=()
for a in "$@"; do
  if [[ "$a" == --symlink ]]; then symlink=1; else args+=("$a"); fi
done
src="${args[1]:?usage: ws-add-driver.zsh <package-dir> <name> [--symlink]}"
name="${args[2]:?}"
src="${src:A}"

# The text of a locale key, with {placeholders} filled from the pairs after the key.
locale_text() {
  local key="$1" text k
  shift
  text="$(awk -v k="## $key" '$0 == k { on = 1; next } /^## / { on = 0 } on' "$platform_root/skills/workspace-add/locales/en.md")"
  while (( $# >= 2 )); do
    text="${text//\{$1\}/$2}"
    shift 2
  done
  print -r -- "$text"
}

# Pre-flight: the root is the first folder up from the cwd that holds workspace.yml.
WSDOCS_CALLER=ws-add-driver
ws_yml="$(wsdocs::find_workspace_yml)" || exit 1
wsyml::load "$ws_yml" || exit $?
wsdocs::refuse_old_layout "$ws_yml" || exit 1
wsyml::validate >&2 || exit 2
wsgraph::check_acyclic >&2 || exit 2
root="${ws_yml:h}"
wsyml::packages | grep -qxF -- "$name" || { print -u2 "ws-add-driver: workspace.yml declares no package '$name'"; exit 2; }

# Before anything is moved: an occupied target stops the run (the skill checks it before editing workspace.yml).
target="$root/$(wsdocs::pkg_dir "$name")"
[[ -e "$target" || -L "$target" ]] && { print -u2 "ws-add-driver: $target already exists"; exit 3; }

# The url Q&A is over: a name that differs from the repository's is a warning, not a stop.
wspkg::url_matches_name "$name" || {
  rc=$?
  if (( rc == 1 )); then
    remote="$(wsyml::remotes | head -n 1)"
    locale_text warn_url_name_mismatch pkg "$name" url "$(wsyml::package_field "$name" "git.\"$remote\"")"
  fi
}

mkdir -p "${target:h}"
if (( symlink )); then ln -s "$src" "$target"; else mv "$src" "$target"; fi
print "placed $target"

# Soft-mutate CLAUDE.md; its marked sections are filled by workspace-docs-regen.
if [[ ! -f "$target/CLAUDE.md" ]]; then
  sed -e "s|{{PACKAGE_NAME}}|$name|g" "$platform_root/templates/workspace/package/CLAUDE.md.tmpl" > "$target/CLAUDE.md"
  print "wrote $target/CLAUDE.md"
else
  print "warning: $target/CLAUDE.md already exists; not overwritten"
fi

cd "$root"
"$platform_root/scripts/workspace-docs-regen.zsh" >&2 || exit 1
