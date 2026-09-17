## description
Add a new package or incorporate an existing standalone package into the workspace; regenerates derived artifacts.

## qa_mode
Mode:

## qa_mode_new
new — create a fresh package

## qa_mode_incorporate
incorporate — pull an existing standalone repo in

## qa_path
Path to existing package repo:

## qa_archetype
Archetype:

## qa_group
Group:

## qa_allowed_deps
Allowed deps (default = archetype rule):

## warn_existing_claude_md
warning: {path}/CLAUDE.md already exists; not overwritten.
to bring it under toolkit management: workspace-docs-regen --adopt --pkg {name}

## report_success_new
Package {name} created at {path}. Workspace artifacts regenerated.

## report_success_incorporate
Package {name} incorporated from {original_path}. Workspace artifacts regenerated.

## preflight_required_swift_missing
swift is not on PATH; a new package's manifest is generated for Swift 6. Install Xcode or a Swift toolchain. exit 3.

## preflight_required_swift_too_old
Swift {version} is older than 6.0; a new package's manifest is generated for Swift 6 language mode. Update the toolchain. exit 3.

## error_validation
workspace.yml validation failed after add; rolled back.

## error_fs
filesystem error: {details}
