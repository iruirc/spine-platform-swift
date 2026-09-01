# CLAUDE.md — swift-platform

> This repo is one Claude Code plugin: `swift-platform`, the Swift/Apple knowledge and agents that
> `spine-toolkit` dispatches to. It declares `spine-toolkit` a dependency and is useless without it.
> This file configures Claude when it works on the plugin itself.

## Language

en

## Persona

- This repo's source-of-truth language is English.
- User-facing strings are localized via `skills/<name>/locales/<lang>.md`. Editing localized strings
  requires updating every locale file with parity.
- When changing a skill body, never inline a localized string — always reference a locale key.
- **No process knowledge lives here.** Not stages, not `Tasks/`, not profiles, not artifacts between
  stages. That is core's, and `tests/foundation/lib/self-containment.test.bats` holds the line.

## Repository layout

- `skills/manifest/SKILL.md` — **the contract core reads.** Five tables: `## Roles`, `## Axes`,
  `## Heuristics`, `## Topics`, `## Entrypoints`. Everything core knows about Swift arrives here.
- `skills/` — knowledge skills: `arch-*`, `di-*`, `net-*`, `persistence-*`, `reactive-*`,
  `workspace-*`, `swift-setup`
- `agents/` — nine `swift-*` Claude Code subagents, named by the manifest's `## Roles` table
- `commands/` — `/swift-init`, `/workspace-*`
- `templates/workspace/`, `tests/foundation/`
- `scripts/` plus `conventions/i18n.md` — five **adapted forks** of core's files, each recording the
  core path it came from and that file's sha256. `lint-locales.sh` and `lint-manifest.sh` differ
  from core only in comments; `lint-i18n.sh`, `test-foundation.sh` and `conventions/i18n.md` also
  differ in logic or content, because this plugin has no `claude-md-stub` template, does have an
  `integration` suite, and has its own orphan-key list. They are not copies — do not "restore" them
  to match core. CI goes red when core's original moves, and a human decides whether the change
  belongs here.

## Conventions

The manifest contract lives in the `spine-toolkit` plugin, as `platform-contract.md` among its
conventions. Read it from a checkout of that plugin before changing `skills/manifest/SKILL.md` —
this repo deliberately keeps no second copy, because a copy of a contract drifts from it. Keep the
filename bare: a directory-prefixed path would resolve under THIS plugin's root and find nothing,
which the self-containment guard rejects.

## When working on this repo

- Adding a user-facing string: add the key to BOTH `locales/en.md` AND `locales/ru.md`, then
  reference it from the skill body. Parity check must be empty.
- Adding an agent: bilingual triggers in the `description:` field, and a `## Roles` row in
  `skills/manifest/SKILL.md` — core dispatches by role, so an agent no row names never runs.
- Changing `skills/manifest/SKILL.md`: run `scripts/lint-manifest.sh .` — this fork differs from
  core's only in comments. Do it before pushing.
