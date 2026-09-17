---
name: workspace-docs-regen
description: |
  Regenerate the marker-delimited sections of workspace docs and the workspace files.
  Use when (en): "regen docs", "refresh workspace docs", "/workspace-docs-regen"
  Use when (ru): "обнови docs", "регенерация docs", "/workspace-docs-regen"
---

# workspace-docs-regen

Rewrites what `workspace.yml` and the package sources determine: the content between the `WORKSPACE_*_BEGIN` / `_END` markers of the meta-repo and package docs and of each package's `Package.swift`, `<workspace>.xcworkspace`, and the `folders` of `<workspace>.code-workspace`. A marker is an HTML comment in a markdown file and a `//` line comment in a Swift one. Text outside the markers, the rest of the `.code-workspace` and the rest of the manifest are never touched.

## Language Resolution

Read `## Language` from meta-repo's `CLAUDE-spine-toolkit.md`. Fallback: `en`.

## Run

`scripts/workspace-docs-regen.zsh` holds every format. Run it; never write a marked section by hand:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/workspace-docs-regen.zsh" [--check | --repair | --adopt] [--yes] [--pkg <name>]
```

It runs from the meta-repo or from any repository beside it, and finds `workspace.yml` itself.

| Flag | Behaviour |
|------|-----------|
| (none) | Regenerate every section and workspace file. A file with malformed markers is skipped and reported. |
| `--check` | Write nothing; print a unified diff per file that would change. |
| `--repair` | Propose fixes for malformed markers. |
| `--adopt` | Propose markers for sections an older workspace kept outside them, listed below. |
| `--yes` | Apply what `--repair` or `--adopt` proposed, then regenerate. |
| `--pkg <name>` | Only that package's files; the meta-repo files still run. |

## Confirmation

`--repair` and `--adopt` without `--yes` print their diffs and change nothing. Show the diffs, ask `repair_prompt`, and on yes run the same command with `--yes`.

## Result

The last line is `workspace-docs-regen: regenerated=<n> drifted=<n> malformed=<n> missing=<n> pending=<n>`; `missing` counts files of packages not cloned here.

| Exit | Emit |
|------|------|
| 0, no `--check` | `report_regenerated_files` with `regenerated` |
| 0, `--check` | `report_no_drift` |
| 1, `--check` | `report_drift_detected` with `drifted`, then the diffs |
| 1, `--repair` / `--adopt` | the confirmation above |
| 2, `malformed` > 0 | `error_malformed_markers` with `malformed` |
| 2, otherwise | `error_validation`, then the script's stderr — unless it opens with `usage:`, a bug in the call: show that line instead |
| 3 | `error_yq_missing` |
| 4 | `error_missing_workspace_yml` when stderr names the search (`no workspace.yml`, `several workspaces`, `is not inside`); otherwise a write failed — the script's stderr names the file, show that line as is |

## What it owns

| File | Markers |
|------|---------|
| meta `README.md` | `PKG_LIST` under `## Packages`, `CLONE` under `## Quickstart`, `DAILY_OPS` under `## Daily ops`, `SCHEMA` under `## Schema` |
| meta `ARCHITECTURE.md` | `LAYERS`, `GRAPH` |
| meta `CONTRIBUTING.md` | `ARCHETYPE_RULES` under `## Archetype rules`; `## Project-specific rules` is the user's |
| package `README.md` | `PKG_HEADER` (holds the title), `PKG_DEPS` (holds `## Dependencies`) |
| package `CLAUDE.md` | `PKG_META`; `PKG_BOUNDARY`, the archetype paragraph under `## Boundary contract` — lines below its end marker are the package's own constraints; `PKG_PUBLIC_API` (holds `## Public API`) |
| package `Package.swift` | `PKG_MANIFEST_DEPS` inside `dependencies:` of the package, `PKG_TARGET_DEPS` inside `dependencies:` of its main target. The tools version, `platforms`, `products` and every other target are the user's |
| `<workspace>.xcworkspace` | the whole file |
| `<workspace>.code-workspace` | `folders` only |

## Older workspaces

A workspace created before 1.14.0 keeps some of these sections outside markers, so regen cannot update them. `--adopt` proposes:

- in the meta `README.md`, markers around the bodies of `## Quickstart`, `## Daily ops` and `## Schema`;
- in the meta `CONTRIBUTING.md`, markers around the body of `## Archetype rules`, and removal of the `WORKSPACE_PROJECT_RULES` pair, keeping what it holds;
- in each package `CLAUDE.md`, markers around the first paragraph under `## Boundary contract`, and around a `## Public API` section that has none;
- in each package `Package.swift`, both marker pairs, when the two arrays are still the empty ones the template rendered. An array that already holds lines is reported instead — only the user hands those over.

After `--yes` the adopted sections are regenerated in the same run.

## What it reports and never changes

Every run and every `--check` also names each manifest that has fallen behind the stack this plugin generates today — an older `swift-tools-version`, a deployment floor below `defaults.platforms`, an `external_deps` entry with no version requirement (SwiftPM has no such form, so it is left out of the manifest). These lines change neither the counters nor the exit code: raising a tools version depends on the machine that happens to run regen, and a low floor may be deliberate. Show them as they are and let the user decide.
