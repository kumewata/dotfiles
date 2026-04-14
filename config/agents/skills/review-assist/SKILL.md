---
name: review-assist
description: |
  Use when the user wants help understanding and reviewing a PR in an unfamiliar domain, needs background explanation of PR changes and surrounding code conventions, wants consistency checks against existing code patterns, or needs to determine whether to escalate the review to a domain expert. Trigger especially when the user says "help me understand this PR", "explain this PR", "who should review this", "review support for unfamiliar code", "PRのレビューを手伝って", "このPRの背景を教えて", or asks for review guidance with context about being unfamiliar with the domain. Do NOT use for automated code review (use codex-delegate instead), posting review comments directly to GitHub (use github skill), or local git-only operations without a PR context.
---

# Review Assist

Supports human PR reviewers in unfamiliar domains through staged analysis: background explanation, convention consistency checks, review point organization (must/want/info/nits), reviewer qualification assessment with escalation support, and review comment drafting.

This skill is a **meta-layer over automated reviews** — it evaluates and supplements automated review comments (Copilot, CodeRabbit, etc.) rather than replacing them.

## 1. Prerequisites

- Target repository is **cloned locally** (required for git log, git blame, surrounding code analysis)
- gh CLI is installed and authenticated
- The user provides a PR URL

## 2. PR URL Parsing

Extract owner, repo, and number from the PR URL:

```
Pattern: https://github.com/{OWNER}/{REPO}/pull/{NUMBER}
```

If the URL is invalid, ask the user to provide a valid GitHub PR URL.

## 3. Phase 0: Reviewer Self-Assessment

**Purpose**: Determine the reviewer's familiarity with the PR's domain to inform Phase 3.5 qualification assessment.

**Step 1**: Fetch the file list to identify the tech stack:

```bash
gh pr view NUMBER --repo OWNER/REPO --json files --jq '.files[].path'
```

**Step 2**: Identify the primary tech stack from file extensions and directory patterns (e.g., `.sql` + `models/` → dbt, `.tf` → Terraform, `.py` → Python).

**Step 3**: Ask the user and **wait for a response before proceeding**:

> このPRは主に **{tech stack}** の変更です。この領域に詳しいですか？
> 得意領域を簡単に教えてください（スキップも可）。

Do NOT proceed to Phase 1 until the user responds or explicitly skips. This is the only interactive pause in the skill.

**Step 4**: Record the response:
- User responds with expertise → store as `reviewer_expertise` for Phase 3.5
- User says "skip", "スキップ", or equivalent → set `reviewer_expertise = unknown`, default to Level B in Phase 3.5
- User provides the PR URL together with context like "dbt は初めて" → extract expertise from context, no separate question needed

## 4. Phase 1: PR Information Retrieval

Fetch all PR data. Run these commands in **parallel**:

```bash
# PR metadata + changed files
gh pr view NUMBER --repo OWNER/REPO --json title,body,author,state,baseRefName,headRefName,url,files

# Diff with line numbers (for comment drafting)
gh pr diff NUMBER --repo OWNER/REPO | awk '
BEGIN { old_line=0; new_line=0; in_hunk=0 }
/^diff --git/ { in_hunk=0; print; next }
/^---/ || /^\+\+\+/ { print; next }
/^@@/ {
  in_hunk=1
  match($0, /-([0-9]+)/, old)
  match($0, /\+([0-9]+)/, new)
  old_line = old[1]
  new_line = new[1]
  print
  next
}
in_hunk && /^-/ { printf "L%-4d     | %s\n", old_line++, $0; next }
in_hunk && /^\+/ { printf "     R%-4d| %s\n", new_line++, $0; next }
in_hunk { printf "L%-4d R%-4d| %s\n", old_line++, new_line++, $0; next }
{ print }
'

# Existing comments (issue comments + review comments)
gh api repos/OWNER/REPO/issues/NUMBER/comments --jq '.[] | {id, user: .user.login, created_at, body}'
gh api repos/OWNER/REPO/pulls/NUMBER/comments --jq '.[] | {id, user: .user.login, path, line, body, in_reply_to_id}'

# Review request status
gh api repos/OWNER/REPO/pulls/NUMBER/requested_reviewers
```

**Large PR guard**: If changed files > 15 OR changed lines > 800, switch to representative file analysis — pick the top 5 files by change volume. Exclude lockfiles and generated files (e.g., `*.lock`, `package-lock.json`, `*.generated.*`) from analysis scope.

## 5. Phase 2: Context Collection

### 5-A: Dependency Tracking

Extract dependency references from the diff based on the detected language:

| Language | Pattern | Example |
|----------|---------|---------|
| dbt | `ref('model')`, `source('src', 'table')` | `ref('stg_orders')` |
| Python | `import mod`, `from mod import name` | `from utils import helper` |
| Terraform | `module "x" { source = "..." }`, `data "type" "name"` | `module "vpc" { source = "./modules/vpc" }` |

For each extracted reference, read the referenced file from the local repository. If the language is not in the table above, note: "この依存パターンは自動追跡の対象外です。手動での確認を推奨します。"

### 5-B: Directory Pattern Analysis

For each directory containing changed files:

1. List existing files in the same directory with Glob
2. Read 2-3 representative files (prefer recently modified)
3. Extract patterns:
   - Config settings (tags, materialized, etc.)
   - Naming conventions (file names, column names)
   - YAML structure (description, meta, test definitions)
   - Import/reference patterns

### 5-C: Contributor Analysis (for Phase 3.5)

Collect contributor data from three sources, in priority order:

**Source 1: CODEOWNERS** (if exists)

```bash
cat CODEOWNERS 2>/dev/null | grep -E "^[^#]" | grep "<directory-pattern>"
```

Skip if CODEOWNERS does not exist.

**Source 2: git log** (6-month window, bot-filtered)

```bash
git log --since='6 months ago' --format='%an' -- <target-directory> \
  | grep -v -E '(dependabot|renovate|github-actions)' \
  | sort | uniq -c | sort -rn | head -5
```

Exclude bulk-formatting commits (single commit touching 50+ files):

```bash
# Identify and exclude bulk commits
BULK_COMMITS=$(git log --since='6 months ago' --pretty=format:'%H' -- <target-directory> | while read sha; do
  count=$(git diff-tree --no-commit-id --name-only -r "$sha" | wc -l)
  [ "$count" -gt 50 ] && echo "$sha"
done)
```

**Source 3: git blame**

```bash
git blame --line-porcelain <target-file> | grep "^author " | sort | uniq -c | sort -rn | head -5
```

## 6. Phase 3: Analysis and Review

### Analysis Framework

| Aspect | Content | Domain Knowledge Required |
|--------|---------|--------------------------|
| Consistency | Deviations from existing patterns | No |
| Missing elements | Required config/meta/tests absent | No |
| Naming | File/column name convention compliance | Low |
| Documentation | Required items present/absent | Low |
| Design decisions | Better alternatives exist? | Yes (supplement with questions) |

**Domain knowledge rule**: When an analysis item requires domain knowledge that the reviewer lacks (marked "Yes" or "Low" above), tag it with `⚠ PR作成者に確認が必要` in the output. This makes it explicit which items are reviewer judgment vs. items requiring author clarification.

### Classification Criteria

| Level | Criteria | Examples |
|-------|----------|---------|
| **must** | Bug, regression risk, safety issue, clear convention violation | Missing required test, SQL injection risk, breaking existing contract |
| **want** | Quality improvement: consistency issue, operational concern | Inconsistent naming vs directory pattern, missing description |
| **info** | Decision material: design alternatives, background knowledge | Alternative approach exists, related model context |
| **nits** | Minor fix: formatting, typo | Trailing whitespace, comment typo |

### Automated Review Comment Evaluation

If automated review comments exist (Copilot, CodeRabbit, etc.):

1. For each automated comment, assess: **agree**, **partially agree**, or **disagree**
2. Provide a reason for the assessment
3. Add supplementary context if the automated comment misses important nuance

Output format:
```
**Copilot comment on file.py:42**: "Consider null check"
→ **Agree** — この関数は外部入力を受けるため、null チェックは必須です。
```

## 7. Phase 3.5: Reviewer Qualification Assessment

### Decision Logic

```
Inputs:
  - reviewer_expertise (from Phase 0)
  - domain_items: list of items from Phase 3 requiring domain knowledge
  - has_blocker: any item affects runtime/security/schema integrity

Level A (self-review sufficient):
  IF reviewer_expertise matches the tech stack
  OR (domain_items count <= 1 AND has_blocker = false)
  → Proceed to Phase 4 with full review

Level B (partial review + handoff):
  IF domain_items count >= 2
  OR reviewer_expertise = unknown (skipped Phase 0)
  → Produce partial review + escalation memo

Level C (escalation recommended):
  IF most changes are outside reviewer_expertise
  AND has_blocker = true (design decisions with runtime/security impact)
  → Produce background summary + escalation memo only
```

### Examples

- **Level A**: dbt に詳しい人が dbt モデル追加PRをレビュー。お作法チェックで十分
- **Level B**: Python に詳しいが Terraform は初めて。命名規則やconfig一貫性は見えるが、state管理の設計判断は持てない
- **Level C**: フロントエンド専門の人がインフラ（Terraform + Airflow DAG）の大規模変更をレビュー

### Expert Identification

Using data from Phase 2-C, present candidates in priority order:

1. CODEOWNERS owner (if available)
2. Top contributor by commit frequency (git log, 6-month window)
3. Recent author of the target file (git blame)

Format: `@{name}（{根拠: このディレクトリの変更の{N}%を担当、直近6ヶ月で{M}件}）`

## 8. Phase 4: Output

### Level A: Full Review

```markdown
## PR #{NUMBER} の解説とレビュー

### 背景の整理
{PRの動機、なぜこの変更が必要か、技術的背景の解説}

### ファイル別解説
{各ファイルの変更内容を解説。技術用語は初回登場時に簡単な説明を添える}

### レビューポイント

各指摘には必ず「なぜそれが問題か」の理由を付与すること。ドメイン知識が必要な判断には「⚠ PR作成者に確認が必要」と明示すること。

#### must（必須修正）
- {指摘内容} — 理由: {なぜ問題か}
- {該当なしの場合は「特になし」と明示}

#### want（改善推奨）
- {指摘内容} — 理由: {なぜ問題か}
- {該当なしの場合は「特になし」と明示}

#### info（参考情報）
- {指摘内容} — 理由: {なぜ参考になるか}
- {該当なしの場合は「特になし」と明示}

#### nits（些細な修正）
- {指摘内容}
- {該当なしの場合は「特になし」と明示}

### 既存の自動レビューコメントの評価
{Copilot等のコメントがあれば、採否を理由付きで評価。なければ「自動レビューコメントなし」}

### まとめ
{変更の安全性評価、主な確認ポイント}
```

### Level B: Partial Review + Handoff

Level A の全セクションに加え、以下を追加:

```markdown
### レビュアー適格性の判定
**判定: Level B — 部分レビュー + 引き継ぎ推奨**

自分でレビューできた範囲:
- {一貫性チェック結果}
- {命名規則の確認結果}

判断に専門知識が必要な部分:
- {具体的な点}

### 適任者候補
- @{name}（{根拠}）

### 引き継ぎメモ（下書き）
> @{name} このPRのレビュー支援をお願いできますか。
> 私が確認できた範囲: {一貫性チェック結果のサマリ}
> 判断に迷っている点: {具体的な点}
> 確認してほしい論点: {具体的に何を判断してほしいか}
```

### Level C: Escalation

```markdown
## PR #{NUMBER} の解説とレビュー

### 背景の整理
{PRの動機を1-2文で要約}

### レビュアー適格性の判定
**判定: Level C — エスカレーション推奨**

理由: {変更の大部分が{技術領域}の専門知識を要するため}

### 適任者候補
- @{name}（{根拠}）

### 状況説明メモ（下書き）
> @{name} このPRのレビューをお願いできますか。
> PR概要: {1-2文の要約}
> 自分にはこの領域の知見が不足しており、適切なレビューが困難です。
> 確認してほしい論点: {具体的に何を判断してほしいか}
```

## 9. Phase 5: Review Comment Drafting

Based on the review points from Phase 4, generate draft comments for posting to the PR.

Format for each comment:

```
**[must/want/info/nits]** `{file_path}` R{line_number}
{指摘内容と理由（なぜそれが問題か / なぜ改善すべきか）}
```

Each draft comment must include the reason for the finding, not just the finding itself.

These are drafts for the user to review and edit before posting. Do NOT post comments automatically.

## 10. Interactive Follow-up

After presenting the review output, remain available for:

- **Deep-dive**: User asks "ここがわからない" → explain the specific code section in detail
- **Comment refinement**: User asks to adjust a draft comment → revise the wording
- **Additional analysis**: User asks about a specific file or pattern → read and analyze
- **Escalation help**: User decides to escalate → help refine the handoff memo

## 11. Related Resources

| Resource | Purpose |
|----------|---------|
| skills/github | gh CLI commands, inline comment format |
| skills/codex-delegate | Automated review delegation (different use case) |
| skills/git | Local git operations |
