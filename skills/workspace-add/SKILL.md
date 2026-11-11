---
name: workspace-add
description: |
  Add a new package or incorporate an existing standalone package into the workspace.
  Use when (en): "add package", "incorporate package", "/workspace-add", "ws add"
  Use when (ru): "добавь пакет", "включи пакет", "/workspace-add", "пакет в workspace"
---

# workspace-add

Adds a package to an existing workspace. Two sub-modes:

- `--new <name>`: create a fresh package from templates.
- `--incorporate <path>`: register an existing standalone package repo.

`<platform-root>` is the plugin root two directories above this `SKILL.md`. Resolve it from the
loaded skill location, not from the project working directory. The `ws*::` functions are zsh
libraries in `<platform-root>/templates/workspace/lib/`, one prefix per file (`wsyml::` is
`workspace-yml-parser.zsh`, `wsdocs::` is `workspace-docs.zsh`).

The functions, and the copy of `workspace.yml` that `wsyml::load` keeps, live only in the shell that
sourced them, and the host starts a fresh shell for each command. Every command that calls a `ws*::`
function therefore opens with the libraries, then finds `<root>` and loads it. The order is fixed: source the libs → `wsdocs::find_workspace_yml` → `wsyml::load` → `wsdocs::refuse_old_layout` (see **Pre-flight**).

```zsh
source "<platform-root>/templates/workspace/lib/workspace-yml-parser.zsh"
source "<platform-root>/templates/workspace/lib/workspace-graph.zsh"
source "<platform-root>/templates/workspace/lib/workspace-doc-markers.zsh"
source "<platform-root>/templates/workspace/lib/workspace-archetypes.zsh"
source "<platform-root>/templates/workspace/lib/workspace-docs.zsh"
source "<platform-root>/templates/workspace/lib/workspace-package.zsh"
yml="$(wsdocs::find_workspace_yml)" || exit 1   # <root> is ${yml:h}
wsyml::load "<root>/workspace.yml"
wsdocs::refuse_old_layout "<root>/workspace.yml" || exit 1
```

`wsyml::validate` and `wsgraph::check_acyclic` read that copy, not the file: a copy loaded before
this skill edits `workspace.yml` validates the document without the edit.

## Workspace root

`<root>` is the first folder up from the cwd (the cwd included) that holds `workspace.yml`. The
workspace root IS the meta repo: `workspace.yml`, `bootstrap.sh`, `SPINE.md` and the docs live in it,
and every package sits at `<root>/<pkg_dir>`, where `<pkg_dir>` is `wsdocs::pkg_dir <name>`:
`packages/<name>`, or `<group-dir>/<name>` for a package in a group. The meta repo's `.gitignore`
keeps the package repos out. There is no `<name>-meta` folder.

## Language Resolution

Read `[LANG]` from `<root>`'s project config (`SPINE.md`, or `CLAUDE-spine-toolkit.md` where it has not migrated). Fallback: `en`. All user-facing strings via `locales/<lang>.md`.

## Pre-flight

Find `<root>` with `wsdocs::find_workspace_yml` (it walks up from the cwd, and also reports a `<name>-meta` folder of the old layout) and, once `wsyml::load` has read the file, `wsdocs::refuse_old_layout <root>/workspace.yml`: `workspace-docs-regen` runs the same two checks. No `workspace.yml` emits `error_missing_workspace_yml` and exits 1; the old layout, where the meta repo sits beside the packages, emits `error_old_layout` (`{guide}`: the absolute path the stderr line gives in parentheses after `docs/migrations/workspace-nested-layout.md`) and exits 1. Both happen before any question and without touching a file.

`--new` renders a manifest, so it also checks `swift --version`: no `swift` emits `preflight_required_swift_missing`, a toolchain older than 6.0 `preflight_required_swift_too_old`, and either exits 3. `--incorporate` renders no manifest and does not check.

## --new <name>

1. Q&A: archetype, group (if `package_groups` non-empty), `qa_pkg_git_url` per declared remote (`{remote}`, reprompt on empty), `qa_pkg_version` (default 0.1.0), `qa_pkg_deps` (multi-select from existing packages). Right after deps, for each picked dep whose archetype `wsarch::default_allowed <archetype>` does not list, ask `qa_pkg_dep_exception` (`{dep}`, `{dep_archetype}`, `{archetype}`): record it in `allowed_deps` as an exception, or drop it from deps. Then: external_deps (`qa_pkg_external_dep` → loop of `qa_pkg_external_dep_url` and `qa_pkg_external_dep_version`), allowed_deps — further exceptions beyond the ones just resolved, default none.
2. Backup current `workspace.yml` to `.workspace-add.backup.yml`.
3. Update `workspace.yml` (insert package entry under `packages:`).
4. `wsyml::load` the updated file, then `wsyml::validate` + `wsgraph::check_acyclic`. On failure: restore from backup, emit `error_validation`, exit 2. Then see **Url and package name**.
5. Resolve the target dir: `<root>/$(wsdocs::pkg_dir <name>)` — `<root>/<group-dir>/<name>/`, or `<root>/packages/<name>/` if no groups.
6. mkdir the target dir, then `wspkg::render_to <name> <target-dir>`.
7. Run `workspace-docs-regen` from `<root>`. It fills the new package's marked sections and the two dependency arrays of its `Package.swift`, and adds the package to the meta-repo docs, the `REPOS` blocks of `.gitignore` and `bootstrap.sh`, the repo map in `SPINE.md`, the `.xcworkspace` and the `.code-workspace`; running it before the commit puts the filled sections in the package's first commit.
8. `git init -b <default-branch>`. If `bootstrap.commit_after_init: true` (read from `workspace.yml`): `git add -A && git commit -m <msg>`.
9. Optional: if `--push` flag AND `bootstrap.use_gh: true`: `gh repo create` + `git push -u remotes[0]`.
10. Emit `report_success_new`.

## --incorporate <path>

1. Read target's `Package.swift` to extract package name. If `--name <override>` supplied, use that; else use parsed name.
2. Read target's `git remote -v` to detect existing remotes.
3. Q&A: archetype, group (if applicable), allowed_deps (exceptions to the archetype rule), `qa_pkg_git_url` for each declared remote the repo lacks.
4. Check the target dir before touching `workspace.yml`: `<root>/<group-dir>/<name>` (the `dir` of the picked group in `package_groups`), or `<root>/packages/<name>` if no groups. If it already exists: emit `error_fs` and stop, with nothing edited and nothing moved.
5. Backup `workspace.yml`. Update with new package entry.
6. `wsyml::load` the updated file, then `wsyml::validate` + `wsgraph::check_acyclic`. On failure: restore + exit 2. Then see **Url and package name**.
7. Resolve the target dir: `<root>/$(wsdocs::pkg_dir <name>)` (the same folder step 4 checked). If `--symlink` flag: `ln -s <absolute-original-path> <target-dir>`, the link target being the absolute path of the original. Else (default): `mv <original-path> <target-dir>`, creating the parent dir first. A symlinked package is listed in `.gitignore` and `bootstrap.sh` like any other.
8. **Soft mutate** target package files. Never call `wspkg::render_to` on an incorporated package — it
   renders the whole package template and would overwrite the user's `Package.swift` and `Sources/`.
   - If `<target-dir>/CLAUDE.md` does NOT exist → render only `<platform-root>/templates/workspace/package/CLAUDE.md.tmpl`
     with `{{PACKAGE_NAME}}` substituted, to `<target-dir>/CLAUDE.md`, `git add` it (no commit).
   - If exists → emit `warn_existing_claude_md`.
9. Run `workspace-docs-regen` from `<root>`: it adds the package to the meta-repo docs, the `REPOS` blocks of `.gitignore` and `bootstrap.sh`, the repo map in `SPINE.md` and the workspace files, and fills the marked sections the package's docs have. An incorporated package's `Package.swift` carries no markers, so its dependencies stay its own; `workspace-docs-regen --adopt --pkg <name>` proposes them when the manifest is in the shape this plugin's template renders.
10. Emit `report_success_incorporate`.

## Url and package name

After the url Q&A, in both modes, with the entry in `workspace.yml` loaded, run `wspkg::url_matches_name <name>`. Exit 1 means the last component of the url under the first declared remote, without `.git`, is not `<name>`: emit `warn_url_name_mismatch` (`{pkg}`, `{url}`) and go on. Exit 2 means the package has no url under that remote: say nothing. The warning matters because Xcode replaces a remote package with a local folder only when the folder name equals the repository name (the last url component): on a mismatch the local copy is silently ignored and the remote one is used. It never stops the command: `bootstrap.sh` still clones into `<root>/<pkg_dir>` whatever the repository is called.

## Failure recovery

`workspace-add` is single-shot (no state file). On any error: restore `workspace.yml` from `.workspace-add.backup.yml`. FS changes (created dirs) are kept; print FS-touch list. User can `rm -rf` and retry.
