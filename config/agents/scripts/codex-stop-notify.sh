#!/usr/bin/env bash
set -euo pipefail

# Codex Stop hook: send a best-effort macOS notification.
# Stop hooks must not print plain text on stdout, so this script stays quiet.

INPUT=$(cat)

STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || STOP_ACTIVE="false"
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // "Task completed"' 2>/dev/null) || MESSAGE="Task completed"
MESSAGE=$(echo "$MESSAGE" | head -c 80)

if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${MESSAGE//\"/\\\"}\" with title \"Codex\" sound name \"Glass\"" 2>/dev/null || true
fi

exit 0
