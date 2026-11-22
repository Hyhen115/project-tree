import type { EngineInterface, Register, VcsChange } from 'claude-code'

// Claude Code asks this mod for every worktree (`claude -w`, EnterWorktree, an
// agent's `isolation: "worktree"`). For a folder of git repos it answers with a
// project tree made by bin/project-tree; for anything else it passes the ask
// on, and Claude Code makes its usual git worktree.
const VCS = 'project-tree'
const NOT_MINE = 3
const STATES = new Set(['modified', 'added', 'deleted', 'untracked', 'conflict'])

const cli = ($: EngineInterface, args: string[], timeoutMs = 600_000) =>
  $.process.run(['bash', `${$.plugin.root}/bin/project-tree`, ...args], { cwd: '/', timeoutMs })

const reason = (stderr: string, fallback: string) => stderr.trim().split('\n').slice(-3).join(' ') || fallback

export const register: Register = (on) => {
  on('vcs.isolate', async ($, e, next) => {
    const made = await cli($, ['create', e.name, '--from', e.from, '--base', e.base])
    if (made.exitCode === NOT_MINE) return next(e)
    const [path, revision] = made.stdout.trim().split('\n')
    if (made.exitCode !== 0 || !path || !revision) {
      return { deny: reason(made.stderr, `project-tree could not make the tree ${e.name}`) }
    }
    return { path, vcs: VCS, branch: e.name, revision }
  })

  // At exit Claude Code waits 5 s for this answer; status stays well under it.
  on('vcs.status', { vcs: VCS }, async ($, e) => {
    const ran = await cli($, ['status', e.path], 4_500)
    if (ran.exitCode !== 0) return { unknown: reason(ran.stderr, 'project-tree status failed') }
    let revision: string | undefined
    let unpublished = 0
    const changes: VcsChange[] = []
    for (const line of ran.stdout.split('\n')) {
      if (line.startsWith('revision ')) revision = line.slice(9)
      else if (line.startsWith('unpublished ')) unpublished = Number(line.slice(12))
      else {
        const tab = line.indexOf('\t')
        const state = line.slice(0, tab)
        if (tab > 0 && STATES.has(state)) changes.push({ path: line.slice(tab + 1), state: state as VcsChange['state'] })
      }
    }
    if (revision === undefined || !Number.isInteger(unpublished)) return { unknown: 'project-tree status gave no revision' }
    return { changes, unpublished, revision }
  })

  on('vcs.release', { vcs: VCS }, async ($, e) => {
    const ran = await cli($, ['remove', e.path, ...(e.isDiscard ? ['--discard'] : [])])
    if (ran.exitCode !== 0) return { kept: reason(ran.stderr, 'project-tree could not remove the tree') }
    const note = ran.stdout.trim()
    return note.startsWith('kept branch') ? { isReleased: true, note } : { isReleased: true }
  })
}
