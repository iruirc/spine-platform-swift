# RegenWS

Multi-package SPM workspace.

## Packages

<!-- WORKSPACE_PKG_LIST_BEGIN -->
- AKit (api-contract) — common
- BEngine (engine) — common
- CFeature (feature) — domain
<!-- WORKSPACE_PKG_LIST_END -->

## Quickstart

<!-- WORKSPACE_CLONE_BEGIN -->
```bash
git clone <meta-repo-url> RegenWS
cd RegenWS
./bootstrap.sh
open RegenWS.xcworkspace
```
<!-- WORKSPACE_CLONE_END -->

## Daily ops

<!-- WORKSPACE_DAILY_OPS_BEGIN -->
- Clone the repositories that are not here yet: `./bootstrap.sh` (prints `clone`, `ok`, `skip` or `error` per repository; safe to re-run)
- Add a package: `workspace-add --new <name>` or `workspace-add --incorporate <path>`
- Regenerate the marked doc sections and the workspace files: `workspace-docs-regen`

Launch `claude` or `codex` from this folder: it is the one that sees every repository. Commit in each
repository separately.

Marker mismatch: `workspace-docs-regen --repair`. CI drift check: `workspace-docs-regen --check`. A
workspace created before its docs had these markers: `workspace-docs-regen --adopt`.
<!-- WORKSPACE_DAILY_OPS_END -->

## Schema

<!-- WORKSPACE_SCHEMA_BEGIN -->
`workspace.yml` is the single source of truth. Every field is annotated in `workspace-yml-skeleton.yml`, which ships inside the `spine-platform-swift` plugin (or run `workspace-init` to scaffold a new one).

This folder is the workspace root and the meta repo at once; every repository sits under it. An app lives at `<dir>/<repo>`: `project.apps.<key>.dir` is its folder, `.` by default, and `project.apps.<key>.git` its remote urls, keyed like a package's `git`. A package lives at `packages/<name>`, or at `<group-dir>/<name>` once it names a group. `tasks.path`, `docs.path` and `symlink_target` are counted from the root.
<!-- WORKSPACE_SCHEMA_END -->

## See also

- `ARCHITECTURE.md` — layer table + dependency graph.
- `CONTRIBUTING.md` — archetype rules.
