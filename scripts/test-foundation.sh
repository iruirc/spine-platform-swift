#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/test-foundation.sh sha256:11626b8b730021a82aa492e67cfe1b44d67d997726e9ddd27c4b507c820c8493
# Vendored copy of spine-toolkit's test runner. Plugins share no code; update both or neither.
# Run Foundation bats tests.
# Usage: scripts/test-foundation.sh [unit|integration|all]
set -euo pipefail

target="${1:-all}"
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v bats >/dev/null 2>&1; then
  echo "error: bats-core not on PATH. install: brew install bats-core" >&2
  exit 3
fi

case "$target" in
  unit)        bats "$root/tests/foundation/lib" ;;
  integration) bats "$root/tests/foundation/integration" ;;
  all)         bats "$root/tests/foundation/lib" "$root/tests/foundation/integration" ;;
  *)           echo "usage: $0 [unit|integration|all]" >&2; exit 2 ;;
esac
