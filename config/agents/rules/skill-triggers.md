# Skill Triggers

定常的に使用するスキルのトリガー条件。
該当する状況では **Skill ツールでスキルを読み込み、手順に従って作業すること**。

## 必須トリガー

### steering（作業計画・進捗管理）

ユーザーから作業指示を受けた場合、**デフォルトで** steering スキルを使用する。

**以下のすべてに該当する場合のみ省略可**:
- 変更対象が単一ファイルかつ変更箇所が明白
- 新規ファイルの作成を伴わない
- テストやビルドの確認が不要
- 単純な質問への回答、または調査のみの依頼

### git（Git 操作）

commit, branch, rebase 等の Git 操作時に使用する。

### github（GitHub 操作）

PR 作成・レビュー、Issue 管理等の GitHub 操作時に使用する。

## 推奨トリガー

| Skill | Trigger |
|-------|---------|
| frontmatter | `.steering/` 配下や docs/ のドキュメント作成時 |
| nix | Nix Flakes / Home Manager の設定変更時 |
| claude-config-optimizer | CLAUDE.md, rules/, skills/, agents/ の編集・最適化時 |
| skill-creator | 新しいスキルの作成・更新時 |
| index-generator | INDEX.md の自動生成が必要なとき |

## コンテキスト一致時に自動発動

以下のスキルは description に基づいて自動発動するため、明示的なトリガーは不要:

terraform, terraform-test, terraform-style-guide, terraform-refactor-module,
draw-io, bigquery, databricks, dbt, pdf, xlsx, codex-delegate
