#!/usr/bin/env bash
# audit-instructions.sh — currency + size audit for CLAUDE.md / AGENTS.md files.
#
# Walks each instruction file, checks every path-like token (inline code spans
# and fenced code blocks) against the filesystem, checks the first word of shell
# commands against PATH, and enforces the "<N>-line budget" declared in the
# file's contract header. Companion to the agents-md skill ("Keeping It Lean",
# guards 2 and 4). Bash 3.2 compatible; needs only git + coreutils + find.
#
# Findings
#   STALE    <file>:<line>  <path>         path exists neither at the root, nor beside
#                                          the file, nor as a suffix under root (hard)
#   BUDGET   <file>         <lines>/<N>    over the declared line budget      (hard)
#   NOCMD    <file>:<line>  <cmd>          first word of a command not on PATH nor in a
#                                          project-local bin (.venv/bin, venv/bin,
#                                          node_modules/.bin beside the file or at root) (advisory)
#   NOHEADER <file>                        no "<N>-line budget" header        (advisory)
#
# Skipped by design: tree listings (lines with ├── or |--), globs, placeholders
# (<name>, {x}, $VAR, _v2, _backup, xxx, …), slash commands (/release), git refs
# and owner/repo slugs, scratch and foreign absolute paths (/tmp, /Users/other).
# Relative paths whose first segment is unknown and that carry no file extension
# are also skipped — the audit prefers silence to a false STALE.
#
# Run it inside a working checkout. A `git archive` extract lacks gitignored paths
# (data dirs, caches, node_modules) and reports every one of them STALE.
#
# Global rulebooks (a dotfiles CLAUDE.md or AGENTS.md that describes other repos,
# machines and the vault) name paths outside this root: audit them with
# --no-relative, which keeps absolute, ~, budget and command checks and drops
# relative-path checks.
#
# Exit: 0 clean · 1 hard findings (or advisory with --strict) · 2 usage error
set -u -o pipefail

usage() {
  cat <<'USAGE'
Usage: audit-instructions.sh [OPTIONS] [FILE...]

  FILE...        instruction files to audit (default: CLAUDE.md and AGENTS.md at --root)
  --root DIR     repo root for resolving relative paths (default: each file's git toplevel)
  --all          audit every CLAUDE.md / AGENTS.md / .claude.local.md below --root
  --no-relative  skip relative-path checks (global rulebooks that describe other roots)
  --strict       advisory findings (NOCMD, NOHEADER) also fail the run
                 (NOCMD looks on PATH, then .venv/bin, venv/bin, node_modules/.bin
                 beside the file and at the root)
  --ignore ERE   skip tokens matching ERE (added to the built-in placeholder list)
  -h, --help     show this help

Exit: 0 clean · 1 findings · 2 usage error
USAGE
}

ROOT_OPT=""
ALL=0
STRICT=0
NO_RELATIVE=0
HARD=0
ADV=0
FILE_COUNT=0
ROOT_NAME=""
FILE_DIR=""

# Tokens that are documentation examples, not facts (anti-pattern names, placeholders).
IGNORE_RE='(_v2|_V2|V2\.|_backup|_improved|_old\.|xxx|XXX|placeholder|\.\.\.|…|^(Next|Node|Vue|Nuxt)\.js$)'
# A word with one of these extensions is checked even when its first segment is unknown.
EXT_RE='\.(sh|bash|zsh|py|rb|md|json|jsonl|ya?ml|toml|ts|tsx|js|mjs|cjs|rs|go|txt|cfg|ini|lock|env|plist|sql|html|css)$'
# Any of these characters marks a word as syntax, a glob, a placeholder, or a ref — never a path.
BAD_CHARS=$'[]<>*?$|"\'{}()[\\=:!]'
# First path segment that is a domain name (github.com/x/) — a URL fragment, not a path.
DOMAIN_RE='^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|org|net|io|dev|ai|app|co|xyz)$'
CMD_RE='^[a-z][a-z0-9._+-]*$'
SHA_RE='^[0-9a-f]{7,40}$'
# First words that look like commands but are not (conventional-commit types, Latin abbreviations).
STOP_CMDS='^(feat|fix|chore|docs|style|refactor|perf|build|ci|revert|e\.g|i\.e|add|am|bisect|blame|branch|checkout|cherry-pick|clean|clone|commit|config|fetch|merge|pull|push|rebase|reflog|remote|reset|restore|show|stash|status|submodule|switch|tag|worktree)$'
# Directory tree listings: paths there are relative to their parent line, not the root.
TREE_RE='(├|└|│|──|^[[:space:]]*[|+\\`]--)'
# Directories find(1) never descends into.
PRUNE=( '(' -name .git -o -name node_modules -o -name .venv -o -name target -o -name .ntm ')' -prune )
# A fenced line that is just "name/" is a tree root or an indentation-only tree entry.
LONE_DIR_RE='^[A-Za-z0-9._-]+/$'

FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root)   [ $# -ge 2 ] || { usage >&2; exit 2; }; ROOT_OPT="$2"; shift 2 ;;
    --all)    ALL=1; shift ;;
    --strict) STRICT=1; shift ;;
    --no-relative) NO_RELATIVE=1; shift ;;
    --ignore) [ $# -ge 2 ] || { usage >&2; exit 2; }; IGNORE_RE="($IGNORE_RE|$2)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --)       shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*)       printf 'audit-instructions: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)        FILES+=("$1"); shift ;;
  esac
done

default_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

if [ "${#FILES[@]}" -eq 0 ]; then
  base="${ROOT_OPT:-$(default_root)}"
  if [ "$ALL" -eq 1 ]; then
    while IFS= read -r f; do FILES+=("$f"); done < <(
      find "$base" "${PRUNE[@]}" -o \( -name CLAUDE.md -o -name AGENTS.md -o -name .claude.local.md \) -type f -print | sort
    )
  else
    for n in CLAUDE.md AGENTS.md; do
      [ -f "$base/$n" ] && FILES+=("$base/$n")
    done
  fi
fi
if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'audit-instructions: no CLAUDE.md or AGENTS.md found (use --root or pass files)\n' >&2
  exit 2
fi

finding() {  # kind where what
  printf '%-8s %-32s %s\n' "$1" "$2" "$3"
}

file_root() {  # file -> repo root used for relative paths
  if [ -n "$ROOT_OPT" ]; then printf '%s\n' "$ROOT_OPT"; return; fi
  local d
  d="$(cd "$(dirname "$1")" && pwd)"
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$d"
}

exists_anywhere() {  # root relpath -> 0 when relpath exists as a path suffix somewhere under root
  local hit
  hit="$(find "$1" "${PRUNE[@]}" -o -path "*/$2" -print 2>/dev/null | head -n1)"
  [ -n "$hit" ]
}

cmd_available() {  # cmd root -> 0 when on PATH or in a project-local bin beside the file or at root
  local c="$1" root="$2" d
  command -v "$c" >/dev/null 2>&1 && return 0
  for d in "$FILE_DIR" "$root"; do
    [ -n "$d" ] || continue
    [ -x "$d/.venv/bin/$c" ] || [ -x "$d/venv/bin/$c" ] || [ -x "$d/node_modules/.bin/$c" ] && return 0
  done
  return 1
}

# resolve_path WORD ROOT — sets RES_WORD / RES_PATH / RES_REL when WORD names a path; returns 1 otherwise.
# RES_REL is the root-relative form (empty for absolute, ~ and ../ paths).
RES_WORD=""
RES_PATH=""
RES_REL=""
resolve_path() {
  local w="$1" root="$2" first candidate=0 t
  w="${w%%:[0-9]*}"          # drop a trailing :LINE reference
  w="${w%[,.;]}"             # drop trailing prose punctuation
  case "$w" in
    ''|/|-*|*://*) return 1 ;;
  esac
  [[ $w =~ $BAD_CHARS ]] && return 1
  [[ $w =~ $IGNORE_RE ]] && return 1
  [ "$w" = "$ROOT_NAME/" ] && return 1          # the repo's own name heading a tree listing
  case "$w" in
    /*)
      t="${w#/}"; t="${t%/}"
      case "$t" in */*) ;; *) return 1 ;; esac    # one segment = slash command or URL route
      case "$w" in                                # only paths this machine can vouch for
        "$root"/*|"$HOME"/*|/usr/*|/etc/*|/opt/*) candidate=1 ;;
        *) return 1 ;;
      esac ;;
    ./*|../*|\~/*|*/) candidate=1 ;;
    *)
      [[ $w =~ $EXT_RE ]] && candidate=1
      if [ "$candidate" -eq 0 ]; then
        case "$w" in
          */*) first="${w%%/*}"; [ -e "$root/$first" ] && candidate=1 ;;
        esac
      fi ;;
  esac
  [ "$candidate" -eq 1 ] || return 1
  first="${w#./}"; first="${first%%/*}"
  [[ $first =~ $DOMAIN_RE ]] && return 1
  RES_WORD="$w"
  RES_REL=""
  case "$w" in
    \~/*) RES_PATH="$HOME/${w#\~/}" ;;
    /*)   RES_PATH="$w" ;;
    ../*) RES_PATH="$root/$w" ;;
    *)    RES_REL="${w#./}"; RES_REL="${RES_REL%/}"; RES_PATH="$root/$RES_REL" ;;
  esac
  RES_PATH="${RES_PATH%/}"
  return 0
}

# check_words TEXT ROOT DISPLAY LINENO MODE — MODE is inline | shell | other
check_words() {
  local text="$1" root="$2" display="$3" lineno="$4" mode="$5"
  if [ "$mode" = inline ]; then                 # a span that is one existing path, spaces and all
    local whole="$text"
    case "$whole" in \~/*) whole="$HOME/${whole#\~/}" ;; esac
    case "$whole" in /*) [ -e "$whole" ] && return 0 ;; esac
  fi
  local -a words
  read -ra words <<<"$text"
  [ "${#words[@]}" -gt 0 ] || return 0
  if [ "${words[0]}" = '$' ]; then          # console prompt
    words=("${words[@]:1}")
    [ "${#words[@]}" -gt 0 ] || return 0
  fi
  local first="${words[0]}" w
  if [ "$mode" = shell ] || { [ "$mode" = inline ] && [ "${#words[@]}" -ge 2 ]; }; then
    if [[ $first =~ $CMD_RE ]] && ! [[ $first =~ $STOP_CMDS ]] && ! [[ $first =~ $SHA_RE ]] \
       && ! [[ $first =~ $EXT_RE ]] && ! cmd_available "$first" "$root"; then
      finding NOCMD "$display:$lineno" "$first"
      ADV=$((ADV + 1))
    fi
  fi
  for w in "${words[@]}"; do
    resolve_path "$w" "$root" || continue
    if [ "$NO_RELATIVE" -eq 1 ]; then
      case "$RES_WORD" in /*|\~/*) ;; *) continue ;; esac
    fi
    [ -e "$RES_PATH" ] && continue
    if [ -n "$RES_REL" ]; then
      [ -e "$FILE_DIR/$RES_REL" ] && continue          # relative to the instruction file itself
      exists_anywhere "$root" "$RES_REL" && continue
    fi
    finding STALE "$display:$lineno" "$RES_WORD"
    HARD=$((HARD + 1))
  done
}

is_shell_lang() {  # fence info string -> shell | other
  case "$1" in
    ''|sh|bash|zsh|shell|console|terminal) printf 'shell' ;;
    *) printf 'other' ;;
  esac
}

audit_file() {
  local file="$1" root display line trimmed lineno=0 infence=0 fencemode=other
  local rest span budget lines hard_before="$HARD" adv_before="$ADV"
  if [ ! -f "$file" ]; then
    printf 'audit-instructions: not a file: %s\n' "$file" >&2
    exit 2
  fi
  root="$(file_root "$file")"
  ROOT_NAME="$(basename "$root")"
  FILE_DIR="$(cd "$(dirname "$file")" && pwd)"
  display="$file"
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
      '```'*|'~~~'*)
        if [ "$infence" -eq 0 ]; then
          infence=1
          span="${trimmed#\`\`\`}"; span="${span#~~~}"; span="${span%% *}"
          fencemode="$(is_shell_lang "$span")"
        else
          infence=0
        fi
        continue ;;
    esac
    [[ $line =~ $TREE_RE ]] && continue
    if [ "$infence" -eq 1 ]; then
      [[ $trimmed =~ $LONE_DIR_RE ]] && continue
      check_words "$line" "$root" "$display" "$lineno" "$fencemode"
      continue
    fi
    rest="$line"
    while [ "$rest" != "${rest#*\`}" ]; do     # a backtick remains
      rest="${rest#*\`}"
      span="${rest%%\`*}"
      [ "$rest" = "$span" ] && break            # unmatched opening backtick
      rest="${rest#*\`}"
      [ -n "$span" ] && check_words "$span" "$root" "$display" "$lineno" inline
    done
  done < "$file"

  # Budget: "<N>-line … budget" (words allowed between, within 40 chars), or "<N> lines" named
  # within 80 chars after the word budget (commas allowed). A line count that merely shares a
  # paragraph with the word does not count.
  budget="$(grep -ioE '[0-9][0-9,]*-line[^.]{0,40}budget|budget[^.]{0,80}[0-9][0-9,]* lines' "$file" | head -n1 | grep -oE '[0-9][0-9,]*(-line| lines)' | head -n1)"
  budget="${budget%-line}"; budget="${budget% lines}"; budget="${budget//,/}"
  lines=$(wc -l < "$file")
  lines=$((lines))
  if [ -n "$budget" ]; then
    if [ "$lines" -gt "$budget" ]; then
      finding BUDGET "$display" "$lines/$budget lines — route lessons out, delete something weaker"
      HARD=$((HARD + 1))
    fi
    printf '%s: %d hard, %d advisory, %d/%s lines\n' "$display" \
      "$((HARD - hard_before))" "$((ADV - adv_before))" "$lines" "$budget"
  else
    finding NOHEADER "$display" 'no "<N>-line budget" (or "budget … N lines") contract header'
    ADV=$((ADV + 1))
    printf '%s: %d hard, %d advisory, %d lines (no budget)\n' "$display" \
      "$((HARD - hard_before))" "$((ADV - adv_before))" "$lines"
  fi
  FILE_COUNT=$((FILE_COUNT + 1))
}

for f in "${FILES[@]}"; do
  audit_file "$f"
done

printf 'audit: %d hard, %d advisory across %d file(s)\n' "$HARD" "$ADV" "$FILE_COUNT"
if [ "$HARD" -gt 0 ]; then exit 1; fi
if [ "$STRICT" -eq 1 ] && [ "$ADV" -gt 0 ]; then exit 1; fi
exit 0
