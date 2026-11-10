#!/usr/bin/env bats
# bootstrap.sh of the meta repo: clones what is missing, leaves what is there, and reports in one
# line per repository. The root has a space in its path, so an unquoted expansion fails here.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/ws-test-helpers"

setup() {
  WS_TEST_TMPDIRS=()
  local lib seed
  lib="$(ws_repo_root)/templates/workspace/lib"
  ROOT="$(ws_mktemp_dir)/with space"; mkdir -p "$ROOT"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  for seed in app pkg; do
    git init -q --bare -b main "$ROOT/remotes/$seed.git"
    git clone -q "$ROOT/remotes/$seed.git" "$ROOT/seed-$seed" 2>/dev/null
    git -C "$ROOT/seed-$seed" checkout -q -b main
    echo "$seed" > "$ROOT/seed-$seed/f"
    git -C "$ROOT/seed-$seed" add f
    git -C "$ROOT/seed-$seed" commit -q -m init
    git -C "$ROOT/seed-$seed" push -q origin main
  done
  mkdir "$ROOT/ws"
  cp "$(ws_repo_root)/templates/workspace/meta-repo/bootstrap.sh.tmpl" "$ROOT/ws/bootstrap.sh"
  chmod +x "$ROOT/ws/bootstrap.sh"
  BOOT="$ROOT/ws/bootstrap.sh"
  LIB="$lib"
}

# Usage: fill_repos <lines>  (each line "<path>\t<url>")
fill_repos() {
  printf '%b\n' "$1" | zsh -c "source '$LIB/workspace-doc-markers.zsh'; wsmark::write '$BOOT' REPOS"
}

both_repos() {
  fill_repos "projects/App\t$ROOT/remotes/app.git\npackages/Pkg\t$ROOT/remotes/pkg.git"
}

@test "first run clones every repository and exits 0" {
  both_repos
  run "$BOOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clone projects/App"* ]]
  [[ "$output" == *"clone packages/Pkg"* ]]
  [ -d "$ROOT/ws/projects/App/.git" ]
  [ -d "$ROOT/ws/packages/Pkg/.git" ]
}

@test "second run reports ok and changes nothing" {
  both_repos
  run "$BOOT"
  before="$(git -C "$ROOT/ws/projects/App" rev-parse HEAD)"
  run "$BOOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok projects/App"* ]]
  [[ "$output" == *"ok packages/Pkg"* ]]
  [[ "$output" != *"clone "* ]]
  [ "$(git -C "$ROOT/ws/projects/App" rev-parse HEAD)" = "$before" ]
}

@test "runs from another working directory" {
  both_repos
  cd /
  run "$BOOT"
  [ "$status" -eq 0 ]
  [ -d "$ROOT/ws/projects/App/.git" ]
}

@test "a symlink to a git repository counts as ok" {
  both_repos
  git clone -q "$ROOT/remotes/pkg.git" "$ROOT/elsewhere"
  mkdir -p "$ROOT/ws/packages"
  ln -s "$ROOT/elsewhere" "$ROOT/ws/packages/Pkg"
  run "$BOOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok packages/Pkg"* ]]
}

@test "a plain folder without .git is an error, and the others are still cloned" {
  both_repos
  mkdir -p "$ROOT/ws/packages/Pkg"
  run "$BOOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error packages/Pkg: exists and is not a git repository"* ]]
  [[ "$output" == *"clone projects/App"* ]]
  [ -d "$ROOT/ws/projects/App/.git" ]
}

@test "a line without a url is skipped" {
  fill_repos "projects/App\t$ROOT/remotes/app.git\npackages/Pkg\t"
  run "$BOOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip packages/Pkg (no remote)"* ]]
  [ ! -e "$ROOT/ws/packages/Pkg" ]
}

@test "a failed clone is an error and exits 1" {
  fill_repos "projects/App\t$ROOT/remotes/missing.git\npackages/Pkg\t$ROOT/remotes/pkg.git"
  run "$BOOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"error projects/App: git clone failed"* ]]
  [ -d "$ROOT/ws/packages/Pkg/.git" ]
}

@test "comment and blank lines inside the list are ignored" {
  fill_repos "# a note\n\npackages/Pkg\t$ROOT/remotes/pkg.git"
  run "$BOOT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "the template runs under /bin/bash and is executable in git" {
  both_repos
  run /bin/bash "$BOOT"
  [ "$status" -eq 0 ]
  run git -C "$(ws_repo_root)" ls-files -s templates/workspace/meta-repo/bootstrap.sh.tmpl
  [[ "$output" == 100755* ]]
}
