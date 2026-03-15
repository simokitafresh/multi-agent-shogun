# DM-signal コンテキスト（索引）
<!-- last_updated: 2026-03-12 cmd_814 cmd_804-cmd_812索引更新 -->
<!-- last_synced_lesson: L317 -->

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
| 25 | 殿確定事項（2026-03-11 trade-rule/business_rules突合） | (本ファイル) |
| 26 | 2026-03-12 性能・運用更新（cmd_804〜cmd_812） | (本ファイル) |

## 弱体化確率推定(P_det)

P(deterioration)=Φ(-Z)方式（3窓: 6/12/24ヶ月、6ラベル、HAC/winsorize）を採用。cmd_539でエンジン実装+7PFパイロット検証を完了し、cmd_540でローリングlong基準(K=120ヶ月)の検知力天井問題を分析してドリフトガード合議を完了。
詳細設計・裁定ログ: `MCP:deterioration_probability_design`（cmd_539, cmd_540）

## §23 Deterioration Monitor 本番稼働

Render BE + cronで本番運用中。P(det)=Φ(-Z)方式、3窓(6/12/24ヶ月)、6段階ラベル(Stable/Watch/Caution/Warning/Danger/Critical)。フォルダフィルタ+ページナビ対応済。
設計詳細: `MCP:deterioration_probability_design` | エンジン実装: cmd_539 | ドリフトガード: cmd_540

## §24 G1/G2/P色丸ラベル(cmd_613)

Dashboard/Compare Summary/Deterioration Monitor/FAQの4ページで数値→色丸(緑/黄/オレンジ + 灰=INSUFFICIENT_DATA)に変換。直感的視認性を確保。

## §25 殿確定事項（2026-03-11 trade-rule/business_rules突合）

| # | 確定内容 | 影響先 |
|---|---------|--------|
| 1 | FoF参照日: 矛盾なし。「直近リバランス時のsignal_dateで確定したsignal」が正。「前月末」表現はリバランスタイミングにより不正確 → 避ける | RULE08, cmd_767 AC1 |
| 2 | wᵢ = 月初目標ウェイト。非リバランス月でも月初にリセット（暗黙的月次リバランス）。どの月からでもユーザーが公平に参加できる意図的設計 | RULE05/06, cmd_767 AC3 |
| 3 | Trade期間リターン: buy-and-holdではなく月次複利合成 R_trade=Π(1+R_月)-1。FoF×非月次シグナルで乖離。四神・忍法の再選定が必要 | cmd_768(critical) |
| 4 | SSOT 3層: Price table(L0データ) → calculate_monthly_return()(L1) → MonthlyReturn table(L2キャッシュ) | cmd_767 AC5 |
| 5 | business_rules.md §3.4 Loading Policy（Optimistic UI禁止）は古い。SWR許可 | cmd_765続行 |
| 6 | Safe Haven: コードとbusiness_rules.md §1.1完全一致。Cash=DTB3、safe_haven_asset設定でGLD/XLU等 | cmd_767 AC7 |

→ `projects/dm-signal.yaml` RULE05/06/08/SSOT階層を更新済み
→ `docs/rule/business_rules.md` は古い箇所あり。§3.4 Loading Policyは陳腐化

## §26 2026-03-12 性能・運用更新（cmd_804〜cmd_812）

| cmd | 結論 | 参照 |
|---|---|---|
| cmd_804 | CDP本番計測は16ページ全閾値PASS。最大改善は Monthly Returns warm `147→129ms (-12.2%)` | `queue/archive/reports/tobisaru_report_cmd_804_20260312.yaml` |
| cmd_805 | `/api/monthly-returns` の主因は `ticker_monthly_returns=0` による fallback 全Price scan。window query化で `months=12` は約 `-88%` 改善見込 | `queue/reports/hayate_report_cmd_805.yaml` / `context/dm-signal-core.md` §8 (`L255`) |
| cmd_806 | N+1を12箇所検出。最重要は `monthly_trade_calculator._build_entries()` で約 `170→3 queries`、約8秒短縮見込 | `queue/reports/hanzo_report_cmd_806.yaml` / `context/dm-signal-core.md` §8 (`L252`,`L254`) |
| cmd_808 | Monthly Returns Before計測は `2026-03-12 04:37 JST` 時点で進行中。比較用ベースライン取得フェーズ | `dashboard.md` 戦果/進行中セクション |
| cmd_810 | CDP preflight fail-fast を実装。ブラウザ未起動を約 `4.63s` で検知し、接続timeoutとコマンドtimeoutを分離 | `reports/cmd_810_fix_kagemaru.yaml` / `dashboard.md` |
| cmd_811 | CDPブラウザ未起動時の `auto_launch_browser` 実装完了。`preflight fail → 自動起動 → 再preflight → 計測続行` の到達経路を確認済み | `reports/cmd_811_impl_kagemaru.yaml` / `queue/archive/reports/kirimaru_report_cmd_811_review_2_20260312.yaml` |
| cmd_812 | 報告YAML欠損の真因は `report file` 未検証の auto-done hook。done通知は `ninja_done.sh` の検証付き経路へ統一が再発防止策 | `queue/archive/reports/hayate_report_cmd_812_20260312.yaml` / `context/infrastructure.md` (`L209`,`L210`) |

## 補助ポインタ

- プロジェクト核心知識: `projects/dm-signal.yaml`
- プロジェクト教訓: `projects/dm-signal/lessons.yaml`
- フロントエンド: `context/dm-signal-frontend.md`
- GS高速化知見: `context/gs-speedup-knowledge.md`
- L3堅牢性: `context/l3-robustness.md`

## 教訓索引（自動追記）

- （現在0件。L149-L272は振り分け済。L273-L301は振り分け済 → auto-ops§CDP計測(L274-276), ops教訓索引(L273), frontend§5/§6/§9(L277/280/284/287/292/300), core§2/§19.4(L296/283), research弱体化確率(L278/279/285)/GS(L286/299)/新§27持続性(L281/282/288/289/291/293-295/297-298/301)。L290はL285重複→統合）
- （L302-L309は振り分け済 → research§持続性(L302-305), research§SPA(L306), ops§16(L307/308), frontend§9(L309)）
- L310: apiCache.clear()はETag IDB(dm-signal-etag-store)を削除しない。clear直後のAPI呼出でETag送信→304→キャッシュなしエラーが発生しうる。clearSignalsCache()は独自対策済みだが汎用clear()にはない。修正対象: frontend/lib/api-cache.ts:204-212, frontend/lib/api-client.ts:254-259
- L311: api-client.tsのisRetryableError()はネットワークエラーのみリトライ対象(failed to fetch/network/aborted/timeout)。HTTP 5xx(サーバー一時障害)はリトライされない。Render cold start時の502/503で即エラーUI表示になる。5xxを1回リトライする改善候補。対象: frontend/lib/api-client.ts:388-401
- L312: 5xxエラーがリトライ対象外（cmd_962）
- L313: apiCache.clear()はETag IDBを削除しない→304エラーの可能性（cmd_962）
- L314: CORS expose_headersなしではFEがカスタムレスポンスヘッダを読めない（cmd_964）
- L315: Payload cacheとvalidator cache分離構成ではinvalidatorが両層同時破棄必須（cmd_964）
- L316: WSL→Windows venv Ruff hook: repo-relative pathを使え
- L317: MetricsCalculator右尾4指標は実装済みだがFE未露出（cmd_976）
