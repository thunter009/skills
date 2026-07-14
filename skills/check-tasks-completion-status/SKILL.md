---
name: check-tasks-completion-status
description: Audit whether a ticket is actually complete without changing files.
when-to-use:
- check task status, is this ticket done, verify completion
- When code and docs may disagree on task status
user_invocable: true
category: pm
---

# Check ticket completion status

Check ticket completion status by auditing the codebase and docs. Do not modify any files. If local execution isn't possible, perform a static audit and explain the limitations.

Review an existing ticket/task and determine whether it is complete based on the current codebase, tests, and documentation. Provide a thorough, evidence-backed report and propose any follow-up actions. Be conservative: if uncertain, mark as "Needs Review" rather than "Complete."

If I want you to check a specific task/ticket, I will include that here: $ARGUMENTS

Examples for $ARGUMENTS:

- File path: docs/tasks/active/01-implement-auth.md
- Task title: "Implement Auth"
- Issue/PR reference: "#123" or "PR-456"
- Keyword(s): "payments webhook"

Primary sources of truth in this repo:

- docs/start-here.md
- docs/tasks/ (active/, backlog/, completed/)
- README.md (root)
- docs/reference/, docs/how-to-guides/
- Source code, tests, configuration, feature flags
- Git history (commits, branches, tags) and local PR branches (if present)

## What to do

### Identify the target ticket

- If $ARGUMENTS is provided:
- Resolve it to one or more task files under docs/tasks or to obvious code references.
- If ambiguous, list candidates and ask me to choose before proceeding.
- If $ARGUMENTS is not provided:
- List tasks in docs/tasks/active/ with a short 1-line summary and ask which to check.

### Extract or define acceptance criteria

- Read the matching task file(s) and pull out explicit acceptance criteria if present.
- If criteria are missing or incomplete:
- Derive a draft criteria set from:
  - Summary, Action Items, Technical Details in the task file
  - docs/start-here.md (Roadmap, phases)
  - README.md (Current Status), docs/reference/, relevant code comments/tests
- Produce a concrete checklist using observable/verify-able conditions (e.g., endpoints respond, UI renders states, tests pass, env vars configured).
- Present the acceptance criteria and your audit plan; pause for my confirmation before evaluating.

### Plan the audit

- Outline exactly where you'll look:
- Code directories/files likely impacted
- Feature flags/config keys
- Database schema/migrations
- API routes/handlers/services
- Frontend components/pages
- Background jobs/cron/queues
- Tests (unit/integration/e2e), plus any fixture or mock data if present
- Outline which commands you'll run (if runnable), with fallbacks if running is not possible.

### Execute a static audit (no changes yet)

- Search the repository for relevant symbols, routes, components, and references.
- Inspect implementation completeness (not just stubs):
- Data flow end-to-end (API -> service -> persistence -> UI)
- Error handling and edge cases
- Permissions/RLS/security checks where applicable
- Feature flags enabled in non-dev envs
- Configuration and environment variables required
- Migrations and seed data (if needed)
- Cross-check docs for drift:
- docs/tasks: does this task still sit in active/ but appears done?
- docs/start-here.md "Roadmap" and README "Current Status" reflect reality?

### Execute a runtime/test audit (if feasible)

- Try to run tests and/or the app using minimal, standard commands (adapt as needed):
- npm install
- npm run build
- npm test
- npm run dev
- If running is not feasible, explain why and provide the closest-possible verification via code/logic/tests review.
- If tests exist for the ticket, verify they cover the acceptance criteria and pass locally.

### Evaluate each acceptance criterion and collect evidence

- For each criterion, mark:
- Met
- Not met
- Unclear (needs manual verification or missing data)
- For each, cite evidence:
- File paths and key lines/functions
- Test names/paths and results
- Commands run and outputs (summarized)
- Screenshots or logs if available (summarize if not attachable)

### Decide status and propose actions

- Overall status:
- Complete
- Not Complete
- Needs Review (insufficient certainty)
- If Complete:
- Propose specific documentation updates:
  - Move task file from docs/tasks/active/ to docs/tasks/completed/
  - Update README.md "Current Status" if applicable
  - Update docs/start-here.md Roadmap statuses if applicable
- Propose a concise PR/commit plan (branch name, commit messages).
- If Not Complete:
- List the smallest next actions needed to reach completion (ordered, time-bounded).
- Point to exact code locations for each action.
- Recommend tests to add/fix.
- Suggest who/what might be needed (env vars, credentials, external services).
- If Needs Review:
- List the specific uncertainties and what would resolve them.

### Ask before making changes

- Do not modify code or docs yet.
- Present the report and proposed changes; ask for approval.
- If approved to update task docs, you may run the "update-task-documentation.md" command or draft the changes as a patch for my review.

Output format (use this structure)

- Summary
- Target ticket:
- Decision: Complete | Not Complete | Needs Review
- Confidence: High | Medium | Low

- Acceptance Criteria
- Checklist in a table with Status and Evidence columns.

- Evidence
- Code paths inspected (list)
- Tests found/run (list with results)
- Commands executed (and summarized outputs)
- Docs cross-checked (list)

- Gaps and Risks
- Items blocking completion or warranting caution.

- Proposed Actions
- If Complete: doc updates, PR/commit plan.
- If Not Complete: ordered next steps with file paths and estimated effort.
- If Needs Review: precise questions or data needed.

- Optional: Patch Plan
- Branch name:
- Commit messages:
- Files to change/move:

Conventions and safeguards

- Be conservative; if any acceptance criterion is unverified, do not mark Complete.
- Prefer direct evidence from code/tests over assumptions.
- Do not rely on external internet resources; use only local repo content and standard dev commands.
- Do not run destructive commands; do not alter data without explicit approval.
- If the project is not Node-based, detect the stack from files (e.g., pyproject.toml, package.json, go.mod) and adapt commands accordingly.

Notes on integration with existing commands

- After confirming completion, propose running "update-task-documentation.md" to reflect the current state across docs/tasks and related docs.
- If the ticket is not complete, consider queuing the needed work via "next-task.md" with a focused plan for the remaining items.
