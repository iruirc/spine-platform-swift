# swift-platform

The Swift/Apple platform plugin for **spine-toolkit**. It carries the stack knowledge — nine
specialized agents, architecture and infrastructure skills, and multi-package SPM workspace
tooling — and declares all of it to the orchestrator through one manifest skill.

It is not a standalone toolkit: on its own it has skills you can invoke by hand, but nothing that
runs a task. spine-toolkit supplies the process; this plugin supplies who does the work and what
they know.

## Install

```
/plugin marketplace add iruirc/claude-marketplace
/plugin install swift-platform
```

`spine-toolkit` is declared as a dependency and installs with it. In your project's
`CLAUDE-spine-toolkit.md`:

```
## Platform

swift-platform
```

That one line is the whole selection mechanism — the orchestrator invokes `swift-platform:manifest`
and reads the rest from there.

A project from scratch is this plugin's own command: `/swift-init` creates an iOS/macOS app or an
SPM package, lays down `Tasks/`, and writes both `CLAUDE.md` and the toolkit config.

## What it provides

**Nine agents**, one per role in the orchestrator's vocabulary:

| Agent | Role |
|---|---|
| `swift-architect` | architect — architecture design and review |
| `swift-developer` | developer — feature implementation and bug fixes |
| `swift-tester` | tester — unit / integration test generation |
| `swift-reviewer` | reviewer — code review |
| `swift-refactorer` | refactorer — refactoring without behavior change |
| `swift-validator` | validator — post-change validation, including mobile MCP runs |
| `swift-security` | security — OWASP Mobile Top-10 audit |
| `swift-diagnostics` | diagnostics — bug hunting, reproduction, instrumentation |
| `swift-init` | init — project bootstrap |

**Knowledge skills**, grouped the way the manifest's `## Topics` table groups them:

- *Architecture* — `architecture-choice` (the compass, run once), then one of `arch-mvc`,
  `arch-mvvm`, `arch-viper`, `arch-clean`, `arch-mvi`, `arch-tca`.
- *Navigation* — `arch-coordinator` (UIKit-first), `arch-swiftui-navigation` (SwiftUI-first),
  `nav-deeplinks`. Picked by UI framework, independently of the architecture. TCA covers its own.
- *DI* — `di-composition-root` (where the graph is assembled), `di-module-assembly`, `di-swinject`,
  `di-factory`. A separate decision from architecture; any pairing works.
- *Cross-cutting* — `error-architecture`, `net-architecture`, `net-openapi`,
  `persistence-architecture`, `persistence-migrations`, `concurrency-architecture`. Needed whatever
  the architecture is.
- *Binding tools* — `reactive-combine`, `reactive-rxswift`. Tools used inside an architecture, not
  architectures.
- *Packaging* — `pkg-spm-design` (package boundaries), plus the workspace skills below.

`concurrency-architecture` covers where concurrency primitives sit across layers. Language-level
questions — `Sendable`, isolation rules, Swift 6 migration, actor reentrancy — belong to the
separately installed `swift-concurrency:swift-concurrency` skill.

**Multi-package SPM workspaces** — `workspace-init` bootstraps a workspace (interactive Q&A or batch
from `workspace.yml`, optionally generating one git repo per platform with an xcodegen app project
wired to local-path package dependencies), `workspace-add` adds or incorporates a package, and
`workspace-docs-regen` regenerates marker-delimited doc sections. Templates live under
`templates/workspace/`.

## The manifest

`skills/manifest/SKILL.md` is the contract surface. Five tables, read by invoking the skill:

| Table | Declares |
|---|---|
| `## Roles` | role → `swift-platform:<agent>`, all nine, none absent |
| `## Axes` | `ecosystem = apple` plus `ui`, `async`, `di`, `architecture`, `baseline`, `tests` and their allowed values |
| `## Heuristics` | which repo signals (imports, tokens, paths) pin which axis value |
| `## Topics` | topic → the skills that cover it, for the orchestrator's methodology skills |
| `## Entrypoints` | `setup = swift-setup` — the platform half of installation |

The manifest is the only thing spine-toolkit reads here. Everything else in this plugin is reached
through it, or invoked by name by an agent.

## Requirements

- `spine-toolkit` (declared dependency).
- The workspace skills need `yq` v4+ (`brew install yq`). `gh` is optional, needed only for
  `bootstrap.use_gh: true`; `xcodegen` is required when a `workspace.yml` carries a `project:` block.
- Foundation tests need `bats-core` ≥ 1.10 (`brew install bats-core`).

## Internationalization

English is the source of truth. User-facing strings live in `skills/<name>/locales/en.md` with a
key-for-key `ru.md` beside it. The active language comes from the project config's `## Language`
block; skill triggers are bilingual regardless. Convention: `conventions/i18n.md`.

## Development

```
bats tests/foundation/lib tests/foundation/integration
scripts/lint-i18n.sh
scripts/lint-locales.sh
scripts/lint-manifest.sh .
```

The lint scripts are vendored copies of spine-toolkit's — the two plugins share no code, so a change
to one is a change to both. `lint-manifest.sh` checks this plugin's manifest against the contract it
came from; the suite runs it too, so conformance is checked here rather than from core.
