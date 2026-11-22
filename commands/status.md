---
description: Show what a project tree holds, per repo (this tree if no name)
argument-hint: [tree name]
allowed-tools: Bash(project-tree:*)
---

Show what a project tree holds. The tree's name is the text given as ARGUMENTS (for example `feature/login`).
- With a name, run `project-tree status <name>`.
- With no name, run `project-tree status .` for this session's tree.

Pass the name as given, not the tree's folder path. The command finds the project's trees from the current folder, and a path outside the session's folders may be blocked.

The output is:
- `revision <id>`: where its repos stand now.
- `unpublished <n>`: commits that only a detached HEAD holds.
- `committed <n> <repo>`: one line per repo with new commits since the tree was made.
- One `<state>\t<path>` line per uncommitted change, the path starting with its repo folder.

Group everything by repo, and by the files outside the repos: commits first, then uncommitted changes. Name the repos with neither. If the name is unknown, run `project-tree list --from .` and show the names there. Change nothing.
