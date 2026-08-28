---
name: manifest
description: Platform manifest for swift-platform. Data, not instructions — the five tables spine-toolkit reads to bind roles, axes, heuristics, topics and entrypoints.
---

# Swift Platform Manifest

> This skill is **data**, not instructions. spine-toolkit reads the five tables below by
> invoking this skill; there is no procedure here to follow.

This is `swift-platform`'s manifest — the contract that `spine-toolkit` documents and demonstrates
with its own reference platform manifest, filled in for the real Swift/Apple platform.
`tests/foundation/lib/manifest.test.bats` checks it structurally.

## Roles

Canonical core role → `plugin:agent`. `swift-platform` carries an agent for all nine core roles —
no role is fanned out across an axis and none is declared absent.

architect   = swift-platform:swift-architect
developer   = swift-platform:swift-developer
tester      = swift-platform:swift-tester
reviewer    = swift-platform:swift-reviewer
refactorer  = swift-platform:swift-refactorer
validator   = swift-platform:swift-validator
security    = swift-platform:swift-security
diagnostics = swift-platform:swift-diagnostics
init        = swift-platform:swift-init

## Axes

`ecosystem` is the one axis every platform must declare, and the one whose meaning spine-toolkit
fixes: it names the ecosystem this platform serves — `apple` here. Declared and reserved, not yet
consumed; a project names the plugin that serves it outright, in the `## Platform` block of its
config. Every other axis, and its allowed values, is this platform's own choice — the catalog below
is the source of truth for both `stack-detect` and the option list the orchestrator renders in AUQ. `baseline` was `platform` before
this catalog moved here; it was renamed so the new `ecosystem` axis would not mean two different
things.

ecosystem    = apple
ui           = SwiftUI, UIKit, AppKit
async        = async/await, Combine, RxSwift
di           = Swinject, Factory, manual
architecture = MVVM+Coordinator, VIPER, Clean Architecture, MVC
baseline     = iOS 17+, iOS 16+, macOS 14+, macOS 13+, iOS+macOS
tests        = XCTest, Quick+Nimble

## Heuristics

How `stack-detect` resolves axis values from repo signals: a `path` pattern flags one or more axes
as relevant, an `import` or `token` literal pins one specific value.

import: `SwiftUI` only (no UIKit/AppKit)                                   → ui=SwiftUI
import: `UIKit` only (no SwiftUI/AppKit)                                   → ui=UIKit
import: `AppKit` only (no SwiftUI/UIKit)                                   → ui=AppKit
import: more than one of SwiftUI/UIKit/AppKit                              → ui unresolved (no detection)
import: `Combine`                                                          → async=Combine
import: `RxSwift`                                                          → async=RxSwift
token:  `await `                                                           → async=async/await
import: `XCTest`                                                           → tests=XCTest
import: `Quick`, `Nimble`                                                  → tests=Quick+Nimble

path: `Views/`, `Screens/`, `*View.swift`, `*Screen.swift`                        → ui, architecture
path: `ViewModels/`, `*ViewModel.swift`, `*Presenter.swift`, `*Coordinator.swift` → architecture (+ ui if SwiftUI binding present)
path: `Networking/`, `API/`, `*Client.swift`, `*Service.swift`                    → async (+ di if container-registered)
path: `Persistence/`, `Storage/`, `*Repository.swift`, `*.xcdatamodeld`           → async, tests
path: `*Tests/`, `*Spec.swift`, `*Tests.swift`                                    → tests (+ axis of the system under test)
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

## Entrypoints

Skills spine-toolkit invokes by name, or `—` for one this platform does not provide. `setup` is the
platform half of installation: core writes the config, this skill fills `## Stack` and `## Modules`.

setup = `swift-setup`
