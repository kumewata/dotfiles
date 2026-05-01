#!/usr/bin/env bash
# tone-stage-draft.sh - tone skill が生成した draft を ~/.local/state/tone/drafts/ にステージング
#
# Usage:
#   tone-stage-draft.sh --context <formal|casual> \
#                       --target-type <pr_description|pr_review|discussion|slack> \
#                       [--target-hint "<text>"] < draft_body
#
# Stdin から draft 本文を読む。成功時は draft_id だけを stdout に出力する。

set -euo pipefail

TONE_DIR="${HOME}/.local/state/tone"
DRAFTS_DIR="${TONE_DIR}/drafts"

usage() {
  cat >&2 <<'EOF'
Usage: tone-stage-draft.sh --context <formal|casual> --target-type <pr_description|pr_review|discussion|slack> [--target-hint "<text>"]

Reads the draft body from stdin. On success, prints the draft_id to stdout.
EOF
  exit 2
}

context=""
target_type=""
target_hint=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      context="${2:-}"
      shift 2
      ;;
    --target-type)
      target_type="${2:-}"
      shift 2
      ;;
    --target-hint)
      target_hint="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      printf 'tone-stage-draft.sh: unknown argument: %s\n' "$1" >&2
      usage
      ;;
  esac
done

case "$context" in
  formal | casual) ;;
  *)
    printf 'tone-stage-draft.sh: --context must be formal|casual (got %q)\n' "$context" >&2
    exit 2
    ;;
esac

case "$target_type" in
  pr_description | pr_review | discussion | slack) ;;
  *)
    printf 'tone-stage-draft.sh: --target-type must be pr_description|pr_review|discussion|slack (got %q)\n' "$target_type" >&2
    exit 2
    ;;
esac

if [[ "$context" == "formal" && "$target_type" == "slack" ]]; then
  printf 'tone-stage-draft.sh: invalid combination context=formal target_type=slack\n' >&2
  exit 2
fi
if [[ "$context" == "casual" && "$target_type" != "slack" ]]; then
  printf 'tone-stage-draft.sh: invalid combination context=casual target_type=%s\n' "$target_type" >&2
  exit 2
fi

body="$(cat)"
if [[ -z "$body" ]]; then
  printf 'tone-stage-draft.sh: empty draft body on stdin\n' >&2
  exit 2
fi

umask 077
mkdir -p "$TONE_DIR" "$DRAFTS_DIR"

short_hash=""
if command -v uuidgen >/dev/null 2>&1; then
  short_hash="$(uuidgen | tr -d - | tr '[:upper:]' '[:lower:]' | head -c 6)"
fi
if [[ -z "$short_hash" ]]; then
  short_hash="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
fi
if [[ -z "$short_hash" ]]; then
  printf 'tone-stage-draft.sh: failed to generate short hash\n' >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
draft_id="${stamp}-${short_hash}"
created_at="$(date +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"

# YAML 文字列のための簡易エスケープ（ダブルクォート + バックスラッシュ + 改行）
escape_yaml() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '%s' "$s"
}

target_hint_escaped="$(escape_yaml "$target_hint")"

draft_path="${DRAFTS_DIR}/${draft_id}.md"
tmp_path="${draft_path}.tmp"
trap 'rm -f "$tmp_path"' EXIT

{
  printf -- '---\n'
  printf 'draft_id: %s\n' "$draft_id"
  printf 'created_at: %s\n' "$created_at"
  printf 'context: %s\n' "$context"
  printf 'target_type: %s\n' "$target_type"
  printf 'target_hint: "%s"\n' "$target_hint_escaped"
  printf -- '---\n'
  printf '%s\n' "$body"
} >"$tmp_path"

mv "$tmp_path" "$draft_path"

printf '%s\n' "$draft_id"
