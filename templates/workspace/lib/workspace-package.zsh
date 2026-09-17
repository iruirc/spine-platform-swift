#!/usr/bin/env zsh
# workspace-package.zsh — the package manifest: the stack it is generated with, and the two
# dependency arrays regen owns. Needs workspace-yml-parser.zsh and workspace-docs.zsh loaded.
# Public API: wspkg::tools_version, wspkg::platform_floor, wspkg::platforms_inline, wspkg::tests_kind,
#   wspkg::rel_path, wspkg::manifest_deps, wspkg::target_deps, wspkg::adopt_to, wspkg::diagnose

# The language mode is what matters, and any tools version from 6.0 up defaults to Swift 6.
typeset -g _WSPKG_FLOOR=6.0

# a >= b over dotted numbers.
_wspkg_ge() {
  local -a a b
  local i av bv
  a=(${(s:.:)1}) b=(${(s:.:)2})
  for ((i = 1; i <= 3; i++)); do
    av="${a[$i]:-0}" bv="${b[$i]:-0}"
    (( av > bv )) && return 0
    (( av < bv )) && return 1
  done
  return 0
}

_wspkg_platform_literal() {
  local key="$1" v="$2" name floor_major major minor patch
  case "$key" in
    ios)   name=iOS;   floor_major=8  ;;
    macos) name=macOS; floor_major=11 ;;
    *)     print -u2 "_wspkg_platform_literal: unknown platform '$key'"; return 2 ;;
  esac
  major="${v%%.*}"
  if [[ "$v" == *.* ]]; then minor="${${v#*.}%%.*}"; else minor=0; fi
  if [[ "$v" == *.*.* ]]; then patch="${v##*.}"; else patch=0; fi
  # .vN exists only for N.0[.0] and only from the major SwiftPM actually declares a case for;
  # anything else — a patch component, or a major below the enum's floor — renders as a string.
  if [[ "$minor" == 0 && "$patch" == 0 && "$major" -ge "$floor_major" ]]; then
    print -r -- ".${name}(.v${major})"
  elif [[ "$v" == *.* ]]; then
    print -r -- ".${name}(\"${v}\")"
  else
    print -r -- ".${name}(\"${v}.0\")"
  fi
}

# The version the machine's toolchain generates manifests with. Older than 6.0 is not a fallback to
# Swift 5: the package must compile in language mode 6, so generation stops instead.
wspkg::tools_version() {
  local out v
  command -v swift >/dev/null 2>&1 || { print -u2 "wspkg::tools_version: swift not on PATH"; return 3; }
  out="$(swift --version 2>/dev/null)" || { print -u2 "wspkg::tools_version: swift --version failed"; return 3; }
  v="$(print -r -- "$out" | sed -n 's/.*[Ss]wift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)"
  if [[ -z "$v" ]]; then
    print -u2 "wspkg::tools_version: no version in: ${out%%$'\n'*}"
    return 3
  fi
  if ! _wspkg_ge "$v" "$_WSPKG_FLOOR"; then
    print -u2 "wspkg::tools_version: Swift $v is older than $_WSPKG_FLOOR"
    return 3
  fi
  print -r -- "$v"
}

# defaults.platforms.<key>, or the toolkit's own floor when the workspace declares no platforms.
wspkg::platform_floor() {
  local key="$1" v declared
  declared="$(wsyml::get '.defaults | has("platforms")' 2>/dev/null || print -- false)"
  if [[ "$declared" == true ]]; then
    v="$(wsyml::get ".defaults.platforms.$key" 2>/dev/null || true)"
  else
    case "$key" in
      ios)   v=17.0 ;;
      macos) v=14.0 ;;
    esac
  fi
  [[ -n "$v" ]] && print -r -- "$v"
  return 0
}

# The value of `platforms:` in a generated manifest, on one line: sed cannot substitute a multi-line
# replacement, and the skills render placeholders with sed.
wspkg::platforms_inline() {
  local key v
  local -a out
  for key in ios macos; do
    v="$(wspkg::platform_floor "$key")"
    [[ -n "$v" ]] || continue
    out+=("$(_wspkg_platform_literal "$key" "$v")") || return 2
  done
  print -r -- "${(j:, :)out}"
}

wspkg::tests_kind() {
  wsyml::get '.defaults.tests' 2>/dev/null || print -r -- swift-testing
}

# The path from one package's directory to another's, as `.package(path:)` needs it. Both come from
# wsdocs::pkg_dir, which counts from the workspace parent, so the shared head is dropped first.
wspkg::rel_path() {
  local from="$1" to="$2" fdir tdir up=""
  local -a f t
  fdir="$(wsdocs::pkg_dir "$from")" || return $?
  tdir="$(wsdocs::pkg_dir "$to")" || return $?
  f=(${(s:/:)fdir}) t=(${(s:/:)tdir})
  while (( ${#f} > 1 && ${#t} > 1 )) && [[ "${f[1]}" == "${t[1]}" ]]; do
    shift f
    shift t
  done
  repeat ${#f} up+="../"
  print -r -- "${up}${(j:/:)t}"
}

# "<key> <value>" of an external dep's version requirement; nothing when it declares none.
_wspkg_ext_req() {
  local p="$1" i="$2" tag key val
  tag="$(wsyml::get ".packages[] | select(.name == \"$p\") | .external_deps[$i].version | tag" 2>/dev/null || true)"
  case "$tag" in
    '!!map')
      key="$(wsyml::get ".packages[] | select(.name == \"$p\") | .external_deps[$i].version | keys | .[0]" 2>/dev/null || true)"
      [[ -n "$key" ]] || return 0
      val="$(wsyml::get ".packages[] | select(.name == \"$p\") | .external_deps[$i].version.\"$key\"" 2>/dev/null || true)"
      ;;
    '!!str'|'!!int'|'!!float')
      key=from
      val="$(wsyml::get ".packages[] | select(.name == \"$p\") | .external_deps[$i].version" 2>/dev/null || true)"
      ;;
    *) return 0 ;;
  esac
  [[ -n "$val" ]] && print -r -- "$key $val"
  return 0
}

_wspkg_ext_url() {
  wsyml::get ".packages[] | select(.name == \"$1\") | .external_deps[$2] | select(tag == \"!!str\") // .url" 2>/dev/null || true
}

_wspkg_ext_count() {
  wsyml::get ".packages[] | select(.name == \"$1\") | .external_deps | length" 2>/dev/null || print -- 0
}

# The lines of the package-level `dependencies:` array: workspace packages in deps order, then
# external ones in declaration order. An external dep with no version requirement is left out —
# SwiftPM has no such form — and wspkg::diagnose names it.
wspkg::manifest_deps() {
  local p="$1" d n i url req
  for d in ${(f)"$(wsyml::package_field "$p" 'deps[]' 2>/dev/null || true)"}; do
    [[ -n "$d" ]] || continue
    print -r -- "        .package(path: \"$(wspkg::rel_path "$p" "$d")\"),"
  done
  n="$(_wspkg_ext_count "$p")"
  for ((i = 0; i < n; i++)); do
    url="$(_wspkg_ext_url "$p" "$i")"
    [[ -n "$url" ]] || continue
    req="$(_wspkg_ext_req "$p" "$i")"
    [[ -n "$req" ]] || continue
    print -r -- "        .package(url: \"$url\", ${req%% *}: \"${req#* }\"),"
  done
}

# The lines of the main target's `dependencies:`. A workspace package declares one library named
# after itself, so product and package names coincide. External products are not derivable from a
# URL and stay the user's to add.
wspkg::target_deps() {
  local p="$1" d
  for d in ${(f)"$(wsyml::package_field "$p" 'deps[]' 2>/dev/null || true)"}; do
    [[ -n "$d" ]] || continue
    print -r -- "            .product(name: \"$d\", package: \"$d\"),"
  done
}

# The floor a manifest declares for one platform, from either literal form.
_wspkg_manifest_floor() {
  local file="$1" key="$2" name v
  case "$key" in
    ios)   name=iOS ;;
    macos) name=macOS ;;
    *)     return 0 ;;
  esac
  v="$(sed -n "s|.*\.${name}(\.v\([0-9_]*\)).*|\1|p" "$file" | head -1)"
  if [[ -n "$v" ]]; then
    print -r -- "${v//_/.}"
    return 0
  fi
  v="$(sed -n "s|.*\.${name}(\"\([0-9.]*\)\").*|\1|p" "$file" | head -1)"
  [[ -n "$v" ]] && print -r -- "$v"
  return 0
}

# One line per way the manifest has fallen behind what this plugin generates today. The toolkit
# reports and never rewrites: the tools version depends on the machine that runs regen, and a low
# floor may be deliberate.
wspkg::diagnose() {
  local p="$1" file="$2" label="${3:-$2}" tools key floor lit n i url req
  [[ -r "$file" ]] || return 0
  tools="$(sed -n 's|^// swift-tools-version:[[:space:]]*\([0-9.]*\).*|\1|p' "$file" | head -1)"
  if [[ -n "$tools" ]] && ! _wspkg_ge "$tools" "$_WSPKG_FLOOR"; then
    print -r -- "$label: swift-tools-version $tools < $_WSPKG_FLOOR (fix by hand)"
  fi
  for key in ios macos; do
    floor="$(wspkg::platform_floor "$key")"
    [[ -n "$floor" ]] || continue
    lit="$(_wspkg_manifest_floor "$file" "$key")"
    [[ -n "$lit" ]] || continue
    _wspkg_ge "$lit" "$floor" && continue
    print -r -- "$label: platforms $(_wspkg_platform_literal "$key" "$lit") below defaults.platforms $key $floor (fix by hand)"
  done
  n="$(_wspkg_ext_count "$p")"
  for ((i = 0; i < n; i++)); do
    url="$(_wspkg_ext_url "$p" "$i")"
    [[ -n "$url" ]] || continue
    req="$(_wspkg_ext_req "$p" "$i")"
    [[ -n "$req" ]] && continue
    print -r -- "$label: external dep $url has no version requirement (add version: { from: \"x.y.z\" })"
  done
  return 0
}

# Puts both marker pairs into a manifest still in the template's shape. Returns 1 when either array
# already holds lines of its own: what the user wrote there only the user hands over.
wspkg::adopt_to() {
  local file="$1" out="$2" pkg="$3"
  if [[ ! -r "$file" || -z "$out" || -z "$pkg" ]]; then
    print -u2 "wspkg::adopt_to: usage: <readable-file> <out-file> <package>"
    return 4
  fi
  if wsmark::has "$file" PKG_MANIFEST_DEPS && wsmark::has "$file" PKG_TARGET_DEPS; then
    cat -- "$file" > "$out" || return 4
    return 0
  fi
  awk -v pkg="$pkg" '
    { line[NR] = $0 }
    END {
      deps = 0; tgt = 0
      # Exact comparison against the two shapes the template renders (with and without the
      # trailing comma): a regex here would let a metacharacter in pkg miss the match.
      want1 = "        .target(name: \"" pkg "\", dependencies: []),"
      want2 = "        .target(name: \"" pkg "\", dependencies: [])"
      for (i = 1; i <= NR; i++) {
        if (line[i] ~ /^    dependencies: \[$/) {
          for (j = i + 1; j <= NR; j++) {
            if (line[j] ~ /^    \],?$/) { deps = i; depsEnd = j; break }
            if (line[j] !~ /^[ \t]*(\/\/.*)?$/) break
          }
        }
        if (line[i] == want1 || line[i] == want2) tgt = i
      }
      if (!deps || !tgt) exit 1
      for (i = 1; i <= NR; i++) {
        if (i == deps) {
          print line[i]
          print "        // WORKSPACE_PKG_MANIFEST_DEPS_BEGIN"
          print "        // WORKSPACE_PKG_MANIFEST_DEPS_END"
          i = depsEnd - 1
          continue
        }
        if (i == tgt) {
          sub(/dependencies: \[\]\),?$/, "dependencies: [", line[i])
          print line[i]
          print "            // WORKSPACE_PKG_TARGET_DEPS_BEGIN"
          print "            // WORKSPACE_PKG_TARGET_DEPS_END"
          print "        ]),"
          continue
        }
        print line[i]
      }
    }
  ' "$file" > "$out" || return 1
  return 0
}
