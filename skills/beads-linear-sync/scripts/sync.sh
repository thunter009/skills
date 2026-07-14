#!/usr/bin/env bash
# beads-linear-sync: preflight check + mapping helpers
# Usage: sync.sh preflight                verify tools and workspace
#        sync.sh map-state <dir> <state>  map state between systems
#        sync.sh map-priority <dir> <pri> map priority between systems
#   <dir> is "to-beads" or "to-linear"
set -euo pipefail

CMD="${1:-preflight}"
shift || true

# --- Preflight: verify tools and workspace ---
preflight() {
  local ok=true
  if br --version >/dev/null 2>&1; then
    echo "br: $(br --version 2>&1 | head -1)"
  else
    echo "ERROR: br not found on PATH" >&2; ok=false
  fi

  if linear --version >/dev/null 2>&1; then
    echo "linear: $(linear --version 2>&1 | head -1)"
  else
    echo "ERROR: linear not found on PATH" >&2; ok=false
  fi

  if br info >/dev/null 2>&1; then
    echo "beads: $(br where 2>/dev/null)"
    echo "prefix: $(br config get issue_prefix 2>/dev/null || echo 'unknown')"
  else
    echo "ERROR: No .beads/ workspace, run 'br init'" >&2; ok=false
  fi

  if linear team list --no-pager >/dev/null 2>&1; then
    echo "linear-team: ok"
  else
    echo "WARN: linear team context not detected (use --team or .linear.toml)" >&2
  fi

  if $ok; then
    echo "STATUS: ready"
  else
    echo "STATUS: failed" >&2
    exit 1
  fi
}

# --- Map Linear state -> beads status ---
linear_state_to_beads() {
  case "$1" in
    triage|backlog|unstarted) echo "open" ;;
    started) echo "in_progress" ;;
    completed|canceled) echo "closed" ;;
    *) echo "open" ;;
  esac
}

# --- Map beads status -> Linear state ---
beads_status_to_linear() {
  case "$1" in
    open) echo "unstarted" ;;
    in_progress) echo "started" ;;
    closed) echo "completed" ;;
    *) echo "unstarted" ;;
  esac
}

# --- Map Linear priority (0-4) -> beads priority (0-4) ---
linear_priority_to_beads() {
  case "$1" in
    0) echo "4" ;;  # No priority -> P4
    1) echo "0" ;;  # Urgent -> P0
    2) echo "1" ;;  # High -> P1
    3) echo "2" ;;  # Medium -> P2
    4) echo "3" ;;  # Low -> P3
    *) echo "4" ;;
  esac
}

# --- Map beads priority (0-4) -> Linear priority (0-4) ---
beads_priority_to_linear() {
  case "$1" in
    0) echo "1" ;;  # P0 -> Urgent
    1) echo "2" ;;  # P1 -> High
    2) echo "3" ;;  # P2 -> Medium
    3) echo "4" ;;  # P3 -> Low
    4) echo "0" ;;  # P4 -> No priority
    *) echo "0" ;;
  esac
}

# --- Dispatch ---
case "$CMD" in
  preflight)
    preflight
    ;;
  map-state)
    dir="${1:?usage: map-state <to-beads|to-linear> <state>}"
    val="${2:?usage: map-state <to-beads|to-linear> <state>}"
    case "$dir" in
      to-beads) linear_state_to_beads "$val" ;;
      to-linear) beads_status_to_linear "$val" ;;
      *) echo "Unknown direction: $dir (to-beads or to-linear)" >&2; exit 1 ;;
    esac
    ;;
  map-priority)
    dir="${1:?usage: map-priority <to-beads|to-linear> <priority>}"
    val="${2:?usage: map-priority <to-beads|to-linear> <priority>}"
    case "$dir" in
      to-beads) linear_priority_to_beads "$val" ;;
      to-linear) beads_priority_to_linear "$val" ;;
      *) echo "Unknown direction: $dir (to-beads or to-linear)" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "Unknown command: $CMD (preflight, map-state, map-priority)" >&2
    exit 1
    ;;
esac
