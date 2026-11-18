# AGENTS.md — spine-platform-swift

> This repo is a dual-runtime Claude Code and Codex plugin: `spine-platform-swift`, the Swift/Apple
> knowledge and agents that `spine-toolkit` dispatches to. The user installs `spine-toolkit` beside
> it: Claude Code through the dependency in `.claude-plugin/plugin.json`, Codex by hand, since the
> Codex manifest declares none.
> User-project templates live in `templates/` here and in `spine-toolkit` (NOT in this file).
> This file configures the agent working on the plugin itself: Claude Code reads it through
> `CLAUDE.md`, Codex reads it directly.

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

- `skills/manifest/SKILL.md` — **the contract core reads.** Five required tables: `## Roles`,
  `## Axes`, `## Heuristics`, `## Topics`, `## Entrypoints`, and `## Driver`, which this
  platform declares. Everything core knows about Swift arrives here.
- `skills/` — knowledge skills: `arch-*`, `di-*`, `net-*`, `persistence-*`, `reactive-*`,
  `workspace-*`, `swift-setup`
- `agents/` — nine `swift-*` Claude Code subagents, named by the manifest's `## Roles` table
- `commands/` — `/swift-init`, `/workspace-*`
- `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` — host manifests with one identity
  and one version, which `spine-ops: scripts/release.sh` moves in both
- `CLAUDE.md` — imports `AGENTS.md` for Claude Code
- `templates/workspace/`, `tests/foundation/`
- `scripts/` plus `conventions/i18n.md` — six **adapted forks** of core's files, each recording the
  core path it came from and that file's sha256. `lint-core-refs.sh`, `lint-locales.sh` and
  `lint-manifest.sh` differ from core only in comments; `lint-i18n.sh`, `test-foundation.sh` and
  `conventions/i18n.md` also differ in logic or content, because this plugin has no `claude-md-stub`
  template, does have an `integration` suite, and has its own orphan-key list. They are not copies —
  do not "restore" them to match core. CI goes red when core's original moves, and a human decides
  whether the change belongs here.

## Conventions

The manifest contract lives in the `spine-toolkit` plugin, as `platform-contract.md` among its
conventions. Read it from a checkout of that plugin before changing `skills/manifest/SKILL.md` —
this repo deliberately keeps no second copy, because a copy of a contract drifts from it. Keep the
filename bare: a directory-prefixed path would resolve under THIS plugin's root and find nothing,
which the self-containment guard rejects.

## When working on this repo

- What to run and when, and how to wait for it: `spine-ops/WORKSPACE.md`.
- After changing a skill, validate it: `${CODEX_HOME:-~/.codex}/skills/.system/skill-creator/scripts/quick_validate.py skills/<name>`.
- Adding a user-facing string: add the key to BOTH `locales/en.md` AND `locales/ru.md`, then
  reference it from the skill body. Parity check must be empty.
- Adding an agent: bilingual triggers in the `description:` field, and a `## Roles` row in
  `skills/manifest/SKILL.md` — core dispatches by role, so an agent no row names never runs.
- Changing `skills/manifest/SKILL.md`: run `scripts/lint-manifest.sh .` — this fork differs from
  core's only in comments. Do it before pushing.
- A reference guide keeps only what its SKILL.md does not; its format and load table are held by
  `tests/foundation/lib/skill-references.test.bats`. A Swift block that must compile carries
  `<!-- typecheck -->` above its fence, and `scripts/typecheck-snippets.sh` compiles it.
- This repository is public, and `spine-ops: leak-guard` checks every commit, commit message, tag
  and push for absolute local paths and the owner's real project names. Never pass `--no-verify`
  and never change `core.hooksPath`. When the check stops you, replace the data with a neutral
  placeholder (`/Users/foo`, `com.example.app`, `MyApp`) instead of working around it.

## Codex compatibility

- Keep `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` aligned on `name`, `version`,
  `author.name`, and `repository`. Never move `version` by hand: a release goes through
  `spine-ops: scripts/release.sh`, which moves it in both. Never commit the `+codex.<cachebuster>`
  suffix Codex's local reinstall flow writes into `version`.
- `skills/`, `scripts/`, `templates/`, and `conventions/` are shared by Claude Code and Codex.
  Shared skill instructions must resolve support files through `<platform-root>`, never solely
  through a host-specific environment variable.
- `agents/` are Claude Code subagents; in Codex the orchestrator hands an agent's file to
  `spawn_agent` as its role instructions (`runtimes/codex-cli.md` of spine-toolkit), so keep them
  free of anything only Claude Code has. `commands/` are Claude Code only.
- The Codex manifest intentionally omits the Claude dependency declaration: the user installs
  `spine-toolkit` beside this plugin. A skill that only `spine-toolkit` or a Claude Code component
  can drive carries `policy.allow_implicit_invocation: false` in its `skills/<name>/agents/openai.yaml`
  and no `default_prompt`. This prevents automatic selection but does not disable explicit `$skill` use.
