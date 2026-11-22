# project-tree

`claude -w` for a folder of git repos.

Say you keep several repos side by side in one folder that is not itself a git
repo, and start Claude in that folder:

```
proj/
  BE/   FE/   BFF/      ← three git repos
  CLAUDE.md  .claude/   ← shared files, not in any repo
```

Claude Code's built-in worktrees (`claude -w`) only work inside one git repo.
This plugin extends them to the whole folder. `claude -w feature-a`, run in
`proj`, makes a **project tree**: a copy of the folder in which every repo is a
git worktree on branch `feature-a`, all made in one step. The session starts
inside it.

```
proj.trees/
  feature-a/
    BE/  FE/  BFF/        ← git worktrees, each on branch feature-a
    CLAUDE.md  .claude/   ← copied from proj
  feature-b/
```

Start a second terminal with `claude -w feature-b` and you have two Claude
sessions working on two features in parallel, across all your repos, without
touching each other or `proj`.

Inside one git repo nothing changes: `claude -w` still makes Claude Code's own
worktree there.

## Install

Requires Claude Code 2.1.330 or newer, git, and bash. It is built for macOS and
works on Linux.

At the prompt of a Claude Code session:

```
/plugin install project-tree --marketplace Hyhen115/project-tree
```

From a shell:

```
claude plugin install project-tree --marketplace Hyhen115/project-tree
```

## Use

1. **Trust the folder once.** Run `claude` in `proj` and accept the trust
   prompt. Claude Code requires this before `-w` works there.
2. **Start a feature:** `cd proj && claude -w feature-a`. Or, in a session
   already open in `proj`, type `/project-tree:new feature-a`. Asking Claude
   to "make a worktree called feature-a" works too.
3. **Work as usual.** Commit in each repo, and push each repo on its own
   (`git -C BE push -u origin feature-a`, or ask Claude to). Merging is
   ordinary git, per repo: each repo has its own `feature-a` branch to merge
   or open a pull request for. The plugin's skill tells Claude this.
4. **Leave with `/exit`.** If nothing changed, the tree is removed, along with
   each branch that got no commits. Otherwise Claude Code asks whether to keep
   or remove it. Removing never deletes commits: a branch with commits stays in
   its repo.
5. **Come back:** `claude -w feature-a` opens the same tree again.

Subagents that Claude starts with worktree isolation in `proj` get project
trees too. A tree an agent changed nothing in is removed when the agent ends.
One it changed is kept, on a branch like `agent-a1b2…` in each repo. Claude
can bring that work into your tree: commit in the agent's tree, then merge or
cherry-pick its branch in each repo. No push is needed.

### Commands

Type these in a Claude session in `proj` or in any of its trees. They are the
project-wide counterparts of git's worktree commands:

| Command | Does | Like |
| --- | --- | --- |
| `/project-tree:new <name>` | makes a tree and moves the session into it | `git worktree add` |
| `/project-tree:list` | lists the project's trees: clean, committed, changed or unknown | `git worktree list` |
| `/project-tree:status [name]` | what a tree holds, per repo (this tree if no name) | `git status` |
| `/project-tree:remove <name>` | removes a tree; one that holds work only after you confirm | `git worktree remove` |

`list` and `status` only read, and run without asking. `remove` asks first.
Commits are never deleted: a branch with commits stays in its repo.

Trees can be left behind, for example after `claude --resume` or `claude rm`,
which keep them. `/project-tree:list` finds them. The commands run
`bin/project-tree`, which also works from a shell:

```
project-tree list --from proj
project-tree status feature-a         # by name, run in proj or a tree
project-tree remove feature-a         # refuses a tree that holds work
project-tree remove feature-a --discard
```

## What's in a tree

- **Each repo is a real git worktree** of the original. It shares the
  original's history, so a commit in `proj.trees/feature-a/BE` is right away on
  branch `feature-a` in `proj/BE`, and `git -C proj/BE worktree list` shows it.
  Git allows a branch to be checked out in only one place.
- **Where new branches start.** Each new branch starts from the repo's latest
  `origin` default branch. This is Claude Code's `worktree.baseRef: "fresh"`
  setting, the default. With `"worktree": { "baseRef": "head" }` in your
  settings, branches start from what each repo has checked out. A repo with no
  `origin` starts from its HEAD. If a repo already has a branch with that
  name, it is checked out as it is.
- **New branches have no upstream,** so a push can't land on `main`.
- **Other branches you make inside a tree** (`git switch -c ...`) live in the
  original repo, like every branch. Removing the tree leaves them there.
- **Everything outside the repos is copied:** CLAUDE.md, `.claude/`, scripts.
  On macOS the copy is an instant APFS clone. Changes to these copies count as
  work, so the tree is kept.
- **Ignored files** a repo lists in `.worktreeinclude` (`.env`, for example)
  are copied in, as Claude Code does for its own worktrees. Edits to ignored
  files count as work too. Folders tools rebuild, such as `node_modules`,
  `dist` or `.venv`, don't count.
- **Not carried over:** uncommitted changes in the original repos, since
  worktrees start from commits.

## Limits

- `vcs.isolate`, the Claude Code hook this uses, is marked experimental and may
  change between releases.
- `claude --resume` does not move into a tree by itself. Run
  `claude -w <name>` again to reopen it, or `cd` into the tree and resume
  there.
- With `permissions.blockFileToolReadsOutsideWorkingDirectories` turned on,
  Claude Code won't move a session into a tree beside the project folder.
- Submodules and Git LFS files inside a tree are not initialised for you. If
  you initialise a submodule, work inside it counts like any other change.
- Gitignored files inside rebuilt folders (`build/`, `dist/`, `out/`,
  `vendor/`, `node_modules/` and the like) are not counted as work. A file you
  wrote there that git ignores is lost when the tree is removed.
- A tree whose repos hold tens of thousands of gitignored files outside those
  folders can take longer than the 5 s Claude Code allows the exit check. The
  check then reads as unknown, so you are asked instead of the tree being
  removed.
- A file or folder name holding a tab or a newline, outside the repos, can't be
  tracked. `create` refuses such a folder, and `status` reports such a tree as
  unknown, so it is never removed without asking.

## How it works

- `hooks/register.ts` is a Claude Code hooks module. It answers the
  `vcs.isolate`, `vcs.status` and `vcs.release` events: make a working copy,
  say what it holds, and take it away.
- For a folder of repos it runs `bin/project-tree`. For anything else it passes
  the event on, and Claude Code makes its usual git worktree.
- `bin/project-tree` is plain bash and can be used on its own:
  - `create` makes the tree and writes its manifest (`.project-tree`) last.
  - `status` reports changes in the repos, commits, and changes to copied and
    ignored files.
  - `remove` deletes a tree only once every worktree in it is removed, and
    keeps branches that have commits.
- `skills/working-in-a-tree/SKILL.md` tells Claude what it can't see from inside a
  tree:
  - the top folder is not a repo, so it commits and pushes per repo;
  - shared files are copies that don't merge back;
  - how to bring a subagent's tree back.
- `commands/` holds the `/project-tree:new`, `list`, `status` and `remove` commands.
  `new` asks Claude to call EnterWorktree; the others run `bin/project-tree`.

Tests:

```
bash tests/cli.test.sh     # the CLI, in throw-away git repos
claude plugin test .       # the hooks module
```

## License

MIT
