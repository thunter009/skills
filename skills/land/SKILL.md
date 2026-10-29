---
name: land
description: Land branch changes through ship, reusing completed checks and review.
when-to-use:
- land this, ready to ship, pre-PR closeout
- After non-trivial work on a branch before opening a PR
permissions:
- read
- write
- bash
category: release
---

# /land

Follow the **ship** skill (`skills/ship/SKILL.md`, or the installed sibling `../ship/SKILL.md`). It owns checking, review, commits, PR creation, and landing; do not run a separate pre-ship review or test pipeline.

Carry forward checks and substantive review already completed for this revision and scope. After fixes or a rebase that changes behavior, recheck affected code and risk. Preserve repository-required checks, human/bot review, and unresolved-HIGH merge gates.

Report the PR link, validation, and any real blocker. No phase table or separate closeout artifact is required.
