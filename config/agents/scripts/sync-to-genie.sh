#!/usr/bin/env bash
# sync-to-genie.sh - ローカル steering ドキュメントを Databricks ワークスペースに同期
#
# Usage:
#   sync-to-genie.sh [options] --init [skill-name]   # SKILL.md の初期配置
#   sync-to-genie.sh [options] <steering-dir>         # steering ドキュメントの同期
#
# Options:
#   --dry-run              アップロードせず内容を表示
#   --profile <name>       Databricks CLI プロファイルを指定
#
# 概念:
#   SKILL.md（スキル定義）と steering ドキュメント（タスク固有の計画）は別物。
#   - --init: SKILL.md を /Users/{user}/.assistant/skills/{skill-name}/ に配置
#   - 通常:   steering docs を /Users/{user}/steering/{task-dir}/ に同期
#
#   SKILL.md はワークスペース上の /Users/<current-user>/steering/ を動的に参照し、
#   Genie Code が実行時にユーザーコンテキストから解決する想定。

set -euo pipefail

DRY_RUN=false
DB_PROFILE=""
DB_PROFILE_FLAG=""
CLEANUP_DIR=""
trap '[[ -n "$CLEANUP_DIR" ]] && rm -rf "$CLEANUP_DIR"' EXIT

# --- 共通関数 ---
check_deps() {
  for cmd in databricks jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: $cmd not found in PATH" >&2
      exit 1
    fi
  done
}

check_auth() {
  if ! databricks auth describe $DB_PROFILE_FLAG &>/dev/null; then
    echo "Error: databricks CLI authentication not configured. Run 'databricks auth login' first." >&2
    exit 1
  fi
}

get_db_user() {
  local db_user
  db_user=$(databricks current-user me $DB_PROFILE_FLAG --output json 2>/dev/null | jq -r '.userName' 2>/dev/null) || {
    echo "Error: failed to get Databricks username. Check authentication." >&2
    exit 1
  }
  if [[ -z "$db_user" || "$db_user" == "null" ]]; then
    echo "Error: failed to parse Databricks username from API response." >&2
    exit 1
  fi
  echo "$db_user"
}

validate_skill_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Error: skill name must be lowercase alphanumeric with hyphens: $name" >&2
    exit 1
  fi
}

# --- --init: SKILL.md の配置 ---
do_init() {
  local skill_name="$1"
  local db_user
  db_user=$(get_db_user)
  local remote_skill="/Users/${db_user}/.assistant/skills/${skill_name}"

  local work_dir
  work_dir=$(mktemp -d)
  CLEANUP_DIR="$work_dir"

  # steering-dir に SKILL.md があればそれを使用、なければデフォルト生成
  local skill_source="${STEERING_SKILL_MD:-}"
  if [[ -n "$skill_source" && -f "$skill_source" ]]; then
    cp "$skill_source" "${work_dir}/SKILL.md"
  else
    cat > "${work_dir}/SKILL.md" << 'SKILL_EOF'
---
name: project-steering
description: |
  プロジェクトの要件・設計・タスクリストに基づいてデータ作業を実行する。
  データパイプライン構築、分析ノートブック作成、SQL クエリ作成、
  ダッシュボード生成のいずれかの作業指示があった場合にこのスキルを使用する。
  タスクリストの進捗に従い、未完了タスクから順に着手する。
---

## steering ドキュメントの場所

steering ドキュメントは、現在のユーザーの workspace 配下に格納されている:

```
/Users/<current-user>/steering/<owner--repo>/<task-dir>/
  requirements.md   — 要件定義
  design.md         — 設計書
  tasklist.md       — タスクリスト
```

`<current-user>` は現在のセッションのユーザー名に読み替えること。

## 作業手順

1. ユーザーから作業対象のタスクを指示されたら、`/Users/<current-user>/steering/` 配下から該当するタスクディレクトリを特定する
2. requirements.md が存在すれば読み、プロジェクトの目的と要件を理解する
3. design.md が存在すれば読み、技術的な設計方針を把握する
4. tasklist.md が存在すれば読み、現在のタスク状態を確認する
5. tasklist の中で未完了（`[ ]`）のタスクを特定し、上から順に着手する
6. 各タスクの実装後、ユーザーに結果を報告する

※ 上記ファイルが存在しない場合はそのステップをスキップする。

## 注意事項

- タスクリストに記載のないスコープ外の作業は行わない
- 設計方針と異なるアプローチが必要な場合はユーザーに確認する
- requirements.md の受け入れ条件を意識して実装する
SKILL_EOF
  fi

  # name フィールドをスキル名に合わせる
  sed -i.bak "s|^name: .*$|name: ${skill_name}|" "${work_dir}/SKILL.md"
  rm -f "${work_dir}/SKILL.md.bak"

  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would deploy SKILL.md to ${remote_skill}/SKILL.md"
    echo "--- SKILL.md content ---"
    cat "${work_dir}/SKILL.md"
    echo "------------------------"
  else
    echo "Initializing skill at ${remote_skill} ..."
    databricks workspace mkdirs "${remote_skill}" $DB_PROFILE_FLAG 2>/dev/null || true
    databricks workspace import "${remote_skill}/SKILL.md" --file "${work_dir}/SKILL.md" --format AUTO --overwrite $DB_PROFILE_FLAG
    echo "Done. SKILL.md deployed to ${remote_skill}/SKILL.md"
  fi
}

# --- 通常実行: steering ドキュメントの同期 ---
do_sync() {
  local steering_dir="$1"
  local db_user
  db_user=$(get_db_user)

  # ローカルのディレクトリ名からリモートパスを構成
  # ~/.local/state/steering/owner--repo/task-dir/ → /Users/{user}/steering/owner--repo/task-dir/
  local dir_name
  dir_name=$(basename "$steering_dir")
  local parent_name
  parent_name=$(basename "$(dirname "$steering_dir")")
  local remote_dir="/Users/${db_user}/steering/${parent_name}/${dir_name}"

  local work_dir
  work_dir=$(mktemp -d)
  CLEANUP_DIR="$work_dir"

  # steering ドキュメントをコピー（SKILL.md と handoff は除外）
  for f in "${steering_dir}"/*.md; do
    [[ -f "$f" ]] || continue
    local basename_f
    basename_f=$(basename "$f")
    [[ "$basename_f" == "SKILL.md" ]] && continue
    [[ "$basename_f" == handoff-* ]] && continue
    cp "$f" "${work_dir}/${basename_f}"
  done

  # ファイルが空なら警告
  shopt -s nullglob
  local md_files=("${work_dir}/"*.md)
  shopt -u nullglob
  if [[ ${#md_files[@]} -eq 0 ]]; then
    echo "Warning: no .md files found in ${steering_dir} to sync" >&2
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would sync to ${remote_dir}"
    echo "Files:"
    for f in "${work_dir}/"*.md; do
      [[ -f "$f" ]] && echo "  $(basename "$f")"
    done
  else
    echo "Syncing steering docs to ${remote_dir} ..."
    databricks workspace import-dir "${work_dir}" "${remote_dir}" --overwrite $DB_PROFILE_FLAG
    echo "Done. Synced files:"
    databricks workspace list "${remote_dir}" $DB_PROFILE_FLAG --output text 2>/dev/null || true
  fi
}

# --- メイン ---
if [[ $# -lt 1 ]]; then
  echo "Usage:" >&2
  echo "  $0 [--dry-run] --init [skill-name]    # Deploy SKILL.md" >&2
  echo "  $0 [--dry-run] <steering-dir>          # Sync steering docs" >&2
  exit 1
fi

# オプション処理
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --profile)
      [[ $# -lt 2 ]] && { echo "Error: --profile requires a value" >&2; exit 1; }
      DB_PROFILE="$2"
      DB_PROFILE_FLAG="--profile $2"
      shift 2
      ;;
    --init)
      break  # --init はオプションではなくサブコマンド
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Error: missing argument" >&2
  exit 1
fi

if [[ "$1" == "--init" ]]; then
  SKILL_NAME="${2:-project-steering}"
  validate_skill_name "$SKILL_NAME"
  check_deps
  check_auth
  do_init "$SKILL_NAME"
  exit 0
fi

STEERING_DIR="$1"

if [[ ! -d "$STEERING_DIR" ]]; then
  echo "Error: steering directory not found: $STEERING_DIR" >&2
  exit 1
fi

check_deps
check_auth
do_sync "$STEERING_DIR"
