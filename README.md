# skills

Production Claude Code skills, mirrored from a private working repo.
Each skill is a directory with a `SKILL.md` entry point.

Install with [skills](https://github.com/vercel-labs/skills): `npx skills add thunter009/skills -s <name>`

| Skill | Description |
|---|---|
| [`add-pytest-coverage`](skills/add-pytest-coverage/SKILL.md) | Add or expand pytest coverage without changing production logic. |
| [`agents-md`](skills/agents-md/SKILL.md) | Create repo-specific AGENTS.md guardrails from the codebase. |
| [`autoreview`](skills/autoreview/SKILL.md) | "Run a structured code review (Codex default, Claude optional) as a closeout check on a local or PR branch before commit or ship." |
| [`beads-linear-sync`](skills/beads-linear-sync/SKILL.md) | Sync beads and Linear so agent state and human tracker stay aligned. |
| [`bug-hunt`](skills/bug-hunt/SKILL.md) | Run a multi-phase bug hunt with Codex, Gemini, or Claude. |
| [`check-tasks-completion-status`](skills/check-tasks-completion-status/SKILL.md) | Audit whether a ticket is actually complete without changing files. |
| [`clean`](skills/clean/SKILL.md) | 'End-of-work cleanup sweep for a multi-agent repo — safely land genuine unpushed commits, squash open PRs, prune merged branches and worktrees, clean the remo |
| [`codebase-knowledge-graph`](skills/codebase-knowledge-graph/SKILL.md) | Build an interactive knowledge graph of any codebase via the Understand-Anything pipeline, with a batch-integrity guard the raw plugin lacks. |
| [`codex`](skills/codex/SKILL.md) | Run Codex CLI for parallel implementation, review, or second opinions. |
| [`colgrep`](skills/colgrep/SKILL.md) | Search code by meaning with colgrep instead of literal grep. |
| [`create-pull-request`](skills/create-pull-request/SKILL.md) | Open a GitHub pull request with repo-specific PR conventions. |
| [`deep-review`](skills/deep-review/SKILL.md) | Run adversarial, flow-tracing code review and fix real issues. |
| [`demo-video-finder`](skills/demo-video-finder/SKILL.md) | Find short, single-topic, reputable how-to and demo videos for a list of items (exercises, techniques, steps, moves), with jump-to timestamps for long ones. Ret |
| [`design`](skills/design/SKILL.md) | Take a feature idea from fuzzy to build-ready — grill, prototype, then plan. |
| [`devbox-cleanup`](skills/devbox-cleanup/SKILL.md) | 'Clean up a project checkout on a remote dev box — tear down a stale agent swarm, verify unpushed work is superseded, reset the checkout to origin, and restar |
| [`diagnose`](skills/diagnose/SKILL.md) | Disciplined diagnosis loop for hard bugs and performance regressions. |
| [`docs-organize`](skills/docs-organize/SKILL.md) | Reorganize loose files already in a folder into its subfolder taxonomy, with hash-based dedup, dry-run preview, and collision-safe moves. Domain-agnostic. |
| [`domain-modeling`](skills/domain-modeling/SKILL.md) | Build and sharpen a project's ubiquitous language — a CONTEXT.md glossary plus sparse ADRs — challenging terms against the glossary and cross-referencing co |
| [`enrich-ticket-detail`](skills/enrich-ticket-detail/SKILL.md) | Flesh out thin or empty beads/Todoist items by mining git history, code-at-HEAD, closed tickets, and the session journal, then verify every drafted claim agains |
| [`external-study`](skills/external-study/SKILL.md) | Study an external project and adapt its best ideas to this repo. |
| [`firecrawl`](skills/firecrawl/SKILL.md) | Use Firecrawl only for JS-heavy web pages Tavily cannot render. |
| [`fix-pytest-failures`](skills/fix-pytest-failures/SKILL.md) | Diagnose and fix failing pytest tests from names or stack traces. |
| [`followup-sweep`](skills/followup-sweep/SKILL.md) | Weekly cross-tracker follow-up hygiene sweep — consume the auto-flagged vault punch list, dedup Todoist work-stream Inbox sections, and merge duplicate tracke |
| [`generate-best-practices`](skills/generate-best-practices/SKILL.md) | Generate a concise best-practices guide for the current stack. |
| [`google-sheets-via-browser`](skills/google-sheets-via-browser/SKILL.md) | >- |
| [`grilling`](skills/grilling/SKILL.md) | Relentlessly interview the user about a plan or design, one question at a time, until every branch of the decision tree is resolved. Use before building anythin |
| [`groom`](skills/groom/SKILL.md) | Surface the next best task across beads, Linear, PRs, Todoist, and git. |
| [`groom-backlog`](skills/groom-backlog/SKILL.md) | Groom docs/tasks and start-here with consistent global ticket IDs. |
| [`idea-wizard`](skills/idea-wizard/SKILL.md) | Run a structured idea funnel to generate and rank project improvements. |
| [`improve-codebase-architecture`](skills/improve-codebase-architecture/SKILL.md) | Find module-deepening refactor opportunities for testability and AI-navigability. |
| [`iterative-critique-polish`](skills/iterative-critique-polish/SKILL.md) | >- |
| [`knowledge-graph-capture`](skills/knowledge-graph-capture/SKILL.md) | Before archiving consumed or reference content (videos, articles, bookmarks, finished tasks), distill its durable knowledge into applied, wikilinked evergreen n |
| [`land`](skills/land/SKILL.md) | Pre-landing closeout — review, ubs scan, fix findings, then ship. |
| [`mealie`](skills/mealie/SKILL.md) | Read and write recipes in self-hosted Mealie via its REST API without corrupting them. |
| [`migrate-cc-command`](skills/migrate-cc-command/SKILL.md) | Convert a Claude command into a Claude Code skill. |
| [`multi-round-research`](skills/multi-round-research/SKILL.md) | "Two-round parallel-subagent research that produces an opinionated proposal, then challenges and surpasses it. Use for deep concept exploration, design-space ma |
| [`new-ticket`](skills/new-ticket/SKILL.md) | Draft a structured issue ticket with clear metadata and acceptance criteria. |
| [`park`](skills/park/SKILL.md) | Create a Todoist resumption task so paused work can restart cleanly. |
| [`plan-review`](skills/plan-review/SKILL.md) | Audit an implementation plan before coding begins. |
| [`playwright-cli`](skills/playwright-cli/SKILL.md) | Automate browser flows, screenshots, and extraction with Playwright CLI. |
| [`pr-review`](skills/pr-review/SKILL.md) | Review a pull request with structured findings and merge-risk checks. |
| [`prototype`](skills/prototype/SKILL.md) | Build a throwaway prototype to answer a design question before committing. |
| [`qa`](skills/qa/SKILL.md) | QA a web app with smoke, full, PR-scoped, or regression testing. |
| [`reality-check`](skills/reality-check/SKILL.md) | Check whether a swarm is busy but not converging on the goal. |
| [`refactor`](skills/refactor/SKILL.md) | Refactor code with scoped cleanup and safer structure changes. |
| [`refine-skill`](skills/refine-skill/SKILL.md) | Mine CASS sessions and rewrite a skill based on real usage. |
| [`release-loop`](skills/release-loop/SKILL.md) | Arm a self-pacing release loop that cuts an immutable release branch and opens a release PR on a velocity-gated cadence. |
| [`ritual-detection`](skills/ritual-detection/SKILL.md) | Mine CASS for repeated prompts that should become new skills. |
| [`roadmap-review`](skills/roadmap-review/SKILL.md) | Review and sync roadmap docs against tracker reality. |
| [`ship`](skills/ship/SKILL.md) | 'Run the full landing workflow: sync, test, split commits, and open a PR.' |
| [`simplify`](skills/simplify/SKILL.md) | Review recent code changes for reuse, quality, and unnecessary complexity. |
| [`skill-health`](skills/skill-health/SKILL.md) | Validate installed skills, frontmatter, refs, and permissions. |
| [`skills-benchmark`](skills/skills-benchmark/SKILL.md) | Run the agent-skills benchmark suite in oracle, paired, or live mode. |
| [`skills-router`](skills/skills-router/SKILL.md) | Advisory UserPromptSubmit hook that suggests 2-3 matching skills per prompt. |
| [`squash-pr`](skills/squash-pr/SKILL.md) | Triage open PRs and squash-merge selected ones onto the integration branch. |
| [`start-project`](skills/start-project/SKILL.md) | Scaffold a new project README, docs, tasks, and roadmap files. |
| [`swarm-start`](skills/swarm-start/SKILL.md) | Join a swarm, register, triage work, and claim a bead. |
| [`sweep-epics`](skills/sweep-epics/SKILL.md) | Close epics whose children are already done. |
| [`tdd`](skills/tdd/SKILL.md) | Implement changes with strict red-green-refactor discipline. |
| [`todoist-capture`](skills/todoist-capture/SKILL.md) | Convert loose context — a conversation, runbook, diagnosis, decision, error dump, or doc — into well-formed Todoist task(s) that are deduped, correctly plac |
| [`todoist-execute-today`](skills/todoist-execute-today/SKILL.md) | From a project directory, surface today's top Todoist task, extract its kickoff prompt, and start executing. The on-ramp from "I'm in a repo" to "agent is doing |
| [`todoist-inbox-triage`](skills/todoist-inbox-triage/SKILL.md) | Triage the Todoist inbox into projects, groups, and deletes. |
| [`todoist-kickoff-prompt`](skills/todoist-kickoff-prompt/SKILL.md) | Generate self-contained kickoff prompts for selected Todoist tasks — cold-start-ready, ready to paste into a fresh Claude Code session. Composable; called aft |
| [`todoist-linkdump-eval`](skills/todoist-linkdump-eval/SKILL.md) | Evaluate raw-URL bookmark tasks in Todoist — fetch each link, post a verdict comment (KEEP-EVAL / SKIP / INSTALL-CANDIDATE), close the SKIPs. Designed to run  |
| [`todoist-sort-projects`](skills/todoist-sort-projects/SKILL.md) | Alphabetize Todoist projects within each parent. |
| [`toon`](skills/toon/SKILL.md) | Convert JSON to TOON before reading it into context to cut tokens; decode TOON back to JSON losslessly. |
| [`ui-polish`](skills/ui-polish/SKILL.md) | Run a UI polish pass focused on friction, aesthetics, and delight. |
| [`update-session`](skills/update-session/SKILL.md) | Append a structured session record to the repo history log. |
| [`update-task-documentation`](skills/update-task-documentation/SKILL.md) | Sync task docs, roadmap, and README with real project state. |
| [`wayfinder`](skills/wayfinder/SKILL.md) | Plan a chunk of work too big for one agent session by charting it as a map of investigation/decision tickets in beads — resolve them one at a time until the r |
| [`zoom-out`](skills/zoom-out/SKILL.md) | Zoom out one abstraction layer and map the relevant modules and callers. |

_Generated by mirror-sync; do not edit here — changes land via the private source repo._
