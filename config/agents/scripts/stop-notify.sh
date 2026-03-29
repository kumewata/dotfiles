#!/usr/bin/env bash
set -euo pipefail

# Stop hook: タスク完了時の macOS デスクトップ通知
# Claude Code が停止する際に通知を送る。停止をブロックしない（JSON 出力なし）。
# 監視目的のため fail-open（エラー時も exit 0）。

INPUT=$(cat)

# 無限ループ防止: stop_hook_active が true なら何もしない
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || STOP_ACTIVE="false"
if [ "$STOP_ACTIVE" = "true" ]; then
  exit 0
fi

# last_assistant_message の先頭80文字を通知本文に使用
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // "Task completed"' 2>/dev/null) || MESSAGE="Task completed"
MESSAGE=$(echo "$MESSAGE" | head -c 80)

# macOS 通知（osascript が使えない環境では静かに失敗）
if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${MESSAGE//\"/\\\"}\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null || true
fi

exit 0
