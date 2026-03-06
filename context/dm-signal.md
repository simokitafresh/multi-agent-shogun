# DM-signal コンテキスト（索引）
<!-- last_updated: 2026-03-05 lesson-sort L168-L186振り分け完了 -->
<!-- last_synced_lesson: L192 -->

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
| 22 | 弱体化確率推定 | (本ファイル) |
| 23 | Deterioration Monitor本番稼働 | (本ファイル) |
| 24 | G1/G2/P色丸ラベル | (本ファイル) |

## 弱体化確率推定(P_det)

P(deterioration)=Φ(-Z)方式（3窓: 6/12/24ヶ月、6ラベル、HAC/winsorize）を採用。cmd_539でエンジン実装+7PFパイロット検証を完了し、cmd_540でローリングlong基準(K=120ヶ月)の検知力天井問題を分析してドリフトガード合議を完了。
詳細設計・裁定ログ: `MCP:deterioration_probability_design`（cmd_539, cmd_540）

## §23 Deterioration Monitor 本番稼働

Render BE + cronで本番運用中。P(det)=Φ(-Z)方式、3窓(6/12/24ヶ月)、6段階ラベル(Stable/Watch/Caution/Warning/Danger/Critical)。フォルダフィルタ+ページナビ対応済。
設計詳細: `MCP:deterioration_probability_design` | エンジン実装: cmd_539 | ドリフトガード: cmd_540

## §24 G1/G2/P色丸ラベル(cmd_613)

Dashboard/Compare Summary/Deterioration Monitor/FAQの4ページで数値→色丸(緑/黄/オレンジ + 灰=INSUFFICIENT_DATA)に変換。直感的視認性を確保。

## 補助ポインタ

- プロジェクト核心知識: `projects/dm-signal.yaml`
- プロジェクト教訓: `projects/dm-signal/lessons.yaml`
- フロントエンド: `context/dm-signal-frontend.md`
- GS高速化知見: `context/gs-speedup-knowledge.md`
- L3堅牢性: `context/l3-robustness.md`

## 教訓索引（自動追記）

- （現在0件。L149-L167は振り分け済。L168-L186は振り分け済 → core§2/§8/§10, ops§9/§12/§14, frontend§4/§5, research影響算定）
- L187: ジェネリックソートフックのnull処理は方向別(multiplier)との合成結果まで検証する（cmd_569）
- L188: window.location遷移を採用する構成ではContext単独の状態共有は永続化要件を満たさない（cmd_570）
- L189: ページ順序定義をsidebar/mobile-menu/page-navigationに重複保持すると導線不整合が発生しやすい（cmd_564）
- L190: 集計要件でrole分離が必要ならイベント記録時点で識別子を保存しないと後段SQLでは復元不能（cmd_574）
- L191: TypeScript列追加時は tsc --noEmit でユニオンキー添字安全性を検証すべき。runtime安全でもunion keyを広げた row.metrics[key] は型で破綻する(cmd_613 TS7053)（cmd_613）
- L192: レビューでは UI 挙動確認に加えて型系ユニオン拡張の添字安全性まで検査すべき（cmd_613）
