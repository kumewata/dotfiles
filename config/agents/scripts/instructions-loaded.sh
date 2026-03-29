#!/usr/bin/env bash
set -euo pipefail

# InstructionsLoaded hook: CLAUDE.md 読み込みのログ出力
# どのファイルがどの理由で読み込まれたかを stderr に記録する。
# 監視目的のため fail-open（エラー時も exit 0）。

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // "unknown"' 2>/dev/null) || FILE_PATH="unknown"
MEMORY_TYPE=$(echo "$INPUT" | jq -r '.memory_type // "unknown"' 2>/dev/null) || MEMORY_TYPE="unknown"
LOAD_REASON=$(echo "$INPUT" | jq -r '.load_reason // "unknown"' 2>/dev/null) || LOAD_REASON="unknown"

echo "[instructions-loaded] ${MEMORY_TYPE}/${LOAD_REASON}: ${FILE_PATH}" >&2

exit 0
