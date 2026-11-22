#!/usr/bin/env bash
# Tests for bin/project-tree. Each case builds a project in a temporary folder
# with its own git config, so nothing outside it is read or changed.
#   bash tests/cli.test.sh            run every case
#   bash tests/cli.test.sh <pattern>  run the cases whose name holds <pattern>
set -uo pipefail

PT="$(cd "$(dirname "$0")/.." && pwd)/bin/project-tree"
ONLY=${1:-}
PASSED=0
FAILED=0
FAILS=""

fail() { printf '    FAIL: %s\n' "$*"; CASE_OK=0; }
check() { "$@" || fail "$*"; }
eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]${3:+ ($3)}"; }
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2" || fail "missing line [$2] in:"$'\n'"$1"; }
no_line() { ! printf '%s\n' "$1" | grep -qF -- "$2" || fail "unexpected [$2] in:"$'\n'"$1"; }
branches() { git -C "$1" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ' | sed 's/ $//'; }
worktrees() { git -C "$1" worktree list --porcelain | grep -c '^worktree '; }
clean_status() { [ "$(printf '%s\n' "$1" | grep -cvE '^(revision |unpublished 0$)')" = 0 ]; }

# A project: BE (with an origin), FE (no remote), services/BFF (nested), and
# files outside the repos, a name with a space and an included ignored .env.
make_project() {
  local r
  export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig" GIT_CONFIG_NOSYSTEM=1
  git config --global user.name test && git config --global user.email test@example.com
  git config --global init.defaultBranch main
  P="$SANDBOX/proj"
  mkdir -p "$P"
  for r in BE FE services/BFF; do
    mkdir -p "$P/$r"
    git -C "$P/$r" init -q
    printf 'hello %s\n' "$r" > "$P/$r/readme.md"
    printf '.env\nnode_modules/\n' > "$P/$r/.gitignore"
    git -C "$P/$r" add -A && git -C "$P/$r" commit -qm init
  done
  printf '.env\n' > "$P/BE/.worktreeinclude"
  git -C "$P/BE" add -A && git -C "$P/BE" commit -qm include
  printf 'SECRET=1\n' > "$P/BE/.env"
  git init -q --bare "$SANDBOX/be-origin.git"
  git -C "$P/BE" remote add origin "$SANDBOX/be-origin.git"
  git -C "$P/BE" push -q origin main 2>/dev/null
  git -C "$P/BE" remote set-head origin main
  printf '# proj\n' > "$P/CLAUDE.md"
  mkdir -p "$P/.claude" "$P/my scripts"
  printf '{}\n' > "$P/.claude/settings.json"
  printf 'echo run\n' > "$P/my scripts/run me.sh"
}

run_case() {
  local name=$1
  [ -z "$ONLY" ] || case "$name" in *"$ONLY"*) ;; *) return 0 ;; esac
  printf '  %s\n' "$name"
  SANDBOX=$(cd "$(mktemp -d)" && pwd -P)
  CASE_OK=1
  # A case fails by printing FAIL; its last command's status is not a verdict
  # (`cmd && fail ...` ends non-zero when cmd rightly fails).
  (cd "$SANDBOX" && make_project || { echo "    FAIL: could not build the project"; exit 1; }; "case_$name"; true) \
    > "$SANDBOX/out" 2>&1
  grep -q '    FAIL:' "$SANDBOX/out" && CASE_OK=0
  if [ $CASE_OK -eq 1 ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    FAILS="$FAILS $name"
    sed 's/^/    | /' "$SANDBOX/out"
  fi
  rm -rf "$SANDBOX"
}

# ------------------------------------------------------------------ cases ---

case_creates_one_worktree_per_repo() {
  local out tree
  out=$("$PT" create feat-a --from "$P" --base head) || fail "create failed"
  tree=$(printf '%s\n' "$out" | sed -n 1p)
  eq "$tree" "$SANDBOX/proj.trees/feat-a"
  for r in BE FE services/BFF; do
    eq "$(git -C "$tree/$r" branch --show-current)" feat-a "$r branch"
    eq "$(git -C "$tree/$r" rev-parse --git-common-dir)" "$P/$r/.git" "$r shares the repo"
  done
  check [ -f "$tree/CLAUDE.md" ]
  check [ -f "$tree/.claude/settings.json" ]
  check [ -f "$tree/my scripts/run me.sh" ]
  eq "$(cat "$tree/BE/.env")" "SECRET=1" ".worktreeinclude copy"
  check [ ! -e "$tree/FE/.env" ]
  check [ ! -e "$tree/.git" ]
  eq "$(git -C "$tree/BE" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo none)" none "no upstream"
}

case_create_twice_is_the_same_tree() {
  local a b
  a=$("$PT" create feat-a --from "$P" --base head) || fail "first create failed"
  echo touched >> "$SANDBOX/proj.trees/feat-a/CLAUDE.md"
  b=$("$PT" create feat-a --from "$P" --base head) || fail "second create failed"
  eq "$b" "$a"
  eq "$(tail -1 "$SANDBOX/proj.trees/feat-a/CLAUDE.md")" touched "the tree is not made again"
}

case_fresh_tree_status_is_clean_with_its_revision() {
  local out st
  out=$("$PT" create feat-a --from "$P" --base head) || fail "create failed"
  st=$("$PT" status "$SANDBOX/proj.trees/feat-a") || fail "status failed"
  has_line "$st" "revision $(printf '%s\n' "$out" | sed -n 2p)"
  has_line "$st" "unpublished 0"
  check clean_status "$st"
}

case_status_reports_every_kind_of_work() {
  local t st
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  echo edit >> "$t/FE/readme.md"
  echo new > "$t/BE/new file.txt"
  echo 'SECRET=2' > "$t/BE/.env"
  echo changed >> "$t/CLAUDE.md"
  rm "$t/.claude/settings.json"
  echo old > "$SANDBOX/old"
  touch -t 202001010000 "$SANDBOX/old"
  mv "$SANDBOX/old" "$t/my scripts/old"
  mkdir -p "$t/BE/notes" && echo idea > "$t/BE/notes/x.md" && echo 'notes/' >> "$t/BE/.git/info/exclude" 2>/dev/null
  mkdir -p "$t/FE/node_modules/p" && echo rebuilt > "$t/FE/node_modules/p/i.js"
  echo junk > "$t/.DS_Store"
  st=$("$PT" status "$t") || fail "status failed"
  has_line "$st" "modified	FE/readme.md"
  has_line "$st" "untracked	BE/new file.txt"
  has_line "$st" "modified	BE/.env"
  has_line "$st" "modified	CLAUDE.md"
  has_line "$st" "deleted	.claude/settings.json"
  has_line "$st" "added	my scripts/old"
  no_line "$st" "node_modules"
  no_line "$st" ".DS_Store"
}

case_status_reports_commits() {
  local t st since
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  since=$(awk '$1 == "since" { print $2 }' "$t/.project-tree")
  (cd "$t/FE" && echo c >> readme.md && git commit -qam c)
  st=$("$PT" status "$t") || fail "status failed"
  no_line "$st" "revision $since"
  has_line "$st" "unpublished 0"
  (cd "$t/BE" && git checkout -q --detach && echo d >> readme.md && git commit -qam d && git checkout -q feat-a)
  st=$("$PT" status "$t") || fail "status failed"
  has_line "$st" "unpublished 0"
  (cd "$t/BE" && git checkout -q --detach && echo e >> readme.md && git commit -qam e)
  st=$("$PT" status "$t") || fail "status failed"
  has_line "$st" "unpublished 1"
}

case_remove_refuses_work_and_discard_removes_it() {
  local t
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  echo edit >> "$t/FE/readme.md"
  "$PT" remove "$t" 2>/dev/null && fail "remove of a tree holding work succeeded"
  check [ -f "$t/FE/readme.md" ]
  eq "$("$PT" remove "$t" --discard)" removed
  check [ ! -e "$t" ]
  check [ ! -e "$SANDBOX/proj.trees" ]
  for r in BE FE services/BFF; do
    eq "$(branches "$P/$r")" main "$r branches after remove"
    eq "$(worktrees "$P/$r")" 1 "$r worktrees after remove"
  done
  eq "$("$PT" remove "$t")" "already removed"
}

case_remove_keeps_branches_with_commits() {
  local t
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  (cd "$t/FE" && echo c >> readme.md && git commit -qam c)
  "$PT" remove "$t" 2>/dev/null && fail "remove of a tree with new commits succeeded without --discard"
  check [ -d "$t/FE" ]
  eq "$("$PT" remove "$t" --discard)" "kept branch feat-a in FE"
  eq "$(branches "$P/FE")" "feat-a main"
  eq "$(branches "$P/BE")" main
  eq "$(git -C "$P/FE" log -1 --format=%s feat-a)" c "the commit is on the branch"
}

case_existing_branch_is_checked_out_and_kept() {
  local t
  git -C "$P/BE" branch feat-a
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  eq "$(git -C "$t/BE" branch --show-current)" feat-a
  eq "$("$PT" remove "$t")" "kept branch feat-a in BE"
  eq "$(branches "$P/BE")" "feat-a main" "a branch it did not make is kept"
}

case_not_a_folder_of_repos_exits_3() {
  "$PT" create x --from "$P/BE" >/dev/null 2>&1
  eq "$?" 3 "inside a repo"
  "$PT" create x --from "$P/FE/." >/dev/null 2>&1
  eq "$?" 3 "inside a repo, dotted"
  mkdir "$SANDBOX/plain"
  "$PT" create x --from "$SANDBOX/plain" >/dev/null 2>&1
  eq "$?" 3 "no repos"
}

case_bad_names_are_refused() {
  local n
  for n in 'a..b' 'x.lock' 'feat a' 'a/' '/a' "$(printf 'x%.0s' $(seq 1 65))"; do
    "$PT" create "$n" --from "$P" >/dev/null 2>&1 && fail "accepted [$n]"
  done
  check [ ! -e "$SANDBOX/proj.trees" ]
}

case_slash_names_use_a_plus_folder() {
  local out
  out=$("$PT" create feature/login --from "$P" --base head) || fail "create failed"
  eq "$(printf '%s\n' "$out" | sed -n 1p)" "$SANDBOX/proj.trees/feature+login"
  eq "$(git -C "$SANDBOX/proj.trees/feature+login/BE" branch --show-current)" feature/login
}

case_failed_create_leaves_nothing() {
  git -C "$P/FE" checkout -q -b busy
  "$PT" create busy --from "$P" --base head >/dev/null 2>&1 && fail "create succeeded with the branch checked out in FE"
  check [ ! -e "$SANDBOX/proj.trees/busy" ]
  check [ ! -e "$SANDBOX/proj.trees/busy.lock" ]
  eq "$(branches "$P/BE")" main "no stray branch in BE"
  eq "$(branches "$P/services/BFF")" main "no stray branch in BFF"
  eq "$(worktrees "$P/BE")" 1 "no stray worktree in BE"
}

case_killed_create_recovers() {
  local pid out
  "$PT" create k --from "$P" --base head >/dev/null 2>&1 &
  pid=$!
  sleep 0.15
  kill -9 $pid 2>/dev/null
  wait $pid 2>/dev/null
  out=$("$PT" create k --from "$P" --base head 2>/dev/null) || fail "create after a kill failed"
  eq "$(printf '%s\n' "$out" | sed -n 1p)" "$SANDBOX/proj.trees/k"
  check [ ! -e "$SANDBOX/proj.trees/k.lock" ]
  check clean_status "$("$PT" status "$SANDBOX/proj.trees/k")"
  eq "$("$PT" remove "$SANDBOX/proj.trees/k")" removed
  eq "$(branches "$P/BE")" main
}

case_parallel_creates_share_one_tree() {
  "$PT" create par --from "$P" --base head > "$SANDBOX/a" 2>/dev/null &
  "$PT" create par --from "$P" --base head > "$SANDBOX/b" 2>/dev/null &
  wait
  eq "$(cat "$SANDBOX/a")" "$(cat "$SANDBOX/b")"
  eq "$(sed -n 1p "$SANDBOX/a")" "$SANDBOX/proj.trees/par"
  eq "$(worktrees "$P/BE")" 2
}

case_fresh_base_starts_from_origin() {
  local t
  git clone -q "$SANDBOX/be-origin.git" "$SANDBOX/other"
  (cd "$SANDBOX/other" && echo up > up.txt && git add up.txt && git commit -qm up && git push -q origin main 2>/dev/null)
  git -C "$P/BE" checkout -q -b local-work
  "$PT" create fresh --from "$P" --base fresh >/dev/null 2>&1 || fail "create failed"
  t="$SANDBOX/proj.trees/fresh"
  check [ -f "$t/BE/up.txt" ]
  eq "$(git -C "$t/BE" rev-parse HEAD)" "$(git -C "$P/BE" rev-parse origin/main)"
  eq "$(git -C "$t/FE" rev-parse HEAD)" "$(git -C "$P/FE" rev-parse HEAD)" "FE has no origin: its HEAD"
}

case_a_tree_made_from_a_tree_sits_beside_it() {
  local out
  "$PT" create one --from "$P" --base head >/dev/null || fail "create failed"
  out=$("$PT" create two --from "$SANDBOX/proj.trees/one" --base head) || fail "create from a tree failed"
  eq "$(printf '%s\n' "$out" | sed -n 1p)" "$SANDBOX/proj.trees/two"
  check [ ! -e "$SANDBOX/proj.trees/one/.project-tree.journal" ]
  eq "$(awk '$1 == "root" { print $2 }' "$SANDBOX/proj.trees/two/.project-tree")" "$P"
}

case_list_shows_each_tree() {
  local out
  "$PT" create clean-one --from "$P" --base head >/dev/null || fail "create failed"
  "$PT" create dirty-one --from "$P" --base head >/dev/null || fail "create failed"
  echo x >> "$SANDBOX/proj.trees/dirty-one/BE/readme.md"
  out=$("$PT" list --from "$P")
  has_line "$out" "clean-one	$SANDBOX/proj.trees/clean-one	clean"
  has_line "$out" "dirty-one	$SANDBOX/proj.trees/dirty-one	changed"
}

case_remove_stops_if_a_repo_fails() {
  local t
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  git -C "$P/FE" worktree lock "$t/FE"
  "$PT" remove "$t" --discard >/dev/null 2>&1 && fail "remove succeeded with FE locked"
  check [ -f "$t/FE/readme.md" ]
  check [ -f "$t/.project-tree" ]
}

case_a_folder_of_only_repos_works() {
  local t
  rm -rf "$P/CLAUDE.md" "$P/.claude" "$P/my scripts" "$P/BE/.env" "$P/BE/.worktreeinclude"
  "$PT" create only --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/only"
  check clean_status "$("$PT" status "$t")"
  eq "$("$PT" remove "$t")" removed
}

case_relative_script_path_works() {
  local t rel
  "$PT" create rel --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/rel"
  rel=$(cd "$(dirname "$PT")/.." && pwd -P)
  eq "$(cd "$rel" && bin/project-tree remove "$t")" removed "remove through bin/project-tree"
}

case_a_large_report_still_keeps_the_tree() {
  local t i
  "$PT" create big --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/big"
  mkdir "$t/BE/gen"
  for i in $(seq 1 3000); do echo "$i" > "$t/BE/gen/a-rather-long-file-name-number-$i.txt"; done
  check [ "$("$PT" status "$t" | wc -c)" -gt 100000 ]
  "$PT" remove "$t" 2>/dev/null && fail "remove of a tree with a 100 KB report succeeded"
  check [ -f "$t/BE/gen/a-rather-long-file-name-number-1.txt" ]
  has_line "$("$PT" list --from "$P")" "big	$t	changed"
}

case_submodule_work_is_reported() {
  local t st
  git init -q "$SANDBOX/lib"
  echo lib > "$SANDBOX/lib/l.txt"
  git -C "$SANDBOX/lib" add -A && git -C "$SANDBOX/lib" commit -qm lib
  git -C "$P/BE" -c protocol.file.allow=always submodule add -q "$SANDBOX/lib" vend 2>/dev/null
  git -C "$P/BE" commit -qm sub
  "$PT" create sub --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/sub"
  git -C "$t/BE" -c protocol.file.allow=always submodule update -q --init 2>/dev/null
  check clean_status "$("$PT" status "$t")"
  echo edit >> "$t/BE/vend/l.txt"
  st=$("$PT" status "$t")
  has_line "$st" "modified	BE/vend"
  "$PT" remove "$t" 2>/dev/null && fail "remove of a tree with a dirty submodule succeeded"
  check [ -f "$t/BE/vend/l.txt" ]
}

case_stash_in_a_tree_is_reported() {
  local t
  echo s > "$P/BE/s.txt" && git -C "$P/BE" add s.txt && git -C "$P/BE" commit -qm s
  echo mine >> "$P/BE/s.txt" && git -C "$P/BE" stash -q
  "$PT" create st --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/st"
  check clean_status "$("$PT" status "$t")"
  echo work >> "$t/BE/s.txt" && git -C "$t/BE" stash -q
  has_line "$("$PT" status "$t")" "modified	BE/(git stash list: stashes on st)"
  "$PT" remove "$t" 2>/dev/null && fail "remove of a tree with a stash succeeded"
}

case_odd_names_are_never_read_as_clean() {
  local t
  "$PT" create odd --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/odd"
  printf 'precious\n' > "$t/$(printf 'notes\tv2.txt')"
  "$PT" status "$t" >/dev/null 2>&1 && fail "status succeeded with a tab-named file"
  "$PT" remove "$t" >/dev/null 2>&1 && fail "remove succeeded with a tab-named file"
  check [ -f "$t/$(printf 'notes\tv2.txt')" ]
  printf 'x\n' > "$P/$(printf 'bad\tname')"
  "$PT" create odd2 --from "$P" --base head >/dev/null 2>&1 && fail "create succeeded with a tab-named file"
  check [ ! -e "$SANDBOX/proj.trees/odd2" ]
}

case_empty_folders_and_exec_bits_count() {
  local t st
  mkdir "$P/empty"
  "$PT" create perm --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/perm"
  check clean_status "$("$PT" status "$t")"
  chmod +x "$t/my scripts/run me.sh"
  mkdir "$t/new-empty"
  rmdir "$t/empty"
  st=$("$PT" status "$t")
  has_line "$st" "modified	my scripts/run me.sh"
  has_line "$st" "added	new-empty"
  has_line "$st" "deleted	empty"
}

case_locks_in_the_way_are_handled() {
  mkdir -p "$SANDBOX/proj.trees"
  : > "$SANDBOX/proj.trees/l1.lock"
  "$PT" create l1 --from "$P" --base head >/dev/null 2> "$SANDBOX/err" && fail "create succeeded with a file as its lock"
  grep -q 'is in the way' "$SANDBOX/err" || fail "no clear message for a file lock: $(cat "$SANDBOX/err")"
  mkdir "$SANDBOX/proj.trees/l2.lock" && echo 1 > "$SANDBOX/proj.trees/l2.lock/pid"
  "$PT" create l2 --from "$P" --base head >/dev/null 2>&1 &
  sleep 1
  check [ ! -e "$SANDBOX/proj.trees/l2/.project-tree" ]
  kill %1 2>/dev/null
  wait 2>/dev/null
}

case_list_and_status_work_from_subfolders() {
  local out t
  "$PT" create sub-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/sub-a"
  mkdir -p "$t/BE/src" "$P/BE/deep"
  for w in "$P" "$P/BE/deep" "$t" "$t/BE/src"; do
    out=$(cd "$w" && "$PT" list --from .)
    has_line "$out" "sub-a	$t	clean"
  done
  out=$(cd "$t/BE/src" && "$PT" status .) || fail "status from a tree subfolder failed"
  has_line "$out" "unpublished 0"
  (cd "$t/BE/src" && "$PT" remove .) >/dev/null 2>&1 && fail "remove resolved a subfolder upward"
  check [ -f "$t/.project-tree" ]
}

case_status_and_remove_take_a_tree_name() {
  local out
  "$PT" create feature/login --from "$P" --base head >/dev/null || fail "create failed"
  "$PT" create plain --from "$P" --base head >/dev/null || fail "create failed"
  echo w >> "$SANDBOX/proj.trees/feature+login/FE/readme.md"
  out=$(cd "$P" && "$PT" status feature/login) || fail "status by name failed"
  has_line "$out" "modified	FE/readme.md"
  out=$(cd "$P/BE" && "$PT" status feature/login) || fail "status by name from a repo failed"
  has_line "$out" "modified	FE/readme.md"
  (cd "$P" && "$PT" remove feature/login) >/dev/null 2>&1 && fail "remove by name of a tree holding work succeeded"
  eq "$(cd "$P" && "$PT" remove plain)" removed
  check [ ! -e "$SANDBOX/proj.trees/plain" ]
  (cd "$P" && "$PT" status nope) >/dev/null 2>&1 && fail "status of an unknown name succeeded"
  eq "$(cd "$P" && "$PT" remove "$SANDBOX/proj.trees/plain")" "already removed"
}

case_status_of_a_broken_tree_fails() {
  local t
  "$PT" create feat-a --from "$P" --base head >/dev/null || fail "create failed"
  t="$SANDBOX/proj.trees/feat-a"
  rm -rf "$t/FE"
  "$PT" status "$t" >/dev/null 2>&1 && fail "status succeeded with FE missing"
  "$PT" remove "$t" >/dev/null 2>&1 && fail "remove succeeded with FE missing"
  check [ -d "$t/BE" ]
}

echo "project-tree CLI tests"
for c in $(declare -F | awk '{ print $3 }' | grep '^case_' | sed 's/^case_//'); do
  run_case "$c"
done
printf '%s passed, %s failed%s\n' "$PASSED" "$FAILED" "${FAILS:+:$FAILS}"
[ "$FAILED" -eq 0 ]
