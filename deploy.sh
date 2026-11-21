#!/usr/bin/env bash
# deploy.sh - link every skill in this repository into the agent skill dirs.
#
# usage: ./deploy.sh [--copy] [--no-pre-review]
#   --copy             copy the skills instead of linking them
#   --no-pre-review    do not link the companion pre-review skill
#
# The canonical copies live at ~/.agents/skills/<name>. Every other agent
# directory points at them, so an edit in this checkout reaches them all.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CANONICAL="$HOME/.agents/skills"
COPY=0
PRE_REVIEW=1

for arg in "$@"; do
  case "$arg" in
    --copy) COPY=1 ;;
    --no-pre-review) PRE_REVIEW=0 ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
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
  saved=$(mktemp -d "$cache/backup.XXXXXX")
  mv "$target" "$saved/$(basename "$target")"
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

shopt -s nullglob
SKILL_DIRS=("$REPO"/skills/*/)
shopt -u nullglob

if [ "${#SKILL_DIRS[@]}" -eq 0 ]; then
  printf 'no skills found under %s/skills\n' "$REPO" >&2
  exit 1
fi

for skill in "${SKILL_DIRS[@]}"; do
  name=$(basename "$skill")
  [ -f "$skill/SKILL.md" ] || continue
  printf '%s\n' "$name"
  install_skill "$CANONICAL/$name" "$skill"
  for dir in "${TARGETS[@]}"; do
    [ "$dir" = "$CANONICAL" ] && continue
    install_skill "$dir/$name" "$CANONICAL/$name"
  done
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

printf '\nskills deployed. Reload or restart the agent to pick them up.\n'
