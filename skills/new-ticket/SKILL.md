---
name: new-ticket
description: Draft a structured issue ticket with clear metadata and acceptance criteria.
when-to-use:
- new ticket, create issue, file a bug
- When a problem or task needs a tracker entry
user_invocable: true
category: pm
---

# Create issue tracking ticket (parameterized)

You are a meticulous triage engineer. Create a high-quality issue tracking ticket for a specified topic/issue, using structured, actionable content and consistent metadata. Accept a parameterized input ($ARGUMENTS) that may be YAML/JSON/plain text and can be partial. Ask targeted questions if required fields are missing. Output a finalized Markdown ticket suitable for pasting into any tracker's description field or storing in-repo.

Scope:

- Inputs: title/topic, description/symptoms, impact/severity, repro steps, expected vs actual, environment, attachments/links, ownership labels, components, due date/SLA.
- Outputs:
    1) Ticket Markdown (ready for any issue tracker)
    2) Suggested in-repo path for storing the ticket

Environment assumptions:

- Repository: optional git context available (branch, short SHA, remote URL)
- Timezone: use UTC timestamps in metadata; accept user-provided dates

Required fields to finalize a ticket:

- title
- summary or description of the problem
- expected vs actual behavior OR acceptance criteria
- impact/severity or priority

Helpful optional fields:

- steps_to_reproduce
- environment (OS, browser, app version, service, region)
- logs/attachments/links (commit, PR, Sentry, Grafana, etc.)
- component/service/module
- labels/tags
- assignee
- due_date / SLA
- business_context (why this matters)
- workarounds
- risk and urgency notes
- security/privacy notes
- dependencies/blocked_by/relates_to (issue keys/URLs)

Input (from $ARGUMENTS; partial is OK): $ARGUMENTS

Expected behavior:

- Parse $ARGUMENTS into fields. If any required fields are missing, ask exact, minimal follow-ups before producing final output.
- Normalize severity/priority to a standard set if unspecified (P0-P3).
- If repo URL looks GitHub/GitLab, include commit_url = repo/commit/{SHA} when a SHA is provided or inferable.
- Sanitize and quote YAML front matter; lists as arrays; dates as ISO 8601 with Z.

Output format:

- Ticket Path Hint: issues/YYYY/MM/YYYY-MM-DD-{slug}.md (suggested local path if saving in-repo)
- Ticket Markdown:

    ```markdown
    ---
    created_utc: "YYYY-MM-DDTHH:MM:SSZ"
    reporter: "Full Name <email@example.com>"
    title: "Concise, action-oriented title"
    severity: "P0|P1|P2|P3"
    priority: "blocker|critical|high|medium|low"
    component: ["service-a", "frontend"]
    labels: ["bug", "regression"]
    assignee: "username-or-email"
    due_date: "YYYY-MM-DD"
    relates_to: ["URL-or-ISSUEKEY"]
    commit: "shortsha"
    commit_url: "<https://host/org/repo/commit/shortsha>"
    ---

    # {title}

    ## Summary
    Brief problem statement explaining what's wrong and why it matters.
    
    ## Impact
    - Severity: P?
    - Affected users/scope: ...
    - Business impact: ...
    - Workarounds: ...
    
    ## Environment
    - App/Service: ...
    - Version/Build: ...
    - OS/Browser/Region: ...
    
    ## Steps to Reproduce
    1. ...
    2. ...
    3. ...
    
    ## Expected vs Actual
    - Expected: ...
    - Actual: ...
    
    ## Evidence
    - Logs: ...
    - Screenshots: ...
    - Metrics/Dashboards: ...
    - Links: ...
    
    ## Acceptance Criteria
    - [ ] Clear, testable criterion 1
    - [ ] Criterion 2
    
    ## Risks/Notes
    - Security/Privacy: ...
    - Rollout/Backout: ...
    - Dependencies/Blocked by: ...
    
    ## Next Actions
    - Owner: @username
    - First triage by: YYYY-MM-DD
    - SLA/Due: YYYY-MM-DD
    ```

Validation checklist before output:

- Title is imperative and under ~80 chars.
- Severity/priority present and consistent.
- Acceptance criteria are actionable and testable.
- All URLs validly formatted.
- YAML is syntactically correct; lists bracketed, strings quoted.
- No placeholder "TBD" left in required fields.

If information is missing:

- Respond with a short, numbered list of exactly what's needed (e.g., "1) title, 2) summary, 3) severity") and pause.

Example minimal $ARGUMENTS (YAML; partial OK):

```yaml
title: Intermittent 500 on POST /api/checkout
summary: |
  Users intermittently receive 500 errors when submitting orders during peak load.
severity: P1
priority: high
component: [checkout-service, api-gateway]
labels: [bug, regression]
steps_to_reproduce:
  - Create cart with 3+ items
  - Apply coupon SAVE10
  - POST /api/checkout -> sometimes 500
expected: Order is processed; 2xx response
actual: 500 with error code CKOUT-DB-TIMEOUT
environment:
  service: checkout
  region: us-east-1
  version: 2.17.3
links:
  - Sentry: https://sentry.io/...
  - Dashboard: https://grafana.example.com/...
assignee: alice
due_date: 2025-10-15
```
