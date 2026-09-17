#!/usr/bin/env zsh
# Minimal driver for workspace-add --incorporate (soft-mutate).
set -euo pipefail

target="${1:?usage: ws-add-driver.zsh <target-package-dir> <package-name>}"
name="${2:?}"

templates_root="${0:A:h}/../../../templates/workspace"

# Soft-mutate CLAUDE.md; its marked sections are filled by workspace-docs-regen.
if [[ ! -f "$target/CLAUDE.md" ]]; then
  sed -e "s|{{PACKAGE_NAME}}|$name|g" "$templates_root/package/CLAUDE.md.tmpl" > "$target/CLAUDE.md"
  print "wrote $target/CLAUDE.md"
else
  print "warning: $target/CLAUDE.md already exists; not overwritten"
fi
