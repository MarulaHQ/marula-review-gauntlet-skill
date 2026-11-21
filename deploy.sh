#!/usr/bin/env bash
# deploy.sh - link review-gauntlet into every agent skills directory found here.
#
# usage: ./deploy.sh [--copy] [--no-pre-review]
#   --copy             copy the skill instead of linking it
#   --no-pre-review    do not link the companion pre-review skill
#
# The canonical copy lives at ~/.agents/skills/review-gauntlet. Every other
# agent directory points at it, so an edit in this checkout reaches them all.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
NAME="review-gauntlet"
CANONICAL="$HOME/.agents/skills"
COPY=0
PRE_REVIEW=1

for arg in "$@"; do
  case "$arg" in
    --copy) COPY=1 ;;
    --no-pre-review) PRE_REVIEW=0 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'unknown flag: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$CANONICAL"
TARGETS=("$CANONICAL")
for dir in \
  "$HOME/.claude/skills" \
  "$HOME/.codex/skills" \
  "$HOME/.cursor/skills" \
  "$HOME/.gemini/skills" \
  "$HOME/.copilot/skills" \
  "$HOME/.config/opencode/skills"
do
  [ -d "$dir" ] && TARGETS+=("$dir")
done

# A real directory at the target is moved out of the skills tree, not deleted:
# a backup left inside the tree would be discovered as a second skill.
backup() {
  local target="$1"
  local cache="$HOME/.cache/review-gauntlet-backups"
  local saved
  mkdir -p "$cache"
  saved="$cache/$(basename "$(dirname "$target")")-$(date +%Y%m%d%H%M%S)"
  mv "$target" "$saved"
  printf '  moved existing %s -> %s\n' "$target" "$saved"
}

install_skill() {
  local target="$1"
  local source="$2"
  if [ "$COPY" -eq 1 ]; then
    [ -e "$target" ] && backup "$target"
    cp -R "$source" "$target"
    printf '  copied %s -> %s\n' "$source" "$target"
    return
  fi
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    backup "$target"
  fi
  ln -sfn "$source" "$target"
  printf '  link   %s -> %s\n' "$target" "$source"
}

for dir in "${TARGETS[@]}"; do
  printf '%s\n' "$dir"
  if [ "$dir" = "$CANONICAL" ]; then
    install_skill "$dir/$NAME" "$REPO"
  else
    install_skill "$dir/$NAME" "$CANONICAL/$NAME"
  fi
done

if [ "$PRE_REVIEW" -eq 1 ]; then
  PRE_SOURCE="$HOME/.agents/skills/marula-pre-review"
  [ -d "$PRE_SOURCE" ] || PRE_SOURCE="$HOME/.agents/skills/pre-review"
  [ -d "$PRE_SOURCE" ] || PRE_SOURCE="$(cd "$REPO/.." && pwd)/marula-code-review-skill"
  if [ -d "$PRE_SOURCE" ]; then
    for dir in "${TARGETS[@]}"; do
      [ -e "$dir/pre-review" ] && continue
      [ -e "$dir/marula-pre-review" ] && continue
      if [ "$COPY" -eq 1 ]; then
        cp -R "$PRE_SOURCE" "$dir/pre-review"
        printf '  copied pre-review -> %s\n' "$dir/pre-review"
      else
        ln -sfn "$PRE_SOURCE" "$dir/pre-review"
        printf '  link   %s -> %s\n' "$dir/pre-review" "$PRE_SOURCE"
      fi
    done
  else
    printf 'pre-review companion not found; pass 1 will fall back to the gauntlet copy\n'
  fi
fi

printf '\nreview-gauntlet deployed. Reload or restart the agent to pick it up.\n'
