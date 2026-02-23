# DM-signal コンテキスト（索引）
<!-- last_updated: 2026-02-23 cmd_280 3ファイル分割 -->

> 読者: エージェント。推測するな。タスクに応じて必要なファイルを読め。

タスクに `project: dm-signal` がある場合、このファイルと必要な分割ファイルを読め。
パス: `/mnt/c/Python_app/DM-signal/`

## 分割ファイル一覧

| ファイル | 内容 | 読むべき場面 |
|---------|------|------------|
| `context/dm-signal-core.md` | DB構造、四神定義、忍法BB、API、ディレクトリ構成、恒久ルール | 実装・DB操作・パイプライン変更 |
| `context/dm-signal-ops.md` | recalculate Phase、OPT-E、性能、GS手順、ドキュメントインデックス、ステータス | 運用・GS実行・デプロイ・保守 |
| `context/dm-signal-research.md` | 月次リターン傾き分析、LA検証、過剰最適化検証 | 研究・分析・検証タスク |
| `context/dm-signal-frontend.md` | フロントエンド固有コンテキスト | フロントエンド変更 |

## セクション→ファイル対応表

| § | セクション名 | 分割先 |
|---|------------|--------|
| 0 | 研究レイヤー構造 | core |
| 1 | システム全体像 | core |
| 1.5 | 再計算の排他制御 | core |
| 2 | DB地図 | core |
| 3 | 四神構成 | core |
| 4 | ビルディングブロック | core |
| 5 | ローカル分析関数 | core |
| 6 | recalculate_fast.py Phase別処理フロー | ops |
| 7 | OPT-Eアーキテクチャ | ops |
| 8 | APIエンドポイント概要 | core |
| 9 | 性能ベースライン | ops |
| 10 | ディレクトリ構成 | core |
| 11 | Lookback標準グリッド | core |
| 12 | 計算データ管理の原則 | ops |
| 13 | StockData API | core |
| 14 | 既存ドキュメントインデックス | ops |
| 15 | 殿の個人PF保護リスト | core |
| 16 | 知識基盤改善 | ops |
| 17 | 現在の全体ステータス | ops |
| 18 | backend folder_id実態 | core |
| 19 | 月次リターン傾き分析 | research |
| 20 | ルックアヘッドバイアス検証 | research |
| 21 | 過剰最適化検証 | research |

## 補助ポインタ

- プロジェクト核心知識: `projects/dm-signal.yaml`
- プロジェクト教訓: `projects/dm-signal/lessons.yaml`
- フロントエンド: `context/dm-signal-frontend.md`
- GS高速化知見: `context/gs-speedup-knowledge.md`
- L3堅牢性: `context/l3-robustness.md`
