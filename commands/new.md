---
description: Make a project tree (a worktree of every repo, on one branch) and move this session into it
argument-hint: <name>
---

Make a project tree named `$ARGUMENTS` and move this session into it, by calling the EnterWorktree tool with `name` set to `$ARGUMENTS`. If `$ARGUMENTS` is empty, ask for a name first. The name becomes the branch in every repo: letters, digits and `. _ -`, in parts joined by `/`, not starting with `-`.

In a folder that holds several git repos, the project-tree plugin makes `<project>.trees/<name with / as +>/`. Each repo there is a git worktree on branch `$ARGUMENTS`, and the files outside the repos are copied in. If a tree with that name already exists, it is entered again as it is, and any files in it are ones the user already had there. In a single git repo, Claude Code makes its usual worktree, on branch `worktree-<name>`.

Once in, report:
- the tree's folder;
- each repo's branch, from `git -C <repo> branch --show-current`;
- whether the tree was new or re-entered: `project-tree status .` printing only `revision` and `unpublished 0` means nothing in it has changed since it was made.
