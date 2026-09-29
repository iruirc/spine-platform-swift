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

## qa_pkg_git_url
Git URL for remote '{remote}':

## qa_pkg_version
Version (default 0.1.0):

## qa_pkg_deps
Workspace-internal deps (multiselect):

## qa_pkg_external_dep
Add an external SwiftPM dependency? [y/N]

## qa_pkg_external_dep_url
External dependency URL:

## qa_pkg_external_dep_version
Version requirement — from, exact, branch or revision, then the value (empty = none):

## qa_pkg_dep_exception
'{dep}' is {dep_archetype}; a package of archetype {archetype} may not depend on it: [allow = record as an allowed_deps exception | drop = remove {dep} from deps]

## qa_allowed_deps
Exceptions to the archetype rule (packages, default none):

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
workspace.yml is invalid after add (errors above); the edit was rolled back.

## error_fs
filesystem error: {details}
