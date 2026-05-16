#!/usr/bin/env bash
set -euo pipefail

# Codex PreToolUse hook.
# Blocks high-confidence unsafe Bash commands before they run.

trap 'echo "codex-pretooluse-guard.sh: unexpected error" >&2; exit 2' ERR

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ "$TOOL_NAME" != "Bash" ]] && exit 0
[[ -z "$COMMAND" ]] && exit 0

deny_decision() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Block direct reads of common credential stores. This is intentionally narrow:
# it targets path-like tokens, not documentation text that merely mentions .env.
if echo "$COMMAND" | grep -qE '(^|[[:space:]"'"'"'`])(~?/)?(\.ssh/|\.aws/|\.gnupg/|\.config/gh/|\.git-credentials|\.netrc|\.npmrc)([[:space:]"'"'"'`]|$|/)'; then
  deny_decision "Sensitive credential path detected in Bash command"
fi

# curl/wget policy:
# - localhost URLs are allowed for local development.
# - external URLs are blocked here; use an explicit approval path instead.
if ! echo "$COMMAND" | grep -qE '(^|/|[;&|][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*|\$\(|\benv[[:space:]]+|\bcommand[[:space:]]+)(curl|wget)\b'; then
  exit 0
fi

LOCALHOST_PATTERN='(localhost|127\.0\.0\.1|\[::1\])'

if echo "$COMMAND" | grep -qE 'https?://'; then
  URLS_STRIPPED=$(echo "$COMMAND" | sed -E 's#https?://(localhost|127\.0\.0\.1|\[::1\])([:/[:space:]][^ ]*|$)##g')
  if echo "$URLS_STRIPPED" | grep -qE 'https?://'; then
    deny_decision "External URL detected in curl/wget command"
  fi
  if echo "$COMMAND" | grep -qE "@${LOCALHOST_PATTERN}"; then
    deny_decision "Suspicious URL pattern: userinfo before localhost"
  fi
  exit 0
fi

if echo "$COMMAND" | grep -qE "(curl|wget)[[:space:]].*${LOCALHOST_PATTERN}"; then
  if ! echo "$COMMAND" | grep -qE "@${LOCALHOST_PATTERN}"; then
    exit 0
  fi
fi

deny_decision "External network access via curl/wget is blocked"
