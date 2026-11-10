- Clone the repositories that are not here yet: `./bootstrap.sh` (prints `clone`, `ok`, `skip` or `error` per repository; safe to re-run)
- Add a package: `workspace-add --new <name>` or `workspace-add --incorporate <path>`
- Regenerate the marked doc sections and the workspace files: `workspace-docs-regen`

Launch `claude` or `codex` from this folder: it is the one that sees every repository. Commit in each
repository separately.

Marker mismatch: `workspace-docs-regen --repair`. CI drift check: `workspace-docs-regen --check`,
after `./bootstrap.sh` on a fresh clone — the `.xcworkspace` refers to the `.xcodeproj` each app folder
holds. A workspace created before its docs had these markers: `workspace-docs-regen --adopt`.
