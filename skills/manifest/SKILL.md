---
name: manifest
description: Platform manifest for spine-platform-swift. Data, not instructions — the five required tables spine-toolkit reads to bind roles, axes, heuristics, topics and entrypoints, and the Driver table this platform declares.
---

# Swift Platform Manifest

> This skill is **data**, not instructions. spine-toolkit reads the five required tables below
> and `## Driver`, which this platform declares, by invoking this skill; there is no procedure
> here to follow.

This is `spine-platform-swift`'s manifest — the contract that `spine-toolkit` documents and demonstrates
with its own reference platform manifest, filled in for the real Swift/Apple platform.
`tests/foundation/lib/manifest.test.bats` checks it structurally.

## Roles

Canonical core role → `plugin:agent`. `spine-platform-swift` carries an agent for all nine core roles —
no role is fanned out across an axis and none is declared absent.

architect   = spine-platform-swift:swift-architect
developer   = spine-platform-swift:swift-developer
tester      = spine-platform-swift:swift-tester
reviewer    = spine-platform-swift:swift-reviewer
refactorer  = spine-platform-swift:swift-refactorer
validator   = spine-platform-swift:swift-validator
security    = spine-platform-swift:swift-security
diagnostics = spine-platform-swift:swift-diagnostics
init        = spine-platform-swift:swift-init

## Axes

`ecosystem` is the one axis every platform must declare, and the one whose meaning spine-toolkit
fixes: it names the ecosystem this platform serves — `apple` here. Declared and reserved, not yet
consumed; a project names the plugin that serves it outright, in the `## Platform` block of its
config. Every other axis, and its allowed values, is this platform's own choice — the catalog below
is the source of truth for both `spine-toolkit:stack-detect` and the option list the orchestrator renders in AUQ. `baseline` was `platform` before
this catalog moved here; it was renamed so the new `ecosystem` axis would not mean two different
things.

ecosystem    = apple
ui           = SwiftUI, UIKit, AppKit
async        = async/await, Combine, RxSwift
di           = Swinject, Factory, manual
architecture = MVVM, MVI, TCA, VIPER, Clean Architecture, MVC
baseline     = iOS 17+, iOS 16+, macOS 14+, macOS 13+, iOS+macOS
tests        = XCTest, Swift Testing, Quick+Nimble

`architecture` names the architecture only; navigation follows `ui`, except under `TCA`, which carries its own (`@Presents`, `StackState`):

| `ui` | Navigation |
|---|---|
| `UIKit` | `arch-coordinator`; SwiftUI screens inside it follow the "Hybrid" section of `arch-swiftui-navigation` |
| `SwiftUI` | `arch-swiftui-navigation`, with a router |
| `AppKit` | no navigation skill |

## Heuristics

How `spine-toolkit:stack-detect` resolves axis values from repo signals: a `path` pattern flags one or more axes
as relevant, an `import` or `token` literal pins one specific value.

import: `SwiftUI` only (no UIKit/AppKit)                                   → ui=SwiftUI
import: `UIKit` only (no SwiftUI/AppKit)                                   → ui=UIKit
import: `AppKit` only (no SwiftUI/UIKit)                                   → ui=AppKit
import: more than one of SwiftUI/UIKit/AppKit                              → ui unresolved (no detection)
import: `Combine`                                                          → async=Combine
import: `RxSwift`                                                          → async=RxSwift
token:  `await `                                                           → async=async/await
import: `XCTest` only (no `Testing`, `Quick`)                              → tests=XCTest
import: `Testing` only (no `XCTest`, `Quick`)                              → tests=Swift Testing
import: `XCTest` and `Testing` (no `Quick`)                                → tests unresolved (no detection)
import: `Quick`, `Nimble`                                                  → tests=Quick+Nimble
import: `ComposableArchitecture`                                           → architecture=TCA

path: `Views/`, `Screens/`, `*View.swift`, `*Screen.swift`                        → ui, architecture
path: `ViewModels/`, `*ViewModel.swift`, `*Presenter.swift`, `*Coordinator.swift` → architecture (+ ui if SwiftUI binding present)
path: `Networking/`, `API/`, `*Client.swift`, `*Service.swift`                    → async (+ di if container-registered)
path: `Persistence/`, `Storage/`, `*Repository.swift`, `*.xcdatamodeld`           → async, tests
path: `*Tests/`, `*Spec.swift`, `*Tests.swift`                                    → tests
path: `Package.swift`, `project.pbxproj`                                         → baseline

`baseline` has no pinning row on purpose: it is written as a version string — `Package.swift`'s
`platforms:` line, or the app target's deployment target — and a version string is never a
`## Axes` value, so the path row flags the axis and the config or the user supplies the value.

## Topics

Topic → comma-separated, backtick-quoted, bare skill names that cover it (no `plugin:` prefix — a
manifest is read one platform at a time, so its own skills need no namespacing). Consumed by
spine-toolkit's methodology skills, which name a topic and resolve it here.

state management → `arch-mvvm`, `arch-mvi`, `arch-tca`, `arch-viper`, `arch-clean`, `architecture-choice`
navigation       → `arch-coordinator`, `arch-swiftui-navigation`
networking       → `net-architecture`, `net-openapi`
persistence      → `persistence-architecture`, `persistence-migrations`
dependency graph → `di-composition-root`, `di-module-assembly`, `di-factory`, `di-swinject`
concurrency      → `concurrency-architecture`
errors           → `error-architecture`
deep links       → `nav-deeplinks`
packaging        → `pkg-spm-design`, `workspace-init`
release ops      → `release-ops`

## Entrypoints

Skills spine-toolkit invokes by name, or `—` for one this platform does not provide. `setup` is the
platform half of installation: core writes the config, this skill fills `## Stack` and `## Modules`.

setup = `swift-setup`

## Driver

The driver plugin this platform recommends, and the surfaces its projects run on. Both are read by
whoever validates: the driver named here is what a project gets when it never chose one, so an
installed project keeps driving its app exactly as it did. The surfaces are half of the compatibility
test — a driver fits when its own targets intersect this list.

default  = spine-driver-mobile
surfaces = ios-simulator, ios-device, macos
