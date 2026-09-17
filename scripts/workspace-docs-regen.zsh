#!/usr/bin/env zsh
# Regenerates what a workspace derives from its workspace.yml: the marked sections of the meta-repo
# and package docs, the .xcworkspace, and the folders of the .code-workspace.
#
#   workspace-docs-regen.zsh [--check | --repair | --adopt] [--yes] [--pkg <name>]
#
# Runs from the meta-repo or any repository beside it. --repair and --adopt print what they would
# change and exit 1 until rerun with --yes. --pkg limits package files; meta-repo files always run.
# Exit: 0 done or no drift; 1 drift under --check, or changes awaiting --yes; 2 invalid workspace.yml
# or malformed markers; 3 yq missing; 4 workspace.yml not found.
# Last line: workspace-docs-regen: regenerated=<n> drifted=<n> malformed=<n> missing=<n> pending=<n>
set -uo pipefail

lib="${0:A:h}/../templates/workspace/lib"
for f in workspace-yml-parser workspace-graph workspace-doc-markers workspace-archetypes workspace-docs; do
  source "$lib/$f.zsh"
done

usage() { print -u2 "usage: workspace-docs-regen.zsh [--check | --repair | --adopt] [--yes] [--pkg <name>]"; exit 2; }
mode=regen yes=0 only=""
while (( $# )); do
  case "$1" in
    --check|--repair|--adopt) [[ "$mode" == regen ]] || usage; mode="${1#--}" ;;
    --yes) yes=1 ;;
    --pkg) (( $# >= 2 )) || usage; only="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

# A package repository sits beside the meta-repo, not inside it.
ws_yml="" d="$PWD"
while :; do
  if [[ -f "$d/workspace.yml" ]]; then ws_yml="$d/workspace.yml"; break; fi
  cands=("$d"/*-meta/workspace.yml(N))
  if (( ${#cands} > 1 )); then print -u2 "workspace-docs-regen: several workspaces beside $d: ${cands[*]}"; exit 4; fi
  if (( ${#cands} == 1 )); then ws_yml="${cands[1]}"; break; fi
  [[ "$d" == / ]] && break
  d="${d:h}"
done
if [[ -z "$ws_yml" ]]; then
  print -u2 "workspace-docs-regen: no workspace.yml in $PWD, its ancestors, or a *-meta directory beside one of them"
  exit 4
fi

wsyml::load "$ws_yml" || exit $?
wsyml::validate || exit 2
wsgraph::check_acyclic || exit 2
if [[ -n "$only" ]] && ! wsyml::packages | grep -qxF -- "$only"; then
  print -u2 "workspace-docs-regen: workspace.yml declares no package '$only'"
  exit 2
fi
meta="${ws_yml:h}" parent="${ws_yml:h:h}" ws="$(wsyml::get '.workspace.name')"

typeset -a files
typeset -A markers adopt pkg_of dir_of
add() { files+=("$1"); markers[$1]="$2"; adopt[$1]="$3"; pkg_of[$1]="${4:-}"; dir_of[$1]="${5:-}"; }
add "$meta/README.md" "PKG_LIST CLONE DAILY_OPS SCHEMA" \
  "wrap|## Quickstart|CLONE|body;wrap|## Daily ops|DAILY_OPS|body;wrap|## Schema|SCHEMA|body"
add "$meta/ARCHITECTURE.md" "LAYERS GRAPH" ""
add "$meta/CONTRIBUTING.md" "ARCHETYPE_RULES" "wrap|## Archetype rules|ARCHETYPE_RULES|body;unwrap|PROJECT_RULES"
for p in ${(f)"$(wsyml::packages)"}; do
  [[ -z "$only" || "$p" == "$only" ]] || continue
  pdir="$parent/$(wsdocs::pkg_dir "$p")"
  add "$pdir/README.md" "PKG_HEADER PKG_DEPS" "" "$p" "$pdir"
  add "$pdir/CLAUDE.md" "PKG_META PKG_BOUNDARY PKG_PUBLIC_API" \
    "wrap|## Boundary contract|PKG_BOUNDARY|paragraph;wrap|## Public API|PKG_PUBLIC_API|section" "$p" "$pdir"
done

content() {
  case "$1" in
    PKG_LIST) wsdocs::pkg_list ;;
    CLONE) wsdocs::clone ;;
    LAYERS) wsdocs::layers ;;
    GRAPH) wsdocs::graph ;;
    DAILY_OPS|SCHEMA|ARCHETYPE_RULES) wsdocs::fragment "$1" ;;
    PKG_HEADER) wsdocs::pkg_header "$2" ;;
    PKG_DEPS) wsdocs::pkg_deps "$2" ;;
    PKG_META) wsdocs::pkg_meta "$2" ;;
    PKG_BOUNDARY) wsdocs::pkg_boundary "$2" ;;
    PKG_PUBLIC_API) wsdocs::pkg_public_api "$2" "$3" ;;
  esac
}

tmp="$(mktemp -t wsregen.XXXXXX)" || exit 4
trap 'rm -f -- "$tmp"' EXIT
regenerated=0 drifted=0 malformed=0 missing=0 pending=0

summary() { print "workspace-docs-regen: regenerated=$regenerated drifted=$drifted malformed=$malformed missing=$missing pending=$pending"; }

# Writes $tmp over <file> in regen mode, shows the diff under --check.
settle() {
  local file="$1" old="$1"
  [[ -f "$file" ]] && cmp -s -- "$file" "$tmp" && return 0
  [[ -f "$file" ]] || old=/dev/null
  (( drifted++ ))
  if [[ "$mode" == check ]]; then
    diff -u --label "$file" --label "$file (regenerated)" -- "$old" "$tmp"
    return 0
  fi
  mkdir -p -- "${file:h}" && cp -- "$tmp" "$file" || exit 4
  (( regenerated++ ))
}

if [[ "$mode" == adopt || "$mode" == repair ]]; then
  for f in $files; do
    [[ -f "$f" ]] || continue
    if [[ "$mode" == repair ]]; then
      wsmark::lint "$f" 2>/dev/null && continue
      wsmark::repair_to "$f" "$tmp" || continue
    else
      wsmark::lint "$f" 2>/dev/null || continue
      cp -- "$f" "$tmp"
      for rule in ${(s:;:)adopt[$f]}; do
        parts=("${(@s:|:)rule}")
        case "${parts[1]}" in
          wrap) wsmark::wrap "$tmp" "${parts[2]}" "${parts[3]}" "${parts[4]}" ;;
          unwrap) wsmark::unwrap "$tmp" "${parts[2]}" ;;
        esac
      done
    fi
    cmp -s -- "$f" "$tmp" && continue
    diff -u --label "$f" --label "$f (proposed)" -- "$f" "$tmp"
    if (( yes )); then cp -- "$tmp" "$f" || exit 4; else (( pending++ )); fi
  done
  if (( pending )); then summary; exit 1; fi
fi

for f in $files; do
  if [[ ! -f "$f" ]]; then (( missing++ )); continue; fi
  if ! wsmark::lint "$f"; then (( malformed++ )); continue; fi
  cp -- "$f" "$tmp"
  for m in ${(s: :)markers[$f]}; do
    grep -qxF -- "<!-- WORKSPACE_${m}_BEGIN -->" "$tmp" || continue
    content "$m" "${pkg_of[$f]}" "${dir_of[$f]}" | wsmark::write "$tmp" "$m" || exit 4
  done
  settle "$f"
done

if [[ "$(wsyml::get '.workspace.xcworkspace' 2>/dev/null)" != false ]]; then
  f="$meta/$ws.xcworkspace/contents.xcworkspacedata"
  wsdocs::xcworkspace > "$tmp" || exit 4
  settle "$f"
fi

# The rest of the .code-workspace is the user's editor settings, so only folders is compared and set.
if [[ "$(wsyml::get '.workspace.code_workspace' 2>/dev/null)" != false ]]; then
  f="$meta/$ws.code-workspace"
  want="$(wsdocs::code_workspace_folders)"
  if [[ -f "$f" ]]; then
    if ! have="$(yq -p=json -o=json -I=0 '.folders' "$f" 2>/dev/null)"; then
      print -u2 "workspace-docs-regen: $f is not plain JSON; its folders were not checked"
      (( malformed++ ))
    elif [[ "$have" != "$(print -r -- "$want" | yq -p=json -o=json -I=0 '.')" ]]; then
      (( drifted++ ))
      if [[ "$mode" == check ]]; then
        diff -u --label "$f folders" --label "$f folders (regenerated)" \
          <(print -r -- "$have" | yq -p=json -o=json -I=2 '.') <(print -r -- "$want" | yq -p=json -o=json -I=2 '.')
      else
        WANT="$want" yq -p=json -o=json -I=2 '.folders = env(WANT)' "$f" > "$tmp" && cp -- "$tmp" "$f" || exit 4
        (( regenerated++ ))
      fi
    fi
  else
    (( drifted++ ))
    if [[ "$mode" != check ]]; then
      sed "s|{{WORKSPACE_NAME}}|$ws|g" "${lib:h}/meta-repo/code-workspace.json.tmpl" \
        | WANT="$want" yq -p=json -o=json -I=2 '.folders = env(WANT)' - > "$f" || exit 4
      (( regenerated++ ))
    fi
  fi
fi

summary
(( malformed )) && exit 2
[[ "$mode" == check ]] && (( drifted )) && exit 1
exit 0
