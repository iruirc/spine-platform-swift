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
source "<platform-root>/templates/workspace/lib/workspace-doc-markers.zsh"
source "<platform-root>/templates/workspace/lib/workspace-docs.zsh"
source "<platform-root>/templates/workspace/lib/workspace-package.zsh"
source "<platform-root>/templates/workspace/lib/workspace-project.zsh"
wsyml::load "<workspace.yml>"
```

`<workspace.yml>` is the `--from` path in batch, and `<root>/workspace.yml` on `--resume` and once
interactive step 10 has written it.

## Workspace root

`<root>` is the folder the command runs in, or the one `--dir <path>` names (relative to the cwd;
created by `s01_meta_dir` when it does not exist). `<root>` is an absolute path: resolve it with
`${root:A}` right after it is chosen, before any step runs, because s06b runs swift-init from inside
`<root>/<app_dir>` and `--config-dir=<root>` would otherwise name a different folder there. The
workspace root IS the meta repo: `git init`
runs in it, and `workspace.yml`, `bootstrap.sh`, `SPINE.md`, `CLAUDE.md`, `AGENTS.md`, the docs and
the `.xcworkspace` live in it. Every app repo sits at `<root>/<app_dir>` (`<app_dir>` is
`wsdocs::app_dir <key>`: `project.apps.<key>.dir`, default `.`, then the repo) and every package at
`<root>/<pkg_dir>` (`wsdocs::pkg_dir <name>`); the meta repo's `.gitignore` keeps them out. There is
no `<name>-meta` folder.

## Language Resolution

`toolkit.lang` comes first: the answer to `qa_toolkit_lang` once the dialog has it, `wsyml::toolkit lang` in batch and `--resume`. Otherwise read `[LANG]` from the meta-repo's project config `<root>/SPINE.md` (or `CLAUDE-spine-toolkit.md` where only that exists). Fallback: the cwd's own project config (`SPINE.md`, else `CLAUDE-spine-toolkit.md`). Fallback: `en`. Use the resolved language for all user-facing strings via `locales/<lang>.md`.

## Modes

- **Interactive** (no flags): full Q&A, render `workspace.yml`, ask for confirmation, then execute.
- **Batch** (`--from <path/to/workspace.yml>`): no Q&A, no confirmation. Validates and executes.
- **Resume** (`--resume`): re-uses persisted `workspace.yml` + state file; skips completed steps.

Each mode takes `--dir <path>` to work in a folder other than the cwd (see **Workspace root**).

## Pre-flight

Always print the pre-flight summary first (using `preflight_*` locale keys):

1. Check `command -v yq` → emit `preflight_required_yq_ok` (with `yq --version`) or `preflight_required_yq_missing`. If missing, exit 3.
2. Check `swift --version` → emit `preflight_required_swift_ok` (with the version) or, when there is no `swift`, `preflight_required_swift_missing`; a toolchain older than 6.0 emits `preflight_required_swift_too_old`. Either failure exits 3: a package manifest is rendered for Swift 6 language mode and never falls back to Swift 5.
3. Check `command -v gh` → emit `preflight_optional_gh_ok` or `preflight_optional_gh_missing` (informational only).
4. Check `command -v xcodegen` → same pattern (informational only at pre-flight time).
5. Check the root: `<root>/workspace.yml` present and `<root>/.workspace-init.state` absent means `<root>` already holds a workspace — emit `error_root_has_workspace` (`{root}`) and exit 4, before any question and without touching a file. A resume has the state file; the one other exception is a batch run whose `--from` is that very `<root>/workspace.yml` while `<root>` has no `.git` yet — a file staged in an empty folder, not a workspace.

## Interactive flow

0. Ask `qa_toolkit_lang` (`en` / `ru`), rendered from both locale files at once. Its default is the language `## Language Resolution` resolves before `toolkit.lang` exists — a config in the cwd, else `en` — so a directory already set to `ru` keeps a Russian dialog by accepting it. Record `toolkit.lang`: it is the language of every later prompt and of the toolkit config.
1. Ask `qa_workspace_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*` regex; reprompt on mismatch.
2. Ask `qa_project_block` (Y/N). If Y:
   1. Ask `qa_project_name` (text). Validate against `[A-Za-z][A-Za-z0-9-]*`; reprompt on mismatch.
   2. Ask the two platforms **as separate Y/N prompts in this exact order** — do NOT combine them into a single multi-select prompt, do NOT mix platform choice with min-version or any other field:
      1. `qa_add_ios_app` (Y/N).
      2. `qa_add_macos_app` (Y/N).
   3. After both answers: if BOTH are N, reprompt both questions from step 2.ii.1 (at least one platform must be selected). Otherwise, for each platform answered Y, in deterministic ios → macos order, ask `qa_app_repo_name` (text). Default value = `{project-name}-{platform}`. Validate against `[A-Za-z][A-Za-z0-9._-]*`.
   4. **Do NOT ask stack Q&A here.** swift-init Q&A (UI framework, DI, architecture, async, min-platform) runs per app during execution phase s06b. Interactive `/workspace-init` MUST delegate the full swift-init Q&A for each declared app — do NOT pass `--no-prompt` in interactive mode. Only batch mode (`--from <yml>`) applies stack defaults silently via `swift-init --no-prompt`.
3. Ask `qa_groups` (Y/N). If Y, repeat-loop: ask `name` + `dir`. Empty `name` ends loop.
4. Ask `qa_remotes` (text, comma-separated). Split + trim.
5. Packages — **iterative loop, ONE package at a time. Do NOT ask "how many packages?" upfront. Do NOT batch multiple package questions into a single prompt.** Each iteration:
   1. Ask `qa_pkg_name` as a free-text prompt that explicitly tells the user that an empty input ends the loop. The locale string already includes this hint — render it verbatim.
   2. If the input is empty:
      - If at least 1 package has been collected so far → exit the loop and continue to step 6.
      - If 0 packages so far → exit the loop when step 2 declared at least one app (a workspace of apps alone is valid), otherwise reprompt: `wsyml::validate` rejects a workspace with neither.
   3. Otherwise, for THIS package only, ask in sequence: `qa_pkg_archetype` (multi-choice), `group` (multi-choice from declared groups, if any), `qa_pkg_git_url` per declared remote (`{remote}`), reprompting on an empty answer, `qa_pkg_version`, `qa_pkg_deps` (multi-select from packages declared in PRIOR iterations). Right after `qa_pkg_deps`, for each picked dep whose archetype `wsarch::default_allowed <this package's archetype>` does not list, ask `qa_pkg_dep_exception` (`{dep}`, `{dep_archetype}`, `{archetype}`): record it in `allowed_deps` as an exception, or drop it from `deps`. Then: external deps (`qa_pkg_external_dep` → nested loop of `qa_pkg_external_dep_url` and `qa_pkg_external_dep_version`), `allowed_deps` — further exceptions beyond the ones just resolved, default none. Record the package.
   4. **Go back to step 5.i** (ask `qa_pkg_name` again, with the same empty-input-ends hint). The loop has no upper bound; the user keeps adding packages until they enter empty input.

   **Anti-pattern to avoid:** presenting "How many packages?" or "Add 1 / 2 / 3 packages?" as a single multi-choice question and then collecting that many in a fixed batch. Always loop with re-prompts.
6. Ask defaults overrides (Y/N) for `default_branch`, `push_remotes`, `release_strategy`. Then, always, ask the stack of the packages this workspace generates — both questions have a default, so accepting them is one keystroke each:
   1. `qa_defaults_platforms` (multi-choice): `ios 17.0 + macos 14.0` (default) / `ios 16.0 + macos 13.0` / `ios 17.0` / custom. Custom asks `qa_defaults_platforms_custom` once more for a comma-separated list (`ios=17.0,macos=14.0`); keys other than `ios` and `macos` are rejected and the question is asked again. Record `defaults.platforms` as a map.
   2. `qa_defaults_tests` (multi-choice): the tokens of `## Spelling` in `spine-platform-swift:test-frameworks`, `swift-testing` the default. Record `defaults.tests`.

   These are the deployment floor and the test stub of every package of this workspace, now and at every later `workspace-add --new`. The `Baseline` axis that `swift-init` asks per app at `s06b` belongs to the app and does not reach them: a package whose floor is above the app's breaks the app's build, so a workspace whose apps target iOS 16 answers `ios 16.0 + macos 13.0` here. `defaults.tests` goes the other way — it reaches the apps too, as the `--tests` swift-init is invoked with. A package and an app on different frameworks both build, which is exactly why the two drift apart unnoticed; an app that really wants its own framework declares `apps.<key>.stack.tests` and overrides the default in batch mode.
7. Ask the Tasks/ block (Y/N, default Y) using `qa_tasks_enabled`. If Y, ask `qa_tasks_mode` (multi-choice: `sibling` / `path` / `symlink`, default `sibling`).
   - `sibling` → record `workspace.tasks.mode = sibling`, `workspace.tasks.path = ./Tasks`. No further prompt.
   - `path` → ask `qa_tasks_path` (text, default `./Tasks`). Validate path: must NOT be absolute (no leading `/`), must NOT contain `..` segments. Reprompt on validation failure. Record `workspace.tasks.mode = path`, `workspace.tasks.path = <answer>`.
   - `symlink` → ask `qa_tasks_symlink_target` (text, required, non-empty). The value may be relative (allowed to contain `..` segments) or absolute. Record `workspace.tasks.mode = symlink`, `workspace.tasks.symlink_target = <answer>`, `workspace.tasks.path = ./Tasks` (used as the link name in `<root>`).
   - If the top-level answer was N, set `tasks.enabled: false` and skip the mode prompt (s09 will skip at execution).

7b. Ask the Docs/ block (Y/N, default Y) using `qa_docs_enabled`. If Y, ask `qa_docs_mode` (multi-choice: `sibling` / `path` / `symlink`, default `sibling`).
   - `sibling` → record `workspace.docs.mode = sibling`, `workspace.docs.path = ./Docs`. No further prompt.
   - `path` → ask `qa_docs_path` (text, default `./Docs`). Validate path: must NOT be absolute (no leading `/`), must NOT contain `..` segments. Reprompt on validation failure. Record `workspace.docs.mode = path`, `workspace.docs.path = <answer>`.
   - `symlink` → ask `qa_docs_symlink_target` (text, required, non-empty). The value may be relative (allowed to contain `..` segments) or absolute. Record `workspace.docs.mode = symlink`, `workspace.docs.symlink_target = <answer>`, `workspace.docs.path = ./Docs` (used as the link name in `<root>`).
   - If the top-level answer was N, set `docs.enabled: false` and skip the mode prompt (s09b will skip at execution).

7c. Ask `qa_toolkit_mode` (`manual` / `auto`, default `manual`), then `qa_toolkit_progress` (`quiet` / `normal` / `live`, default `normal`). Record `toolkit.mode` and `toolkit.progress`. With `toolkit.lang` these are the answers the first app's swift-init, or `s02b_meta_config` when there is no app, hands to `spine-toolkit:setup`, so execution never asks them.
8. Ask bootstrap (`qa_bootstrap_use_gh`, `qa_bootstrap_push_after_init`, `qa_bootstrap_commit_after_init`). Optional: `initial_commit_message` (default "Initial commit"), `git_author` (text, optional).
9. Render `workspace.yml` to chat (use yq from collected values). Print `confirm_summary_header` + summary table (workspace root `<root>`, which is the meta repo, package count, remote count, tasks-repo path-and-mode or `disabled`, docs-repo path-and-mode or `disabled`, `Toolkit: <lang> · <mode> · <progress>`, will-commit Y/N, will-push Y/N). For `mode: symlink` show the target value next to the path, e.g. `Tasks (symlink → ../../Tasks)`.

   When `project:` block is present, the summary additionally shows:
   - `{N} project repos: {ios=<repo>, macos=<repo>}`
   - `Will trigger /swift-init for: {apps_csv}` (interactive mode only — batch runs swift-init silently with `--no-prompt`)
10. Ask `confirm_prompt` (Y/N). On N, emit `abort_no_changes`, exit 0. On Y, write `workspace.yml` to `<root>/workspace.yml` (creating `<root>` first when `--dir` named a folder that does not exist) and, together with it, an empty `<root>/.workspace-init.state` — an interruption before the first step completes then leaves a run `--resume` can finish, not a folder pre-flight refuses. Load it with `wsyml::load`, validate it with `wsyml::validate` and `wsgraph::check_acyclic`, then continue to **shared execution**.

## Batch flow

1. Open the command as **Platform Root** shows, loading the `--from` path, and run `wsyml::validate`, `wsgraph::check_acyclic`. On any failure, emit `error_validation`, exit 2.
2. Continue to **shared execution**.

## Shared execution

Maintain `<root>/.workspace-init.state` (newline-delimited list of completed step IDs; the meta repo's `.gitignore` ignores it). For each step below: skip if step ID is in state file OR if the idempotency check matches; otherwise execute and append step ID to state file on success. On any failure, emit `error_step_failed`, exit 1 (operational), 2 (schema), 3 (missing dep), 4 (FS).

The table is in execution order. Step IDs are kept from the earlier layout so a state file still names the same steps; only `s02b_meta_config` moved — see its row — and the step that gave each app repo a `## Workspace meta` of its own is gone, since an app repo keeps no config.

| Step | Action | Idempotency check |
|------|--------|-------------------|
| s01_meta_dir | Only when `--dir` named a folder that does not exist: `mkdir -p <root>`. The cwd, or an existing `--dir` folder, is used as it is. | `[[ -d <root> ]]` |
| s02_meta_files | render meta-repo templates from `<platform-root>/templates/workspace/meta-repo/` into `<root>`, recursively (preserves subdir layout). Substitutes `{{WORKSPACE_NAME}}`. Excludes `xcworkspace-contents.xml.tmpl` and `code-workspace.json.tmpl` — `s07_regen` writes those (NOT rendered by s02). `sed … >` writes a new file with the default mode, so `chmod +x <root>/bootstrap.sh` right after rendering it: the meta repo commits it executable, and a fresh clone runs `./bootstrap.sh` as it is. `.gitignore` and `bootstrap.sh` carry an empty `WORKSPACE_REPOS` marker pair that `s07_regen` fills. | per-file `[[ -f ]]`; `bootstrap.sh` also `[[ -x ]]` (present but not executable → only the `chmod +x`) |
| s03_meta_git | `git init -b <default-branch>` in `<root>` | `[[ -d <root>/.git ]]` |
| s04_meta_yml | copy `workspace.yml` into `<root>`; nothing to copy when the source already is `<root>/workspace.yml` (interactive step 10, or a `--from` pointing there) | `[[ -f <root>/workspace.yml ]]` |
| s05_groups | mkdir each `package_groups[].dir` under `<root>`; also mkdir `<root>/packages/` when there are no groups AND at least one package (an app-only workspace with zero packages creates no `packages/`) | dir exists |
| s06_pkg_<name> | per-package: `<pkg-dir>` is `<root>/$(wsdocs::pkg_dir <name>)`. mkdir `<pkg-dir>`, then `wspkg::render_to <name> <pkg-dir>` renders `<platform-root>/templates/workspace/package/` into it — placeholders, the `Tests/` variant `wspkg::tests_kind` names, `.gitignore`; the dependency marker pairs stay empty for `s07_regen`. A `<pkg-dir>` holding a `Package.swift` but no `.git` is this step's own interrupted render — remove that directory and render again. `git init`. | dir + `.git` exist |
| s06b_project_<app> | **Pre-condition:** `command -v xcodegen` — emit `error_xcodegen_missing` and exit 3 if missing. Then `mkdir -p <root>/<app_dir>` and, from inside it, invoke `swift-init $(wsproj::swift_init_flags <key> interactive <root>)` in interactive mode and `swift-init $(wsproj::swift_init_flags <key> batch <root>)` in batch mode. The function passes `--main-target-name=<apps.<key>.repo>` in both, so each platform's `.xcodeproj` is named after its repo and the two do not collide in one xcworkspace. **Interactive** runs the full swift-init Q&A: `apps.<key>.stack` is not applied, and `--tests` is passed only as the question's default, since the workspace already asked it at step 6.2 (`agents/swift-init.md`, "Flags present without `--no-prompt`"). **Batch** adds `--no-prompt` and the axes `apps.<key>.stack` sets; swift-init supplies its per-platform defaults for the rest. Both end with `--config-dir=<root>`: the config lives in the root, not in the app repo. The first app finds no `<root>/SPINE.md`, and its swift-init has `spine-toolkit:setup` write it in `<root>` with this app's stack as `## Stack`; every later app finds it, and its swift-init adds one `## Modules` row with `wsproj::append_module`. The app repo gets no `SPINE.md`, `CLAUDE.md`, `AGENTS.md` or `DocsMap.md`. swift-init has finished once `<root>/<app_dir>/project.yml` is on disk and `<root>/SPINE.md` names its `## Platform`; every app but the first (the first is the first line of `wsdocs::apps`, whose swift-init wrote the config) also needs its `## Modules` row. **Re-entry** — `project.yml` is already there and only that row is missing (swift-init stopped between the project and `wsproj::append_module`): do NOT run swift-init over the existing app, which may refuse or overwrite it. Only run `wsproj::append_module <root> <key> <Axis=value>...`: in batch with the axes of `project.apps.<key>.stack` and swift-init's per-platform defaults for the rest, spelled as `agents/swift-init.md` "Flag values in `## Stack`" spells them; in interactive mode emit `note_app_stack_reconfirm` (`{app}`, `{stack}`) with the same values, take the user's confirmed or corrected stack, then append. main-target-name for downstream steps = `apps.<key>.repo`. Per-project `Tasks/` MUST NOT be created — `--tasks=skip` is in both flag sets, and the shared Tasks/ repo is provisioned in s09 instead. | `[[ -f <root>/<app_dir>/project.yml ]] && grep -q '^## Platform$' <root>/SPINE.md && { [[ <key> == $(wsdocs::apps \| head -n 1 \| cut -d' ' -f1) ]] \|\| grep -qF -- "- <repo>: /<app_dir>" <root>/SPINE.md; }` |
| s06c_project_inject_<app> | `wsproj::inject_deps <root>/<app_dir> <repo> <key>` (`<repo>` is the main-target-name; the function writes each package's path from the app repo, `wsproj::package_path <key> <pkg>`). Run `xcodegen generate` in `<root>/<app_dir>/` (second xcodegen run regenerates `.xcodeproj` reflecting injected deps). | Always rerun (declarative; state file authoritative for skip — see "State file precedence" below) |
| s06e_project_git_<app> | `git init -b <default-branch>` in `<root>/<app_dir>`. | `[[ -d <root>/<app_dir>/.git ]]` |
| s02b_meta_config | **Runs here, after the last app's `s06e`, not after `s02`:** the first app's swift-init is what normally writes `<root>/SPINE.md`, with that app's stack, and this step only completes it. The config comes from core, never from a template here. (1) Only if `<root>/SPINE.md` is absent — a workspace with no app: invoke `spine-toolkit:setup` with `<root>` as the working directory, filling its `## Input` with `lang`, `mode` and `progress` from `wsyml::toolkit`, `platform = spine-platform-swift`, `stack` = the workspace's own two axes — `Tests` from `defaults.tests` (`wspkg::tests_kind`) and `Baseline` from `defaults.platforms` (`wspkg::platform_floor ios` and `macos`), each spelled as `agents/swift-init.md` "Flag values in `## Stack`" spells it, so `## Stack` never keeps the template's placeholder line — `tasks = skip` and `docs_map = skip` (Tasks/ and Docs/ are provisioned by s09 / s09b). `CLAUDE.md` from s02 already imports the config, and setup leaves it as it is. The condition is for `--resume`: setup finding a config asks whether to overwrite it, and batch has nobody to answer. (2) `wsproj::append_workspace_meta <root>` — the empty `## Workspace meta` pair `s07_regen` fills with the repo map. (3) `wsproj::append_paths <root>` — `## Paths` from the root. | none: (1) is guarded by its condition, (2) by its heading, (3) per line |
| s07_regen | Run `workspace-docs-regen` from `<root>`. It writes `<workspace-name>.xcworkspace` with a `FileRef` per app repo and per package, sets the `folders` of `<workspace-name>.code-workspace`, fills every marked section of the meta-repo and package docs — the `WORKSPACE_REPOS` lists of `.gitignore` and `bootstrap.sh`, and `## Workspace meta` in `SPINE.md` among them — and fills the two dependency arrays of each package's `Package.swift`. It runs after every package and project repo exists, so the refs and each package's `## Public API` are complete. It rewrites `bootstrap.sh` in place, so the mode s02 set survives. | Always rerun (a run with nothing to change writes nothing) |
| s09_tasks | iff `workspace.tasks.enabled` (default `true`): provision Tasks/ per `workspace.tasks.mode`. See "Tasks/Docs provisioning" below for the per-mode behavior. | per-mode (see "Tasks/Docs idempotency") |
| s09b_docs | iff `workspace.docs.enabled` (default `true`): provision Docs/ per `workspace.docs.mode`. See "Tasks/Docs provisioning" below for the per-mode behavior. Skip (mark complete) if the target path at `<root>/<docs-link-name>` already exists as a folder, symlink, or file — preserves manually placed `Docs` symlinks already on disk. | per-mode (see "Tasks/Docs idempotency") |
| s10_meta_initial_commit | iff `bootstrap.commit_after_init`: `git -C <root> add -A && git -C <root> -c user.name=... -c user.email=... commit`. The `.gitignore` s07 filled keeps every app and package repo out, and the Tasks/Docs repos of `sibling` and `path` mode; a Tasks or Docs symlink is a file of the meta repo and goes into this commit. Afterwards `git -C <root> status --porcelain` is empty. | `git -C <root> rev-list HEAD` non-empty |
| s10b_tasks_initial_commit | iff `workspace.tasks.enabled` AND `workspace.tasks.mode != symlink` AND `bootstrap.commit_after_init`: `git -C <tasks-path> add -A && git -C <tasks-path> commit -m <msg>` | `git -C <tasks-path> rev-list HEAD` non-empty |
| s10c_docs_initial_commit | iff `workspace.docs.enabled` AND `workspace.docs.mode != symlink` AND `bootstrap.commit_after_init`: `git -C <docs-path> add -A && git -C <docs-path> commit -m <msg>` | `git -C <docs-path> rev-list HEAD` non-empty |
| s11_pkg_initial_commit_<name> | same per package, in `<root>/<pkg_dir>` | as above |
| s11b_project_initial_commit_<app> | Iff `bootstrap.commit_after_init`: `git -C <root>/<app_dir> add -A && git -C <root>/<app_dir> commit -m <msg>`. | `git -C <root>/<app_dir> rev-list HEAD` non-empty |
| s12_gh_repos | iff `use_gh`: `gh repo create` for the meta repo (`<root>`) + each package + tasks-repo (when `tasks.enabled` AND `tasks.mode != symlink`) + docs-repo (when `docs.enabled` AND `docs.mode != symlink`), register `remotes[0]` URL. Symlink-mode tasks/docs are NEVER registered with `gh repo create` — they point to an external folder whose repo lifecycle is out of scope for workspace-init. | `git -C <root> remote get-url <remotes[0]>` succeeds (per repo, in its own folder) |
| s12b_gh_project_<app> | Iff `bootstrap.use_gh`: `gh repo create` for the app repo in `<root>/<app_dir>`, register `remotes[0]` URL. | `git -C <root>/<app_dir> remote get-url <remotes[0]>` succeeds |
| s13_push | iff `push_after_init`: `git push -u remotes[0] <branch>` per repo (the meta repo in `<root>` + packages + tasks-repo when `tasks.mode != symlink` + docs-repo when `docs.mode != symlink`) | always idempotent |
| s13b_push_project_<app> | Iff `bootstrap.push_after_init`: `git -C <root>/<app_dir> push -u remotes[0] <branch>`. | always idempotent |
| s14_local_skills | iff `generate_local_skills`: render `<root>/.claude/skills/v-*/SKILL.md` shims | per-file `[[ -f ]]` |

After s14, delete `<root>/.workspace-init.state`. Emit `report_success`.

### Tasks/Docs path resolution

For both `tasks` and `docs` blocks, two derived values are used elsewhere in the skill. Every path in the two blocks counts from `<root>`:

- `<tasks-path>` / `<docs-path>` — the location on disk:
  - mode `sibling` → `<root>/Tasks` or `<root>/Docs` (fixed link name).
  - mode `path` → `<root>/<path-without-leading-./>`.
  - mode `symlink` → `<root>/Tasks` or `<root>/Docs` (the symlink itself; its target is `symlink_target`).
- `<tasks-link-name>` / `<docs-link-name>` — the folder name each block provisions under `<root>`; `workspace-docs-regen` uses the same name for the `.code-workspace`'s `folders`:
  - mode `sibling` / `symlink` → `Tasks` or `Docs`.
  - mode `path` → `basename(path)`.
- `symlink_target` — written into the link as it is: a relative target resolves from `<root>`, where the link sits (e.g. `../../myapp-tasks` from a root two levels below the folder that holds `myapp-tasks`).

`wsdocs::gitignore_repos` lists the `sibling` and `path` repos in the meta repo's `.gitignore`, beside the app and package repos; a symlink is not listed, since the meta repo commits it.

### Tasks/Docs provisioning

s09_tasks and s09b_docs share the same per-mode algorithm. Apply with `<block>` ∈ {`tasks`, `docs`}, `<name>` ∈ {`Tasks`, `Docs`}, and `<repo-template>` ∈ {`<platform-root>/templates/workspace/tasks-repo/`, `<platform-root>/templates/workspace/docs-repo/`}:

- mode `sibling`:
  1. `mkdir -p <root>/<name>` (plus the conventional subfolders defined by `<repo-template>` — `TODO/ ACTIVE/ DONE/` for tasks, `architecture/ api/ guides/ notes/` for docs).
  2. Render `<repo-template>` files (substitutes `{{WORKSPACE_NAME}}`).
  3. `git init -b <default-branch>` inside `<root>/<name>`.
- mode `path`:
  1. `mkdir -p <root>/<path-without-leading-./>` (plus the conventional subfolders from `<repo-template>`).
  2. Render `<repo-template>` files into that directory (substitutes `{{WORKSPACE_NAME}}`).
  3. `git init -b <default-branch>` inside that directory.
- mode `symlink`:
  1. `ln -s <symlink_target> <root>/<name>`. The target is NOT created, validated, or modified by workspace-init — it is the user's responsibility. The symlink may dangle at creation time; it will resolve when the target appears.
  2. NO `mkdir`, NO template render, NO `git init`. The target's content lifecycle is out of scope.

The default mode is `sibling`. Tasks and Docs default to `enabled: true` so old `workspace.yml` files (with no `tasks:` or `docs:` block, or with only `enabled`/`path`) keep working — missing fields are filled with `mode: sibling` + `path: ./Tasks` / `./Docs`.

### Tasks/Docs idempotency

For s09_tasks and s09b_docs the idempotency check depends on mode:

- mode `sibling` / `path` → `[[ -d <tasks|docs-path>/.git ]]`.
- mode `symlink` → `[[ -L <root>/<tasks|docs-link-name> ]]` (regular `-L` test; check that it is a symlink, not whether the target exists).

In addition, both s09_tasks and s09b_docs MUST skip (mark complete in state file) if `<root>/<tasks|docs-link-name>` already exists as ANY of: folder, symlink, or file. This protects existing manual layouts (e.g. a hand-placed `Docs -> ../../Docs` symlink before workspace-init was rerun in `--resume` mode).

### Per-app sequencing

When multiple apps are declared in `project.apps` (e.g. ios + macos), execute **per-app full chain** order: `s06b_ios → s06c_ios → s06e_ios → s06b_macos → s06c_macos → s06e_macos`, and `s02b_meta_config` only after the last chain. NOT step-major (`s06b_ios → s06b_macos → s06c_ios → ...`). Reason: failure mid-chain leaves earlier apps in fully-completed state, simplifying recovery boundaries. The order of the apps is also the order of the config: the first chain's swift-init writes `<root>/SPINE.md`, each later one adds its `## Modules` row.

### State file precedence

The `.workspace-init.state` file is the authoritative record of completed steps. Idempotency checks in the table act as fallback when the state file is missing (e.g. deleted by hand).

Skip semantics:
- Step ID present in `.workspace-init.state` → skip.
- Step ID absent + idempotency check matches → mark as completed (write to state file) + skip.
- Otherwise → execute, then on success write step ID to state file.

State file is deleted only after `s14_local_skills` completes successfully.

## --resume

Read `<root>/.workspace-init.state`. If absent or malformed, emit error and exit 1. An empty file is valid — interactive step 10 writes one — and means no step is recorded as done: resume skips only the steps whose idempotency check passes. Otherwise, run the shared execution table — skipping completed step IDs and verifying idempotency for the rest.

For project-block workflows: interruption of swift-init Q&A (Ctrl-C during s06b interactive) leaves state file unmodified; `--resume` re-enters Q&A for the interrupted app. State file marks s06b done only after swift-init returns, `<root>/<app_dir>/project.yml` is on disk and `<root>/SPINE.md` names its `## Platform` — the check in the table. No stack question outlives that point: every value swift-init hands to setup, `--di=plain` included, is one the catalog lists.

## Templates path

`<platform-root>/templates/workspace/` — resolved from this skill as described above. Skill body invokes zsh subshell to copy + interpolate placeholders (`{{WORKSPACE_NAME}}`, etc.), per `## Template substitution rules` below.

## Template substitution rules

- `*.tmpl` files are rendered to their target location with the `.tmpl` suffix stripped.
- Inside each rendered file, `{{...}}` placeholders are substituted via `sed`, for the meta-repo, Tasks and Docs templates.
- Known placeholders:
  - `{{WORKSPACE_NAME}}` — workspace name (`workspace.name` from `workspace.yml`).
- The package template is rendered by `wspkg::render_to` in `templates/workspace/lib/workspace-package.zsh`, never by hand: it owns the package placeholders, the `Tests/` variant and the directory renames.
