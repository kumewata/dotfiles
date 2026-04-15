#!/usr/bin/env bash
# sync-to-genie.sh - ローカル steering ドキュメントを Databricks ワークスペースに同期
#
# Usage:
#   sync-to-genie.sh [options] --init [skill-name]            # 単一スキルの SKILL.md 配置
#   sync-to-genie.sh [options] --init-all                     # 全 Genie Code スキルを一括デプロイ
#   sync-to-genie.sh [options] <steering-dir>                  # push（差分同期）
#   sync-to-genie.sh [options] --full <steering-dir>           # push（完全同期・削除反映）
#   sync-to-genie.sh [options] --watch <steering-dir>          # push + ファイル監視
#   sync-to-genie.sh [options] --pull <steering-dir>           # pull（diff を stdout に出力）
#   sync-to-genie.sh [options] --pull --force <steering-dir>   # pull（バックアップ + 即上書き）
#   sync-to-genie.sh [options] --pull --dry-run <steering-dir> # pull（リモートファイル一覧のみ）
#
# Options:
#   --dry-run              アップロードせず内容を表示（push: ネイティブ / pull: workspace list）
#   --profile <name>       Databricks CLI プロファイルを指定
#   --full                 削除も反映する完全同期（push のみ）
#   --watch                ファイル監視による継続同期（push のみ）
#   --pull                 逆方向同期（workspace → local）
#   --force                --pull と併用。バックアップ作成後に即上書き
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
DB_PROFILE_FLAG=()
FULL_SYNC=false
WATCH_MODE=false
PULL_MODE=false
FORCE_MODE=false
CLEANUP_DIR=""

# Genie Code 用スキルのソースディレクトリ（Nix でデプロイ済み、環境変数で override 可）
GENIE_SKILLS_DIR="${GENIE_SKILLS_DIR:-${HOME}/.claude/genie-skills}"

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
  if ! databricks auth describe ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"} &>/dev/null; then
    echo "Error: databricks CLI authentication not configured. Run 'databricks auth login' first." >&2
    exit 1
  fi
}

get_db_user() {
  local db_user
  db_user=$(databricks current-user me ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"} --output json 2>/dev/null | jq -r '.userName' 2>/dev/null) || {
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

# --- --init: 単一スキルの SKILL.md 配置 ---
do_init() {
  local skill_name="$1"
  local db_user
  db_user=$(get_db_user)
  local remote_skill="/Users/${db_user}/.assistant/skills/${skill_name}"

  # スキルソースの決定: 環境変数 > genie-skills ディレクトリ > エラー
  local skill_file="${STEERING_SKILL_MD:-}"
  if [[ -z "$skill_file" || ! -f "$skill_file" ]]; then
    skill_file="${GENIE_SKILLS_DIR}/${skill_name}/SKILL.md"
  fi
  if [[ ! -f "$skill_file" ]]; then
    echo "Error: SKILL.md not found for skill '${skill_name}'" >&2
    echo "  Checked: ${GENIE_SKILLS_DIR}/${skill_name}/SKILL.md" >&2
    exit 1
  fi

  # ディレクトリ名と SKILL.md 内の name: フィールドの整合性チェック
  local yaml_name
  yaml_name=$(grep -m1 '^name:' "$skill_file" | sed 's/^name:[[:space:]]*//' || true)
  if [[ -n "$yaml_name" && "$yaml_name" != "$skill_name" ]]; then
    echo "Warning: skill name mismatch: directory='${skill_name}' vs SKILL.md name='${yaml_name}'" >&2
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would deploy ${skill_file} to ${remote_skill}/SKILL.md"
  else
    echo "Deploying ${skill_name} to ${remote_skill} ..."
    databricks workspace mkdirs "${remote_skill}" ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"} 2>/dev/null || true
    databricks workspace import "${remote_skill}/SKILL.md" --file "${skill_file}" --format AUTO --overwrite ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"}
    echo "Done."
  fi
}

# --- --init-all: 全 Genie Code スキルを一括デプロイ ---
do_init_all() {
  if [[ ! -d "$GENIE_SKILLS_DIR" ]]; then
    echo "Error: Genie skills directory not found: ${GENIE_SKILLS_DIR}" >&2
    echo "  Run 'hms' to deploy genie skills via Home Manager." >&2
    exit 1
  fi

  # --init-all では STEERING_SKILL_MD による override を無効化
  # （全スキルに同じファイルが配られるのを防ぐ）
  unset STEERING_SKILL_MD

  local count=0
  for skill_dir in "${GENIE_SKILLS_DIR}"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_file="${skill_dir}SKILL.md"
    [[ -f "$skill_file" ]] || continue

    local skill_name
    skill_name=$(basename "$skill_dir")
    validate_skill_name "$skill_name"

    do_init "$skill_name"
    count=$((count + 1))
  done

  if [[ $count -eq 0 ]]; then
    echo "Warning: no skills found in ${GENIE_SKILLS_DIR}" >&2
  else
    echo ""
    echo "Deployed ${count} skill(s)."
  fi
}

# --- push: databricks sync ベースの同期 ---
do_sync() {
  local steering_dir="$1"
  local db_user
  db_user=$(get_db_user)

  local dir_name parent_name remote_dir
  dir_name=$(basename "$steering_dir")
  parent_name=$(basename "$(dirname "$steering_dir")")
  remote_dir="/Users/${db_user}/steering/${parent_name}/${dir_name}"

  local sync_flags=()
  sync_flags+=(--include "*.md")
  sync_flags+=(--exclude "SKILL.md")
  sync_flags+=(--exclude "handoff-*")
  [[ "$FULL_SYNC" == true ]] && sync_flags+=(--full)
  [[ "$WATCH_MODE" == true ]] && sync_flags+=(--watch)

  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] databricks sync ${sync_flags[*]} $steering_dir $remote_dir"
    databricks sync "${sync_flags[@]}" --dry-run "$steering_dir" "$remote_dir" ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"}
  else
    echo "Syncing steering docs to ${remote_dir} ..."
    databricks sync "${sync_flags[@]}" "$steering_dir" "$remote_dir" ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"}
    echo "Done."
  fi
}

# --- pull: リモートパス解決ヘルパー ---
resolve_pull_paths() {
  local steering_dir="$1"
  local db_user
  db_user=$(get_db_user)

  local dir_name parent_name
  dir_name=$(basename "$steering_dir")
  parent_name=$(basename "$(dirname "$steering_dir")")
  _pull_remote_dir="/Users/${db_user}/steering/${parent_name}/${dir_name}"
}

# --- pull: diff ベースの安全な pull ---
do_pull() {
  local steering_dir="$1"
  resolve_pull_paths "$steering_dir"
  local remote_dir="$_pull_remote_dir"

  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "${tmp_dir:-}"; [[ -n "${CLEANUP_DIR:-}" ]] && rm -rf "$CLEANUP_DIR"' EXIT

  echo "Pulling remote steering docs ..." >&2
  if ! databricks workspace export-dir "${remote_dir}" "${tmp_dir}" --overwrite ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"}; then
    echo "Error: failed to export from ${remote_dir}. Check that the remote directory exists." >&2
    exit 1
  fi

  # *.md のみを対象に diff（push の --include "*.md" と範囲を揃える）
  local has_diff=false
  local found_md=false
  for remote_f in "${tmp_dir}"/*.md; do
    [[ -f "$remote_f" ]] || continue
    found_md=true
    local fname
    fname=$(basename "$remote_f")
    local local_f="${steering_dir}/${fname}"

    local diff_exit=0
    if [[ -f "$local_f" ]]; then
      diff -u "$local_f" "$remote_f" || diff_exit=$?
    else
      diff -u /dev/null "$remote_f" || diff_exit=$?
    fi

    if [[ $diff_exit -eq 1 ]]; then
      has_diff=true
    elif [[ $diff_exit -gt 1 ]]; then
      echo "Error: diff failed for ${fname} (exit code: $diff_exit)" >&2
      exit 1
    fi
  done

  # ローカルにだけ存在する .md（リモートで削除された可能性）を検出
  for local_f in "${steering_dir}"/*.md; do
    [[ -f "$local_f" ]] || continue
    local fname
    fname=$(basename "$local_f")
    [[ "$fname" == "SKILL.md" ]] && continue
    [[ "$fname" == handoff-* ]] && continue
    if [[ ! -f "${tmp_dir}/${fname}" ]]; then
      echo "--- ${fname}: exists locally but not on remote (may have been deleted) ---"
      has_diff=true
    fi
  done

  if [[ "$found_md" == false ]]; then
    echo "Warning: no .md files found in remote directory ${remote_dir}" >&2
  elif [[ "$has_diff" == false ]]; then
    echo "No differences. Local and remote are in sync." >&2
  else
    echo "" >&2
    echo "--- Differences found (local=left, remote=right) ---" >&2
  fi
}

# --- pull --dry-run: リモートファイル一覧 ---
do_pull_dry_run() {
  local steering_dir="$1"
  resolve_pull_paths "$steering_dir"
  local remote_dir="$_pull_remote_dir"

  echo "Remote files in ${remote_dir}:"
  databricks workspace list "${remote_dir}" ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"} --output text 2>/dev/null || {
    echo "Error: remote directory not found: ${remote_dir}" >&2
    exit 1
  }
}

# --- pull --force: バックアップ + 即上書き ---
do_pull_force() {
  local steering_dir="$1"
  resolve_pull_paths "$steering_dir"
  local remote_dir="$_pull_remote_dir"

  # バックアップ作成
  local backup
  backup="${steering_dir}.bak.$(date +%s)"
  cp -r "$steering_dir" "$backup"
  echo "Backup created: ${backup}"

  # 一時ディレクトリに取得してから *.md のみコピー（push と同じスコープ）
  local tmp_dir
  tmp_dir=$(mktemp -d)
  if ! databricks workspace export-dir "${remote_dir}" "${tmp_dir}" --overwrite ${DB_PROFILE_FLAG[@]+"${DB_PROFILE_FLAG[@]}"}; then
    rm -rf "$tmp_dir"
    echo "Error: failed to export from ${remote_dir}" >&2
    exit 1
  fi

  # *.md のみ上書き（SKILL.md / handoff-* は除外）
  local copied=0
  for f in "${tmp_dir}"/*.md; do
    [[ -f "$f" ]] || continue
    local fname
    fname=$(basename "$f")
    [[ "$fname" == "SKILL.md" ]] && continue
    [[ "$fname" == handoff-* ]] && continue
    cp "$f" "${steering_dir}/${fname}"
    copied=$((copied + 1))
  done
  rm -rf "$tmp_dir"
  echo "Done. Pull completed with overwrite (${copied} files)."
}

# --- メイン ---
# --init のみの場合も cleanup が必要
trap '[[ -n "$CLEANUP_DIR" ]] && rm -rf "$CLEANUP_DIR"' EXIT

if [[ $# -lt 1 ]]; then
  echo "Usage:" >&2
  echo "  $0 [--dry-run] [--profile <name>] --init <skill-name>            # Deploy single skill" >&2
  echo "  $0 [--dry-run] [--profile <name>] --init-all                     # Deploy all Genie skills" >&2
  echo "  $0 [--dry-run] [--profile <name>] [--full|--watch] <steering-dir> # Push steering docs" >&2
  echo "  $0 [--dry-run] [--profile <name>] --pull [--force] <steering-dir>  # Pull steering docs" >&2
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
      [[ $# -lt 2 ]] && {
        echo "Error: --profile requires a value" >&2
        exit 1
      }
      DB_PROFILE_FLAG=(--profile "$2")
      shift 2
      ;;
    --full)
      FULL_SYNC=true
      shift
      ;;
    --watch)
      WATCH_MODE=true
      shift
      ;;
    --pull)
      PULL_MODE=true
      shift
      ;;
    --force)
      FORCE_MODE=true
      shift
      ;;
    --init | --init-all)
      break # サブコマンドとして処理
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

# --init-all サブコマンド
if [[ "$1" == "--init-all" ]]; then
  check_deps
  check_auth
  do_init_all
  exit 0
fi

# --init サブコマンド
if [[ "$1" == "--init" ]]; then
  SKILL_NAME="${2:-}"
  if [[ -z "$SKILL_NAME" ]]; then
    echo "Error: skill name is required. Usage: $0 --init <skill-name>" >&2
    echo "Hint: use --init-all to deploy all skills under \$GENIE_SKILLS_DIR" >&2
    exit 1
  fi
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

# オプションの排他制御
if [[ "$FORCE_MODE" == true && "$PULL_MODE" != true ]]; then
  echo "Error: --force can only be used with --pull" >&2
  exit 1
fi
if [[ "$PULL_MODE" == true && "$DRY_RUN" == true && "$FORCE_MODE" == true ]]; then
  echo "Error: --dry-run and --force cannot be combined with --pull" >&2
  exit 1
fi
if [[ "$PULL_MODE" == true && ("$FULL_SYNC" == true || "$WATCH_MODE" == true) ]]; then
  echo "Error: --full and --watch are push-only options, cannot be combined with --pull" >&2
  exit 1
fi

check_deps
check_auth

if [[ "$PULL_MODE" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    do_pull_dry_run "$STEERING_DIR"
  elif [[ "$FORCE_MODE" == true ]]; then
    do_pull_force "$STEERING_DIR"
  else
    do_pull "$STEERING_DIR"
  fi
else
  do_sync "$STEERING_DIR"
fi
