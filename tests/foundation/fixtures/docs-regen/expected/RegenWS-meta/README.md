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
git clone <meta-repo-url> RegenWS-meta
cd RegenWS-meta
git clone git@github.com:user/AKit.git ../sharedPackages/AKit
git clone git@github.com:user/BEngine.git ../sharedPackages/BEngine
git clone git@github.com:user/CFeature.git ../domainPackages/CFeature
open RegenWS.xcworkspace
```
<!-- WORKSPACE_CLONE_END -->

## Daily ops

<!-- WORKSPACE_DAILY_OPS_BEGIN -->
- Add a package: `workspace-add --new <name>` or `workspace-add --incorporate <path>`
- Regenerate the marked doc sections and the workspace files: `workspace-docs-regen`

Marker mismatch: `workspace-docs-regen --repair`. CI drift check: `workspace-docs-regen --check`. A
workspace created before its docs had these markers: `workspace-docs-regen --adopt`.
<!-- WORKSPACE_DAILY_OPS_END -->

## Schema

<!-- WORKSPACE_SCHEMA_BEGIN -->
`workspace.yml` is the single source of truth. Every field is annotated in `workspace-yml-skeleton.yml`, which ships inside the `spine-platform-swift` plugin (or run `workspace-init` to scaffold a new one).
<!-- WORKSPACE_SCHEMA_END -->

## See also

- `ARCHITECTURE.md` — layer table + dependency graph.
- `CONTRIBUTING.md` — archetype rules.
