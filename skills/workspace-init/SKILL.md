---
name: workspace-init
description: |
  Bootstrap a new multi-package SPM workspace.
  Use when (en): "init workspace", "create workspace", "bootstrap multi-package", "/workspace-init"
  Use when (ru): "создай workspace", "новый workspace", "инициализируй workspace", "/workspace-init"
---

# workspace-init

Bootstraps a new multi-package SPM workspace from an interactive Q&A or a supplied `workspace.yml`. Strict trigger — only activates on the phrases listed in the `description` field.

## Platform Root

`<platform-root>` is the plugin root two directories above this `SKILL.md`. Resolve it from the
loaded skill location, not from the project working directory. This works in both Claude Code and
Codex; every template and script path below is relative to that root. The `ws*::` functions are zsh
libraries in `<platform-root>/templates/workspace/lib/`, one prefix per file (`wsyml::` is
`workspace-yml-parser.zsh`, `wsproj::` is `workspace-project.zsh`).

The functions, and the copy of `workspace.yml` that `wsyml::load` keeps, live only in the shell that
sourced them, and the host starts a fresh shell for each command. Every command that calls a `ws*::`
function therefore opens with:

```zsh
source "<platform-root>/templates/workspace/lib/workspace-yml-parser.zsh"
source "<platform-root>/templates/workspace/lib/workspace-graph.zsh"
source "<platform-root>/templates/workspace/lib/workspace-package.zsh"
source "<platform-root>/templates/workspace/lib/workspace-project.zsh"
wsyml::load "<workspace.yml>"
```

`<workspace.yml>` is the `--from` path in batch, and `<meta>/workspace.yml` on `--resume` and once
interactive step 10 has written it.

## Language Resolution

`toolkit.lang` comes first: the answer to `qa_toolkit_lang` once the dialog has it, `wsyml::toolkit lang` in batch and `--resume`. Otherwise read `[LANG]` from `<workspace-parent>/<meta-repo>/CLAUDE-spine-toolkit.md` if it exists. Fallback: `CLAUDE-spine-toolkit.md` in the cwd. Fallback: `en`. Use the resolved language for all user-facing strings via `locales/<lang>.md`.

## Modes

- **Interactive** (no flags): full Q&A, render `workspace.yml`, ask for confirmation, then execute.
- **Batch** (`--from <path/to/workspace.yml>`): no Q&A, no confirmation. Validates and executes.
- **Resume** (`--resume`): re-uses persisted `workspace.yml` + state file; skips completed steps.

## Pre-flight

Always print the pre-flight summary first (using `preflight_*` locale keys):

1. Check `command -v yq` → emit `preflight_required_yq_ok` (with `yq --version`) or `preflight_required_yq_missing`. If missing, exit 3.
2. Check `swift --version` → emit `preflight_required_swift_ok` (with the version) or, when there is no `swift`, `preflight_required_swift_missing`; a toolchain older than 6.0 emits `preflight_required_swift_too_old`. Either failure exits 3: a package manifest is rendered for Swift 6 language mode and never falls back to Swift 5.
3. Check `command -v gh` → emit `preflight_optional_gh_ok` or `preflight_optional_gh_missing` (informational only).
4. Check `command -v xcodegen` → same pattern (informational only at pre-flight time).

## Interactive flow

0. Ask `qa_toolkit_lang` (`en` / `ru`), rendered from both locale files at once. Its default is the language `## Language Resolution` resolves before `toolkit.lang` exists — a config in the cwd, else `en` — so a directory already set to `ru` keeps a Russian dialog by accepting it. Record `toolkit.lang`: it is the language of every later prompt and of the toolkit config.
1. Ask `qa_workspace_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*` regex; reprompt on mismatch.
2. Ask `qa_project_block` (Y/N). If Y:
   1. Ask `qa_project_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*`; reprompt on mismatch.
   2. Ask the two platforms **as separate Y/N prompts in this exact order** — do NOT combine them into a single multi-select prompt, do NOT mix platform choice with min-version or any other field:
      1. `qa_add_ios_app` (Y/N).
      2. `qa_add_macos_app` (Y/N).
   3. After both answers: if BOTH are N, reprompt both questions from step 2.ii.1 (at least one platform must be selected). Otherwise, for each platform answered Y, in deterministic ios → macos order, ask `qa_app_repo_name` (text). Default value = `{project-name}-{platform}`. Validate against `[A-Za-z][A-Za-z0-9-]*`.
   4. **Do NOT ask stack Q&A here.** swift-init Q&A (UI framework, DI, architecture, async, min-platform) runs per app during execution phase s06b. Interactive `/workspace-init` MUST delegate the full swift-init Q&A for each declared app — do NOT pass `--no-prompt` in interactive mode. Only batch mode (`--from <yml>`) applies stack defaults silently via `swift-init --no-prompt`.
3. Ask `qa_groups` (Y/N). If Y, repeat-loop: ask `name` + `dir`. Empty `name` ends loop.
4. Ask `qa_remotes` (text, comma-separated). Split + trim.
5. Packages — **iterative loop, ONE package at a time. Do NOT ask "how many packages?" upfront. Do NOT batch multiple package questions into a single prompt.** Each iteration:
   1. Ask `qa_pkg_name` as a free-text prompt that explicitly tells the user that an empty input ends the loop. The locale string already includes this hint — render it verbatim.
   2. If the input is empty:
      - If at least 1 package has been collected so far → exit the loop and continue to step 6.
      - If 0 packages so far → reprompt: `wsyml::validate` rejects a workspace without packages.
   3. Otherwise, for THIS package only, ask in sequence: `qa_pkg_archetype` (multi-choice), `group` (multi-choice from declared groups, if any), one git URL per declared remote, `qa_pkg_version`, `qa_pkg_deps` (multi-select from packages declared in PRIOR iterations), external deps (Y/N → nested loop), `allowed_deps` (default = archetype rule, override Y/N), `qa_pkg_example_app`. Record the package.
   4. **Go back to step 5.i** (ask `qa_pkg_name` again, with the same empty-input-ends hint). The loop has no upper bound; the user keeps adding packages until they enter empty input.

   **Anti-pattern to avoid:** presenting "How many packages?" or "Add 1 / 2 / 3 packages?" as a single multi-choice question and then collecting that many in a fixed batch. Always loop with re-prompts.
6. Ask defaults overrides (Y/N) for `default_branch`, `push_remotes`, `release_strategy`. Then, always, ask the stack of the packages this workspace generates — both questions have a default, so accepting them is one keystroke each:
   1. `qa_defaults_platforms` (multi-choice): `ios 17.0 + macos 14.0` (default) / `ios 16.0 + macos 13.0` / `ios 17.0` / custom. Custom asks `qa_defaults_platforms_custom` once more for a comma-separated list (`ios=17.0,macos=14.0`); keys other than `ios` and `macos` are rejected and the question is asked again. Record `defaults.platforms` as a map.
   2. `qa_defaults_tests` (multi-choice): `swift-testing` (default) / `xctest`. Record `defaults.tests`.

   These are the deployment floor and the test stub of every package of this workspace, now and at every later `workspace-add --new`. The `Baseline` axis that `swift-init` asks per app at `s06b` belongs to the app and does not reach them: a package whose floor is above the app's breaks the app's build, so a workspace whose apps target iOS 16 answers `ios 16.0 + macos 13.0` here.
7. Ask the Tasks/ block (Y/N, default Y) using `qa_tasks_enabled`. If Y, ask `qa_tasks_mode` (multi-choice: `sibling` / `path` / `symlink`, default `sibling`).
   - `sibling` → record `workspace.tasks.mode = sibling`, `workspace.tasks.path = ./Tasks`. No further prompt.
   - `path` → ask `qa_tasks_path` (text, default `./Tasks`). Validate path: must NOT be absolute (no leading `/`), must NOT contain `..` segments. Reprompt on validation failure. Record `workspace.tasks.mode = path`, `workspace.tasks.path = <answer>`.
   - `symlink` → ask `qa_tasks_symlink_target` (text, required, non-empty). The value may be relative (allowed to contain `..` segments) or absolute. Record `workspace.tasks.mode = symlink`, `workspace.tasks.symlink_target = <answer>`, `workspace.tasks.path = ./Tasks` (used as the link name in workspace-parent).
   - If the top-level answer was N, set `tasks.enabled: false` and skip the mode prompt (s09 will skip at execution).

7b. Ask the Docs/ block (Y/N, default Y) using `qa_docs_enabled`. If Y, ask `qa_docs_mode` (multi-choice: `sibling` / `path` / `symlink`, default `sibling`).
   - `sibling` → record `workspace.docs.mode = sibling`, `workspace.docs.path = ./Docs`. No further prompt.
   - `path` → ask `qa_docs_path` (text, default `./Docs`). Validate path: must NOT be absolute (no leading `/`), must NOT contain `..` segments. Reprompt on validation failure. Record `workspace.docs.mode = path`, `workspace.docs.path = <answer>`.
   - `symlink` → ask `qa_docs_symlink_target` (text, required, non-empty). The value may be relative (allowed to contain `..` segments) or absolute. Record `workspace.docs.mode = symlink`, `workspace.docs.symlink_target = <answer>`, `workspace.docs.path = ./Docs` (used as the link name in workspace-parent).
   - If the top-level answer was N, set `docs.enabled: false` and skip the mode prompt (s09b will skip at execution).

7c. Ask `qa_toolkit_mode` (`manual` / `auto`, default `manual`), then `qa_toolkit_progress` (`quiet` / `normal` / `live`, default `normal`). Record `toolkit.mode` and `toolkit.progress`. With `toolkit.lang` these are the answers `s02b_meta_config` hands to `spine-toolkit:setup`, so execution never asks them.
8. Ask bootstrap (`qa_bootstrap_use_gh`, `qa_bootstrap_push_after_init`, `qa_bootstrap_commit_after_init`). Optional: `initial_commit_message` (default "Initial commit"), `git_author` (text, optional).
9. Render `workspace.yml` to chat (use yq from collected values). Print `confirm_summary_header` + summary table (meta-repo dir, package count, remote count, tasks-repo path-and-mode or `disabled`, docs-repo path-and-mode or `disabled`, `Toolkit: <lang> · <mode> · <progress>`, will-commit Y/N, will-push Y/N). For `mode: symlink` show the target value next to the path, e.g. `Tasks (symlink → ../../Tasks)`.

   When `project:` block is present, the summary additionally shows:
   - `{N} project repos: {ios=<repo>, macos=<repo>}`
   - `Will trigger /swift-init for: {apps_csv}` (interactive mode only — batch runs swift-init silently with `--no-prompt`)
10. Ask `confirm_prompt` (Y/N). On N, emit `abort_no_changes`, exit 0. On Y, write `workspace.yml` to `<workspace-parent>/<workspace-name>-meta/workspace.yml`, load it with `wsyml::load`, validate it with `wsyml::validate` and `wsgraph::check_acyclic`, then continue to **shared execution**.

## Batch flow

1. Open the command as **Platform Root** shows, loading the `--from` path, and run `wsyml::validate`, `wsgraph::check_acyclic`. On any failure, emit `error_validation`, exit 2.
2. Continue to **shared execution**.

## Shared execution

Maintain `<workspace-parent>/.workspace-init.state` (newline-delimited list of completed step IDs). For each step below: skip if step ID is in state file OR if the idempotency check matches; otherwise execute and append step ID to state file on success. On any failure, emit `error_step_failed`, exit 1 (operational), 2 (schema), 3 (missing dep), 4 (FS).

| Step | Action | Idempotency check |
|------|--------|-------------------|
| s01_meta_dir | mkdir `<workspace-parent>/<workspace-name>-meta/` | dir exists |
| s02_meta_files | render meta-repo templates from `<platform-root>/templates/workspace/meta-repo/`, recursively (preserves subdir layout). Substitutes `{{WORKSPACE_NAME}}`. Excludes `xcworkspace-contents.xml.tmpl` and `code-workspace.json.tmpl` — `s07_regen` writes those (NOT rendered by s02). | per-file `[[ -f ]]` |
| s02b_meta_config | The config comes from core, never from a template here. (1) Only if `<meta>/CLAUDE-spine-toolkit.md` is absent: invoke `spine-toolkit:setup` with `<meta>` as the working directory, filling its `## Input` with `lang`, `mode` and `progress` from `wsyml::toolkit`, `platform = spine-platform-swift`, `stack = —` (a meta-repo has no stack to ask about), `tasks = skip` and `docs_map = skip` (Tasks/ and Docs/ are workspace siblings, provisioned by s09 / s09b). `CLAUDE.md` from s02 already imports the config, and setup leaves it as it is. The condition is for `--resume`: setup finding a config asks whether to overwrite it, and batch has nobody to answer. (2) `wsproj::append_workspace_meta <meta> meta`. | `grep -q '^## Workspace meta' <meta>/CLAUDE-spine-toolkit.md` |
| s03_meta_git | `git init -b <default-branch>` in meta-repo | `[[ -d .git ]]` |
| s04_meta_yml | copy `workspace.yml` into meta-repo | `[[ -f workspace.yml ]]` |
| s05_groups | mkdir each `package_groups[].dir` (or `packages/` if no groups) under workspace-parent | dir exists |
| s06_pkg_<name> | per-package: mkdir, render `<platform-root>/templates/workspace/package/`, recursively. Rename directory components named `PACKAGE_NAME` → `<name>`, `PACKAGE_NAMETests` → `<name>Tests`. Of the `Tests/` variants render only the one `wspkg::tests_kind` names. Substitute `{{SWIFT_TOOLS_VERSION}}` (`wspkg::tools_version`) and `{{PLATFORMS}}` (`wspkg::platforms_inline`) beside the other placeholders. `git init`. | dir + `.git` exist |
| s06b_project_<app> | **Pre-condition:** `command -v xcodegen` — emit `error_xcodegen_missing` and exit 3 if missing. Then invoke `swift-init` per mode, **always passing `--main-target-name=<apps.<key>.repo>`** so the generated `.xcodeproj` is named after the repo (e.g. `SmokeApp-ios.xcodeproj`) and does NOT collide with the sibling platform's `.xcodeproj` when both are opened in the same xcworkspace: **Interactive mode** — invoke `swift-init --platform=<key> --main-target-name=<repo> --lang=<toolkit.lang> --mode=<toolkit.mode> --progress=<toolkit.progress> --tasks=skip` WITHOUT `--no-prompt` and without `--docs-map`, since whether a project repo keeps a documentation registry is its own question; the user goes through the full swift-init Q&A (UI framework, DI, architecture, async, min-platform). Stack overlay from `apps.<key>.stack` (if user pre-filled in `workspace.yml`) is NOT applied in interactive mode — swift-init owns those decisions. **Batch mode** — invoke `swift-init --no-prompt --platform=<key> --main-target-name=<repo> --lang=<toolkit.lang> --mode=<toolkit.mode> --progress=<toolkit.progress> --tasks=skip [stack-flags]` with values from `apps.<key>.stack` or per-platform defaults (overlay); `--no-prompt` already defaults `--docs-map` to `skip`. The `<toolkit.*>` values come from `wsyml::toolkit`. Output in `<workspace-parent>/<repo-name>/`. swift-init has finished this step once `spine-toolkit:setup` has written `<repo>/CLAUDE-spine-toolkit.md` beside `project.yml` — setup runs after the artifact is on disk, and nothing `s06c` needs comes later. main-target-name for downstream steps = `apps.<platform>.repo`. Per-project `Tasks/` MUST NOT be created — the shared `<workspace-parent>/Tasks/` repo is provisioned in s09 instead. | `[[ -f <repo>/project.yml ]] && grep -q '^## Platform$' <repo>/CLAUDE-spine-toolkit.md` |
| s06c_project_inject_<app> | Source `<platform-root>/templates/workspace/lib/workspace-project.zsh` (`wsproj::*`). Read `wsyml::packages`. Run `wsproj::inject_deps <repo> <main-target-name>`. Run `xcodegen generate` in `<repo>/` (second xcodegen run regenerates `.xcodeproj` reflecting injected deps). | Always rerun (declarative; state file authoritative for skip — see "State file precedence" below) |
| s06d_project_workspace_meta_<app> | Run `wsproj::append_workspace_meta <repo>` to add `## Workspace meta` section to `<repo>/CLAUDE-spine-toolkit.md`. | `grep -q '^## Workspace meta' <repo>/CLAUDE-spine-toolkit.md` |
| s06e_project_git_<app> | `git init -b <default-branch>` in `<repo>`. | `[[ -d <repo>/.git ]]` |
| s07_regen | Run `workspace-docs-regen` from `<meta>`. It writes `<workspace-name>.xcworkspace` with a `FileRef` per app repo and per package, sets the `folders` of `<workspace-name>.code-workspace`, fills every marked section of the meta-repo and package docs, and fills the two dependency arrays of each package's `Package.swift`. It runs after every package and project repo exists, so the refs and each package's `## Public API` are complete. | Always rerun (a run with nothing to change writes nothing) |
| s09_tasks | iff `workspace.tasks.enabled` (default `true`): provision Tasks/ per `workspace.tasks.mode`. See "Tasks/Docs provisioning" below for the per-mode behavior. | per-mode (see "Tasks/Docs idempotency") |
| s09b_docs | iff `workspace.docs.enabled` (default `true`): provision Docs/ per `workspace.docs.mode`. See "Tasks/Docs provisioning" below for the per-mode behavior. Skip (mark complete) if the target path at `<workspace-parent>/<docs-link-name>` already exists as a folder, symlink, or file — preserves manually placed `Docs` symlinks already on disk. | per-mode (see "Tasks/Docs idempotency") |
| s10_meta_initial_commit | iff `bootstrap.commit_after_init`: `git -c user.name=... -c user.email=... commit` | `git rev-list HEAD` non-empty |
| s10b_tasks_initial_commit | iff `workspace.tasks.enabled` AND `workspace.tasks.mode != symlink` AND `bootstrap.commit_after_init`: `git -C <workspace-parent>/<tasks-path> add -A && git -C <workspace-parent>/<tasks-path> commit -m <msg>` | `git -C <workspace-parent>/<tasks-path> rev-list HEAD` non-empty |
| s10c_docs_initial_commit | iff `workspace.docs.enabled` AND `workspace.docs.mode != symlink` AND `bootstrap.commit_after_init`: `git -C <workspace-parent>/<docs-path> add -A && git -C <workspace-parent>/<docs-path> commit -m <msg>` | `git -C <workspace-parent>/<docs-path> rev-list HEAD` non-empty |
| s11_pkg_initial_commit_<name> | same per package | as above |
| s11b_project_initial_commit_<app> | Iff `bootstrap.commit_after_init`: `git -C <repo> add -A && git -C <repo> commit -m <msg>`. | `git -C <repo> rev-list HEAD` non-empty |
| s12_gh_repos | iff `use_gh`: `gh repo create` for meta + each package + tasks-repo (when `tasks.enabled` AND `tasks.mode != symlink`) + docs-repo (when `docs.enabled` AND `docs.mode != symlink`), register `remotes[0]` URL. Symlink-mode tasks/docs are NEVER registered with `gh repo create` — they point to an external folder whose repo lifecycle is out of scope for workspace-init. | `git remote get-url <remotes[0]>` succeeds |
| s12b_gh_project_<app> | Iff `bootstrap.use_gh`: `gh repo create` for `<repo>`, register `remotes[0]` URL. | `git -C <repo> remote get-url <remotes[0]>` succeeds |
| s13_push | iff `push_after_init`: `git push -u remotes[0] <branch>` per repo (meta + packages + tasks-repo when `tasks.mode != symlink` + docs-repo when `docs.mode != symlink`) | always idempotent |
| s13b_push_project_<app> | Iff `bootstrap.push_after_init`: `git -C <repo> push -u remotes[0] <branch>`. | always idempotent |
| s14_local_skills | iff `generate_local_skills`: render `.claude/skills/v-*/SKILL.md` shims | per-file `[[ -f ]]` |

After s14, delete `.workspace-init.state`. Emit `report_success`.

### Tasks/Docs path resolution

For both `tasks` and `docs` blocks, two derived values are used elsewhere in the skill:

- `<tasks-path>` / `<docs-path>` — the location on disk:
  - mode `sibling` → `<workspace-parent>/Tasks` or `<workspace-parent>/Docs` (fixed link name).
  - mode `path` → `<workspace-parent>/<path-without-leading-./>`.
  - mode `symlink` → `<workspace-parent>/Tasks` or `<workspace-parent>/Docs` (the symlink itself; its target is `symlink_target`).
- `<tasks-link-name>` / `<docs-link-name>` — the folder name each block provisions under the workspace parent; `workspace-docs-regen` uses the same name for the `.code-workspace`'s `folders`:
  - mode `sibling` / `symlink` → `Tasks` or `Docs`.
  - mode `path` → `basename(path)`.

### Tasks/Docs provisioning

s09_tasks and s09b_docs share the same per-mode algorithm. Apply with `<block>` ∈ {`tasks`, `docs`}, `<name>` ∈ {`Tasks`, `Docs`}, and `<repo-template>` ∈ {`<platform-root>/templates/workspace/tasks-repo/`, `<platform-root>/templates/workspace/docs-repo/`}:

- mode `sibling`:
  1. `mkdir -p <workspace-parent>/<name>` (plus the conventional subfolders defined by `<repo-template>` — `TODO/ ACTIVE/ DONE/` for tasks, `architecture/ api/ guides/ notes/` for docs).
  2. Render `<repo-template>` files (substitutes `{{WORKSPACE_NAME}}`).
  3. `git init -b <default-branch>` inside `<workspace-parent>/<name>`.
- mode `path`:
  1. `mkdir -p <workspace-parent>/<path-without-leading-./>` (plus the conventional subfolders from `<repo-template>`).
  2. Render `<repo-template>` files into that directory (substitutes `{{WORKSPACE_NAME}}`).
  3. `git init -b <default-branch>` inside that directory.
- mode `symlink`:
  1. `ln -s <symlink_target> <workspace-parent>/<name>`. The target is NOT created, validated, or modified by workspace-init — it is the user's responsibility. The symlink may dangle at creation time; it will resolve when the target appears.
  2. NO `mkdir`, NO template render, NO `git init`. The target's content lifecycle is out of scope.

The default mode is `sibling`. Tasks and Docs default to `enabled: true` so old `workspace.yml` files (with no `tasks:` or `docs:` block, or with only `enabled`/`path`) keep working — missing fields are filled with `mode: sibling` + `path: ./Tasks` / `./Docs`.

### Tasks/Docs idempotency

For s09_tasks and s09b_docs the idempotency check depends on mode:

- mode `sibling` / `path` → `[[ -d <workspace-parent>/<tasks|docs-path>/.git ]]`.
- mode `symlink` → `[[ -L <workspace-parent>/<tasks|docs-link-name> ]]` (regular `-L` test; check that it is a symlink, not whether the target exists).

In addition, both s09_tasks and s09b_docs MUST skip (mark complete in state file) if `<workspace-parent>/<tasks|docs-link-name>` already exists as ANY of: folder, symlink, or file. This protects existing manual layouts (e.g. a hand-placed `Docs -> ../../Docs` symlink before workspace-init was rerun in `--resume` mode).

### Per-app sequencing

When multiple apps are declared in `project.apps` (e.g. ios + macos), execute **per-app full chain** order: `s06b_ios → s06c_ios → s06d_ios → s06e_ios → s06b_macos → s06c_macos → ...`. NOT step-major (`s06b_ios → s06b_macos → s06c_ios → ...`). Reason: failure mid-chain leaves earlier apps in fully-completed state, simplifying recovery boundaries.

### State file precedence

The `.workspace-init.state` file is the authoritative record of completed steps. Idempotency checks in the table act as fallback when the state file is missing (e.g. deleted by hand).

Skip semantics:
- Step ID present in `.workspace-init.state` → skip.
- Step ID absent + idempotency check matches → mark as completed (write to state file) + skip.
- Otherwise → execute, then on success write step ID to state file.

State file is deleted only after `s14_local_skills` completes successfully.

## --resume

Read `.workspace-init.state`. If absent or malformed, emit error and exit 1. Otherwise, run the shared execution table — skipping completed step IDs and verifying idempotency for the rest.

For project-block workflows: interruption of swift-init Q&A (Ctrl-C during s06b interactive) leaves state file unmodified; `--resume` re-enters Q&A for the interrupted app. State file marks s06b done only after swift-init returns and `<repo>/CLAUDE-spine-toolkit.md` names its `## Platform` — the check in the table.

## Templates path

`<platform-root>/templates/workspace/` — resolved from this skill as described above. Skill body invokes zsh subshell to copy + interpolate placeholders (`{{WORKSPACE_NAME}}`, `{{PACKAGE_NAME}}`, etc.) using sed.

## Template substitution rules

- `*.tmpl` files are rendered to their target location with the `.tmpl` suffix stripped.
- The package template tree (`<platform-root>/templates/workspace/package/`) is walked recursively. Directory components literally named `PACKAGE_NAME` are renamed to `<name>`, and `PACKAGE_NAMETests` to `<name>Tests` (the longer form must be substituted first).
- Inside each rendered file, `{{...}}` placeholders are substituted via `sed`.
- A template named `<base>.<variant>.tmpl` renders to `<base>` only when `<variant>` equals
  `defaults.tests`; the other variants are skipped. The variants are the tokens of `## Spelling` in
  `spine-platform-swift:test-frameworks`, and the `Tests/` stub is the only template that has them.
- Known placeholders:
  - `{{WORKSPACE_NAME}}` — workspace name (`workspace.name` from `workspace.yml`).
  - `{{PACKAGE_NAME}}` — package name (per-package).
  - `{{VERSION}}` — package version (semver-like string).
  - `{{SWIFT_TOOLS_VERSION}}` — the machine's toolchain, from `wspkg::tools_version`; never a hardcoded number.
  - `{{PLATFORMS}}` — the value of `platforms:` on one line, from `wspkg::platforms_inline`.
  - `{{TEST_FRAMEWORK_MANIFEST_DEPS}}` and `{{TEST_FRAMEWORK_TARGET_DEPS}}` — the packages the chosen
    test framework needs, from `wspkg::test_framework_manifest_deps` and
    `wspkg::test_framework_target_deps`. Each sits alone on its line, and unlike the placeholders
    above, an empty value removes the line instead of blanking it: a framework that ships with the
    toolchain leaves the manifest exactly as the template wrote it.
- Marker pairs render empty; `s07_regen` fills them.
