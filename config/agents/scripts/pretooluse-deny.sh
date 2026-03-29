#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: curl/wget の動的権限検証
# - localhost のみへのアクセス → allow（開発用途）
# - 外部 URL を含む → deny（外部ネットワークアクセスをブロック）
# - curl/wget 以外 → パススルー（JSON なしで exit 0）
#
# セキュリティ方針: fail-closed（エラー時は exit 2 でブロック）
# 注意: macOS 互換のため grep -P (PCRE) は使用しない
#
# 既知の制限事項:
# - --connect-to, --resolve, -x (--proxy) 等の curl オプションで接続先を
#   書き換えられた場合、URL 上は localhost でも実際は外部に接続される
#   (例: curl --connect-to localhost:80:evil.com:80 http://localhost/)
# - 変数展開による間接呼び出し (例: c=curl; $c https://...) は検出不可
# - \b, \s は BSD grep (macOS) の ERE で非標準。現状動作するが、
#   厳密な移植性が必要なら [[:space:]] 等に置き換えること
# これらは文字列ベースの検査の本質的限界であり、Claude Code が生成する
# コマンドとしては非現実的なため、現段階では許容する。

# エラー時は fail-closed（exit 2 = ブロック）
trap 'echo "pretooluse-deny.sh: unexpected error" >&2; exit 2' ERR

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || {
  echo "pretooluse-deny.sh: failed to parse input" >&2
  exit 2
}
[[ -z $COMMAND ]] && exit 0

# curl/wget を含まないコマンドはパススルー
# パス付き（/usr/bin/curl）、env/command 経由、パイプ内も検出
if ! echo "$COMMAND" | grep -qE '(^|/|[;&|]\s*|&&\s*|\|\|\s*|\$\(|\benv\s+|\bcommand\s+)(curl|wget)\b'; then
  exit 0
fi

# deny を出力するヘルパー
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

# allow を出力するヘルパー
allow_decision() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# ── localhost のみアクセスの判定 ──
# 方針: 外部 URL が含まれていたら deny（--proxy localhost + external URL 対策）

LOCALHOST_PATTERN='(localhost|127\.0\.0\.1|\[::1\])'

# URL が含まれる場合の判定
if echo "$COMMAND" | grep -qE 'https?://'; then
  # 外部 URL の検出: localhost URL を除去した後に残る URL があれば外部アクセス
  # macOS 互換: sed -E でデリミタに # を使用（| は正規表現と衝突）
  # localhost の後が @ の場合は userinfo なので除去しない（http://localhost@evil.com 対策）
  URLS_STRIPPED=$(echo "$COMMAND" | sed -E 's#https?://(localhost|127\.0\.0\.1|\[::1\])([:/[:space:]][^ ]*|$)##g')
  if echo "$URLS_STRIPPED" | grep -qE 'https?://'; then
    deny_decision "External URL detected in curl/wget command"
  fi
  # userinfo bypass 対策: @ が localhost の前にないこと
  if echo "$COMMAND" | grep -qE "@${LOCALHOST_PATTERN}"; then
    deny_decision "Suspicious URL pattern: userinfo before localhost"
  fi
  # 全 URL が localhost 系 → allow
  allow_decision "localhost access is allowed"
fi

# URL スキームなしの localhost 形式（curl localhost:8080 等）
if echo "$COMMAND" | grep -qE "(curl|wget)\s.*${LOCALHOST_PATTERN}"; then
  if ! echo "$COMMAND" | grep -qE "@${LOCALHOST_PATTERN}"; then
    allow_decision "localhost access is allowed"
  fi
fi

# URL もホスト名も特定できない場合、または外部アクセスの場合はブロック
deny_decision "External network access via curl/wget is blocked"
