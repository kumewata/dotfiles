#!/usr/bin/env bash
set -euo pipefail

# Codex PermissionRequest hook.
# Denies escalation requests that should not be delegated to Auto-review.

trap 'echo "codex-permission-request-guard.sh: unexpected error" >&2; exit 2' ERR

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ "$TOOL_NAME" != "Bash" ]] && exit 0
[[ -z "$COMMAND" ]] && exit 0

deny_decision() {
  jq -n --arg message "$1" '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior: "deny",
        message: $message
      }
    }
  }'
  exit 0
}

# Keep clearly destructive shell escalations out of Auto-review. The user can
# still choose a safer explicit command or review the request manually later.
if echo "$COMMAND" | grep -qE '(^|[;&|][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+(-[^[:space:]]*[rf][^[:space:]]*|-r|-f|-rf|-fr)[[:space:]]+'; then
  deny_decision "Destructive recursive/force removal requires explicit manual handling"
fi

if echo "$COMMAND" | grep -qE '(^|[;&|][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)git[[:space:]]+reset[[:space:]]+--hard\b'; then
  deny_decision "git reset --hard is not eligible for Auto-review"
fi

if echo "$COMMAND" | grep -qE '(^|[;&|][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)git[[:space:]]+clean[[:space:]].*(-[a-zA-Z]*f|--force)\b'; then
  deny_decision "git clean --force is not eligible for Auto-review"
fi

if echo "$COMMAND" | grep -qE '(^|[;&|][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)(chmod|chown)[[:space:]]+(-[^[:space:]]*R[^[:space:]]*|--recursive)\b'; then
  deny_decision "Recursive chmod/chown escalation is not eligible for Auto-review"
fi

if echo "$COMMAND" | grep -qE '(^|[[:space:]"'"'"'`])(~?/)?(\.ssh/|\.aws/|\.gnupg/|\.config/gh/|\.git-credentials|\.netrc|\.npmrc)([[:space:]"'"'"'`]|$|/)'; then
  deny_decision "Credential paths are not eligible for Auto-review"
fi

exit 0
