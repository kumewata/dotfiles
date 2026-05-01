#!/usr/bin/env bash
# tone-status.sh - tone corpus の統計表示と drafts/ の TTL GC
#
# Usage:
#   tone-status.sh [--gc-dry-run] [--rebuild-index]
#
# Env:
#   TONE_PHASE2_THRESHOLD  Phase 2 移行 notice 閾値 (default: 10)
#   TONE_DRAFT_TTL_DAYS    drafts/ TTL 日数 (default: 30)

set -euo pipefail

TONE_DIR="${HOME}/.local/state/tone"
DRAFTS_DIR="${TONE_DIR}/drafts"
PAIRS_DIR="${TONE_DIR}/pairs"
INDEX_FILE="${TONE_DIR}/index.json"

THRESHOLD="${TONE_PHASE2_THRESHOLD:-10}"
TTL_DAYS="${TONE_DRAFT_TTL_DAYS:-30}"

dry_run=false
rebuild=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gc-dry-run)
      dry_run=true
      shift
      ;;
    --rebuild-index)
      rebuild=true
      shift
      ;;
    -h | --help)
      cat <<'EOF'
Usage: tone-status.sh [--gc-dry-run] [--rebuild-index]

Show tone corpus stats and GC stale drafts (older than TONE_DRAFT_TTL_DAYS).
EOF
      exit 0
      ;;
    *)
      printf 'tone-status.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  printf 'tone-status.sh: jq is required\n' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf 'tone-status.sh: python3 is required\n' >&2
  exit 1
fi

umask 077
mkdir -p "$TONE_DIR" "$DRAFTS_DIR" "$PAIRS_DIR/formal" "$PAIRS_DIR/casual"

needs_rebuild=false
if [[ "$rebuild" == "true" ]]; then
  needs_rebuild=true
elif [[ ! -s "$INDEX_FILE" ]]; then
  needs_rebuild=true
elif ! jq -e . "$INDEX_FILE" >/dev/null 2>&1; then
  printf '⚠️  index.json appears to be corrupt; rebuilding from pairs/\n' >&2
  needs_rebuild=true
fi

if [[ "$needs_rebuild" == "true" ]]; then
  tmp_index="${INDEX_FILE}.tmp"
  trap 'rm -f "$tmp_index"' EXIT
  python3 - "$TONE_DIR" >"$tmp_index" <<'PYEOF'
import sys, os, re, json, datetime

tone_dir = sys.argv[1]
pairs = []

for context in ('formal', 'casual'):
    pair_dir = os.path.join(tone_dir, 'pairs', context)
    if not os.path.isdir(pair_dir):
        continue
    for name in sorted(os.listdir(pair_dir)):
        if not name.endswith('.md'):
            continue
        path = os.path.join(pair_dir, name)
        try:
            with open(path, encoding='utf-8') as f:
                text = f.read()
        except OSError:
            continue
        m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
        if not m:
            continue
        fm = m.group(1)

        def get(key, default=None):
            m2 = re.search(rf'^{re.escape(key)}:\s*(.*?)$', fm, re.MULTILINE)
            if not m2:
                return default
            v = m2.group(1).strip()
            if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                v = v[1:-1]
                v = v.replace('\\"', '"').replace('\\\\', '\\')
            return v

        edit_ratio = 0.0
        m_diff = re.search(r'^diff_summary:\n((?:[ \t]+.*\n)+)', fm, re.MULTILINE)
        if m_diff:
            m_er = re.search(r'^[ \t]+edit_ratio:\s*([0-9.]+)', m_diff.group(1), re.MULTILINE)
            if m_er:
                edit_ratio = float(m_er.group(1))

        pairs.append({
            'pair_id': get('pair_id') or '',
            'captured_at': get('captured_at') or '',
            'context': context,
            'target_type': get('target_type') or '',
            'source_url': get('source_url') or '',
            'edit_ratio': edit_ratio,
            'path': f'pairs/{context}/{name}',
        })

formal_count = sum(1 for p in pairs if p['context'] == 'formal')
casual_count = sum(1 for p in pairs if p['context'] == 'casual')
latest = max(pairs, key=lambda p: p['captured_at'] or '') if pairs else None

now = datetime.datetime.now(datetime.timezone.utc).astimezone()
out = {
    'schema_version': 1,
    'updated_at': now.isoformat(timespec='seconds'),
    'totals': {
        'pairs': len(pairs),
        'by_context': {'formal': formal_count, 'casual': casual_count},
    },
    'latest_capture': {
        'captured_at': latest['captured_at'] if latest else None,
        'context': latest['context'] if latest else None,
        'source_url': latest['source_url'] if latest else None,
    },
    'pairs': pairs,
}

print(json.dumps(out, indent=2))
PYEOF
  mv "$tmp_index" "$INDEX_FILE"
fi

# ── 統計表示 ────────────────────────────────────
total_pairs="$(jq -r '.totals.pairs' "$INDEX_FILE")"
formal_count="$(jq -r '.totals.by_context.formal' "$INDEX_FILE")"
casual_count="$(jq -r '.totals.by_context.casual' "$INDEX_FILE")"
latest_at="$(jq -r '.latest_capture.captured_at // "(none)"' "$INDEX_FILE")"
latest_ctx="$(jq -r '.latest_capture.context // "-"' "$INDEX_FILE")"
latest_url="$(jq -r '.latest_capture.source_url // "-"' "$INDEX_FILE")"

printf 'Tone corpus status\n'
printf '  Total pairs: %s\n' "$total_pairs"
printf '  By context:  formal=%s / casual=%s\n' "$formal_count" "$casual_count"
printf '  Latest:      %s (%s) %s\n' "$latest_at" "$latest_ctx" "$latest_url"
printf '\n'

# ── drafts TTL GC ──────────────────────────────
draft_count=0
gc_count=0
keep_count=0

if [[ -d "$DRAFTS_DIR" ]]; then
  for p in "$DRAFTS_DIR"/*.md; do
    [[ -e "$p" ]] || continue
    draft_count=$((draft_count + 1))
    created_at="$(awk '
      BEGIN { fm_state = 0 }
      /^---[[:space:]]*$/ {
        fm_state++
        if (fm_state >= 2) exit
        next
      }
      fm_state == 1 && /^created_at:/ {
        v = $0
        sub(/^created_at:[ \t]*/, "", v)
        gsub(/^"|"$/, "", v)
        print v
        exit
      }
    ' "$p")"
    if [[ -z "$created_at" ]]; then
      keep_count=$((keep_count + 1))
      continue
    fi
    age_days="$(
      python3 - "$created_at" <<'PYEOF'
import sys, datetime
created = sys.argv[1]
try:
    dt = datetime.datetime.fromisoformat(created)
except ValueError:
    print(-1)
    sys.exit(0)
now = datetime.datetime.now(dt.tzinfo) if dt.tzinfo else datetime.datetime.now()
delta = now - dt
print(delta.days)
PYEOF
    )"
    if [[ "$age_days" =~ ^-?[0-9]+$ ]] && ((age_days > TTL_DAYS)); then
      if [[ "$dry_run" == "true" ]]; then
        printf '[would-gc] %s (%s days old)\n' "$p" "$age_days"
      else
        rm -f "$p"
        printf '[gc] %s (%s days old)\n' "$p" "$age_days"
      fi
      gc_count=$((gc_count + 1))
    else
      keep_count=$((keep_count + 1))
    fi
  done
fi

printf 'Drafts: total=%s, kept=%s' "$draft_count" "$keep_count"
if [[ "$dry_run" == "true" ]]; then
  printf ', would-gc=%s\n' "$gc_count"
else
  printf ', gc=%s\n' "$gc_count"
fi

# ── Phase 2 移行 notice ─────────────────────────
if [[ "$total_pairs" =~ ^[0-9]+$ ]] && ((total_pairs > THRESHOLD)); then
  printf '\n📈 Phase 2 設計を検討する時期です (pairs=%s, threshold=%s)\n' \
    "$total_pairs" "$THRESHOLD"
fi
