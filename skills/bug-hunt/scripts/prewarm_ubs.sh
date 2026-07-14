#!/usr/bin/env bash
set -euo pipefail

# Best-effort: ensure ubs language modules are cached on the host before codex
# iterations run, so the first sandboxed `ubs <file>` call doesn't pay download
# cost (which reads as a hang from inside the codex sandbox).
#
# Uses `ubs doctor --fix`, which downloads any missing modules without running
# a scan. (Earlier draft used `ubs --update-modules`, but that also scans the
# current working directory as a side effect — wrong primitive for a prewarm
# step called from inside hunt.sh after `cd "$PROJECT_DIR"`.)
#
# Idempotent: doctor --fix only downloads modules that are missing or stale.
# Never exits non-zero — bug-hunt should not block on prewarm failure.
#
# Usage: prewarm_ubs.sh

TIMEOUT_SECONDS="${UBS_PREWARM_TIMEOUT:-180}"

if ! command -v ubs >/dev/null 2>&1; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../shared/timeout-detect.sh
if ! source "${SCRIPT_DIR}/../../shared/timeout-detect.sh" 2>/dev/null; then
  # shared/ absent (partial deploy) — inline fallback, per the never-fail contract
  detect_timeout_bin() { command -v gtimeout || command -v timeout || true; }
fi
TIMEOUT_BIN="$(detect_timeout_bin)"

# Quick check: if doctor reports no uncached modules, skip the doctor --fix run
# (which is fast but emits output). Doctor exits 0 even with warnings, so we
# parse output rather than rely on $?.
if [[ -n "$TIMEOUT_BIN" ]]; then
  DOCTOR_OUT="$("$TIMEOUT_BIN" 30 ubs doctor 2>&1 || true)"
else
  DOCTOR_OUT="$(ubs doctor 2>&1 || true)"
fi

if ! grep -q "module not cached yet" <<<"$DOCTOR_OUT"; then
  exit 0
fi

UNCACHED=$(grep -c "module not cached yet" <<<"$DOCTOR_OUT" || true)
echo "prewarm_ubs: ${UNCACHED} module(s) uncached, running 'ubs doctor --fix' (${TIMEOUT_SECONDS}s budget)" >&2

if [[ -n "$TIMEOUT_BIN" ]]; then
  "$TIMEOUT_BIN" "$TIMEOUT_SECONDS" ubs doctor --fix >/dev/null 2>&1 || \
    echo "prewarm_ubs: WARN: module download did not finish cleanly; iterations may still hit cold cache" >&2
else
  ubs doctor --fix >/dev/null 2>&1 || \
    echo "prewarm_ubs: WARN: module download did not finish cleanly; iterations may still hit cold cache" >&2
fi

exit 0
