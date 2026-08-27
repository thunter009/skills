---
name: ui-polish
description: Run a UI polish pass focused on friction, aesthetics, and delight.
when-to-use:
- polish the ui, ux polish, make it look better
- After functionality works but before shipping
permissions:
- read
- bash
category: testing
related-skills:
- playwright-cli
- better-interface
- interface-review
- refactoring-ui
---

# /ui-polish

UI/UX polish cycle targeting premium quality. Separate from bug hunting — this is about friction, aesthetics, and delight.

**Target:** $ARGUMENTS (if empty, polish the entire frontend)

## Prerequisites

Core functionality must be working. This skill targets polish, not correctness. If there are functional bugs, fix those first.

**How to see the UI:** Use `playwright-cli` to take screenshots and interact with the app. If a dev server isn't running, start one first. See the playwright-cli skill for command reference.

**Rulebook:** Load the `better-interface` skill (jakubkrehel/skills collection) — it routes to the six `better-*` domain skills: ui, typography, colors, layout, accessibility, writing. Grade findings against those concrete rules and cite the rule when suggesting a change. Compressed public version: https://interfaces.dev/cheat-sheet.

**Systems rulebook:** Load `refactoring-ui` (s0xDk/refactoring-ui-skill) next to it. `better-*` grades the details (motion, a11y, copy). `refactoring-ui` grades the systems: every spacing, type, color, shadow, and radius value must come from a fixed scale. Existing UI: read its diagnose reference first (symptom → fix table). New token set: start from its tokens.css asset and retune the hues.

**Scope check:** Polishing a specific diff, branch, or PR rather than a running app? Use `/interface-review` instead — it resolves change scope and hands the domain review to `better-interface`.

## Step 1: General Scrutiny

Examine every aspect of the application workflow and implementation. Look for:

- Things that seem sub-optimal or wrong from a user perspective
- Obvious improvements for user-friendliness and intuitiveness
- UI/UX that could be slicker, more visually appealing, more premium-feeling
- Inconsistent spacing, typography, or color usage
- Missing loading states, empty states, error states
- Interactions that feel laggy or jarring
- Visual hierarchy problems (what draws the eye vs what should)
- Accessibility gaps (contrast, focus states, screen reader support)
- Violations of the `better-*` rulebook (concrete CSS, a11y, and copy rules)
- Values off the `refactoring-ui` scales: ad hoc px, `em` type sizes, runtime `lighten()`/`darken()`, grey text on color, `label: value` data dumps

Target quality: Stripe-level apps. Ultra high quality, polished, premium.

**Generate a numbered list of improvement suggestions. Do NOT make code changes yet.**

**Present suggestions to the user. Wait for them to select which to pursue.**

## Step 2: Implement Selected Improvements

For each selected improvement:
1. Make the change
2. Verify it doesn't break existing functionality
3. Check that it looks right on both wide and narrow viewports

## Step 3: Platform-Specific Polish

Run two separate passes:

### Desktop Pass
Consider desktop-specific UX patterns:
- Hover states and tooltips
- Keyboard navigation and shortcuts
- Wide-viewport layout utilization
- Multi-column layouts where appropriate
- Mouse interaction affordances

### Mobile Pass
Consider mobile-specific UX patterns:
- Touch target sizes (minimum 44x44px)
- Swipe gestures where natural
- Bottom-sheet patterns for actions
- Thumb-zone optimization
- Viewport-appropriate font sizes
- No hover-dependent interactions

**Optimize each platform separately rather than compromising both.**

## Step 4: Iterate

Run another scrutiny pass on the changes made. Look for:
- Regressions introduced by polish changes
- New inconsistencies created
- Further opportunities revealed by the improvements

Repeat until improvements become marginal (typically 2-3 rounds total).

## Output

Summary of changes made, organized by category:
- Visual improvements
- Interaction improvements
- Responsive/platform improvements
- Accessibility improvements

Note any suggestions that were generated but not pursued (for future reference).

## Anti-patterns
- Polishing before core functionality works
- Making all changes without user review of suggestions first
- Treating desktop and mobile as the same optimization problem
- Over-animating (subtle > flashy)
- Ignoring accessibility in pursuit of aesthetics
