#!/usr/bin/env bash
# skills-router classifier — keyword heuristics, zero LLM, minimal forks
# (bd-lf1; 8 score() substitutions per classification, no per-pattern greps).
# Maps a prompt to a category from setup/categories.json and 2-3 candidate
# skills. Modeled on effort-router/scripts/classify.sh but tuned for the
# <100ms budget: pure-bash [[ =~ ]] with nocasematch, printf JSON, no jq.
#
# Usage:
#   classify.sh "PROMPT"          -> JSON {category, skills, strength, hits}
#   classify.sh --batch           -> one prompt per stdin line, one JSON per
#                                    line out; single bash process (this is
#                                    what benchmark/perf paths use)
#   classify.sh --list-categories -> newline list of supported categories
#
# Output skills are capped at 3. strength=weak means no keyword signal —
# callers (hook.sh) suppress the advisory.
set -euo pipefail

# Categories this classifier can produce — unit tests diff this list against
# setup/categories.json keys so a new category can't silently go unrouted.
CATEGORIES="code testing web pm release infra docs meta home"

if [ "${1:-}" = "--list-categories" ]; then
  for c in $CATEGORIES; do echo "$c"; done
  exit 0
fi

shopt -s nocasematch

# --- Per-category keyword patterns ------------------------------------------
# One full ERE per LINE; each line that matches counts as one hit. No \b —
# bash =~ uses the platform ERE where \b is not portable (BSD libc); use
# (^|[^a-z]) style boundaries instead. Parens are fine within a line.
kw_code='refactor
debug
diagnos
(^|[^a-z])bugs?([^a-z]|$)
implement
architect
codebase
simplify
prototype
scaffold
review.{0,12}(code|diff|module)
race condition
memory leak'
kw_testing='(^|[^a-z])tests?([^a-z]|$)
testing
pytest
coverage
tdd
flaky
(^|[^a-z])lint
pre-commit
typecheck
regression
(^|[^a-z])e2e([^a-z]|$)'
kw_web='(^|[^a-z])search
research
crawl
extract
scrape
web ?page
website
(^|[^a-z])url([^a-z]|$)
browse
look up online'
kw_pm='ticket
(^|[^a-z])tasks?([^a-z]|$)
todoist
linear
backlog
groom
bead
triage
follow.?up
meeting
prioriti[sz]e
sprint'
kw_release='deploy
release
(^|[^a-z])ship([^a-z]|$)
pull request
(^|[^a-z])pr([^a-z]|$)
(^|[^a-z])merge
(^|[^a-z])land([^a-z]|$)
squash
changelog
version bump
hotfix'
kw_infra='install
bootstrap
set ?up
devbox
environment
toolchain
dotfiles
launchd
agents\.md
repo standards
worktree
swarm
mcp server
(^|[^a-z])hooks?([^a-z]|$)'
kw_docs='document
readme
(^|[^a-z])docs([^a-z]|$)
write.?up
de-?slop
polish.{0,10}(doc|prose|writing)
architecture doc'
kw_meta='(^|[^a-z])skills?([^a-z]|$)
session
journal
clean.?up.{0,10}(repo|branch)
vault
(^|[^a-z])memory([^a-z]|$)'
kw_home='recipe
mealie
meal ?plan
grocer
(^|[^a-z])cook(ing|book)?([^a-z]|$)
ingredient'

# UI / visual-design signal. Alias-only (no category keyword list): fires
# ui-polish + refactoring-ui. Kept narrow — the hook runs on every prompt.
re_ui='looks? (off|amateur|cheap|unfinished|cluttered)|make (this|it) look (better|nicer)|polish (the |this |my )?(ui|ux|frontend|front-end|screen|page|dashboard)|(^|[^a-z])(css|tailwind|stylesheet)([^a-z]|$)|(color|colour) (palette|scale|ramp)|design tokens?|(font|type) (size|scale)|(box|drop)[- ]shadows?|border[- ]radius|dark mode'

add_alias() { # $1 skill, $2 category
  case " $alias_skills " in *" $1 "*) return 0 ;; esac
  alias_skills="${alias_skills:+$alias_skills }$1"
  [ -z "$alias_category" ] && alias_category="$2"
  return 0
}

score() { # $1 = newline-separated ERE list; echoes number of lines that match
  local n=0 line
  local IFS=$'\n'
  for line in $1; do
    [ -n "$line" ] || continue
    [[ $prompt =~ $line ]] && n=$((n + 1))
  done
  echo "$n"
}

defaults_for() {
  case "$1" in
    code)    echo "refactor deep-review bug-hunt" ;;
    testing) echo "tdd fix-pytest-failures qa" ;;
    web)     echo "search research extract" ;;
    pm)      echo "groom todoist linear" ;;
    release) echo "ship release create-pull-request" ;;
    infra)   echo "start-project repo-standards agents-md" ;;
    docs)    echo "de-slopify roadmap-docs iterative-critique-polish" ;;
    meta)    echo "skill-health refine-skill clean" ;;
    home)    echo "mealie" ;;
    *)       echo "" ;;
  esac
}

classify_one() {
  prompt="$1"
  alias_skills=""
  alias_category=""

  # Direct skill-name aliases: a mention is the strongest signal. All
  # word-anchored — an alias forces a strong advisory, so substrings
  # ("nonlinear", "beading") must never fire.
  [[ $prompt =~ (^|[^a-z])linear([^a-z]|$) ]]     && add_alias linear pm
  [[ $prompt =~ (^|[^a-z])todoist([^a-z]|$) ]]    && add_alias todoist pm
  [[ $prompt =~ (^|[^a-z])beads?([^a-z]|$) ]]     && add_alias beads-bv pm
  [[ $prompt =~ (^|[^a-z])granola([^a-z]|$)|meeting\ notes ]] && add_alias meeting-sync pm
  [[ $prompt =~ (^|[^a-z])crawl ]]                && add_alias crawl web
  [[ $prompt =~ (^|[^a-z])extract ]]              && add_alias extract web
  [[ $prompt =~ (^|[^a-z])research ]]             && add_alias research web
  [[ $prompt =~ (^|[^a-z])search ]]               && add_alias search web
  [[ $prompt =~ (^|[^a-z])refactor ]]             && add_alias refactor code
  [[ $prompt =~ (^|[^a-z])bugs?([^a-z]|$) ]]      && add_alias bug-hunt code
  [[ $prompt =~ (^|[^a-z])tdd([^a-z]|$) ]]        && add_alias tdd testing
  [[ $prompt =~ (^|[^a-z])pytest([^a-z]|$) ]]     && add_alias fix-pytest-failures testing
  [[ $prompt =~ (^|[^a-z])(deploy|release)([^a-z]|$) ]] && add_alias release release
  [[ $prompt =~ (^|[^a-z])ship([^a-z]|$) ]]       && add_alias ship release
  [[ $prompt =~ pull\ request|open\ a\ pr ]]      && add_alias create-pull-request release
  [[ $prompt =~ agents\.md ]]                     && add_alias agents-md infra
  [[ $prompt =~ (^|[^a-z])de-?slop ]]             && add_alias de-slopify docs
  [[ $prompt =~ (^|[^a-z])mealie([^a-z]|$) ]]     && add_alias mealie home
  [[ $prompt =~ process\ porn|reward\ hack|(^|[^a-z])ceremony([^a-z]|$) ]] && add_alias just-say-no-to-process-porn-and-ceremony meta
  [[ $prompt =~ $re_ui ]] && { add_alias ui-polish code; add_alias refactoring-ui code; }

  local best_cat="" best_n=0 second_n=0 total_hits=0 cat n
  for cat in $CATEGORIES; do
    case "$cat" in
      code)    n=$(score "$kw_code") ;;
      testing) n=$(score "$kw_testing") ;;
      web)     n=$(score "$kw_web") ;;
      pm)      n=$(score "$kw_pm") ;;
      release) n=$(score "$kw_release") ;;
      infra)   n=$(score "$kw_infra") ;;
      docs)    n=$(score "$kw_docs") ;;
      meta)    n=$(score "$kw_meta") ;;
      home)    n=$(score "$kw_home") ;;
    esac
    total_hits=$((total_hits + n))
    if [ "$n" -gt "$best_n" ]; then
      second_n=$best_n
      best_n=$n
      best_cat=$cat
    elif [ "$n" -gt "$second_n" ]; then
      second_n=$n
    fi
  done

  # Direct alias beats a tied/weak category race
  if [ -n "$alias_category" ] && [ "$best_n" -le "$second_n" ]; then
    best_cat="$alias_category"
  fi
  [ -z "$best_cat" ] && best_cat="$alias_category"

  local strength="weak"
  if [ -n "$alias_skills" ]; then
    strength="strong"
  elif [ "$best_n" -ge 2 ] && [ "$best_n" -gt "$second_n" ]; then
    strength="strong"
  elif [ "$best_n" -ge 1 ]; then
    strength="moderate"
  fi

  # Candidates: aliases first, then category defaults, dedup, cap 3
  local skills="" count=0 s
  for s in $alias_skills $(defaults_for "$best_cat"); do
    case " $skills " in *" $s "*) continue ;; esac
    skills="${skills:+$skills }$s"
    count=$((count + 1))
    [ "$count" -ge 3 ] && break
  done

  local json_skills=""
  for s in $skills; do
    json_skills="${json_skills:+$json_skills,}\"$s\""
  done
  printf '{"category":"%s","skills":[%s],"strength":"%s","hits":%d}\n' \
    "${best_cat:-none}" "$json_skills" "$strength" "$total_hits"
}

if [ "${1:-}" = "--batch" ]; then
  while IFS= read -r line; do
    classify_one "$line"
  done
  exit 0
fi

classify_one "${1:-$(cat)}"
