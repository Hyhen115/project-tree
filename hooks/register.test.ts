import { expect, test } from 'claude-code/testing'

// Hooks a test registers sit beneath the plugin and stand for the engine: the
// `process.run` hook plays bin/project-tree, a `vcs.isolate` hook plays core.
const ran = (exitCode: number, stdout = '', stderr = '') => ({
  value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false },
})
const ASK = { name: 'feat-a', from: '/work/proj', for: 'session', base: 'fresh' } as const
const TREE = '/work/proj.trees/feat-a'

test('a folder of repos becomes a project tree', async ($, on) => {
  const calls: string[][] = []
  on('process.run', (_, e) => {
    calls.push([...e.argv])
    return ran(0, `${TREE}\nabc123\n`)
  })
  on('vcs.isolate', () => ({ deny: 'core must not be asked' }))

  expect(await $.vcs.isolate(ASK)).toEqual({ path: TREE, vcs: 'project-tree', branch: 'feat-a', revision: 'abc123' })
  expect(calls[0]?.slice(-6)).toEqual(['create', 'feat-a', '--from', '/work/proj', '--base', 'fresh'])
})

test('anything else goes on to the usual git worktree', async ($, on) => {
  on('process.run', () => ran(3))
  on('vcs.isolate', () => ({ path: '/repo/.claude/worktrees/feat-a', vcs: 'git', branch: 'worktree-feat-a' }))

  expect(await $.vcs.isolate(ASK)).toEqual({ path: '/repo/.claude/worktrees/feat-a', vcs: 'git', branch: 'worktree-feat-a' })
})

test('a create that fails is denied with its reason', async ($, on) => {
  on('process.run', () => ran(1, '', 'project-tree: FE: could not check out branch feat-a\n'))
  on('vcs.isolate', () => ({ deny: 'core must not be asked' }))

  expect(await $.vcs.isolate(ASK)).toEqual({ deny: 'project-tree: FE: could not check out branch feat-a' })
})

test('status lines become the changes the exit dialog reads', async ($, on) => {
  on('process.run', () =>
    ran(0, 'revision def456\nunpublished 2\nmodified\tBE/a.ts\nuntracked\tFE/new file.ts\nadded\tCLAUDE.md\n'))

  expect(await $.vcs.status({ path: TREE, name: 'feat-a', vcs: 'project-tree', since: 'abc123' })).toEqual({
    revision: 'def456',
    unpublished: 2,
    changes: [
      { path: 'BE/a.ts', state: 'modified' },
      { path: 'FE/new file.ts', state: 'untracked' },
      { path: 'CLAUDE.md', state: 'added' },
    ],
  })
})

test('a status that fails keeps the tree as unknown', async ($, on) => {
  on('process.run', () => ran(1, '', 'project-tree: BE is missing from the tree\n'))

  expect(await $.vcs.status({ path: TREE, name: 'feat-a', vcs: 'project-tree' })).toEqual({
    unknown: 'project-tree: BE is missing from the tree',
  })
})

test('release removes the tree, passing on a kept branch', async ($, on) => {
  const calls: string[][] = []
  on('process.run', (_, e) => {
    calls.push([...e.argv])
    return ran(0, 'kept branch feat-a in BE\n')
  })
  const release = { path: TREE, name: 'feat-a', vcs: 'project-tree', reason: 'test' }

  expect(await $.vcs.release({ ...release, isDiscard: true })).toEqual({ isReleased: true, note: 'kept branch feat-a in BE' })
  expect(calls[0]?.slice(-3)).toEqual(['remove', TREE, '--discard'])
})

test('release of a tree that holds work keeps it', async ($, on) => {
  on('process.run', () => ran(1, '', 'project-tree: /work/proj.trees/feat-a holds work; it is kept\n'))

  expect(
    await $.vcs.release({ path: TREE, name: 'feat-a', vcs: 'project-tree', isDiscard: false, reason: 'test' }),
  ).toEqual({ kept: 'project-tree: /work/proj.trees/feat-a holds work; it is kept' })
})
