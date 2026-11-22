---
description: Remove a project tree; refuses one that holds work unless you confirm
argument-hint: <tree name>
---

Remove the project tree `$ARGUMENTS`. If no name is given, run `project-tree list --from .` and ask which one. Pass the tree's name as given (`feature/login`), not its folder path: the command finds the project's trees from the current folder, and a path outside the session's folders may be blocked.

1. **If it is the tree this session is in** (the current folder is that tree), call the ExitWorktree tool with `action: "remove"`. It leaves the tree and removes it in one step. If it refuses because the tree holds work, show what it lists. Retry with `discard_changes: true` only if the user confirms.
2. **Otherwise**, run `project-tree remove $ARGUMENTS`.
   - It removes a tree that holds nothing and prints `removed`, or `kept branch <name> in <repos>`.
   - It refuses one that holds work: it lists the changes, or says the tree has new commits.
3. **If it refused**, show what the tree holds and say what removing it would lose. Branches with commits are kept either way. Run `project-tree remove $ARGUMENTS --discard` only after the user confirms.

Never delete a tree with `rm` or `git worktree remove`.
