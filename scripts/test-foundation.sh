#!/usr/bin/env bash
# Adapted from spine-toolkit scripts/test-foundation.sh sha256:b6d399f3dd7281c3a245f3119ae3094915e776fd88a8a65a6e681f5ad6b66ce4
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
