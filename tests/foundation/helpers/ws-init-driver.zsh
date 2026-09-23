#!/usr/bin/env zsh
# Minimal driver for batch workspace-init, used by integration tests.
# Mirrors the skill's "shared execution" steps. NOT shipped to users.
set -euo pipefail

source "${0:A:h}/../../../templates/workspace/lib/workspace-yml-parser.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-graph.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-project.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-doc-markers.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-docs.zsh"
source "${0:A:h}/../../../templates/workspace/lib/workspace-package.zsh"

ws_yml="${1:?usage: ws-init-driver.zsh <workspace.yml> <workspace-parent-dir>}"
ws_parent="${2:?}"

wsyml::load "$ws_yml" || exit $?
wsyml::validate >&2 || exit $?
wsgraph::check_acyclic >&2 || exit $?

ws_name="$(wsyml::get '.workspace.name')"
meta_dir="$ws_parent/${ws_name}-meta"
mkdir -p "$meta_dir"

# Copy meta-repo templates with placeholder substitution. Walk recursively so any
# subdirs in the template tree are preserved.
templates_root="${0:A:h}/../../../templates/workspace"
while IFS= read -r src; do
  rel="${src#$templates_root/meta-repo/}"
  rel="${rel%.tmpl}"
  # Skip LLM-driven workspace artifacts (rendered/filled by the skill body, not the driver).
  case "$rel" in
    xcworkspace-contents.xml|code-workspace.json) continue ;;
  esac
  dst="$meta_dir/$rel"
  mkdir -p "${dst:h}"
  sed "s|{{WORKSPACE_NAME}}|$ws_name|g" "$src" > "$dst"
done < <(find "$templates_root/meta-repo" -type f -name '*.tmpl')

# s02b: the skill has spine-toolkit:setup write this; the stub carries only what the
# suite reads, so it cannot grow back into a copy of core's template.
config="$meta_dir/CLAUDE-spine-toolkit.md"
if [[ ! -f "$config" ]]; then
  cat > "$config" <<EOF
# CLAUDE-spine-toolkit.md — Toolkit Configuration

## Project settings

[LANG] = [$(wsyml::toolkit lang)]
[PROGRESS] = [$(wsyml::toolkit progress)]

## Task defaults

[WORKFLOW_MODE] = [$(wsyml::toolkit mode)]

## Platform

spine-platform-swift
EOF
fi
wsproj::append_workspace_meta "$meta_dir" meta

cp "$ws_yml" "$meta_dir/workspace.yml"
( cd "$meta_dir" && git init -q -b main && touch .gitkeep )

# Shared helper: provision Tasks/ or Docs/ block per mode.
# Args: <block-name (tasks|docs)> <default-link-name (Tasks|Docs)> <template-subdir (tasks-repo|docs-repo)>
ws_provision_block() {
  local block="$1" default_name="$2" tmpl_subdir="$3"
  local enabled mode bpath target target_dir link_name
  enabled="$(wsyml::get ".workspace.${block}.enabled" 2>/dev/null || echo 'true')"
  mode="$(wsyml::get ".workspace.${block}.mode" 2>/dev/null || echo 'sibling')"
  bpath="$(wsyml::get ".workspace.${block}.path" 2>/dev/null || echo "./${default_name}")"
  target="$(wsyml::get ".workspace.${block}.symlink_target" 2>/dev/null || echo '')"

  [[ "$enabled" == "true" ]] || return 0

  case "$mode" in
    sibling)
      link_name="$default_name"
      target_dir="$ws_parent/$link_name"
      ;;
    path)
      target_dir="$ws_parent/${bpath#./}"
      ;;
    symlink)
      link_name="$default_name"
      target_dir="$ws_parent/$link_name"
      ;;
  esac

  # Idempotency / preservation: skip if anything already exists at the target location.
  if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    return 0
  fi

  if [[ "$mode" == "symlink" ]]; then
    mkdir -p "${target_dir:h}"
    ln -s "$target" "$target_dir"
    return 0
  fi

  mkdir -p "$target_dir"
  while IFS= read -r src; do
    local rel dst
    rel="${src#$templates_root/${tmpl_subdir}/}"
    rel="${rel%.tmpl}"
    dst="$target_dir/$rel"
    mkdir -p "${dst:h}"
    sed "s|{{WORKSPACE_NAME}}|$ws_name|g" "$src" > "$dst"
  done < <(find "$templates_root/${tmpl_subdir}" -type f \( -name '*.tmpl' -o -name '.gitkeep' \))

  if [[ "$block" == "tasks" ]]; then
    mkdir -p "$target_dir/TODO" "$target_dir/ACTIVE" "$target_dir/DONE"
  fi
  ( cd "$target_dir" && git init -q -b main )
}

# s09_tasks + s09b_docs
ws_provision_block tasks Tasks tasks-repo
ws_provision_block docs  Docs  docs-repo

# Per package
tools_version="$(wspkg::tools_version)"
platforms_inline="$(wspkg::platforms_inline)"
tests_kind="$(wspkg::tests_kind)"
tf_manifest_deps="$(wspkg::test_framework_manifest_deps)"
tf_target_deps="$(wspkg::test_framework_target_deps)"
for p in $(wsyml::packages); do
  group="$(wsyml::package_field "$p" group 2>/dev/null || echo '')"
  ver="$(wsyml::package_field "$p" version)"
  if [[ -n "$group" ]]; then
    group_dir="$(wsyml::get ".package_groups[] | select(.name == \"$group\") | .dir")"
    pkg_dir="$ws_parent/$group_dir/$p"
  else
    pkg_dir="$ws_parent/packages/$p"
  fi
  mkdir -p "$pkg_dir"
  while IFS= read -r src; do
    rel="${src#$templates_root/package/}"
    rel="${rel%.tmpl}"
    # A variant template renders only for the workspace's defaults.tests.
    variant="${rel##*.}"
    if (( ${WSYML_TESTS_KINDS[(Ie)$variant]} )); then
      [[ "$variant" == "$tests_kind" ]] || continue
      rel="${rel%.*}"
    fi
    rel="${rel//PACKAGE_NAMETests/${p}Tests}"
    rel="${rel//PACKAGE_NAME/$p}"
    dst="$pkg_dir/$rel"
    mkdir -p "${dst:h}"
    # ENVIRON, not -v: a multi-line value in a -v assignment trips "newline in string" on
    # macOS's /usr/bin/awk (the one true awk), which runs -v assignments through the same
    # escape processing as a string literal.
    sed -e "s|{{PACKAGE_NAME}}|$p|g" -e "s|{{VERSION}}|$ver|g" \
        -e "s|{{SWIFT_TOOLS_VERSION}}|$tools_version|g" -e "s|{{PLATFORMS}}|$platforms_inline|g" "$src" \
      | TF_MANIFEST_DEPS="$tf_manifest_deps" TF_TARGET_DEPS="$tf_target_deps" awk '
          $0 == "{{TEST_FRAMEWORK_MANIFEST_DEPS}}" { if (ENVIRON["TF_MANIFEST_DEPS"] != "") print ENVIRON["TF_MANIFEST_DEPS"]; next }
          $0 == "{{TEST_FRAMEWORK_TARGET_DEPS}}"   { if (ENVIRON["TF_TARGET_DEPS"] != "") print ENVIRON["TF_TARGET_DEPS"]; next }
          { print }' > "$dst"
  done < <(find "$templates_root/package" -type f -name '*.tmpl')
  ( cd "$pkg_dir" && git init -q -b main )
done

# Detect project block
proj_name="$(wsyml::get '.project.name' 2>/dev/null || true)"
if [[ -n "$proj_name" ]]; then
  # Per-app full chain: ios → macos
  app_keys="$(wsyml::get '.project.apps | keys | .[]' 2>/dev/null || true)"
  for ak in ${(f)app_keys}; do
    [[ "$ak" =~ ^(ios|macos)$ ]] || continue
    # Resolve repo name (long-form or string-form)
    app_repo="$(wsyml::get ".project.apps.$ak.repo" 2>/dev/null || true)"
    if [[ -z "$app_repo" ]]; then
      app_repo="$(wsyml::get ".project.apps.$ak" 2>/dev/null || true)"
    fi
    [[ -z "$app_repo" ]] && continue
    "${0:A:h}/ws-project-init-driver.zsh" "$ws_yml" "$ws_parent" "$ak" "$app_repo"
  done
fi

# s07_regen
regen="${0:A:h}/../../../scripts/workspace-docs-regen.zsh"
( cd "$meta_dir" && "$regen" >&2 )
