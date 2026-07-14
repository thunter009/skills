#!/usr/bin/env bash
# skills-router UserPromptSubmit hook (bd-lf1).
# Reads hook JSON from stdin, classifies the prompt, and injects a one-line
# "consider these skills" advisory as additionalContext. Advisory only —
# never blocks, never rewrites the prompt, exits 0 on every path.
#
# Env: SKILLS_ROUTER_QUIET=1  suppress all output
#      SKILLS_ROUTER_LOG=DIR  decision log dir (default ~/.cache/skills-router)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
input=$(cat)

if [ "${SKILLS_ROUTER_QUIET:-}" = "1" ]; then
  exit 0
fi

user_prompt=$(echo "$input" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null) || exit 0

# Bypass: empty / very short prompts — no signal worth routing
if [ -z "$user_prompt" ] || [ ${#user_prompt} -lt 5 ]; then
  exit 0
fi

# Bypass: slash commands (with or without args) — already dispatched.
# Anchored so prompts that merely START with a file path (/Users/..., /tmp/x
# has a bug) still get routed: slash + lowercase command word + space-or-end.
if echo "$user_prompt" | grep -qE '^[[:space:]]*/[a-z][a-z0-9_:-]*([[:space:]]|$)'; then
  exit 0
fi

# Keyword signal lives in the head of the prompt; classifying a 500KB paste
# is O(length) (~0.85s measured) for no accuracy gain. Truncate first.
classify_input=${user_prompt:0:4096}

result=$("$SCRIPT_DIR/classify.sh" "$classify_input" 2>/dev/null) || exit 0

strength=$(echo "$result" | jq -r '.strength' 2>/dev/null) || exit 0
if [ "$strength" = "weak" ]; then
  exit 0
fi

category=$(echo "$result" | jq -r '.category')
skills_list=$(echo "$result" | jq -r '.skills | map("/" + .) | join(", ")')
[ -z "$skills_list" ] && exit 0

# Fire-and-forget decision log (same shape as effort-router's)
LOG_DIR="${SKILLS_ROUTER_LOG:-$HOME/.cache/skills-router}"
if mkdir -p "$LOG_DIR" 2>/dev/null; then
  # Pure-bash preview: a pipeline (printf|tr|head -c) SIGPIPEs on >64KB
  # prompts under pipefail and kills the hook before it emits JSON
  prompt_preview=${user_prompt:0:80}
  prompt_preview=${prompt_preview//$'\n'/ }
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg category "$category" \
    --arg skills "$skills_list" \
    --arg strength "$strength" \
    --arg prompt_preview "$prompt_preview" \
    '{ts:$ts,category:$category,skills:$skills,strength:$strength,prompt_preview:$prompt_preview}' \
    >> "$LOG_DIR/decisions.jsonl" 2>/dev/null || true
fi

advisory="Skills router: looks like a ${category} task (${strength}) -- consider ${skills_list} if one fits; ignore if not."

jq -n --arg ctx "$advisory" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
