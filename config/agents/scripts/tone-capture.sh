#!/usr/bin/env bash
# tone-capture.sh - 投稿後の final を fetch して draft とペア化、~/.local/state/tone/pairs/ に保存
#
# Usage:
#   tone-capture.sh <url> [--draft-id <id>] [--final-stdin]
#
# Exit codes:
#   0  success
#   2  invalid arguments / unsupported URL / unknown draft_id
#   3  ambiguous draft candidates (caller must re-invoke with --draft-id)
#   4  gh fetch failed
#   1  other / unexpected

set -euo pipefail

TONE_DIR="${HOME}/.local/state/tone"
DRAFTS_DIR="${TONE_DIR}/drafts"
PAIRS_DIR="${TONE_DIR}/pairs"
INDEX_FILE="${TONE_DIR}/index.json"

usage() {
  cat >&2 <<'EOF'
Usage: tone-capture.sh <url> [--draft-id <id>] [--final-stdin]

Supported URLs:
  GitHub PR description:    https://github.com/<owner>/<repo>/pull/<n>
  GitHub PR inline review:  https://github.com/<owner>/<repo>/pull/<n>#discussion_r<id>
  GitHub PR toplevel cmt:   https://github.com/<owner>/<repo>/pull/<n>#issuecomment-<id>
  GitHub PR review submit:  https://github.com/<owner>/<repo>/pull/<n>#pullrequestreview-<id>
  GitHub Discussion body:   https://github.com/<owner>/<repo>/discussions/<n>
  GitHub Discussion cmt:    https://github.com/<owner>/<repo>/discussions/<n>#discussioncomment-<id>
  Slack permalink:          https://<workspace>.slack.com/archives/<channel>/p<ts>

Slack URLs require --final-stdin; the /tone-capture command fetches the body
via the Slack MCP tool and pipes it via heredoc.
EOF
  exit 2
}

url=""
override_draft_id=""
final_from_stdin=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --draft-id)
      override_draft_id="${2:-}"
      shift 2
      ;;
    --final-stdin)
      final_from_stdin=true
      shift
      ;;
    -h | --help)
      usage
      ;;
    --*)
      printf 'tone-capture.sh: unknown option: %s\n' "$1" >&2
      usage
      ;;
    *)
      if [[ -n "$url" ]]; then
        printf 'tone-capture.sh: unexpected positional argument: %s\n' "$1" >&2
        usage
      fi
      url="$1"
      shift
      ;;
  esac
done

if [[ -z "$url" ]]; then
  printf 'tone-capture.sh: <url> is required\n' >&2
  usage
fi

# ── URL parser ───────────────────────────────────────
target_type=""
slug=""
gh_subtype="" # description | inline | toplevel | slack

owner=""
repo=""
pr_num=""
comment_id=""
slack_channel=""
slack_ts=""

if [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  pr_num="${BASH_REMATCH[3]}"
  target_type="pr_description"
  gh_subtype="description"
  slug="pr-${pr_num}"
elif [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)#discussion_r([0-9]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  pr_num="${BASH_REMATCH[3]}"
  comment_id="${BASH_REMATCH[4]}"
  target_type="pr_review"
  gh_subtype="inline"
  slug="pr-${pr_num}-r${comment_id}"
elif [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)#issuecomment-([0-9]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  pr_num="${BASH_REMATCH[3]}"
  comment_id="${BASH_REMATCH[4]}"
  target_type="pr_review"
  gh_subtype="toplevel"
  slug="pr-${pr_num}-c${comment_id}"
elif [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)#pullrequestreview-([0-9]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  pr_num="${BASH_REMATCH[3]}"
  comment_id="${BASH_REMATCH[4]}"
  target_type="pr_review"
  gh_subtype="review"
  slug="pr-${pr_num}-rv${comment_id}"
elif [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/discussions/([0-9]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  pr_num="${BASH_REMATCH[3]}"
  target_type="discussion"
  gh_subtype="discussion_body"
  slug="disc-${pr_num}"
elif [[ "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/discussions/([0-9]+)#discussioncomment-([0-9]+)$ ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  pr_num="${BASH_REMATCH[3]}"
  comment_id="${BASH_REMATCH[4]}"
  target_type="discussion"
  gh_subtype="discussion_comment"
  slug="disc-${pr_num}-c${comment_id}"
elif [[ "$url" =~ ^https://[^.]+\.slack\.com/archives/([^/]+)/p([0-9]+)(\?.*)?$ ]]; then
  slack_channel="${BASH_REMATCH[1]}"
  slack_ts="${BASH_REMATCH[2]}"
  target_type="slack"
  gh_subtype="slack"
  ts_tail="${slack_ts: -6}"
  slug="slack-${slack_channel}-${ts_tail}"
else
  printf 'tone-capture.sh: unsupported URL: %s\n' "$url" >&2
  usage
fi

if [[ "$target_type" == "slack" ]]; then
  context="casual"
else
  context="formal"
fi

# ── Slack 系で --final-stdin が無い場合は早期エラー ──
if [[ "$gh_subtype" == "slack" && "$final_from_stdin" != "true" ]]; then
  cat >&2 <<'EOF'
tone-capture.sh: Slack capture requires --final-stdin.
Run via the /tone-capture command, which fetches the message body via the
Slack MCP tool and pipes it as stdin to this script.
EOF
  exit 2
fi

# ── 必要な依存コマンド ───────────────────────────
for cmd in jq python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'tone-capture.sh: required command not found: %s\n' "$cmd" >&2
    exit 1
  fi
done

if [[ "$gh_subtype" != "slack" && "$final_from_stdin" != "true" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    printf 'tone-capture.sh: gh CLI is required for GitHub URLs\n' >&2
    exit 1
  fi
fi

# ── ステージから候補 draft を絞り込む ────────────
umask 077
mkdir -p "$TONE_DIR" "$DRAFTS_DIR" "$PAIRS_DIR/$context"

# frontmatter のフラットフィールド抽出（context, target_type, created_at, draft_id, target_hint）
parse_frontmatter_field() {
  local file="$1"
  local field="$2"
  awk -v key="$field" '
    BEGIN { fm_state = 0 }
    /^---[[:space:]]*$/ {
      fm_state++
      if (fm_state >= 2) exit
      next
    }
    fm_state == 1 {
      if (match($0, /^[a-zA-Z_][a-zA-Z0-9_]*:/)) {
        k = substr($0, 1, RLENGTH - 1)
        v = substr($0, RLENGTH + 1)
        sub(/^[ \t]+/, "", v)
        sub(/[ \t]+$/, "", v)
        if (length(v) >= 2 && substr(v, 1, 1) == "\"" && substr(v, length(v), 1) == "\"") {
          v = substr(v, 2, length(v) - 2)
          gsub(/\\"/, "\"", v)
          gsub(/\\\\/, "\\", v)
        }
        if (k == key) { print v; exit }
      }
    }
  ' "$file"
}

# 候補 draft 配列（draft_id<TAB>created_at<TAB>target_hint<TAB>path で stdout）
list_candidates() {
  local p
  if [[ -d "$DRAFTS_DIR" ]]; then
    for p in "$DRAFTS_DIR"/*.md; do
      [[ -e "$p" ]] || continue
      local ctx tgt did cat_ at_
      ctx="$(parse_frontmatter_field "$p" context)"
      tgt="$(parse_frontmatter_field "$p" target_type)"
      [[ "$ctx" == "$context" && "$tgt" == "$target_type" ]] || continue
      did="$(parse_frontmatter_field "$p" draft_id)"
      cat_="$(parse_frontmatter_field "$p" created_at)"
      at_="$(parse_frontmatter_field "$p" target_hint)"
      printf '%s\t%s\t%s\t%s\n' "$did" "$cat_" "$at_" "$p"
    done
  fi
}

candidates_tsv="$(list_candidates | sort -t$'\t' -k2,2 -r || true)"

selected_draft_path=""
selected_draft_id=""
selected_draft_created_at=""
selected_draft_body=""

if [[ -n "$override_draft_id" ]]; then
  while IFS=$'\t' read -r did cat_ _hint p; do
    [[ -z "$did" ]] && continue
    if [[ "$did" == "$override_draft_id" ]]; then
      selected_draft_path="$p"
      selected_draft_id="$did"
      selected_draft_created_at="$cat_"
      break
    fi
  done <<<"$candidates_tsv"
  if [[ -z "$selected_draft_path" ]]; then
    printf 'tone-capture.sh: --draft-id %s did not match any staged draft for context=%s target_type=%s\n' \
      "$override_draft_id" "$context" "$target_type" >&2
    exit 2
  fi
else
  cand_count="$(printf '%s' "$candidates_tsv" | grep -c -v '^$' || true)"
  if [[ "$cand_count" -eq 0 ]]; then
    : # orphan mode
  elif [[ "$cand_count" -eq 1 ]]; then
    IFS=$'\t' read -r selected_draft_id selected_draft_created_at _hint selected_draft_path <<<"$candidates_tsv"
  else
    {
      printf 'tone-capture.sh: multiple draft candidates match (context=%s, target_type=%s):\n' \
        "$context" "$target_type"
      printf 'draft_id\tcreated_at\ttarget_hint\n'
      printf '%s\n' "$candidates_tsv" | awk -F'\t' '{ printf "%s\t%s\t%s\n", $1, $2, $3 }'
      printf 'Re-run with --draft-id <id>.\n'
    } >&2
    exit 3
  fi
fi

# Draft 本文を抽出（frontmatter の終了 `---` の次行以降）
extract_body() {
  local file="$1"
  awk '
    BEGIN { fm_state = 0; printing = 0 }
    /^---[[:space:]]*$/ {
      fm_state++
      if (fm_state == 2) { printing = 1; next }
      next
    }
    printing { print }
  ' "$file"
}

if [[ -n "$selected_draft_path" ]]; then
  selected_draft_body="$(extract_body "$selected_draft_path")"
else
  selected_draft_body=""
fi

# ── final fetch ─────────────────────────────────
final_body=""
if [[ "$final_from_stdin" == "true" ]]; then
  final_body="$(cat)"
  if [[ -z "$final_body" ]]; then
    printf 'tone-capture.sh: --final-stdin given but stdin was empty\n' >&2
    exit 2
  fi
else
  case "$gh_subtype" in
    description)
      if ! final_body="$(gh api "repos/${owner}/${repo}/pulls/${pr_num}" --jq '.body // ""')"; then
        printf 'tone-capture.sh: gh api failed for PR %s/%s#%s\n' "$owner" "$repo" "$pr_num" >&2
        exit 4
      fi
      ;;
    inline)
      if ! final_body="$(gh api "repos/${owner}/${repo}/pulls/comments/${comment_id}" --jq '.body // ""')"; then
        printf 'tone-capture.sh: gh api failed for inline review comment %s\n' "$comment_id" >&2
        exit 4
      fi
      ;;
    toplevel)
      if ! final_body="$(gh api "repos/${owner}/${repo}/issues/comments/${comment_id}" --jq '.body // ""')"; then
        printf 'tone-capture.sh: gh api failed for issue comment %s\n' "$comment_id" >&2
        exit 4
      fi
      ;;
    review)
      if ! final_body="$(gh api "repos/${owner}/${repo}/pulls/${pr_num}/reviews/${comment_id}" --jq '.body // ""')"; then
        printf 'tone-capture.sh: gh api failed for PR review %s\n' "$comment_id" >&2
        exit 4
      fi
      ;;
    discussion_body)
      # shellcheck disable=SC2016 # GraphQL variable refs (not shell)
      if ! final_body="$(gh api graphql \
        -F owner="$owner" -F name="$repo" -F num="$pr_num" \
        -f query='query($owner:String!,$name:String!,$num:Int!){repository(owner:$owner,name:$name){discussion(number:$num){body}}}' \
        --jq '.data.repository.discussion.body // ""')"; then
        printf 'tone-capture.sh: gh api graphql failed for discussion %s/%s#%s\n' "$owner" "$repo" "$pr_num" >&2
        exit 4
      fi
      ;;
    discussion_comment)
      # Walk all top-level comments + replies, filter by databaseId.
      # Pagination limit: first 100 top-level comments × first 100 replies each.
      # shellcheck disable=SC2016 # GraphQL variable refs (not shell)
      if ! all_comments_json="$(gh api graphql \
        -F owner="$owner" -F name="$repo" -F num="$pr_num" \
        -f query='query($owner:String!,$name:String!,$num:Int!){repository(owner:$owner,name:$name){discussion(number:$num){comments(first:100){nodes{databaseId body replies(first:100){nodes{databaseId body}}}}}}}')"; then
        printf 'tone-capture.sh: gh api graphql failed for discussion %s/%s#%s\n' "$owner" "$repo" "$pr_num" >&2
        exit 4
      fi
      final_body="$(printf '%s' "$all_comments_json" | jq -r --argjson target "$comment_id" '
        .data.repository.discussion.comments.nodes
        | map(., .replies.nodes[])
        | flatten
        | map(select(.databaseId == $target))
        | .[0].body // ""
      ')"
      ;;
  esac
fi

if [[ -z "$final_body" ]]; then
  printf 'tone-capture.sh: final body is empty (URL may be wrong or content was deleted)\n' >&2
  exit 4
fi

# ── diff_summary 計算 ────────────────────────────
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

draft_tmp="${tmpdir}/draft.txt"
final_tmp="${tmpdir}/final.txt"
printf '%s' "$selected_draft_body" >"$draft_tmp"
printf '%s' "$final_body" >"$final_tmp"

draft_chars=${#selected_draft_body}
final_chars=${#final_body}

if [[ -z "$selected_draft_body" ]]; then
  edit_ratio="1.0"
else
  edit_ratio="$(
    python3 - "$draft_tmp" "$final_tmp" <<'PYEOF'
import sys, difflib
a = open(sys.argv[1]).read()
b = open(sys.argv[2]).read()
ratio = difflib.SequenceMatcher(None, a, b).ratio()
print(round(1 - ratio, 4))
PYEOF
  )"
fi

# ── pair file の決定（既存があれば上書き） ─────────
captured_at="$(date +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"
date_part="$(date +%F)"

# 既存 pair を source_url で検索（同一 URL → 上書き）
existing_pair=""
if [[ -d "$PAIRS_DIR/$context" ]]; then
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    src="$(parse_frontmatter_field "$p" source_url)"
    if [[ "$src" == "$url" ]]; then
      existing_pair="$p"
      break
    fi
  done < <(find "$PAIRS_DIR/$context" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
fi

if [[ -n "$existing_pair" ]]; then
  pair_path="$existing_pair"
else
  pair_path="${PAIRS_DIR}/${context}/${date_part}-${slug}.md"
fi

if [[ -n "$selected_draft_id" ]]; then
  pair_id="$selected_draft_id"
  draft_created_at="$selected_draft_created_at"
else
  # orphan
  if command -v uuidgen >/dev/null 2>&1; then
    rand="$(uuidgen | tr -d - | tr '[:upper:]' '[:lower:]' | head -c 6)"
  else
    rand="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
  fi
  pair_id="orphan-$(date +%Y%m%d-%H%M%S)-${rand}"
  draft_created_at=""
fi

# ── pair file 書き出し（temp + rename） ─────────
escape_yaml_val() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '%s' "$s"
}

tmp_pair="${pair_path}.tmp"

{
  printf -- '---\n'
  printf 'pair_id: %s\n' "$pair_id"
  if [[ -n "$draft_created_at" ]]; then
    printf 'draft_created_at: %s\n' "$draft_created_at"
  else
    printf 'draft_created_at: null\n'
  fi
  printf 'captured_at: %s\n' "$captured_at"
  printf 'context: %s\n' "$context"
  printf 'target_type: %s\n' "$target_type"
  printf 'slug: %s\n' "$slug"
  printf 'source_url: "%s"\n' "$(escape_yaml_val "$url")"
  printf 'diff_summary:\n'
  printf '  draft_chars: %d\n' "$draft_chars"
  printf '  final_chars: %d\n' "$final_chars"
  printf '  edit_ratio: %s\n' "$edit_ratio"
  printf -- '---\n'
  printf '\n## Draft\n\n'
  if [[ -n "$selected_draft_body" ]]; then
    printf '%s\n' "$selected_draft_body"
  else
    printf '(orphan capture)\n'
  fi
  printf '\n## Final\n\n'
  printf '%s\n' "$final_body"
} >"$tmp_pair"

mv "$tmp_pair" "$pair_path"

# ── staged draft 削除 ────────────────────────────
if [[ -n "$selected_draft_path" && -f "$selected_draft_path" ]]; then
  rm -f "$selected_draft_path"
fi

# ── index.json 更新 ─────────────────────────────
rel_path="pairs/${context}/$(basename "$pair_path")"
updated_at="$captured_at"

if [[ ! -s "$INDEX_FILE" ]]; then
  printf '{"schema_version":1,"updated_at":null,"totals":{"pairs":0,"by_context":{"formal":0,"casual":0}},"latest_capture":{"captured_at":null,"context":null,"source_url":null},"pairs":[]}\n' >"$INDEX_FILE"
fi

if ! jq -e . "$INDEX_FILE" >/dev/null 2>&1; then
  # 破損していたら骨組みを再作成（pairs は tone-status.sh で rebuild）
  printf '{"schema_version":1,"updated_at":null,"totals":{"pairs":0,"by_context":{"formal":0,"casual":0}},"latest_capture":{"captured_at":null,"context":null,"source_url":null},"pairs":[]}\n' >"$INDEX_FILE"
fi

tmp_index="${INDEX_FILE}.tmp"
jq \
  --arg pair_id "$pair_id" \
  --arg captured_at "$captured_at" \
  --arg context "$context" \
  --arg target_type "$target_type" \
  --arg source_url "$url" \
  --arg path "$rel_path" \
  --argjson edit_ratio "$edit_ratio" \
  --arg updated_at "$updated_at" \
  '
  .pairs |= map(select(.source_url != $source_url))
  | .pairs += [{
    pair_id: $pair_id,
    captured_at: $captured_at,
    context: $context,
    target_type: $target_type,
    source_url: $source_url,
    edit_ratio: $edit_ratio,
    path: $path
  }]
  | .totals.pairs = (.pairs | length)
  | .totals.by_context.formal = ([.pairs[] | select(.context == "formal")] | length)
  | .totals.by_context.casual = ([.pairs[] | select(.context == "casual")] | length)
  | .latest_capture = (
      if (.pairs | length) > 0
      then (.pairs | sort_by(.captured_at) | last | {captured_at, context, source_url})
      else {captured_at: null, context: null, source_url: null}
      end
    )
  | .updated_at = $updated_at
  ' "$INDEX_FILE" >"$tmp_index"
mv "$tmp_index" "$INDEX_FILE"

printf '✅ Pair saved: %s (edit_ratio: %s)\n' "$rel_path" "$edit_ratio"
