---
description: Update existing steering documents for the current task
---

今のタスク向けに既存の steering ドキュメント（~/.local/state/steering/ 配下）があれば、最新状態に更新してください。

## 手順

1. steering-research エージェントを使って、現在のリポジトリ・ブランチに関連する steering ドキュメントを検索する
2. 該当ドキュメントが見つかった場合:
   - requirements.md, design.md, tasklist.md の内容を現在のコード・git 状態と照合する
   - 差分があればドキュメントを更新する（完了タスクのチェック、新たな知見の反映等）
3. 該当ドキュメントが見つからない場合: その旨を報告する
