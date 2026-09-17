#!/usr/bin/env zsh
# workspace-doc-markers.zsh — parse + replace WORKSPACE_*_BEGIN / _END regions.

wsmark::read() {
  local file="$1" name="$2"
  if [[ -z "$file" || -z "$name" ]]; then
    print -u2 "wsmark::read: usage: <file> <marker-name>"
    return 4
  fi
  if [[ ! -r "$file" ]]; then
    print -u2 "wsmark::read: cannot read $file"
    return 4
  fi
  local begin="<!-- WORKSPACE_${name}_BEGIN -->"
  local end="<!-- WORKSPACE_${name}_END -->"
  awk -v b="$begin" -v e="$end" '
    BEGIN { inside = 0; found = 0 }
    $0 == b { inside = 1; found++; next }
    $0 == e { inside = 0; next }
    inside { print }
    END { if (found != 1) exit 2 }
  ' "$file"
}

wsmark::write() {
  local file="$1" name="$2"
  if [[ -z "$file" || -z "$name" ]]; then
    print -u2 "wsmark::write: usage: <file> <marker-name> (content via stdin)"
    return 4
  fi
  if [[ ! -r "$file" || ! -w "$file" ]]; then
    print -u2 "wsmark::write: cannot read+write $file"
    return 4
  fi
  local begin="<!-- WORKSPACE_${name}_BEGIN -->"
  local end="<!-- WORKSPACE_${name}_END -->"
  # Guard: refuse to write to ambiguous targets. awk's $0 == b matches every
  # BEGIN line, so duplicates would be silently populated together. Missing
  # markers leave nothing to write to.
  local count
  count="$(grep -cF -- "$begin" "$file" 2>/dev/null)"
  count="${count//[^0-9]/}"
  : "${count:=0}"
  if (( count > 1 )); then
    print -u2 "wsmark::write: $file has multiple WORKSPACE_${name}_BEGIN markers; refusing to write to ambiguous target. Run wsmark::lint and fix."
    return 2
  fi
  if (( count == 0 )); then
    print -u2 "wsmark::write: $file has no WORKSPACE_${name}_BEGIN marker"
    return 2
  fi
  local nc_file
  nc_file="$(mktemp -t wsmark-nc.XXXXXX)" || return 4
  cat - > "$nc_file"
  local tmp
  tmp="$(mktemp -t wsmark.XXXXXX)" || { rm -f "$nc_file"; return 4; }
  awk -v b="$begin" -v e="$end" -v nc_file="$nc_file" '
    BEGIN {
      inside = 0
      nc = ""
      while ((getline line < nc_file) > 0) {
        if (nc == "") nc = line
        else nc = nc "\n" line
      }
      close(nc_file)
    }
    $0 == b { print; print nc; inside = 1; next }
    $0 == e { print; inside = 0; next }
    inside { next }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$nc_file"; return 4; }
  mv -- "$tmp" "$file"
  rm -f "$nc_file"
  return 0
}

wsmark::lint() {
  local file="$1"
  if [[ ! -r "$file" ]]; then
    print -u2 "wsmark::lint: cannot read $file"
    return 4
  fi
  local errs=0
  local -a open_stack open_lines
  local -A closed_at
  local lineno=0 line name top i
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((lineno++))
    if [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_BEGIN -->$' ]]; then
      name="${match[1]}"
      if (( ${+closed_at[$name]} )); then
        print -u2 "$file:$lineno: second WORKSPACE_${name} pair (first closed at line ${closed_at[$name]})"
        ((errs++))
      fi
      # duplicate BEGIN of same name?
      for ((i=1; i<=${#open_stack[@]}; i++)); do
        if [[ "${open_stack[$i]}" == "$name" ]]; then
          print -u2 "$file:$lineno: duplicate WORKSPACE_${name}_BEGIN (previous at line ${open_lines[$i]})"
          ((errs++))
          break
        fi
      done
      open_stack+=("$name")
      open_lines+=("$lineno")
    elif [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_END -->$' ]]; then
      name="${match[1]}"
      if (( ${#open_stack[@]} == 0 )); then
        print -u2 "$file:$lineno: orphan WORKSPACE_${name}_END (no matching _BEGIN)"
        ((errs++))
      else
        top="${open_stack[-1]}"
        if [[ "$top" != "$name" ]]; then
          print -u2 "$file:$lineno: marker WORKSPACE_${name}_END crosses WORKSPACE_${top} boundary"
          ((errs++))
          # pop until match found or stack empty
          while (( ${#open_stack[@]} > 0 )) && [[ "${open_stack[-1]}" != "$name" ]]; do
            open_stack[-1]=()
            open_lines[-1]=()
          done
        fi
        if (( ${#open_stack[@]} > 0 )); then
          (( ${+closed_at[$name]} )) || closed_at[$name]=$lineno
          open_stack[-1]=()
          open_lines[-1]=()
        fi
      fi
    fi
  done < "$file"
  # any remaining opens = missing END
  for ((i=1; i<=${#open_stack[@]}; i++)); do
    print -u2 "$file:${open_lines[$i]}: missing WORKSPACE_${open_stack[$i]}_END for opener"
    ((errs++))
  done
  if (( errs > 0 )); then
    print -u2 "$errs marker error(s)."
    return 2
  fi
  return 0
}

wsmark::repair_to() {
  local file="$1" out="$2" lineno line name top m i found
  if [[ ! -r "$file" || -z "$out" ]]; then
    print -u2 "wsmark::repair_to: usage: <readable-file> <out-file>"
    return 4
  fi
  : > "$out" || return 4
  local -a open_stack
  local -A closed seconds
  lineno=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((lineno++))
    if [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_BEGIN -->$' ]]; then
      name="${match[1]}"
      found=0
      for ((i=1; i<=${#open_stack[@]}; i++)); do
        if [[ "${open_stack[$i]}" == "$name" ]]; then found=1; break; fi
      done
      (( found )) && continue
      # A second pair loses its markers and keeps its text.
      if (( ${+closed[$name]} )); then seconds[$name]=1; continue; fi
      open_stack+=("$name")
      print -r -- "$line" >> "$out"
    elif [[ "$line" =~ '^<!-- WORKSPACE_([A-Z_]+)_END -->$' ]]; then
      name="${match[1]}"
      if (( ${+seconds[$name]} )); then unset "seconds[$name]"; continue; fi
      (( ${#open_stack[@]} == 0 )) && continue
      top="${open_stack[-1]}"
      if [[ "$top" != "$name" ]]; then
        print -u2 "wsmark::repair_to: cannot auto-repair cross-nested boundary at $file:$lineno"
        return 2
      fi
      closed[$name]=1
      open_stack[-1]=()
      print -r -- "$line" >> "$out"
    else
      print -r -- "$line" >> "$out"
    fi
  done < "$file"
  while (( ${#open_stack[@]} > 0 )); do
    m="${open_stack[-1]}"
    print -r -- "<!-- WORKSPACE_${m}_END -->" >> "$out"
    open_stack[-1]=()
  done
  return 0
}

wsmark::repair() {
  local file="$1" tmp resp rc
  if [[ ! -r "$file" || ! -w "$file" ]]; then
    print -u2 "wsmark::repair: cannot read+write $file"
    return 4
  fi
  tmp="$(mktemp -t wsmark-repair.XXXXXX)" || return 4
  wsmark::repair_to "$file" "$tmp" || { rc=$?; rm -f "$tmp"; return $rc; }
  print "Proposed changes to $file:"
  diff -u "$file" "$tmp" || true
  print -n "Apply? (y/N) "
  read -r resp
  if [[ "$resp" != "y" && "$resp" != "Y" ]]; then
    rm -f "$tmp"
    return 1
  fi
  mv -- "$tmp" "$file"
  return 0
}

# Puts an unmarked section under a marker so regen can own it. <scope> is where the pair goes:
# body — everything under <heading>; paragraph — its first paragraph only, so text the user added
# below stays theirs; section — <heading> and its body. A section ends at the next H1/H2 or marker
# line outside a code fence. Returns 0 when the file already has the marker or was wrapped, 1 when
# <heading> is absent.
wsmark::wrap() {
  local file="$1" heading="$2" name="$3" scope="$4"
  if [[ -z "$file" || -z "$heading" || -z "$name" || ! "$scope" =~ ^(body|paragraph|section)$ ]]; then
    print -u2 "wsmark::wrap: usage: <file> <heading> <marker-name> body|paragraph|section"
    return 4
  fi
  [[ -r "$file" && -w "$file" ]] || { print -u2 "wsmark::wrap: cannot read+write $file"; return 4; }
  grep -qxF -- "<!-- WORKSPACE_${name}_BEGIN -->" "$file" && return 0
  grep -qxF -- "$heading" "$file" || return 1
  local tmp
  tmp="$(mktemp -t wsmark-wrap.XXXXXX)" || return 4
  awk -v h="$heading" -v b="<!-- WORKSPACE_${name}_BEGIN -->" -v e="<!-- WORKSPACE_${name}_END -->" -v scope="$scope" '
    { line[NR] = $0 }
    END {
      fence = 0; hl = 0
      for (i = 1; i <= NR; i++) {
        if (line[i] ~ /^```/) fence = !fence
        if (!fence && line[i] == h) { hl = i; break }
      }
      if (!hl) exit 1
      fence = 0; last = NR
      for (i = hl + 1; i <= NR; i++) {
        if (line[i] ~ /^```/) fence = !fence
        if (!fence && (line[i] ~ /^##? / || line[i] ~ /^<!-- WORKSPACE_[A-Z_]+_(BEGIN|END) -->$/)) { last = i - 1; break }
      }
      first = 0
      for (i = hl + 1; i <= last; i++) if (line[i] != "") { first = i; break }
      if (first && scope == "paragraph") {
        fence = 0
        for (i = first; i <= last; i++) {
          if (line[i] ~ /^```/) fence = !fence
          if (!fence && line[i] == "") { last = i - 1; break }
        }
      }
      while (last > hl && line[last] == "") last--
      for (i = 1; i <= NR; i++) {
        if (scope == "section" && i == hl) print b
        if (scope != "section" && first && i == first) print b
        print line[i]
        if (!first && i == hl) { if (scope != "section") { print ""; print b }; print e }
        else if (first && i == last) print e
      }
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -- "$tmp" "$file"
  return 0
}

# Drops a marker pair and keeps what it held, handing the section back to the user.
wsmark::unwrap() {
  local file="$1" name="$2"
  [[ -r "$file" && -w "$file" && -n "$name" ]] || { print -u2 "wsmark::unwrap: usage: <file> <marker-name>"; return 4; }
  local tmp
  tmp="$(mktemp -t wsmark-unwrap.XXXXXX)" || return 4
  grep -vxF -e "<!-- WORKSPACE_${name}_BEGIN -->" -e "<!-- WORKSPACE_${name}_END -->" -- "$file" > "$tmp"
  mv -- "$tmp" "$file"
  return 0
}
