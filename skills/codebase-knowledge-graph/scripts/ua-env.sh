#!/usr/bin/env bash
# ua-env.sh — resolve the installed Understand-Anything plugin and ensure core is built.
# SOURCE this script (it exports PLUGIN_ROOT and SKILL_DIR); do not run in a subshell.
#   source skills/codebase-knowledge-graph/scripts/ua-env.sh
# Idempotent. Requires Node >=22 and pnpm >=10 for the one-time core build.
#
# shellcheck disable=SC2317  # `return||exit` is the portable sourced-or-executed guard; exit reads as unreachable to shellcheck

_ua_version_gt() {
  local a="$1" b="$2" i max ai bi
  local -a a_parts b_parts

  IFS=. read -r -a a_parts <<< "$a"
  IFS=. read -r -a b_parts <<< "$b"
  max="${#a_parts[@]}"
  if [ "${#b_parts[@]}" -gt "$max" ]; then max="${#b_parts[@]}"; fi

  for ((i = 0; i < max; i++)); do
    ai="${a_parts[$i]:-0}"
    bi="${b_parts[$i]:-0}"
    if [[ "$ai" =~ ^[0-9]+$ && "$bi" =~ ^[0-9]+$ ]]; then
      if ((10#$ai > 10#$bi)); then return 0; fi
      if ((10#$ai < 10#$bi)); then return 1; fi
    elif [ "$ai" != "$bi" ]; then
      [ "$ai" \> "$bi" ]
      return
    fi
  done

  return 1
}

# Resolve PLUGIN_ROOT: prefer harness-provided, else the highest semver dir in the CC plugin cache.
_ua_resolve_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/pnpm-workspace.yaml" ]; then
    printf '%s\n' "$CLAUDE_PLUGIN_ROOT"; return 0
  fi
  local base="$HOME/.claude/plugins/cache/understand-anything/understand-anything"
  [ -d "$base" ] || return 1
  # Pick the highest version subdir that contains the workspace marker.
  local best=""
  local best_version=""
  local d
  local version
  for d in "$base"/*/; do
    [ -f "${d}pnpm-workspace.yaml" ] || continue
    version="${d%/}"
    version="${version##*/}"
    if [ -z "$best" ] || _ua_version_gt "$version" "$best_version"; then
      best="$d"
      best_version="$version"
    fi
  done
  [ -n "$best" ] || return 1
  printf '%s\n' "${best%/}"
}

PLUGIN_ROOT="$(_ua_resolve_root)" || {
  echo "ua-env: cannot find the understand-anything plugin. Install it:" >&2
  echo "  claude plugin marketplace add Egonex-AI/Understand-Anything && claude plugin install understand-anything" >&2
  return 1 2>/dev/null || exit 1
}
SKILL_DIR="$PLUGIN_ROOT/skills/understand"
export PLUGIN_ROOT SKILL_DIR

# Build @understand-anything/core once (the .mjs scripts import its dist).
if [ ! -f "$PLUGIN_ROOT/packages/core/dist/index.js" ]; then
  echo "ua-env: building @understand-anything/core (one-time)..." >&2
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "ua-env: pnpm not found. Install Node >=22 and pnpm >=10, then re-run." >&2
    return 1 2>/dev/null || exit 1
  fi
  # NOTE: no '| tail' here — a swallowed exit code would mask a failed build.
  ( cd "$PLUGIN_ROOT" && PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false \
      pnpm install --config.dangerouslyAllowAllBuilds=true >/dev/null 2>&1 \
    && PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN=false pnpm --filter @understand-anything/core build >/dev/null 2>&1 )
  if [ -f "$PLUGIN_ROOT/packages/core/dist/index.js" ]; then
    echo "ua-env: core built." >&2
  else
    echo "ua-env: core build FAILED — run manually: (cd '$PLUGIN_ROOT' && pnpm install && pnpm --filter @understand-anything/core build)" >&2
    return 1 2>/dev/null || exit 1
  fi
fi

echo "ua-env: PLUGIN_ROOT=$PLUGIN_ROOT" >&2
