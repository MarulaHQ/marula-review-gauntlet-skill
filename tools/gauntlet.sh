#!/usr/bin/env bash
# gauntlet.sh - mechanical preflight for the review gauntlet.
#
# Runs the checks that are too small to remember and too expensive to miss:
# PR body completeness, broken doc links, dead paths in prose, env vars and
# compose profiles that exist only in documentation, plus the linters that
# cover the artifact classes the sample PRs kept failing on.
#
# Nothing here is a verdict. Every hit is a prompt to look, and the exit status
# is 0 unless --strict is given and a candidate in a blocking class was found.
#
# usage: tools/gauntlet.sh [base] [--strict] [--max N] [--pr-body] [--coderabbit]
#                          [--no-sweep]
#   base        revision to compare against (default: origin/main, then HEAD~1)
#   --strict    exit 1 when any candidate is found
#   --max N     candidates shown per check (default 10)
#   --pr-body   print a draft PR body with the evidence this script can gather
#   --coderabbit  run `coderabbit review --agent --gate major` when available
#   --no-sweep  skip the sibling prereview-sweep.sh delegation
#
# Scope includes committed branch changes and uncommitted edits to tracked
# files. Untracked files are named but not read.

set -u

BASE=""
STRICT=0
MAX=10
PR_BODY=0
RUN_CODERABBIT=0
RUN_SWEEP=1

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --max) shift; MAX="${1:-10}"; shift ;;
    --pr-body) PR_BODY=1; shift ;;
    --coderabbit) RUN_CODERABBIT=1; shift ;;
    --no-sweep) RUN_SWEEP=0; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
    *) BASE="$1"; shift ;;
  esac
done

TOTAL=0
add() { TOTAL=$((TOTAL + ${1:-1})); }

section() { printf '\n== %s\n' "$1"; }
sub() { printf '\n-- %s (%s)\n' "$1" "$2"; }

if [ -z "$BASE" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
    BASE=origin/main
  else
    BASE=HEAD~1
  fi
fi
if ! git rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
  printf 'base revision not found: %s\n' "$BASE" >&2
  exit 2
fi

MERGE_BASE=$(git merge-base "$BASE" HEAD 2>/dev/null || printf '%s' "$BASE")
FILES=$(git diff --name-only "$MERGE_BASE" -- . 2>/dev/null)
if [ -z "$FILES" ]; then
  printf 'no changes against %s (merge base %s)\n' "$BASE" "$MERGE_BASE"
  exit 0
fi

CHANGED_COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')
ADDED=$(git diff -U0 --no-color "$MERGE_BASE" -- . 2>/dev/null | awk '/^\+\+\+ b\//{f=substr($0,7);next} /^\+/ && !/^\+\+\+/{print f "\t" substr($0,2)}')
ADDED_LINES=$(printf '%s\n' "$ADDED" | grep -c . | tr -d ' ')

MD_FILES=$(printf '%s\n' "$FILES" | grep -E '\.mdx?$' || true)
SH_FILES=$(printf '%s\n' "$FILES" | grep -E '\.sh$' || true)
WF_FILES=$(printf '%s\n' "$FILES" | grep -E '^\.github/workflows/.*\.ya?ml$' || true)
CHART_CHANGED=$(printf '%s\n' "$FILES" | grep -cE '^deploy/helm/' || true)

printf 'review gauntlet: %s...%.10s  (%s added lines in %s files)\n' \
  "$BASE" "$MERGE_BASE" "$ADDED_LINES" "$CHANGED_COUNT"

UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | head -20)
if [ -n "$UNTRACKED" ]; then
  printf 'untracked (not read; stage them or check by hand):\n'
  printf '%s\n' "$UNTRACKED" | sed 's/^/  /'
fi

if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  printf 'working tree is dirty: the pre-review sweep reads committed changes only.\n'
  printf '  commit a signed-off WIP first, or read its result as covering the commit only.\n'
fi

# ---------------------------------------------------------------------------
# 1. The sibling sweep: contract classes, panics, SQLx, migrations.
# ---------------------------------------------------------------------------
if [ "$RUN_SWEEP" -eq 1 ] && [ "$PR_BODY" -eq 0 ]; then
  SWEEP=""
  # `..` after a symlinked skill resolves to the checkout's parent, not the
  # skills directory, so strip the path textually instead of walking through it.
  TOOLS_DIR=$(cd -L "$(dirname "$0")" >/dev/null 2>&1 && pwd -L)
  SKILL_DIR=${TOOLS_DIR%/tools}
  SKILLS_DIR=${SKILL_DIR%/*}
  for candidate in \
    "${GAUNTLET_PRE_REVIEW:-}" \
    "$SKILLS_DIR/marula-pre-review/tools/prereview-sweep.sh" \
    "$SKILLS_DIR/pre-review/tools/prereview-sweep.sh" \
    "$SKILLS_DIR/marula-code-review-skill/tools/prereview-sweep.sh" \
    "$HOME/.agents/skills/marula-pre-review/tools/prereview-sweep.sh" \
    "$TOOLS_DIR/prereview-sweep.sh"
  do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then SWEEP="$candidate"; break; fi
  done
  if [ -n "$SWEEP" ]; then
    section "pre-review sweep"
    sweep_out=$(bash "$SWEEP" "$BASE" --max "$MAX" 2>&1) || true
    printf '%s\n' "$sweep_out"
    sweep_n=$(printf '%s\n' "$sweep_out" | sed -n 's/^\([0-9][0-9]*\) candidate(s).*/\1/p' | tail -1)
    add "${sweep_n:-0}"
  else
    printf '\n(pre-review sweep not found beside this script; skipped)\n'
  fi
fi

# ---------------------------------------------------------------------------
# 2. Documentation claims: links, paths, env vars, profiles.
# ---------------------------------------------------------------------------
if [ "$PR_BODY" -eq 0 ] && [ -n "$MD_FILES" ]; then
  section "docs claims"

  # 2a. Relative links that do not resolve.
  broken=""
  for f in $MD_FILES; do
    [ -f "$f" ] || continue
    dir=$(dirname "$f")
    while IFS= read -r link; do
      case "$link" in
        ''|'#'*|http://*|https://*|mailto:*|tel:*|"<"*|*'{{'*|*'$'*) continue ;;
      esac
      target=${link%%#*}
      target=${target%%\?*}
      [ -z "$target" ] && continue
      case "$target" in
        /*) continue ;;
      esac
      if [ ! -e "$dir/$target" ]; then
        broken="$broken$f -> $link"$'\n'
      fi
    done < <(grep -oE '\]\([^)]+\)' "$f" 2>/dev/null | sed -e 's/^](//' -e 's/)$//')
  done
  if [ -n "$broken" ]; then
    n=$(printf '%s' "$broken" | grep -c . | tr -d ' ')
    add "$n"
    sub "relative links that do not resolve" "$n"
    printf '%s' "$broken" | sed -n "1,${MAX}p" | sed 's/^/  /'
  fi

  # 2b. Backticked repo paths that do not exist (added lines only).
  dead_paths=$(printf '%s\n' "$ADDED" | awk -F'\t' '$1 ~ /\.mdx?$/ {print $2}' | \
    grep -oE '`[^`]+`' | tr -d '`' | sort -u | \
    awk '{
      p=$0
      gsub(/[.,;:)]+$/, "", p)
      if (p ~ / /) { split(p, a, " "); p=a[1] }
      if (p ~ /[ *{}<>$|]/) next
      if (p ~ /^(crates|apps|packages|scripts|deploy|docs|e2e|fixtures|release-notes|plugins|workers|native|installer|desktop)\// ||
          p ~ /^(AGENTS|CONTRIBUTING|SECURITY|RELEASING|CHANGELOG|ROADMAP|README)\.md$/) {
        print p
      }
    }' | while IFS= read -r p; do
      [ -z "$p" ] && continue
      if [ ! -e "$p" ]; then printf '%s\n' "$p"; fi
    done)
  if [ -n "$dead_paths" ]; then
    n=$(printf '%s\n' "$dead_paths" | wc -l | tr -d ' ')
    add "$n"
    sub "paths named in prose that do not exist" "$n"
    printf '%s\n' "$dead_paths" | sed -n "1,${MAX}p" | sed 's/^/  /'
  fi

  # 2c. MARULA_* env vars in prose that exist nowhere in code or config.
  have_rg=0; command -v rg >/dev/null 2>&1 && have_rg=1
  ghost_vars=$(printf '%s\n' "$ADDED" | awk -F'\t' '$1 ~ /\.mdx?$/ {print $2}' | \
    grep -oE '\bMARULA_[A-Z0-9_]+' | sort -u | while IFS= read -r v; do
      [ -z "$v" ] && continue
      if [ "$have_rg" -eq 1 ]; then
        found=$(rg -l --glob '!*.md' --glob '!*.mdx' --glob '!node_modules' \
          --glob '!target' --glob '!.git' -- "$v" . 2>/dev/null | head -1)
      else
        found=$(grep -rl --exclude='*.md' --exclude-dir=node_modules \
          --exclude-dir=target --exclude-dir=.git -- "$v" . 2>/dev/null | head -1)
      fi
      [ -z "$found" ] && printf '%s\n' "$v"
    done)
  if [ -n "$ghost_vars" ]; then
    n=$(printf '%s\n' "$ghost_vars" | wc -l | tr -d ' ')
    add "$n"
    sub "env vars documented but not read by code" "$n"
    printf '%s\n' "$ghost_vars" | sed -n "1,${MAX}p" | sed 's/^/  /'
  fi

  # 2d. docker compose profiles named in prose that compose does not define.
  if [ -f deploy/docker-compose.yml ]; then
    ghost_profiles=$(printf '%s\n' "$ADDED" | awk -F'\t' '$1 ~ /\.mdx?$/ {print $2}' | \
      grep -oE '\-\-profile[= ][a-zA-Z0-9_-]+' | awk '{print $NF}' | sed 's/^=//' | sort -u | \
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        if ! grep -nE '^[[:space:]]*-[[:space:]]*'"$p"'[[:space:]]*$' deploy/docker-compose.yml >/dev/null 2>&1; then
          printf '%s\n' "$p"
        fi
      done)
    if [ -n "$ghost_profiles" ]; then
      n=$(printf '%s\n' "$ghost_profiles" | wc -l | tr -d ' ')
      add "$n"
      sub "compose profiles named in prose that compose does not define" "$n"
      printf '%s\n' "$ghost_profiles" | sed -n "1,${MAX}p" | sed 's/^/  /'
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3. Infrastructure: run the linters that cover the changed artifact.
# ---------------------------------------------------------------------------
if [ "$PR_BODY" -eq 0 ] && { [ -n "$WF_FILES" ] || [ -n "$SH_FILES" ] || [ "$CHART_CHANGED" -gt 0 ]; }; then
  section "infrastructure"
fi

if [ "$PR_BODY" -eq 0 ] && [ -n "$WF_FILES" ]; then
  if command -v actionlint >/dev/null 2>&1; then
    existing=""
    for f in $WF_FILES; do [ -f "$f" ] && existing="$existing $f"; done
    if [ -n "$existing" ]; then
      out=$(actionlint $existing 2>&1) || true
      if [ -n "$out" ]; then
        n=$(printf '%s\n' "$out" | grep -cE '^[^ ]+:[0-9]+:[0-9]+:' || true)
        [ "${n:-0}" -eq 0 ] && n=1
        add "$n"
        sub "actionlint" "$n"
        printf '%s\n' "$out" | sed -n "1,${MAX}p" | sed 's/^/  /'
      else
        printf '\n-- actionlint: clean on %s workflow file(s)\n' "$(printf '%s\n' "$existing" | wc -w | tr -d ' ')"
      fi
    fi
  else
    printf '\n(actionlint not installed; workflows changed but not linted)\n'
  fi
fi

if [ "$PR_BODY" -eq 0 ] && [ -n "$SH_FILES" ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    existing=""
    for f in $SH_FILES; do [ -f "$f" ] && existing="$existing $f"; done
    if [ -n "$existing" ]; then
      out=$(shellcheck -S warning -f gcc $existing 2>&1) || true
      if [ -n "$out" ]; then
        n=$(printf '%s\n' "$out" | grep -c . | tr -d ' ')
        add "$n"
        sub "shellcheck -S warning" "$n"
        printf '%s\n' "$out" | sed -n "1,${MAX}p" | sed 's/^/  /'
      else
        printf '\n-- shellcheck: clean on the changed script(s)\n'
      fi
    fi
  else
    printf '\n(shellcheck not installed; scripts changed but not linted)\n'
  fi
fi

if [ "$PR_BODY" -eq 0 ] && [ "$CHART_CHANGED" -gt 0 ] && command -v helm >/dev/null 2>&1; then
  for chart in deploy/helm/*/; do
    [ -f "${chart}Chart.yaml" ] || continue
    out=$(helm lint "$chart" 2>&1) || true
    printf '\n-- helm lint %s\n' "$chart"
    printf '%s\n' "$out" | tail -5 | sed 's/^/  /'
    values=""
    if [ -f deploy/helm/test/hosted-values.yaml ]; then
      values="--values deploy/helm/test/hosted-values.yaml"
    fi
    # Render once at defaults and once at the values a user is told to set.
    # Schema violations surface here, not at lint time.
    render_out=$(helm template marula "$chart" $values 2>&1) && render_rc=0 || render_rc=$?
    if [ "$render_rc" -eq 0 ]; then
      printf '  template: renders%s\n' "${values:+ with hosted values}"
    else
      add 1
      printf '  template: FAILED%s\n' "${values:+ with hosted values}"
      printf '%s\n' "$render_out" | sed -n '1,8p' | sed 's/^/    /'
    fi
  done
elif [ "$PR_BODY" -eq 0 ] && [ "$CHART_CHANGED" -gt 0 ]; then
  printf '\n(helm not installed; chart changed but not rendered)\n'
fi

# ---------------------------------------------------------------------------
# 4. PR body.
# ---------------------------------------------------------------------------
if [ "$PR_BODY" -eq 1 ]; then
  section "draft PR body"
  subjects=$(git log --format='%s' "$MERGE_BASE..HEAD" 2>/dev/null)
  bad_subjects=$(printf '%s\n' "$subjects" | grep -vE '^(feat|fix|docs|refactor|test|chore|ci|perf|build|revert)(\([^)]+\))?!?: ' || true)
  trailer_missing=""
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    if [ -z "${row##*| }" ]; then trailer_missing="$trailer_missing$row"$'\n'; fi
  done < <(git log --format='%h| %(trailers:key=Signed-off-by,valueonly)' "$MERGE_BASE..HEAD" 2>/dev/null)
  fragment=$(printf '%s\n' "$FILES" | grep -c '^release-notes/unreleased/' || true)
  new_tables=$(git diff "$MERGE_BASE" -- crates/core-db/migrations 2>/dev/null | grep -cE '^\+.*CREATE TABLE' || true)

  printf '## What this changes\n\n'
  printf '<one or two sentences; link the issue if there is one>\n\n'
  printf '## Checklist\n\n'
  if [ -z "$trailer_missing" ]; then
    printf -- '- [x] Every commit is signed off per the DCO, and the trailer matches the author.\n'
  else
    printf -- '- [ ] DCO: missing or unreadable trailer on these commits — %s\n' "$(printf '%s' "$trailer_missing" | awk -F'|' '{printf "%s ", $1}')"
  fi
  if [ -z "$bad_subjects" ]; then
    printf -- '- [x] Conventional commit subjects.\n'
  else
    printf -- '- [ ] Conventional subjects: %s\n' "$(printf '%s' "$bad_subjects" | tr '\n' ';')"
  fi
  if [ "$fragment" -gt 0 ]; then
    printf -- '- [x] Release-note fragment present.\n'
  else
    printf -- '- [ ] Changelog: add a fragment with `node scripts/release-note.mjs add ...`, or say why no user-visible change.\n'
  fi
  printf -- '- [ ] No raw hex outside `packages/ui`; clippy and tsc results stated (checked / not applicable — reason).\n'
  if [ "$new_tables" -gt 0 ]; then
    printf -- '- [ ] New user-data table(s) in the migration diff: confirm `org_id` and an RLS policy.\n'
  else
    printf -- '- [x] New user-data tables: none in this diff.\n'
  fi
  exit 0
fi

if command -v gh >/dev/null 2>&1; then
  pr=$(gh pr view --json number,body,url 2>/dev/null || true)
  if [ -n "$pr" ]; then
    section "PR body"
    if command -v jq >/dev/null 2>&1; then
      body=$(printf '%s' "$pr" | jq -r '.body // ""')
      url=$(printf '%s' "$pr" | jq -r '.url // ""')
      unchecked=$(printf '%s\n' "$body" | grep -c '^[[:space:]]*- \[ \]' || true)
      has_sections=1
      printf '%s\n' "$body" | grep -q '^## What this changes' || has_sections=0
      printf '%s\n' "$body" | grep -q '^## Checklist' || has_sections=0
      printf '  %s\n' "$url"
      if [ "$has_sections" -eq 0 ]; then
        add 1
        printf '  -> missing the template headings (What this changes / Checklist)\n'
      fi
      if [ "${unchecked:-0}" -gt 0 ]; then
        add "$unchecked"
        printf '  -> %s unchecked checklist item(s)\n' "$unchecked"
        printf '%s\n' "$body" | grep '^[[:space:]]*- \[ \]' | sed -n "1,${MAX}p" | sed 's/^/     /'
      else
        printf '  -> every checklist item is answered\n'
      fi
    else
      printf '  (jq not installed; PR body not parsed)\n'
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. The oracle.
# ---------------------------------------------------------------------------
section "external oracle"
if [ "$RUN_CODERABBIT" -eq 1 ]; then
  if command -v coderabbit >/dev/null 2>&1; then
    printf 'running: coderabbit review --agent --committed --deep --gate major\n'
    printf '(exit 2 = blocking finding, exit 1 = incomplete review, 0 = gate passed)\n\n'
    coderabbit review --agent --committed --deep --gate major
    rc=$?
    case "$rc" in
      0) printf '\n  gate: passed\n' ;;
      2) add 1; printf '\n  gate: BLOCKED — findings at or above major\n' ;;
      *) add 1; printf '\n  gate: INCOMPLETE (exit %s) — this is not a clean result\n' "$rc" ;;
    esac
  else
    printf '  coderabbit CLI not installed; run `coderabbit review --agent --gate major` once it is\n'
  fi
else
  printf '  not run. Before a push:\n'
  printf '    coderabbit review --agent --uncommitted          # during the loop\n'
  printf '    coderabbit review --agent --committed --deep --gate major\n'
fi

printf '\n%d candidate(s). None of these is a verdict: read each one.\n' "$TOTAL"
if [ "$STRICT" -eq 1 ] && [ "$TOTAL" -gt 0 ]; then
  printf '%d candidate(s) remain: resolve or justify each before pushing.\n' "$TOTAL" >&2
  exit 1
fi
exit 0
