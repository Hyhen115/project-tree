---
description: List the project trees of this project, and whether each holds work
allowed-tools: Bash(project-tree:*)
---

Run `project-tree list --from .`. Inside a tree this lists its siblings too, since every tree records the project it came from.

Each line is `<name> <path> <state>`. Show them as a table of name, folder and state, where the state means:
- `clean`: nothing changed since the tree was made.
- `committed`: new commits only; they are safe on the tree's branch in each repo.
- `changed`: uncommitted changes, stashes, or edited copied files.
- `unknown`: it could not be read, so it is kept.

If there are no lines, say this project has no project trees.
