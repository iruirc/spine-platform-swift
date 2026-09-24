# spine-platform-swift

[![release](https://img.shields.io/github/v/tag/iruirc/spine-platform-swift?sort=semver&label=release&color=0969da)](https://github.com/iruirc/spine-platform-swift)
[![license](https://img.shields.io/github/license/iruirc/spine-platform-swift?color=555)](LICENSE)
[![requires spine-toolkit](https://img.shields.io/badge/requires-spine--toolkit-0969da)](https://github.com/iruirc/spine-toolkit)

The Swift/Apple platform plugin for **spine-toolkit**, with native manifests for Claude Code and
Codex. It carries the stack knowledge — nine Claude Code agents, architecture and infrastructure
skills, and multi-package SPM workspace tooling — and declares all of it to the orchestrator
through one manifest skill.

It is not a standalone toolkit: on its own it has skills you can invoke by hand, but nothing that
runs a task. spine-toolkit supplies the process; this plugin supplies who does the work and what
they know.

## Install

### Claude Code

```
/plugin marketplace add iruirc/claude-marketplace
/plugin install spine-platform-swift
```

`spine-toolkit` is declared as a dependency and installs with it. Then, in an existing project:

```
/setup
```

That is spine-toolkit's command: it writes `CLAUDE-spine-toolkit.md`, and when more than one
platform plugin is installed it asks which serves this project. The answer lands in `## Platform`:

```
## Platform

spine-platform-swift
```

That one line is the whole selection mechanism — the orchestrator invokes `spine-platform-swift:manifest`
and reads the rest from there. Editing it by hand is how you move an already-configured project to
a different platform; on a project with no config yet, run `/setup` instead — hand-writing only
this block leaves every other block the orchestrator reads missing.

A project from scratch is this plugin's own command: `/swift-init` creates an iOS/macOS app or an
SPM package and hands the answers it collected to spine-toolkit's setup, which writes both
`CLAUDE.md` and the toolkit config and offers `Tasks/`.

### Codex

The repository includes `.codex-plugin/plugin.json`; `skills/`, `scripts/`, `templates/`, and
`conventions/` are shared with Claude Code. Codex installs a plugin from a marketplace entry whose
path is relative to the marketplace root: for the personal marketplace,
`~/.agents/plugins/marketplace.json`, that is `~/plugins/spine-platform-swift`. Put a copy of this
repository there, then install it:

```bash
codex plugin add spine-platform-swift@personal
```

Start a new Codex session after installation. What Codex gets is a subset:

- **Works:** every standalone knowledge skill, plus `workspace-add` and `workspace-docs-regen` on an
  existing workspace.
- **Not supported in Codex yet:** the nine `agents/` and four `commands/` are Claude Code
  components. `spine-toolkit` ships no Codex manifest, so nothing orchestrates tasks, and its
  internal `manifest`, `swift-setup`, and `workspace-init` skills cannot complete their workflows;
  `workspace-init` also calls the Claude-only `swift-init`. Codex still permits an explicit
  `$skill-name` invocation, but `policy.allow_implicit_invocation: false` prevents these three
  skills from being selected automatically and their UI metadata offers no starter prompt.

Codex caches a plugin by version. To pick up a change, refresh the copy and reinstall; to
reinstall at an unchanged version, run the `plugin-creator` cachebuster **on the copy**. The suffix
it writes into `version` is not a release, and the foundation suite fails on a checkout that
carries it.

## What it provides

**Nine agents**, one per role in the orchestrator's vocabulary:

| Agent | Role |
|---|---|
| `swift-architect` | architect — architecture design and review |
| `swift-developer` | developer — feature implementation and bug fixes |
| `swift-tester` | tester — unit / integration test generation |
| `swift-reviewer` | reviewer — code review |
| `swift-refactorer` | refactorer — refactoring without behavior change |
| `swift-validator` | validator — post-change validation, including driving the app through the project's driver |
| `swift-security` | security — OWASP Mobile Top-10 audit |
| `swift-diagnostics` | diagnostics — bug hunting, reproduction, instrumentation |
| `swift-init` | init — project bootstrap |

**Knowledge skills**, grouped by topic:

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
- *Release ops* — `release-ops`, the Apple-specific answers behind spine-toolkit's release-ops topic.
- *Testing* — `test-frameworks`, one section per value of the `tests` axis plus the surfaces that
  force a framework. Which value a file takes is core's `test-authoring`; this is what it means in
  code.

`concurrency-architecture` covers where concurrency primitives sit across layers. Language-level
questions — `Sendable`, isolation rules, Swift 6 migration, actor reentrancy — belong to the
separately installed `swift-concurrency:swift-concurrency` skill
(<https://github.com/iruirc/swift-concurrency>).

**Multi-package SPM workspaces** — `workspace-init` bootstraps a workspace (interactive Q&A or batch
from `workspace.yml`, optionally generating one git repo per platform with an xcodegen app project
wired to local-path package dependencies), `workspace-add` adds or incorporates a package, and
`workspace-docs-regen` regenerates the marker-delimited doc sections and the workspace files.
Templates live under `templates/workspace/`.

## The manifest

`skills/manifest/SKILL.md` is the contract surface. Five required tables and `## Driver`, read by
invoking the skill:

| Table | Declares |
|---|---|
| `## Roles` | role → `spine-platform-swift:<agent>`, all nine, none absent |
| `## Axes` | `ecosystem = apple` plus `ui`, `async`, `di`, `architecture`, `baseline`, `tests` and their allowed values |
| `## Heuristics` | which repo signals (imports, tokens, paths) pin which axis value |
| `## Topics` | topic → the skills that cover it, for the orchestrator's methodology skills |
| `## Entrypoints` | `setup = swift-setup` — the platform half of installation |
| `## Driver` | the driver a project gets when it never chose one, and the surfaces its projects run on |

The manifest is the only thing spine-toolkit reads here. Everything else in this plugin is reached
through it, or invoked by name by an agent.

## Requirements

- `spine-toolkit` `>=2.12.0 <3`, declared as a dependency in `plugin.json`.
  An installed core outside that range is not a warning: the host demotes this plugin and it does
  not load at all — no agents, no skills, no manifest.
- The workspace skills need `yq` v4+ (`brew install yq`). `gh` is optional, needed only for
  `bootstrap.use_gh: true`; `xcodegen` is required when a `workspace.yml` carries a `project:` block.
- Foundation tests need `bats-core` ≥ 1.10 (`brew install bats-core`).

## Internationalization

English is the source of truth. User-facing strings live in `skills/<name>/locales/en.md` with a
key-for-key `ru.md` beside it. The active language comes from the project config's `[LANG]`
field. Whatever it is, the agents, `swift-setup` and the three workspace skills list their triggers
in both languages; the knowledge skills list English ones. Convention: `conventions/i18n.md`.

## Development

```
bats tests/foundation/lib tests/foundation/integration
scripts/lint-i18n.sh
scripts/lint-locales.sh
scripts/lint-manifest.sh .
scripts/lint-core-refs.sh . --core "$SPINE_TOOLKIT_CORE"
```

The foundation suite also checks that the Claude Code and Codex manifests have the same plugin
identity and release version, and that shared skills contain no runtime-only
`${CLAUDE_PLUGIN_ROOT}` dependency. `spine-ops: scripts/release.sh` moves the version in both
manifests. Validate the Codex package with the validator bundled with Codex's `plugin-creator`
skill before publishing a release.

`SPINE_TOOLKIT_CORE` is a checkout of core; the suite falls back to one sitting beside this
repository, and skips the check when there is none.

The five forked scripts under `scripts/` and `conventions/i18n.md` are **adapted forks** of
spine-toolkit's, not copies: each records the core file it came from and that file's sha256, and CI
goes red when the original moves, so a human decides whether the change belongs here.
`lint-manifest.sh` checks this plugin's manifest against the contract it came from; the suite runs
it too, so conformance is checked here rather than from core.
