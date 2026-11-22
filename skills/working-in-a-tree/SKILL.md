---
name: working-in-a-tree
description: This skill should be used when working inside a project tree (a folder under <project>.trees/ that holds several git repos, made by `claude -w`, `/project-tree:new` or `project-tree codex` with the project-tree plugin), or when committing, pushing, opening pull requests, merging, or bringing back a subagent's worktree across several repos.
---

# Working in a project tree

A project tree is a copy of a folder of git repos. Its top folder holds a `.project-tree` file and is **not** a git repo. Each repo in it is a git worktree of the original repo, on the branch named on the `name` line of `.project-tree`.

- **Git runs per repo.** The top folder has no git status. Run `project-tree status .` to see what changed: one line per changed file, each starting with its repo folder. Commit, push and open a pull request in each repo that changed (`git -C BE ...`), using the same branch name in every repo. Say which repos had no changes.
- **Shared files are copies, not git.** CLAUDE.md, `.claude/` and other files outside the repos were copied from the project folder (the `root` line of `.project-tree`). Edits to them stay in this tree. Tell the user, and copy a file back to the project folder only if they ask.
- **Subagents with `isolation: "worktree"` get a project tree of their own** beside this one, on a branch like `agent-a1b2…` in every repo. Tell each one to commit in every repo it changes before it finishes. Its branches are shared with this tree, so bringing its work back needs no push:
  1. If it left changes uncommitted, run `project-tree status <agent-branch>` (a tree is named by its branch) to see which repos changed, then commit there (`git -C <agent-tree>/BE add -A && git -C <agent-tree>/BE commit -m ...`).
  2. Its own commits in a repo are `<start>..<agent-branch>`, where `<start>` is that repo's commit on its `repo` line in `<agent-tree>/.project-tree`. Check `git -C BE log --oneline HEAD..<agent-branch>`:
     - Commits beyond those mean the agent's tree started from origin's latest default branch (Claude Code's `worktree.baseRef: "fresh"`). Run `git -C BE cherry-pick <start>..<agent-branch>`.
     - Otherwise run `git -C BE merge <agent-branch>`.
  3. Run `project-tree remove <agent-branch> --discard`.
  4. Delete the agent's branch from this tree. After a merge, use `git -C BE branch -d <agent-branch>`; run from the original repo it says "not fully merged". A cherry-pick gives the commits new ids, so `-d` refuses: check they all landed (`git -C BE log --oneline -n <count>`), then use `-D`.
- **Agent trees sit outside this session's folder**, so Claude Code may ask before touching them. `/add-dir <project>.trees` allows them all.
- **In Codex:**
  - `project-tree` is not on PATH unless the user linked it. If `command -v project-tree` prints nothing, tell them to link it (the plugin's README shows how) and stop there.
  - A git command failing with "Operation not permitted" on a `.git/...lock` file means the session wasn't started with `project-tree codex <name>`. That launcher makes each repo's git folder writable, so tell the user to restart Codex with it.
- **Never** run git at the top folder, or `git worktree remove` or `rm -rf` on a tree. `project-tree remove <tree>` takes a tree away, and refuses one that holds work unless given `--discard`.
