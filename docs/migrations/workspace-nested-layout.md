# Migrating a workspace to the nested layout

Up to 1.32.0, `workspace-init` put the meta repo in a `<name>-meta/` folder beside the app and the
packages:

```
develop/
├── <name>-meta/        ← meta repo: workspace.yml, .xcworkspace, SPINE.md, CLAUDE.md, ...
├── <app-repo>/         ← its own SPINE.md, CLAUDE.md, AGENTS.md, DocsMap.md
└── packages/<pkg>/
```

Now the meta repo is the workspace folder itself, and every other repository sits under it, kept out
of the meta repo by its `.gitignore`:

```
develop/                ← meta repo; launch claude / codex here
├── .gitignore          ← one line per app and package repo (generated)
├── workspace.yml, bootstrap.sh
├── SPINE.md, CLAUDE.md, AGENTS.md, DocsMap.md      ← the one config for every repository
├── README.md, ARCHITECTURE.md, CONTRIBUTING.md
├── <Name>.xcworkspace, <Name>.code-workspace
├── Tasks, Docs
├── <app-repo>/         ← no SPINE.md, DocsMap.md, AGENTS.md or Tasks/Docs links
└── packages/<pkg>/     ← or <group-dir>/<pkg>
```

The workspace commands refuse the old layout and point here. There is no command that migrates: you
move the files by hand, in the order below. The app repositories do not move, so the paths from an
app to its packages (`../packages/<pkg>` in `project.yml`) stay what they are.

Every command below runs from the workspace folder — the one that holds `<name>-meta/` today — unless
it says otherwise. The code blocks carry no comments, so they paste into a zsh that has
`interactivecomments` off. Set these once in that shell, each value edited to your workspace: `P` is
the folder of the installed `spine-platform-swift` plugin, the release that ships this layout (in
Claude Code, under `~/.claude/plugins/cache/spine/spine-platform-swift/`); `NAME` is `workspace.name`;
`M` the meta folder; `APP` the app repo's folder; `PKGS` the folder that holds the packages
(`packages`, or a group's `dir`).

```bash
P=~/.claude/plugins/cache/spine/spine-platform-swift/VERSION
NAME=MyApp
M=myapp-meta
APP=myapp
PKGS=packages
```

## Before you start

1. **The plugin ships the nested layout.** Such a release refuses the old layout: run from inside
   `$M` (the folder name may differ from `workspace.name` in case, as `myapp-meta` would for `MyApp`),
   `--check` exits 4 and names this guide, writing nothing:

   ```bash
   (cd "$M" && "$P/scripts/workspace-docs-regen.zsh" --check); echo "exit $?"
   ```

2. **Every repository is clean.** No modified or staged tracked file in the meta repo, the app repo or
   any package:

   ```bash
   for r in "$M" "$APP" "$PKGS"/*; do echo "== $r"; git -C "$r" status --short; done
   ```

   Commit or discard every `M` line first. An untracked `??` entry is fine if you know what it is —
   build output (`.build/`, `.swiftpm/`) and Xcode state move with their folders.

3. **Write down where every repository is**, so that `## Rollback` can return to it. The file sits
   beside the workspace folder, outside every repository:

   ```bash
   for r in "$M" "$APP" "$PKGS"/*; do printf '%s %s\n' "$r" "$(git -C "$r" rev-parse HEAD)"; done \
     > "../$NAME-migration-heads.txt"
   ```

4. Nothing is pushed until step 6 passes. Until then everything here can be undone.

## General order

### 1. Move the meta repo up

List what the meta repo tracks that already has a namesake in the workspace folder. Each name this
prints needs a decision before the move — the project sections below say which:

```bash
for f in $(git -C "$M" ls-files | cut -d/ -f1 | sort -u); do
  { [ -e "$f" ] || [ -L "$f" ]; } && echo "already here: $f"
done
```

Then move `.git` and every tracked top-level entry up, recording each moved name for `## Rollback`.
Use `mv`, not `git mv`: the repository itself changes folders, so to git the files never move — they
are where its index says they are once `.git` sits in the parent. An entry that already has a
namesake here stays in `$M`.

```bash
mv "$M/.git" .
for f in $(git ls-files | cut -d/ -f1 | sort -u); do
  [ -e "$f" ] || [ -L "$f" ] || { mv "$M/$f" . && echo "$f" >> "../$NAME-migration-moved.txt"; }
done
```

Look at what is left in `$M`:

```bash
ls -A "$M"
```

It may hold `.DS_Store` and the entries step 1 reported as already here; nothing else. Anything else
is a file the meta repo did not track but you keep — move it to the root by hand first. The next
command deletes `$M` only when nothing else is left, and otherwise names what is:

```bash
left="$(cd "$M" && for f in $(ls -A); do [ "$f" = .DS_Store ] || [ -e "../$f" ] || [ -L "../$f" ] || echo "$f"; done)"
if [ -z "$left" ]; then rm -rf "$M"; else echo "still in $M: $left"; fi
```

`git status --short` now lists the app and package folders as untracked; step 5 adds them to
`.gitignore`.

### 2. Assemble the root `SPINE.md`

The root `SPINE.md` is the one config. Its `## Stack` is the app's stack; a second app adds a row to
`## Modules`. Take the app's `SPINE.md` — its `## Stack` is filled, the meta copy's is a placeholder.
Two sections pointed from one repository to another: the first `awk` drops the old
`## Workspace meta` (regen fills a new one between markers), the second drops each `## Paths` line
that climbed out of a repository (`../packages/*`, `../Tasks`, `../<name>-meta`):

```bash
cp "$APP/SPINE.md" SPINE.md
awk '/^## Workspace meta$/ {skip = 1; next} skip && /^## / {skip = 0} !skip' SPINE.md > SPINE.md.new && mv SPINE.md.new SPINE.md
awk '/^## / {inpaths = ($0 == "## Paths")} inpaths && /^- [^:]+: \.\.\// {next} {print}' SPINE.md > SPINE.md.new && mv SPINE.md.new SPINE.md
```

The app's `- Sources:` and `- Tests:` lines were relative to the app repo; prefix each with
`/<app-repo>/`, e.g. `- Sources: MyApp` becomes `- Sources: /myapp/MyApp`. Then add
the root's own lines — `- External packages: /<group-dir>/*`, `- Roots: /Tasks`, `- Roots: /Docs` —
and the empty `## Workspace meta` with its markers:

```bash
zsh -c 'P="$1"; for f in workspace-yml-parser workspace-docs workspace-doc-markers workspace-project; do
  source "$P/templates/workspace/lib/$f.zsh"; done
  wsyml::load workspace.yml && wsproj::append_paths . && wsproj::append_workspace_meta .' _ "$P"
```

A workspace whose config still has the swift-toolkit name `CLAUDE-swift-toolkit.md` has no
`SPINE.md` to copy: run `/setup` from the root instead (see `## Special cases`), then the two sections
as above.

`CLAUDE.md` and `AGENTS.md` came up with the meta repo. `CLAUDE.md` must import the config
(`@./SPINE.md`); `AGENTS.md` points Codex at `SPINE.md`. Keep `DocsMap.md` from the meta repo, or
from the app when the app's declares components.

### 3. Strip the config out of the app repo

The app repo keeps no config of its own: remove `SPINE.md`, `DocsMap.md`, `AGENTS.md` and the
`Tasks`/`Docs` links. Its `CLAUDE.md` goes too when it holds nothing but the import and the template
comment; otherwise delete only the `@./SPINE.md` line. Name in `git rm` only the files the app repo
has, and make one commit:

```bash
git -C "$APP" rm SPINE.md DocsMap.md AGENTS.md Tasks Docs CLAUDE.md
git -C "$APP" commit -m "chore: move the spine config to the workspace root"
```

### 4. Declare the app's folder and remote in `workspace.yml`

The app's clone url is the one its `origin` names; `yq` reads it from the environment:

```bash
URL="$(git -C "$APP" remote get-url origin)" yq -i '.project.apps.ios.dir = "." | .project.apps.ios.git = {"origin": strenv(URL)}' workspace.yml
```

`dir: .` is the default and puts the app repo directly under the root. `git` is what `bootstrap.sh`
clones; an app with no remote leaves it out (only `dir` is set, see `## Special cases`),
and bootstrap then says `skip` for it on a machine where it is missing.

`tasks.path`, `docs.path` and `symlink_target` are now counted from the root. They used to be counted
from the folder that held `<name>-meta/` — the folder that is now the root — so a value that worked
before keeps working. Check that each link resolves:

```bash
ls Tasks/ Docs/
```

### 5. Regenerate, then bootstrap

The meta repo needs two files the old layout did not have: the marker pair regen fills with the
repositories `.gitignore` keeps out, and `bootstrap.sh`:

```bash
printf '%s\n' '# WORKSPACE_REPOS_BEGIN' '# WORKSPACE_REPOS_END' >> .gitignore
sed "s|{{WORKSPACE_NAME}}|$NAME|g" "$P/templates/workspace/meta-repo/bootstrap.sh.tmpl" > bootstrap.sh
chmod +x bootstrap.sh
```

`--adopt` puts markers around the sections an older workspace kept outside them (`## Quickstart`,
`## Daily ops`, `## Schema` in `README.md`, `## Archetype rules` in `CONTRIBUTING.md`, the first
paragraph of `## Boundary contract` and `## Public API` in each package `CLAUDE.md`). Run it once
without `--yes` and read what it proposes — a package whose boundary paragraph is your own text loses
it to the archetype's standard sentence — then apply, then regenerate:

```bash
"$P/scripts/workspace-docs-regen.zsh" --adopt
"$P/scripts/workspace-docs-regen.zsh" --adopt --yes
"$P/scripts/workspace-docs-regen.zsh"
```

The last run must end with `regenerated=0 drifted=0 malformed=0`. A line `<pkg>/Package.swift: not
the shape the package template renders` means the manifest's dependency arrays stay yours; nothing
else follows from it. Regen rewrites the `.xcworkspace`, the folders of the `.code-workspace`,
`README.md`, `ARCHITECTURE.md`, the `REPOS` blocks of `.gitignore` and `bootstrap.sh`, the repo map
in `SPINE.md`, and in each package `CLAUDE.md` the `**Workspace**:` link (now the path to the root,
`../..`).

```bash
./bootstrap.sh
```

Every line must be `ok <path>` — on this machine every repository is already in place — and the exit
code 0. A repository with no remote (`git: {}`) prints `ok` too while its folder is here; on a machine
without it, bootstrap prints `skip <path> (no remote)`. A `clone` line means a path in `workspace.yml`
does not match the folder on disk; an `error` line names a folder that is not a git repository.

### 6. Check, then commit and push

- `git status --short` at the root lists no app or package folder: only the meta repo's own files.
- `"$P/scripts/workspace-docs-regen.zsh" --check` exits 0. On a fresh clone run it only after
  `./bootstrap.sh`: the `.xcworkspace` refers to the `.xcodeproj` the app folder holds, so before the
  app is cloned the check sees a different file.
- `claude` launched from the root reads a file of the app and a file of a package without asking
  for another directory, and knows the repo map (`## Workspace meta`). The same with `codex`: it reads
  `AGENTS.md` from its git root down to the folder it was launched in, so launch it from the root,
  never from inside an app or package repo.
- Xcode opens `<Name>.xcworkspace` at the root and builds the app scheme with the packages taken from
  their local folders.

Then commit the meta repo, review each package's diff and commit what you keep, and push the meta
repo, the app repo and each package you committed:

```bash
git add -A && git commit -m "chore(workspace): make the meta repo the workspace root"
for r in "$PKGS"/*; do git -C "$r" diff --stat; done
git push && git -C "$APP" push
```

## Rollback

Before the first push, everything returns to the old layout. From the root, with the variables set
as above: put `.git` back into `$M`; reset each repository to the head `## Before you start` recorded
(the meta repo first — that restores every meta file into `$M`); then delete what step 1 moved to the
root, and `bootstrap.sh`:

```bash
mkdir -p "$M" && mv .git "$M/"
while read -r r h; do git -C "$r" reset --hard "$h"; done < "../$NAME-migration-heads.txt"
while read -r f; do rm -rf "./$f"; done < "../$NAME-migration-moved.txt"
rm -f bootstrap.sh
```

`reset --hard` drops the migration commits and every uncommitted change in that repository, which is
why `## Before you start` asks for clean repositories. Deleting the moved `<Name>.xcworkspace` also
deletes the untracked `xcshareddata/` inside it — Xcode's `Package.resolved` for that workspace,
which it writes again on the next package resolution. Files the migration created at the root rather
than moved there go too: `SPINE.md` and `AGENTS.md` written by `/setup` (a pre-split config) and a
`.gitignore` the meta repo did not have. A root file you moved aside comes back from where
you put it. After a push, undo with a new commit in each repository instead.

## Special cases

- **A config under the pre-split name.** Repositories that still carry `CLAUDE-swift-toolkit.md` have
  no `SPINE.md` to copy in step 2. Before running `/setup` from the root, `git rm` that file in the
  meta repo and drop its `@./CLAUDE-swift-toolkit.md` line from the root `CLAUDE.md`; `/setup` then
  writes a fresh `SPINE.md` and its import line. Answer the stack from the app's old config, in the
  current `## Axes` spelling (`MVVM+Coordinator` is `MVVM`; navigation follows the UI). Move any text
  of your own from the old app config — simulator choice, DI conventions, binding rules — into the
  root `CLAUDE.md` under `## Project notes`, reading `../packages/` as `packages/`. Uncommitted edits
  to the old config files can be discarded: the files are removed.
- **A root that already holds `CLAUDE.md` or another file the meta repo tracks.** Step 1 reports it as
  already here. When it only mirrors the meta repo's config, move it aside before step 1
  (`mkdir ../aside && mv CLAUDE.md ../aside/`) and delete it once step 6 passes.
- **A repository with no remote.** The app gets `dir` and no `git`; a package keeps or gets `git: {}`
  (an empty url, `origin: ""`, is rejected). `bootstrap.sh` lists it with no url and prints `skip`
  for it on a machine where it is missing. Nothing is pushed in step 6.
- **`allowed_deps` holding archetype names** (`api-contract`, `engine`, …) from an older workspace:
  the field now takes package names and regen stops on it. Delete the field.
- **A package `CLAUDE.md` you wrote yourself.** `--adopt` wraps its first `## Boundary contract`
  paragraph and its `## Public API`, and regen then replaces them with generated text. Discard that
  file's change after step 5 (`git -C <pkg> checkout -- CLAUDE.md`); without markers regen leaves it
  alone.
- **The meta repo has no `.gitignore`.** Copy the template's, which already holds the marker pair:
  `cp "$P/templates/workspace/meta-repo/.gitignore.tmpl" .gitignore`. Add local tool folders (for
  example `.xcodebuildmcp/`) before the marker pair.
- **An app repo that ignores its `*.xcodeproj/`.** On a fresh clone, run `xcodegen generate` in the
  app folder before opening the root `.xcworkspace`.
- **An app's committed `.xcworkspace` that a script rewrites to switch packages between remote and
  local.** The root `.xcworkspace` now holds the local packages, so the script's local mode is no
  longer needed: restore the app's `.xcworkspace` and `Package.resolved` to their committed state
  (the script's remote mode, or `git checkout --`).
- **Several checkouts of one workspace** (one folder per branch or task): each is its own clone of the
  meta repo followed by `./bootstrap.sh`. A checkout whose `Tasks` is a real folder rather than the
  link the meta repo tracks makes the checkout abort: move the folder aside, check out, then copy its
  content into the shared Tasks target.
