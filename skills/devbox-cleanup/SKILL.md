---
name: devbox-cleanup
description: 'Clean up a project checkout on a remote dev box — tear down a stale agent swarm, verify unpushed work is superseded, reset the checkout to origin, and restart its services. Use when a remote box has an abandoned swarm, a diverged or dirty project checkout, or leftover worktrees that need to be made ready for work again.'
when-to-use:
- '"clean up dev-box" / "get the dev box ready for work again"'
- A remote box has a stale or abandoned agent (NTM) swarm
- A remote project checkout is diverged, dirty, or has leftover worktrees
- '"tear down the dead swarm on a remote host"'
category: infra
related-skills:
- clean
- prune-branches
---

# devbox-cleanup

Make a project's checkout on a **remote box** ready for work again: tear down a dead
agent swarm, reset a diverged checkout, restart its services — **without destroying
unpushed work or disturbing a live swarm.**

## Scope

- One project on one remote box per run. The box is reached over SSH (e.g. `ssh dev-box`).
- **Destructive on the remote box** (`git reset --hard`, process kills, worktree
  removal). Every destructive step is gated behind verification and one user confirmation.
- Not for the local working checkout — that is `clean` / `prune-branches` territory.

## Cardinal rule

**Verify before you destroy.** Never discard an unpushed commit you have not proven is
superseded; never touch a swarm you have not proven is dead.

A stale remote checkout almost always carries unpushed commits and leftover worktrees.
They are *usually* superseded — the work shipped via a parallel path while the box sat
idle — but "usually" is not "verified." One un-verified `git reset --hard` destroys real work.

## Step 1 — Locate and assess (read-only)

SSH in and gather, changing nothing:

```bash
ssh -o BatchMode=yes <host> 'set -e
  R=~/path/to/project
  hostname; uptime
  git -C "$R" status --porcelain=v1 -b
  git -C "$R" worktree list
  git -C "$R" log --oneline -3
  pgrep -fa "claude|codex|ntm|am serve" | head -30
  tmux ls
  df -h ~ | tail -1'
```

If you do not know the checkout path: `find ~ -maxdepth 4 -type d -name <project>`.

Do **not** pipe a `git` command into `head` / `tail` and then `&&` another command — the
pipe swallows the git exit code. Keep `git` invocations un-piped, or split them into
separate calls.

## Step 2 — Is the swarm alive or dead?

Classify the project's swarm before touching it. Treat it as **dead** only when ALL hold:

- The `ntm internal-monitor <project>` process and its panes have produced no output for
  hours or days. Read the last pane lines (`tmux capture-pane -p -t <session> -S -20`) — a
  dead swarm shows a concluded or idle state ("nothing left to do", an unsent prompt).
- The ntm session directory under `~/.config/ntm/sessions/<project>/` has an old mtime.
- No pane process shows recent CPU.

If the swarm shows **any** sign of life — recent pane output, a running task, fresh CPU —
**STOP.** Do not clean a live swarm. Report it and exit.

**Other projects' swarms are off-limits.** A busy box runs several swarms. Identify every
one; only the target project's swarm is in scope. Scope every later kill so it cannot hit
another project.

## Step 3 — Verify ALL unpushed work is superseded

For the checkout's branch and every worktree branch, list commits not on `origin` and
prove each is already shipped:

```bash
git -C "$R" fetch origin --quiet
git -C "$R" log --oneline origin/<branch>..<branch>
git -C "$R" log --oneline origin/<branch>..<worktree-branch>
```

Find positive evidence for each unpushed commit:

| Commit kind | "Superseded" evidence |
|---|---|
| Feature / script | The files already exist on `origin/<branch>` — the feature was re-implemented and landed via the parallel path. Check with `git ls-tree -r origin/<branch>` and `git grep <token> origin/<branch>`. |
| Bead chore | The bead is already `closed` or already filed on `origin` — inspect `git show origin/<branch>:.beads/issues.jsonl`. |
| Worktree feature branch | Its PR is merged (`gh pr view <n> --json state`), or its bead is closed on `origin`. A huge `diff --stat` is usually staleness noise (git-ignored bead-history snapshots) — judge by the **commits**, not the diff size. |

**Every unpushed commit verifiably superseded → safe to reset.**
**Anything not → STOP.** Surface the un-verified commits to the user and offer to push
them to a rescue branch first. Never `reset --hard` over unproven work.

## Step 4 — Confirm scope with the user

Present what you found and exactly what you will destroy — swarm teardown, worktree
removal, checkout reset, service restarts — and get one explicit confirmation
(`AskUserQuestion`). Destructive ops on a remote box are hard to reverse; confirm even
though the box looks abandoned.

## Step 5 — Tear down the dead swarm

```bash
ssh <host> 'tmux kill-session -t <project>'   # kills the session and all its panes
```

Kill the project's ntm monitor. **Beware the `pkill -f` self-match footgun:** a plain
`pkill -f "ntm internal-monitor <project>"` matches its own SSH command line and kills
your remote shell. Use a bracketed pattern so the literal command cannot match itself:

```bash
ssh <host> 'pkill -f "[n]tm internal-monitor <project>"'
```

Then verify: the target swarm is gone **and** every other project's swarm is still alive.

## Step 6 — Clean the checkout

Once the swarm is down and no process holds the checkout:

```bash
ssh <host> 'R=~/path/to/project
  git -C "$R" worktree remove --force "$R/.ntm/worktrees/<wt>"
  git -C "$R" branch -D <superseded-branch>
  git -C "$R" reset --hard origin/<branch>
  rm -rf "$R/.beads/.br_history"'
```

`git reset --hard` here is sanctioned **only** because Step 3 proved every dropped commit
is superseded. The bead-history snapshot directory is git-ignored and regenerates locally.

## Step 7 — Restart services

Restart the box's per-project or shared services (e.g. `agent-mail.service`):

```bash
ssh <host> 'systemctl --user restart <service>
  sleep 30
  systemctl --user is-active <service>
  ss -ltn | grep ":<port>"'
```

Two failure patterns to watch for — they need different verification:

- **Fast-fail (N seconds after start).** SIGTERM, OOM, missing config, a port collision
  on bind. The crash happens within a known window after startup. Wait past that window
  (`sleep N+10` or so) and then check `is-active`. The example above is set for this.

- **Event-triggered.** The service comes up clean and runs for minutes or hours, then is
  killed by an *external* event — another process on the same storage root starting up,
  a `doctor`-style cleanup, a deploy script. A `sleep`-based check cannot prove
  healthiness here, because the trigger event has not happened yet. Three options:
  1. Report that the service started clean and explicitly call out that long-term
     stability is unverified — surface to the user.
  2. Actively trigger the suspected event (start the contending process, run the
     `doctor`, etc.) and observe whether the service survives.
  3. Defer the restart until the deeper root cause is addressed (e.g. resolve a
     storage-root sharing decision), because a restart-without-fix will just recur.

If a shared service contends with per-swarm ephemeral servers for a storage root, the
event-triggered pattern is likely — every new swarm spawn is a potential trigger.
Restart only when no swarm is competing **and** the contention root cause is being
tracked — or restart anyway and flag the contention to the user.

## Guardrails

- **Verify before destroy** — Step 3 is not optional. No `reset --hard` over unproven commits.
- **Never touch a live swarm**, and never another project's swarm.
- **Scope every process kill** — a pattern-kill must not catch other projects or your own
  SSH shell. Use the `[n]tm` bracket trick.
- **One user confirmation** before the destructive phase (Step 4).
- **No `git ... | head && ...`** — the pipe hides the git exit code.
- Report honestly: if a restarted service held only briefly, say so. Root-causing a crash
  is separate work — do not claim a fix you did not verify.
