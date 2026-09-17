- Add a package: `workspace-add --new <name>` or `workspace-add --incorporate <path>`
- Regenerate the marked doc sections and the workspace files: `workspace-docs-regen`

Marker mismatch: `workspace-docs-regen --repair`. CI drift check: `workspace-docs-regen --check`. A
workspace created before its docs had these markers: `workspace-docs-regen --adopt`.
