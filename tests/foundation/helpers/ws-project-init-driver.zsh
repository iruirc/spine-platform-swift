#!/usr/bin/env zsh
# Per-app steps of workspace-init (s06b / s06c / s06e), one per call, for ws-init-driver.zsh.
# NOT shipped to users — testing only. s06b stubs swift-init: a minimal project.yml in
# <root>/<app_dir>, and the config swift-init --config-dir=<root> leaves in the root — setup's
# SPINE.md for the first app, a `## Modules` row (wsproj::append_module) for every later one.
# s06c exercises wsproj::inject_deps + xcodegen against real templates.

set -euo pipefail

ws_yml="${1:?usage: ws-project-init-driver.zsh <workspace.yml> <root> <app-key> s06b|s06c|s06e}"
root="${2:?}"
key="${3:?}"
step="${4:?}"

helpers="${0:A:h}"
lib="$helpers/../../../templates/workspace/lib"
for f in workspace-yml-parser workspace-doc-markers workspace-archetypes workspace-docs workspace-package workspace-project; do
  source "$lib/$f.zsh"
done
source "$helpers/ws-setup-stub.zsh"

wsyml::load "$ws_yml" >&2 || exit $?

app_dir="$root/$(wsdocs::app_dir "$key")"
repo="${app_dir:t}"

# swift-init --no-prompt as s06b invokes it: the flags wsproj::swift_init_flags gives, and the
# per-platform defaults for every decision flag that is missing.
s06b() {
  local -A v=(ui-framework swiftui di factory architecture mvvm async async-await)
  local flag ax sdk_platform floor baseline config_dir
  local -a axes
  for flag in ${(z)"$(wsproj::swift_init_flags "$key" batch "$root")"}; do
    [[ "$flag" == --*=* ]] && v[${${flag%%=*}#--}]="${flag#*=}"
  done
  [[ "${v[platform]}" == "$key" ]] || { print -u2 "ws-project-init-driver: --platform is not $key"; return 2; }
  case "$key" in
    ios)   sdk_platform=iOS   floor="${v[min-ios]:-17.0}" baseline="$(wsstub::baseline "${v[min-ios]:-17.0}" '')" ;;
    macos) sdk_platform=macOS floor="${v[min-macos]:-14.0}" baseline="$(wsstub::baseline '' "${v[min-macos]:-14.0}")" ;;
  esac
  for ax flag in UI ui-framework Async async DI di Architecture architecture; do
    axes+=("$ax=$(wsstub::axis_value "$ax" "${v[$flag]}")")
  done
  [[ -n "$baseline" ]] && axes+=("Baseline=$baseline")
  axes+=("Tests=$(wsstub::axis_value Tests "${v[tests]}")")

  mkdir -p "$app_dir/Sources" "$app_dir/Tests"
  cat > "$app_dir/project.yml" <<EOF
name: ${v[main-target-name]}
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    $sdk_platform: "$floor"
targets:
  ${v[main-target-name]}:
    type: application
    platform: $sdk_platform
    sources: [Sources]
    dependencies: []
EOF

  config_dir="${v[config-dir]}"
  if [[ ! -f "$config_dir/SPINE.md" ]]; then
    wsstub::setup "$config_dir" "${v[lang]}" "${v[mode]}" "${v[progress]}" "${axes[@]}"
  else
    wsproj::append_module "$config_dir" "$key" "${axes[@]}"
  fi
}

s06c() {
  wsproj::inject_deps "$app_dir" "$repo" "$key"
  ( cd "$app_dir" && xcodegen generate >&2 ) || {
    print -u2 "ws-project-init-driver: xcodegen generate failed in $app_dir"
    return 1
  }
}

s06e() {
  [[ -d "$app_dir/.git" ]] && return 0
  git -C "$app_dir" init -q -b "$(wsyml::get '.defaults.default_branch' 2>/dev/null || print main)"
}

case "$step" in
  s06b|s06c|s06e) "$step" ;;
  *) print -u2 "ws-project-init-driver: unknown step '$step'"; exit 2 ;;
esac
