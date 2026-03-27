# Global Rules

全プロジェクト共通の行動指針。フリクション分析に基づき策定。

## Pull Request Workflow

- PR レビューコメント対応時は必ず:
  1. 全レビューコメントに返信（完了前に未返信がないか `gh api graphql` で確認）
  2. PR description をスコープ変更に合わせて更新（`gh pr edit --body`）

## Planning & Investigation

- steering document や設計を始める前に、CLI/API で現状を調査する
- 仮定に基づく設計ではなく、事実に基づく設計を行う
- インフラ管理状況（Terraform 管理の有無等）について推測で記述しない。記述前に必ず実態を確認する

## Code Generation & Verification

- コード生成・変更前に schema / config / source of truth を確認する
- 変更後は該当テスト or lint or dry-run を実行して検証する

## Interaction Rules

- 曖昧な指示の場合は、着手前に解釈の要約と完了条件を確認する
- 破壊的操作（ファイル削除、force push 等）や大きな変更の前に必ず確認を取る
- 複数のアプローチがある場合は選択肢を提示して確認する

## Git Workflow

- git worktree 使用時は、ブランチ操作前に CWD が正しいか確認する
- `git merge` の前に必ず `git fetch` を実行する
- submodule clone は SSH を優先する
