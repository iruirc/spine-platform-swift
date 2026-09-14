#!/usr/bin/env bash
# Typecheck the Swift blocks marked for it in skills/*/SKILL.md and
# skills/*/references/detailed-guide.md, under Swift 6 against the iOS simulator SDK.
# Usage: scripts/typecheck-snippets.sh [root]    (root defaults to this plugin)
# A marker, <!-- typecheck --> or <!-- typecheck: <group> -->, sits on the line above a swift
# fence. A file's blocks of one group compile as one unit, after the stubs in
# tests/snippets/<skill>/<SKILL|detailed-guide>[.<group>].swift when that file exists.
# Exit: 0 every unit compiles, 1 a unit does not, 2 the input or the toolchain is wrong.
set -euo pipefail

root="$(cd -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/..}" && pwd)"

die() { echo "typecheck-snippets: $*" >&2; exit 2; }

command -v xcrun >/dev/null 2>&1 || die "xcrun not found: the typecheck needs Xcode"
version="$(xcrun swiftc --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' | head -1)"
[ -n "$version" ] || die "cannot read the swiftc version"
major="${version% *}"; minor="${version#* }"
[ "$major" -gt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -ge 2 ]; } \
  || die "swiftc $major.$minor is older than 6.2: select a newer Xcode with xcode-select -s"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/units"; : > "$tmp/errors"

extract='
BEGIN {
  n = split("Foundation UIKit SwiftUI Combine Observation SwiftData CoreData OSLog os XCTest Testing CoreSpotlight UserNotifications BackgroundTasks Security", m, " ")
  for (i = 1; i <= n; i++) allowed[m[i]] = 1
}
function err(msg) { print "ERR|" rel ":" FNR ": " msg }
pending {
  pending = 0
  if ($0 !~ /^```swift[ \t]*$/) { err("a typecheck marker must sit directly above a swift fence"); next }
  if (!(group in count)) { order[++groups] = group; count[group] = 0 }
  count[group]++
  unit = dir "/" id "." (group == "" ? "_" : group) ".swift"
  print "#sourceLocation(file: \"" rel "\", line: " FNR + 1 ")" > unit
  inblock = 1
  next
}
inblock && /^```[ \t]*$/ { print "#sourceLocation()" > unit; inblock = 0; next }
inblock {
  line = $0
  sub(/^[ \t]*/, "", line)
  sub(/^@(testable|preconcurrency)[ \t]+/, "", line)
  if (line ~ /^import[ \t]/) {
    sub(/^import[ \t]+/, "", line)
    sub(/^(typealias|struct|class|enum|protocol|let|var|func)[ \t]+/, "", line)
    split(line, part, /[^A-Za-z0-9_]/)
    if (!(part[1] in allowed)) err("import " part[1] " is not an Apple SDK module the typecheck allows")
  }
  print > unit
  next
}
/^<!-- typecheck -->$/ { group = ""; pending = 1; next }
/^<!-- typecheck: [a-z0-9-]+ -->$/ { group = $3; pending = 1; next }
/<!-- typecheck/ { err("malformed typecheck marker") }
END {
  if (pending) err("a typecheck marker ends the file")
  if (inblock) err("a marked swift fence is never closed")
  for (i = 1; i <= groups; i++) {
    g = order[i]
    print "UNIT|" dir "/" id "." (g == "" ? "_" : g) ".swift|" rel "|" g "|" count[g]
  }
}'

files=0
for f in "$root"/skills/*/SKILL.md "$root"/skills/*/references/detailed-guide.md; do
  [ -f "$f" ] || continue
  files=$((files + 1))
  out="$(awk -v rel="${f#"$root"/}" -v dir="$tmp" -v id="$files" "$extract" "$f")"
  printf '%s\n' "$out" | sed -n 's/^ERR|//p' >> "$tmp/errors"
  printf '%s\n' "$out" | sed -n 's/^UNIT|//p' >> "$tmp/units"
done
if [ -s "$tmp/errors" ]; then
  { echo "typecheck-snippets: malformed input, nothing compiled:"; cat "$tmp/errors"; } >&2
  exit 2
fi

platform="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)"
toolchain="$(dirname "$(dirname "$(xcrun -f swiftc)")")"
compile() {
  xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library -swift-version 6 \
    -target arm64-apple-ios17.0-simulator \
    -F "$platform/Developer/Library/Frameworks" -I "$platform/Developer/usr/lib" \
    -plugin-path "$toolchain/lib/swift/host/plugins/testing" "$@" 2>&1
}

units=0; blocks=0; failed=0
while IFS='|' read -r unit rel group n; do
  skill="${rel#skills/}"; skill="${skill%%/*}"
  case "$rel" in */SKILL.md) base=SKILL ;; *) base=detailed-guide ;; esac
  prelude="$root/tests/snippets/$skill/$base${group:+.$group}.swift"
  label="$rel${group:+ ($group)}"
  units=$((units + 1)); blocks=$((blocks + n))
  if [ -f "$prelude" ]; then set -- "$prelude" "$unit"; else set -- "$unit"; fi
  if log="$(compile "$@")"; then
    echo "ok   $label, $n block(s)"
  else
    failed=$((failed + 1))
    echo "FAIL $label"
    printf '%s\n' "$log"
  fi
done < "$tmp/units"

echo "scanned $files files, $units units, $blocks blocks, $failed failed"
[ "$failed" -eq 0 ]
