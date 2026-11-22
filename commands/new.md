---
description: Make a project tree (a worktree of every repo, on one branch) and move this session into it
argument-hint: <name>
---

Make a project tree and move this session into it. Its name is the text given as ARGUMENTS (for example `feature/login`). If no name was given, ask for one first. The name becomes the branch in every repo: letters, digits and `. _ -`, in parts joined by `/`, not starting with `-`.

In Claude Code, call the EnterWorktree tool with `name` set to that name. In a folder that holds several git repos, the project-tree plugin then makes `<project>.trees/<name with / as +>/`. Each repo there is a git worktree on that branch, and the files outside the repos are copied in. If a tree with that name already exists, it is entered again as it is, and any files in it are ones the user already had there. In a single git repo, Claude Code makes its usual worktree, on branch `worktree-<name>`.

In Codex, a running session can't move into a new folder. Run `project-tree create <name>` to make the tree. Then tell the user to start Codex there with `project-tree codex <name>`, which lets Codex write to the repos' git folders.

Once in, report:
- the tree's folder;
- each repo's branch, from `git -C <repo> branch --show-current`;
- whether the tree was new or re-entered: `project-tree status .` printing only `revision` and `unpublished 0` means nothing in it has changed since it was made.
