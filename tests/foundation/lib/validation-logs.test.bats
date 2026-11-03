#!/usr/bin/env bats

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

# Open items after 2.29.0: Validation.md linked logs in the temporary folder long-run.sh writes to
# (/var/folders/…/long-run.*), gone after the session; one run kept its own validation-evidence/.
# The logs Validation.md names are copied into the task folder, one subfolder per run.
@test "every validator keeps the logs Validation.md names in the task folder" {
  for f in "$ROOT"/agents/*-validator.md; do
    grep -qF 'validation-evidence/<timestamp>/' "$f" || { echo "$(basename "$f"): no evidence folder"; return 1; }
    ! grep -qF 'Logs stay on disk, in the file `long-run.sh`' "$f" || { echo "$(basename "$f"): still the temporary log"; return 1; }
  done
}
