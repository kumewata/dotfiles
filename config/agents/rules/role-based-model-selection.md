# Role-Based Model / Effort Selection

タスクの目的ごとに、Claude Code の subagent へ **モデル**と **reasoning effort** を構造的に割り当てるための運用ルール。
「多くのトークンを安いモデル単価・低 effort に寄せる」ことでコストを抑えつつ、判断が要る箇所には強いモデルと高 effort を残す。

参考: [genda_jp / Fable をコスパよく運用する](https://zenn.dev/genda_jp/articles/b6045575e2e13d)、
[サブエージェントネスト](https://zenn.dev/genda_jp/articles/16d35ffa464d65)。

## 基本原則

- **コスト = トークン数 × モデル単価 × effort**。判断が不要な広域探索・実装・テスト実行は、安いモデル・低 effort の subagent に逃がす。
- **メインセッションは計画・設計判断・最終レビューに専念する**。広い調査や確定仕様の実装は subagent に委譲し、メインの context を汚さない。
- **frontmatter で構造的に固定する**。`model:` / `effort:` は subagent 定義に書くことで、メイン・孫を問わず全階層から同じ選択肢として再利用される（ネスト時も一貫）。
  - `effort:` の有効値: `low` / `medium` / `high` / `xhigh` / `max`（利用可否はモデル依存。session の effort を override）。
  - `model:` の有効値: `sonnet` / `opus` / `haiku` / `fable` / フルID / `inherit`（既定は `inherit`）。

## 役割マッピング

| タスク                           | 委譲先                                                                 | モデル                       | effort |
| -------------------------------- | ---------------------------------------------------------------------- | ---------------------------- | ------ |
| 計画・設計判断・最終レビュー     | メインセッション                                                       | （セッション既定 / Opus 等） | —      |
| 広域コード調査（read-only）      | `code-explore`                                                         | sonnet                       | medium |
| 仕様が確定した実装               | `implementer`                                                          | sonnet                       | medium |
| 複数ファイル実装・デバッグ       | `heavy-implementer`                                                    | opus                         | high   |
| テスト / lint / build 実行と要約 | `test-runner`                                                          | haiku                        | low    |
| 設計計画の作成                   | `planner` / `architect`                                                | opus                         | high   |
| コード / セキュリティレビュー    | `code-reviewer` / `security-reviewer`                                  | sonnet                       | high   |
| 言語別レビュー・TDD・doc 更新    | `python-reviewer` / `terraform-reviewer` / `tdd-guide` / `doc-updater` | sonnet                       | medium |
| ドキュメント / steering 検索     | `doc-search` / `steering-research`                                     | haiku                        | low    |

## 使い分けの判断軸

- **迷ったら安い方から。** まず `implementer`（sonnet/medium）を試し、スコープが複数ファイルに広がる・デバッグが要る・失敗が不明瞭なら `heavy-implementer`（opus/high）へエスカレーションする。
- **read-only の広域探索は必ず `code-explore` に寄せる。** 大量の grep 結果・ファイル本文をメイン context に載せない。返るのは `file_path:line_number` 参照と要約のみ。
- **検証は `test-runner` に委譲する。** `implementer` / `heavy-implementer` は自分の変更検証時に `test-runner` を孫として呼んでよい（ネスト）。汎用ロールなので早めに使う。
- **effort を上げすぎない。** 仕様が明確な単純作業では `low` / `medium` で十分。深い推論・セキュリティ・複雑なデバッグにのみ `high` 以上を使う。

## 報告契約（context 最小化）

subagent はコード全文を返さない。以下に絞る:

- 変更ファイル一覧（`file_path` 参照）
- 検証コマンドと結果（pass/fail + 要点）
- 未検証リスク・前提・エスカレーション事項

メインセッションは必要なファイルだけを個別に Read する。
