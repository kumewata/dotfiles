#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: 認証情報ファイルの読み取りガード
# Read/Edit/Write/Grep/Glob ツールが機密ファイルにアクセスしようとしたら
# ユーザーに確認を求める（permissionDecision: "ask"）
#
# セキュリティ方針: fail-closed（エラー時は exit 2 でブロック）
# 参考: https://github.com/kumewata/obsidian/issues/140

# エラー時は fail-closed（exit 2 = ブロック）
trap 'echo "credential-guard.sh: unexpected error" >&2; exit 2' ERR

INPUT=$(cat)

# file_path / path / pattern のいずれかを抽出（ツールによってフィールド名が異なる）
FILE_PATH=$(echo "$INPUT" | jq -r '
  .tool_input.file_path //
  .tool_input.path //
  .tool_input.pattern //
  empty
' 2>/dev/null) || {
  echo "credential-guard.sh: failed to parse input" >&2
  exit 2
}

[[ -z $FILE_PATH ]] && exit 0

BASENAME=$(basename "$FILE_PATH")

# ask を出力するヘルパー
ask_decision() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# ── 機密ファイルパターンの検出 ──

# .env 系ファイル（.env, .env.local, .env.production 等）
if echo "$BASENAME" | grep -qiE '^\.(env|env\..*)$'; then
  ask_decision "credential-guard: .env file detected"
fi

# token*.json（OAuth トークン等）
if echo "$BASENAME" | grep -qiE '^token.*\.json$'; then
  ask_decision "credential-guard: token file detected"
fi

# credentials / secret / key 系
if echo "$BASENAME" | grep -qiE '(credential|secret|private[._-]key|\.pem$|\.key$|api[._-]key)'; then
  ask_decision "credential-guard: credential/secret/key file detected"
fi

# ディレクトリパスによる検出（~/.ssh/, ~/.aws/, ~/.config/gh/ 等）
if echo "$FILE_PATH" | grep -qE '(\.ssh/|\.aws/|\.config/gh/|\.gnupg/|\.git-credentials|\.netrc|\.npmrc)'; then
  ask_decision "credential-guard: sensitive directory path detected"
fi

# パススルー
exit 0
