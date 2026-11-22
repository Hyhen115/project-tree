---
description: Show what a project tree holds, per repo (this tree if no name)
argument-hint: [tree name]
allowed-tools: Bash(project-tree:*)
---

Show what the project tree `$ARGUMENTS` holds. Run `project-tree status $ARGUMENTS`, or `project-tree status .` for this session's tree when no name is given. Pass the tree's name as given (`feature/login`), not its folder path: the command finds the project's trees from the current folder, and a path outside the session's folders may be blocked.

The output is:
- `revision <id>`: where its repos stand now.
- `unpublished <n>`: commits that only a detached HEAD holds.
- One `<state>\t<path>` line per change, the path starting with its repo folder.

Group the changes by repo, and by the files outside the repos. Name the repos with no changes. If the name is unknown, run `project-tree list --from .` and show the names there. Change nothing.
