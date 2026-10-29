#!/usr/bin/env bash
# Shared helper: orchestrator-side enforcement of --exclude-files.
#
# Safe to source — declares functions only, no side effects. Callers set
# their own shell flags.
#
# Usage:
#   bug_hunt_exclude_enforce <start_sha> <exclude_file>
#
# - start_sha: HEAD SHA captured before the engine ran
# - exclude_file: path to a newline-delimited list of excluded paths/globs
#                 (blank lines and lines starting with '#' are ignored)
#
# For each non-merge commit in start_sha..HEAD that touched any path on the
# exclude list, performs a remediation on top of HEAD:
#   - whole-commit revert: if every file in the commit is excluded, the
#                          entire commit is reverted via `git revert`.
#   - surgical restore:    if the commit mixes excluded + legitimate files,
#                          excluded paths are restored to their start_sha
#                          state in a single new commit; legitimate work in
#                          the same commit is preserved.
#
# Prints an `!!! EXCLUDE-FILE VIOLATION REMEDIATED !!!` banner when any
# remediation happens. Always returns 0 — errors are reported, not fatal.

bug_hunt_exclude_enforce() {
  local start_sha="${1:?bug_hunt_exclude_enforce: missing start_sha}"
  local exclude_file="${2:?bug_hunt_exclude_enforce: missing exclude_file path}"

  [[ -f "$exclude_file" ]] || return 0
  # start_sha must be a real object — guard against "none" / empty / typo
  git cat-file -e "${start_sha}^{commit}" 2>/dev/null || return 0

  local -a excluded=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    # ltrim/rtrim
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    excluded+=("$line")
  done < "$exclude_file"

  (( ${#excluded[@]} == 0 )) && return 0

  # Only walk non-merge commits — merge commits in this window are already a
  # Layer-2 violation (implies fetch/pull), and `git revert` requires `-m N`
  # for merges, which we don't want to guess at here.
  local -a commits=()
  while IFS= read -r commit; do
    [[ -n "$commit" ]] && commits+=("$commit")
  done < <(git rev-list --reverse --no-merges "${start_sha}..HEAD" 2>/dev/null || true)
  (( ${#commits[@]} == 0 )) && return 0

  local banner_printed=0
  local -a reverted_commits=() restore_files=() restored_commits=()
  local -a all_restore_files=() all_restored_commits=()
  local commit

  for commit in "${commits[@]}"; do
    local -a touched=() excl=() kept=()
    local f
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      touched+=("$f")
    done < <(git show --no-renames --pretty=format: --name-only "$commit" 2>/dev/null)
    (( ${#touched[@]} == 0 )) && continue

    local matched pat
    for f in "${touched[@]}"; do
      matched=0
      for pat in "${excluded[@]}"; do
        if [[ "$f" == "$pat" ]]; then matched=1; break; fi
        # shellcheck disable=SC2053
        if [[ "$f" == $pat ]]; then matched=1; break; fi
      done
      if (( matched == 1 )); then
        excl+=("$f")
      else
        kept+=("$f")
      fi
    done

    (( ${#excl[@]} == 0 )) && continue

    if (( banner_printed == 0 )); then
      printf '\n!!! EXCLUDE-FILE VIOLATION REMEDIATED !!!\n'
      banner_printed=1
    fi

    if (( ${#kept[@]} == 0 )); then
      if (( ${#restore_files[@]} > 0 )); then
        if git diff --cached --quiet -- "${restore_files[@]}"; then
          restore_files=()
          restored_commits=()
        elif git -c commit.gpgsign=false commit --quiet \
            -m "revert(bug-hunt): restore excluded paths" \
            -m "Restored paths: ${restore_files[*]}" \
            -m "From commits: ${restored_commits[*]}" \
            -- "${restore_files[@]}" >/dev/null 2>&1; then
          restore_files=()
          restored_commits=()
        else
          printf '  WARNING: surgical-restore commit failed before revert (no staged changes?)\n'
          continue
        fi
      fi
      printf '  Reverting commit %s (all files excluded): %s\n' \
        "$commit" "${excl[*]}"
      if ! git -c commit.gpgsign=false revert --no-edit "$commit" >/dev/null 2>&1; then
        printf '    WARNING: git revert failed for %s\n' "$commit"
        git revert --abort >/dev/null 2>&1 || true
        printf '    Falling back to restoring excluded paths from %s\n' "$start_sha"
        restored_commits+=("$commit")
        all_restored_commits+=("$commit")
        local p
        for p in "${excl[@]}"; do
          if git cat-file -e "${start_sha}:${p}" 2>/dev/null; then
            if git checkout "$start_sha" -- "$p" 2>/dev/null; then
              if ! git diff --cached --quiet -- "$p"; then
                restore_files+=("$p")
                all_restore_files+=("$p")
              fi
            else
              printf '    WARNING: checkout failed for %s\n' "$p"
            fi
          else
            if git rm -f --quiet -- "$p" 2>/dev/null; then
              if ! git diff --cached --quiet -- "$p"; then
                restore_files+=("$p")
                all_restore_files+=("$p")
              fi
            else
              printf '    WARNING: rm failed for %s\n' "$p"
            fi
          fi
        done
        continue
      fi
      reverted_commits+=("$commit")
    else
      printf '  Surgical restore from %s: excluded=%s kept=%s\n' \
        "$commit" "${excl[*]}" "${kept[*]}"
      restored_commits+=("$commit")
      all_restored_commits+=("$commit")
      local p
      for p in "${excl[@]}"; do
        if git cat-file -e "${start_sha}:${p}" 2>/dev/null; then
          if git checkout "$start_sha" -- "$p" 2>/dev/null; then
            if ! git diff --cached --quiet -- "$p"; then
              restore_files+=("$p")
              all_restore_files+=("$p")
            fi
          else
            printf '    WARNING: checkout failed for %s\n' "$p"
          fi
        else
          # File did not exist at start_sha; engine created it as excluded.
          if git rm -f --quiet -- "$p" 2>/dev/null; then
            if ! git diff --cached --quiet -- "$p"; then
              restore_files+=("$p")
              all_restore_files+=("$p")
            fi
          else
            printf '    WARNING: rm failed for %s\n' "$p"
          fi
        fi
      done
    fi
  done

  if (( ${#restore_files[@]} > 0 )); then
    if git diff --cached --quiet -- "${restore_files[@]}"; then
      :
    elif ! git -c commit.gpgsign=false commit --quiet \
        -m "revert(bug-hunt): restore excluded paths" \
        -m "Restored paths: ${restore_files[*]}" \
        -m "From commits: ${restored_commits[*]}" \
        -- "${restore_files[@]}" >/dev/null 2>&1; then
      printf '  WARNING: surgical-restore commit failed (no staged changes?)\n'
    fi
  fi

  if (( banner_printed == 1 )); then
    printf '  Reverted commits: %s\n' "${reverted_commits[*]:-(none)}"
    printf '  Restored paths:   %s\n' "${all_restore_files[*]:-(none)}"
    printf '  From commits:     %s\n' "${all_restored_commits[*]:-(none)}"
    printf '!!! END EXCLUDE-FILE VIOLATION !!!\n\n'
  fi
}
