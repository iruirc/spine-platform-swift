#!/usr/bin/env bats
# Navigation follows the UI framework, not the architecture flag: a SwiftUI scaffold
# gets a router, a UIKit one a coordinator. These pin what swift-init is told to generate.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  INIT="$ROOT/agents/swift-init.md"
}

# The body of the section whose heading line is exactly $1, up to the next heading.
section() { awk -v h="$1" '$0 == h {f = 1; next} f && /^#+ / {exit} f' "$INIT"; }

@test "each UI framework names its navigation layer" {
  s="$(section '### Navigation layer by UI framework')"
  grep -qF '| `uikit` | `Coordinators/AppCoordinator.swift`' <<<"$s" || { echo "no uikit row"; return 1; }
  grep -qF '| `swiftui` | `Navigation/AppRouter.swift`' <<<"$s" || { echo "no swiftui row"; return 1; }
  grep -qF '| `appkit` |' <<<"$s" || { echo "no appkit row"; return 1; }
}

@test "both platforms default to mvvm, and no example passes the retired flag" {
  grep -qF '| `architecture` | `mvvm` | `mvvm` |' "$INIT" || { echo "defaults differ"; return 1; }
  ! grep -qE '^ +--architecture=mvvm-coordinator' "$INIT"
}

@test "the layout and the grep check know Navigation/" {
  grep -qF '├── Navigation/' "$INIT" || { echo "the layout has no Navigation/"; return 1; }
  grep -F 'After generating, run these greps' "$INIT" | grep -qF '`Navigation/`' \
    || { echo "the grep check skips Navigation/"; return 1; }
}

@test "the router takes nothing from DI" {
  grep -qF 'it takes no init parameter from DI at all' "$INIT"
}
