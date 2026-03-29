#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
set -o posix

input=$(cat)

USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
MODEL=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
VERSION=$(echo "$input" | jq -r '.version // "?"')
CWD=$(echo "$input" | jq -r '.cwd // ""')

BRANCH=""
WORKTREE=""
if [ -n "$CWD" ] && [ -d "$CWD/.git" ] || [ -f "$CWD/.git" ]; then
  BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  # Check if inside a worktree (not the main working tree)
  GIT_DIR=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null || true)
  if [ -n "$GIT_DIR" ] && echo "$GIT_DIR" | grep -q '/worktrees/'; then
    WORKTREE=$(basename "${GIT_DIR//\/.git\/worktrees\//\/}")
  fi
fi

GIT_INFO=""
if [ -n "$BRANCH" ]; then
  GIT_INFO=" | ${BRANCH}"
  if [ -n "$WORKTREE" ]; then
    GIT_INFO="${GIT_INFO} (worktree: ${WORKTREE})"
  fi
fi

echo "${USED}% context used | ${MODEL} | v${VERSION}${GIT_INFO}"
