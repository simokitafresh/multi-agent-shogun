# DM-signal コンテキスト（索引）
<!-- last_updated: 2026-03-20 cmd_1123 シン四神v2/シン忍法v2確定+GS高速化+パリティ検証+p̄検証 -->
<!-- last_synced_lesson: L504 -->

> 読者: エージェント。推測するな。タスクに応じて必要なファイルを読め。

タスクに `project: dm-signal` がある場合、このファイルと必要な分割ファイルを読め。
パス: `/mnt/c/Python_app/DM-signal/`

## 分割ファイル一覧

| ファイル | 内容 | 読むべき場面 |
|---------|------|------------|
| `context/dm-signal-core.md` | DB構造、四神定義、忍法BB、API、ディレクトリ構成、恒久ルール | 実装・DB操作・パイプライン変更 |
| `context/dm-signal-ops.md` | recalculate Phase、OPT-E、性能、GS手順、ドキュメントインデックス、ステータス | 運用・GS実行・デプロイ・保守 |

## DB操作ランブック（必読）

本番DB操作（PF登録・削除・再計算・Lookback変換等）を行うタスクでは必ず参照せよ:
→ `docs/rule/db-operations-runbook.md` （§1接続〜§9教訓索引、全9章）
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
| 27 | シン四神v2設計（2026-03-19確定） | research |
| 28 | 2026-03-12〜03-20 主要更新（シン四神v2/GS高速化/パリティ） | (本ファイル) |

## 弱体化確率推定(P_det)

P(deterioration)=Φ(-Z)方式（3窓: 6/12/24ヶ月、6ラベル、HAC/winsorize）を採用。cmd_539でエンジン実装+7PFパイロット検証を完了し、cmd_540でローリングlong基準(K=120ヶ月)の検知力天井問題を分析してドリフトガード合議を完了。
詳細設計・裁定ログ: `MCP:deterioration_probability_design`（cmd_539, cmd_540）
P(det)と構造変化検定は別概念: P(det)=rolling recent vs longの方向付き悪化確率（生成過程変化を探索しない）、構造変化検定=break date探索。補完関係が自然。レジーム検出追加時はbreak検出と悪化方向判定を分離せよ → `lessons.yaml` L285参照

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

## §28 2026-03-12〜03-20 主要更新

| 領域 | 結論 | 参照 |
|---|---|---|
| シン四神v2確定 | 旧v1(191,796広探索→CPCV→32体)を全廃。DNA事前制約→データ駆動lookback→3モードチャンピオン直接選出。**12スロット設計**(4ファミリー×3モード)。GS結果(cmd_1018)では重複吸収後**10体**(朱雀・玄武の激攻=常勝同一→常勝消滅) | `context/dm-signal-research.md` §27 |
| シン忍法v2確定 | 10体×7忍法=173,625パターンGS。全**21体**ユニーク(吸収0)。最強: 加速D-激攻 CAGR 86.6% | `context/dm-signal-research.md` §27 シン忍法v2 |
| 本番登録計画 | 事故歴あり(cmd_1082: パリティ未検証で登録→汚染33体DELETE)→段階的チェックリストで進行中 | `context/checklist-shin-v2-registration.md` |
| CPCV廃止 | FoF材料に完成品基準を当てていた。殿裁定: 素材は一瞬のきらめきで十分(cmd_1078) | `context/dm-signal-research.md` §27 L415 |
| GS高速化 | 23h→42min(PPE+picks vectorize)→並列12min。numpy momentum cube追加最適化 | `context/gs-speedup-knowledge.md` |
| p̄検証 | PBarSelectionBlock実装+BT。月次戦術運用は無効(Sharpe 0/192全敗, cmd_1009)。p̄はFoFレイヤーの「計算と解釈の分離」原則に準拠 | `context/dm-signal-research.md` §27 L337 |
| パリティ修正 | FoF component_weights flush未配線修正(cmd_1096)、resample月末修正(cmd_1115)、valid_start_date全構成シンボル包含(cmd_1115) | `context/dm-signal-core.md` §4 L419/L427/L428 |
| 本番不変量(PI) | standard PFにpipeline_config必須(Cash fallback防止, PI-001)。PI-001〜PI-008運用開始 | `projects/dm-signal.yaml` production_invariants |
| PF健全性スイープ | 全122PF×5項目パス(cmd_1091)。定期実行候補 | `context/dm-signal-ops.md` §17 |
| 304キャッシュ修正 | 本番304 Not Modifiedキャッシュ不整合バグ緊急修正(cmd_1011) | — |
| FE Biome導入 | ESLint→Biome移行+PostToolUse Hook(cmd_971) | `context/dm-signal-frontend.md` |
| 金融ML知識辞書 | Vercelスタイル骨格構築+López de Prado全知見体系化(cmd_863-872) | `docs/knowledge-base/` |
| OOS検証配置 | ルールベース戦略のOOS検証はpipeline block(allocation)ではなくGS runner上位の評価層に配置。parity/registry無破壊で拡張可能。oos_r2をchampion選定補助指標化 | `lessons.yaml` L286参照 |
| GS出力先自動振り分け | run_077スクリプトはuniverse名からサブディレクトリを自動生成(例: shin_ninpo_v2_12body/)。cmd AC設計時にスクリプトの実際の出力先仕様を事前確認すべき | `lessons.yaml` L433参照 |

## 補助ポインタ

- プロジェクト核心知識: `projects/dm-signal.yaml`
- プロジェクト教訓: `projects/dm-signal/lessons.yaml`
- フロントエンド: `context/dm-signal-frontend.md`
- GS高速化知見: `context/gs-speedup-knowledge.md`
- L3堅牢性: `context/l3-robustness.md`

## 教訓索引（自動追記）

- （現在0件。L149-L272は振り分け済。L273-L301は振り分け済 → auto-ops§CDP計測(L274-276), ops教訓索引(L273), frontend§5/§6/§9(L277/280/284/287/292/300), core§2/§19.4(L296/283), research弱体化確率(L278/279/285)/GS(L286/299)/新§27持続性(L281/282/288/289/291/293-295/297-298/301)。L290はL285重複→統合）
- （L302-L309は振り分け済 → research§持続性(L302-305), research§SPA(L306), ops§16(L307/308), frontend§9(L309)）
- （L310-L321は振り分け済 → core§8(L310/311/314/315), core§5(L317), core§4(L318/320), ops§6-7(L319), ops§9(L321), infra WSL2(L316)。L312/L313はL311/L310重複→削除）
- （L322-L333は振り分け済 → research§持続性(L322-L324/L327-L328), core§3(L325), frontend§4(L326)/§8(L333), ops§6-7(L330/L332)/Ops索引(L329)。L331はL330重複→削除）
- （L334-L350は振り分け済 → research§持続性(L334-L337), research§GS(L338/L341-L343/L348), ops索引(L339/L344-L347/L349-L350), frontend§12(L340)）
- （L351-L378は振り分け済 → research§27シン四神(L351/352/354/355/356), research§GS結果(L358/359), research§パリティ(L361/378), gs-speedup§3(L366/369/372/373/374), gs-speedup§4(L364/365/367), gs-speedup§5(L360/363), gs-speedup§6(L368/370), ops教訓索引(L357[PI-002]), infra§レビュー(L375), infra§git(L377), infra§報告(L362), infra§知識管理(L353)。L371はL367重複→統合、L376はL374重複→統合）
- （L379-L388は振り分け済 → gs-speedup§3(4)(L380), gs-speedup§3(5)(L382), gs-speedup§3(6)(L383), gs-speedup§3(7)(L385), gs-speedup§4(L379/L384), gs-speedup§6(L381)。L386はL384重複→統合、L387はL382重複→統合、L388はL383重複→統合）
- （L389-L402は振り分け済 → research§パリティ(L389/L391/L392), gs-speedup§3(4)(L395), gs-speedup§3(5)(L398), gs-speedup§3(6)(L396), gs-speedup§3(7)(L390/L393/L394/L399), gs-speedup§4(L397/L401), gs-speedup§5(L402), infra§LLM(L400)）
- （L403-L407は振り分け済 → gs-speedup§3(4)(L403/L404/L407), gs-speedup§6(L405/L406)）
- （L408は振り分け済 → gs-speedup§3(1)）
- （L409-L410は振り分け済 → research§GS結果(L409), gs-speedup§4(L410)）
- （L411-L422は振り分け済 → gs-speedup§4(L411), core§8(L412), research§27(L413/L414/L415), gs-speedup§3(L416), ops§17(L417), infra§知識サイクル(L418), core§4(L419/L421), core§2[PI-008](L420), research教訓索引(L422)）
- （L423-L429は振り分け済 → research§パリティ検証。L426はL424重複→削除）
- （L430-L457は振り分け済 → research§パリティ(L430/L439/L440/L441/L442/L444/L448/L449/L452/L454), research§GS結果(L432/L433/L434/L435), core§19.2(L438/L445/L447), core§19.4(L431), gs-speedup§3(L451)/§4(L450), infra§知識管理(L436)/§報告(L437)。重複削除: L426=L424, L443=L440, L446=L441, L453=L451, L455=L454, L456=L450, L457=L452）
- （L458-L460は振り分け済 → gs-speedup§3(8)(L458), research§パリティ(L459)。L460はL458重複→削除）
- （L461/L473は振り分け済 → research§パリティ検証(L461/L473[PI-010])）
- （L474/L475は振り分け済 → ops§6-7 recalculate_fast.py(L474:事前計算データソース統一, L475:DTB3リサンプルPI-010同根)）
- （L476-L478は振り分け済 → research§パリティ検証(L476[PI候補]), ops§6-7(L477), core§19.4(L478)）
- （L479-L484は振り分け済 → research§パリティ(L479/L480/L482), core§19.4(L481), ops教訓索引(L483)。L484はL483重複→削除）
- （L485-L488は振り分け済 → research§パリティ検証(L485/L486/L487/L488)）
- （L493-L504は振り分け済 → research§24(L493), research§27(L494/L495/L498), core§13[PI-017](L496), core§5(L497), research§26(L499), core§1(L500/L501), ops§6-7(L502), ops§9(L503), ops索引(L504)）
