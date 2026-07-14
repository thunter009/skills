# Snapshot Diff Patterns

Baseline/diff verification using accessibility tree snapshots. Take a snapshot before an action, take another after, then diff to confirm the action had the expected effect.

## Core pattern

```bash
# Capture baseline snapshot
playwright-cli snapshot --filename=/tmp/baseline.yaml

# ... perform action ...

# Capture new state and diff against baseline
playwright-cli snapshot --filename=/tmp/after.yaml
diff /tmp/baseline.yaml /tmp/after.yaml
```

The diff is text-based (accessibility tree), not pixel-based — it shows structural changes in page content and element state.

## Common workflows

### Verify click changed page state

```bash
playwright-cli snapshot --filename=/tmp/before-click.yaml
playwright-cli click e5
playwright-cli snapshot --filename=/tmp/after-click.yaml
diff /tmp/before-click.yaml /tmp/after-click.yaml
# Expect: new elements visible, button state changed, content updated
```

### Verify form submission succeeded

```bash
# Fill form
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"

# Baseline right before submit
playwright-cli snapshot --filename=/tmp/before-submit.yaml
playwright-cli click e3
playwright-cli snapshot --filename=/tmp/after-submit.yaml
diff /tmp/before-submit.yaml /tmp/after-submit.yaml
# Expect: form replaced by success message, or page navigated
```

### Verify navigation happened

```bash
playwright-cli snapshot --filename=/tmp/before-nav.yaml
playwright-cli click e10  # nav link
playwright-cli snapshot --filename=/tmp/after-nav.yaml
diff /tmp/before-nav.yaml /tmp/after-nav.yaml
# Expect: entirely different page content, new URL in snapshot header
```

### Verify toggle/accordion expand

```bash
playwright-cli snapshot --filename=/tmp/collapsed.yaml
playwright-cli click e7  # toggle button
playwright-cli snapshot --filename=/tmp/expanded.yaml
diff /tmp/collapsed.yaml /tmp/expanded.yaml
# Expect: new content lines appear (the expanded section)
```

### Multi-step verification (chained diffs)

```bash
# Step 1
playwright-cli snapshot --filename=/tmp/step0.yaml
playwright-cli click e2
playwright-cli snapshot --filename=/tmp/step1.yaml
diff /tmp/step0.yaml /tmp/step1.yaml

# Step 2 — use step1 as new baseline
playwright-cli fill e4 "data"
playwright-cli snapshot --filename=/tmp/step2.yaml
diff /tmp/step1.yaml /tmp/step2.yaml
```

## Tips

- Use `diff -u` for unified diff format (easier to read)
- Snapshots are YAML accessibility trees — grep the diff for specific text or element refs
- If diff output is empty, the action had no visible effect — investigate
- For large pages, pipe through `head -50` to focus on the first changes
- Name snapshot files descriptively (`/tmp/before-login.yaml`, `/tmp/after-login.yaml`) when running multiple diff sequences
