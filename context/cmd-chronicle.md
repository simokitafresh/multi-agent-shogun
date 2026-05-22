# CMD年代記
<!-- last_updated: 2026-05-22 -->

> 完了cmdの1行索引。詳細は queue/archive/cmds/{cmd_id}.yaml 参照。

## 2026-03

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| — | → 3月前半(03-09, cmd_662-707)は `context/archive/cmd-chronicle-2026-03-early.md` 参照 | — | 03-09 | 43件 |
| cmd_940 | 偵察+整備 — Drive確定申告フォルダの整合性検証+チェックリスト恒久化 | | auto-ops | 03-14 | Drive「2026確定申告 個人事業」フォルダの完全性・整合性チェック完了。 3AC全て調査完了。ローカルCSVとDrive版の間に体系的な差異を検出。 |
| cmd_942 | 偵察 — 確定申告証票PDFの重複・有効性調査 | | auto-ops | 03-14 | — |
| cmd_944 | 修正 — マスターCSV更新（MFクレカ追加反映） | | auto-ops | 03-14 | — |
| cmd_945 | 修正 — PayPal公式レシートPDFでDrive既存PDFを差し替え | | auto-ops | 03-14 | — |
| cmd_946 | 実装 — マスターCSV列16「使用カード」追加 | | auto-ops | 03-14 | — |
| cmd_943 | 修正+整備 — 確定申告証票PDF浄化 | | auto-ops | 03-14 | — |
| cmd_949 | 修正 — CDP修復+note領収書DL試行 | | auto-ops | 03-15 | — |
| cmd_948 | 修正 — Anthropic領収書アップロード+[OK]格上げ | | auto-ops | 03-15 | — |
| cmd_947 | 修正 — note.com領収書DL（売上手数料2件+振込手数料11件） | | auto-ops | 03-15 | — |
| cmd_950 | 偵察 — 欠損領収書6商号Gmail調査+取得可能性判定 | | auto-ops | 03-15 | — |
| cmd_951 | 修正 — 全Driveフォルダ Invoice/Receipt混在是正 | | auto-ops | 03-15 | — |
| cmd_955 | 最適化 — monthly-returns fallback window query化（-88%改善） | | dm-signal | 03-15 | — |
| cmd_956 | 最適化 — monthly_trade N+1クエリ修正（170→3 queries） | | dm-signal | 03-15 | — |
| cmd_957 | 偵察 — MCP obs正本突合（Vercel原則適用） | | infra | 03-15 | — |
| cmd_959 | 偵察 — MCP判定割れobs万全偵察（8名独立判定） | | infra | 03-15 | — |
| cmd_960 | 強化 — 逆瀬川記事知見4点取込 | | infra | 03-15 | — |
| cmd_961 | 強化 — tdd-guard型Hook＋Gate（テストSKIP/FAIL機械強制） | | infra | 03-15 | — |
| cmd_962 | 万全偵察 — DM-signal UX快適性の現況再調査 | | dm-signal | 03-15 | — |
| cmd_964 | 修正 — FEキャッシュ整合性修復（ETag孤児/SWR不統一） | | dm-signal | 03-15 | — |
| cmd_963 | 修正 — BE N+1クエリ修正High3件 | | dm-signal | 03-15 | — |
| cmd_967 | 修正 — trade-rule.md §7.3aに§2.1 SSOT 3層への逆参照追加 | | dm-signal | 03-15 | trade-rule.md §7.3aの逆参照注記を強化。既 |
| cmd_968 | 強化 — 金融ML知識辞書 ID予約済み5エントリの辞書化 | | dm-signal | 03-15 | 金融ML知識辞書 ID予約済み5エントリの辞書化完了。 全フ |
| cmd_965 | 最適化 — Recharts/KaTeX dynamic import強化（バンドル27%削減） | | dm-signal | 03-15 | Recharts/KaTeX dynamic import強 |
| cmd_966 | 修正 — FEテスト5件FAIL修復（現行コードへの追随） | | dm-signal | 03-16 | — |
| cmd_958 | 修正 — MCP Vercel原則適用（構造改革） | | infra | 03-16 | — |
| cmd_969 | 強化 — DM-Signal Ruff導入 + PostToolUse Hook品質ループ構築 | | dm-signal | 03-16 | — |
| cmd_971 | 強化 — DM-Signal FE Biome PostToolUse Hook + Hurl API E2Eテスト | | dm-signal | 03-16 | DM-Signal FE Biome導入+PostToolU |
| cmd_974 | 偵察 — Codex忍者のアイデンティティ認識状況調査 | | infra | 03-16 | — |
| cmd_975 | 偵察 — DM-Signal PF健全性・現在ポジション・実績の定量調査 | | dm-signal | 03-16 | — |
| cmd_970 | 強化 — infra shellcheck PostToolUse Hook + リンター設定保全 | | infra | 03-16 | — |
| cmd_972 | 強化 — Stop Hook完了ゲート + エラーメッセージ修正 | | infra | 03-16 | — |
| cmd_973 | 強化 — AIアンチパターン検出 + ast-grepアーキテクチャ | | infra | 03-16 | — |
| cmd_976 | 偵察 — 殿の哲学から導くDM-Signal診断指標の再設計 | | dm-signal | 03-16 | — |
| cmd_978 | 衛生 — 全プロジェクト .gitignore整備 + 未プッシュ一覧 | | infra | 03-16 | — |
| cmd_980 | 偵察 — 教訓注入率低下の原因精査と改善提案 | | infra | 03-16 | — |
| cmd_979 | 強化 — lint違反放置禁止ルール + Stop Hook lint残留チェック | | infra | 03-16 | — |
| cmd_1010 | 四神12体+忍法15体 — 極値プロファイル・相関構造・忍法コンビネーション分析 | | dm-signal | 03-16 | AC7横断サマリー完了。4サブタスク(Sub-A〜D)の結果 |
| cmd_1301 | startup gate bash算術エラー修正 — grep -c || echo anti-pattern根絶 | infra | 03-23 | gate_shogun_startup.sh L101/L282の grep -c || echo anti-pattern を修正。syntax error  |

## 2026-04

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_1696 | 影丸(Sonnet 4.6)の@model_nameが「Opus」と誤表示。根因: model_detect.shのバナー検出パターンが (Opus|Haiku)のみでSonnetが欠落。Sonnetバナーがマッチせずキャッシュの古い値が返される。 加えて、陣形図(karo_snapshot.txt)にモデル情報列がなく、編成状態が不可視。 | infra | 04-03 | model_detect.shにSonnet検出パターン追加 |
| cmd_1697 | cmd_save.sh L152-153のgrep "scope_mode:"/"scout_exempt:"がcmdブロック内にマッチしない場合、 set -eで即exit 1。|| trueがないのが原因。cmd_1696でscout_exemptなし初回BLOCK発生の根因。 | infra | 04-03 | cmd_save.sh L152-153のgrep scop |
| cmd_1825 | 奥義-シン忍法 WF直列実行 — AC1完了済み7 CSVに対し1本ずつWF実行 | dm-signal | 04-22 | — |
| cmd_1824 | 研究道具レジストリ構築 — cmd起票時に道具の最新CLI引数を自動表示 | infra | 04-22 | — |
| cmd_karo_gs_benchmark | GS Phase1c — 8スクリプト現行ベンチマーク | dm-signal | 04-22 | — |
| cmd_1775 | ALM四神 pipeline_config再生成 — 本番制約内champion再選別 | dm-signal | 04-22 | — |
| cmd_1806 | fix — CI赤根治 — gunshi_role.md commit + bats期待値動的化 + 未追跡.md検出 | infra | 04-22 | — |
| cmd_1818 | ALM青龍-激攻 1体パリティ — 研究L0リターンと本番monthly_returnsの完全一致 | dm-signal | 04-22 | — |
| cmd_1820 | ALM四神 本番パリティ — 研究vs本番の月次リターン不一致原因特定+修正 | dm-signal | 04-22 | — |
| cmd_1822 | 奥義-シン忍法(再) — シン忍法20体を材料にGS新規実行+67窓WF | dm-signal | 04-22 | — |
| cmd_1839 | 奥義-シン忍法 WF実行+チャンピオン選出 — 3目的(CAGR/NHF/MaxDD)×7忍法 | dm-signal | 04-22 | — |
| cmd_1843 | perf — wf_runner.py WF並列ランナー新規作成（7忍法メモリグループ並列） | dm-signal | 04-22 | — |
| cmd_1828 | fix — l1_alm_wf_engine.py メモリ削減第2弾（中間配列float32化+drawdown追従） | dm-signal | 04-22 | — |
| cmd_1876 | L2奥義 正しい設計で再実行 — 各方式3目的(最大21体)universe+GS+8パターン選出+因子分析 | dm-signal | 04-22 | — |
| cmd_karo_ci_fix_1885 | CI修正 — cmd_1885 autofix pre-step導入によるテスト期待値不整合4件 | infra | 04-22 | — |
| cmd_1895 | L3忍法GS — L2奥義84体(GS固定①③⑤⑦)を材料にした既存忍法パイプライン実行+β調整 | dm-signal | 04-22 | — |
| cmd_karo_ci_fix_ga122 | CI修正 — cmd_2109副作用のテスト10件失敗修正 | infra | 04-22 | — |
| cmd_2121 | 強化(将軍) — cmd_save.sh q_ambiguity追加 (不明瞭自覚の自己申告) | infra | 04-22 | scripts/cmd_save.shにq_ambiguit |
| cmd_karo_ci_fix_2221 | CI RED修正 — cmd_save.sh関連テスト16件FAIL | infra | 04-22 | — |
| cmd_2224 | 検証 — CLAUDE.md英語化の突合+4ロールテスト(cmd_2223後追い) | infra | 04-22 | CLAUDE.md日本語原本との40行突合を完了し、4ロール |
| cmd_2225 | 整備 — Language Policy Phase 3b deploy_task.sh出力英語化 | infra | 04-22 | — |
| cmd_2226 | 整備 — Language Policy Phase 3a/3d/3e 小規模スクリプト出力英語化 | infra | 04-22 | — |
| cmd_karo_ci_fix_2225 | CI RED修正 — deploy_task.sh英語化によるテスト期待値不一致4件 | infra | 04-22 | Updated the two failing deploy |
| cmd_karo_ci_fix_gp199 | CI RED修正 — GP-199テスト期待値が日本語のまま | infra | 04-22 | Updated the GP-199 warning exp |
| cmd_2227 | research-tool — Vintage分析パイプライン雛形作成(道具磨き) | dm-signal | 04-22 | Implemented vintage_pipeline.p |
| cmd_2228 | research — Vintage 2020分析(コロナショック L0→L1→L2再選出+OOS検証) | dm-signal | 04-22 | python3 scripts/analysis/alm_r |
| cmd_2229 | research-tool — Vintage L0→L1→L2全レイヤーGSにend_date引数追加(道具磨き) | dm-signal | 04-22 | Added end-date cutoff propagat |
| cmd_2230 | 殿裁定: 英語化により全エージェントの日本語理解が著しく低下。 CLAUDE.md/AGENTS.md/スクリプト出力/テストを全て日本語に戻す。 設計書: docs/research/rollback_english_design_20260422.md 軍師レビュー: APPROVE (confidence: HIGH, 指摘0件) | infra | 04-22 | Phase 3の10本をgit historyから日本語期待 |
| cmd_karo_context_freshness_2224 | 整備 — dm-signal context鮮度回復(9日未更新) | dm-signal | 04-22 | dm-signal context indexes refr |
| cmd_2231 | fix — ETL cron OOM解消: curl→python直接実行 + メモリ計測 | dm-signal | 04-22 | AC4: log_memory_usage()を全Phase |
| cmd_2232 | 強化 — CDP CLI標準化: cdp_cli.shをワンストップCDP入口に拡張 | auto-ops | 04-22 | cdp_cli.sh に launch/navigate/e |
| cmd_karo_auto_ops_context_freshness | 調査 — auto-ops context freshness ALERTの原因分析 | auto-ops | 04-22 | cmd_2232 の context未反映箇所を特定し、co |
| cmd_2233 | CoDD偵察 — daily_etl.pyの存在理由調査: 本番fullrecalculateとの乖離分析 | dm-signal | 04-22 | FILL_THIS |
| cmd_karo_ci_fix_ga158 | CI RED修正 — cmd_save environment_change テスト317-320復旧 | infra | 04-22 | cmd_save.shのPythonパーサーがassumpt |
| cmd_2234 | fix — sync-prices(L0)を全期間取得+UPSERTに変更: 730日固定→FULL_HISTORY_START | dm-signal | 04-22 | sync_layers.py DEFAULT_LOOKBAC |
| cmd_2236 | 廃止 — daily_etl.py + ETL cron削除: L0-L3 sync cronに統一 | dm-signal | 04-22 | ETL cron廃止完了。Render ETL cron(c |
| cmd_2235 | 検証 — sync cron L0→L3手動実行: 全期間再取得+再計算の完走確認 | dm-signal | 04-22 | L0/L1/L2はRender logs+timinig h |
| cmd_karo_deploy_notice_fix | 修正 — deploy_task.sh task YAML破損(_deploy_notice継続行残留)を根治 | infra | 04-22 | yaml_field_set.sh が scalar sib |
| cmd_2237 | fix — 壊れた一回限りパリティテスト2本削除: pytest collection error解消 | dm-signal | 04-22 | 壊れたパリティテスト2本を削除して commit e7c69 |
| cmd_2238 | 偵察 — pytest残存失敗8件の切り分け(修正候補 vs 削除候補) | dm-signal | 04-22 | FILL_THIS |
| cmd_karo_max_inject_fix | 修正 — deploy_task lesson注入でMAX_INJECT未定義になる経路を根治 | infra | 04-22 | MAX_INJECT を tag fallback 前へ前倒 |
| cmd_2141 | 実装 — Up vs Down MarketにSideways行追加 + レスポンシブ対応 | dm-signal | 04-23 | — |
| cmd_2210 | 研究 — L2 GS固定選出 vs WF動的選出 比較分析記事+gist共有 | dm-signal | 04-23 | — |
| cmd_2239 | CoDD最適化 — ticker_returns.py(L1: リターン計算) | dm-signal | 04-23 | — |
| cmd_2240 | CoDD最適化 — recalculate_fast.py(L2/L3計算本体) | dm-signal | 04-23 | — |
| cmd_2241 | CoDD最適化 — recalculate_fof.py(L3: FoF再計算, 最大ボトルネック) | dm-signal | 04-23 | — |
| cmd_2242 | CoDD最適化 — sync_layers.py(オーケストレーター) | dm-signal | 04-23 | — |
| cmd_2243 | CoDD準備 — data_fetcher.py(L0) extract+spec作成 | dm-signal | 04-23 | 既存sandbox抽出物とspecの再確認でAC1/AC2は |
| cmd_2244 | CoDD準備 — ticker_returns.py(L1) extract+spec作成 | dm-signal | 04-23 | AC1: CoDD extract完了(codd/extra |
| cmd_2245 | CoDD準備 — recalculate_fast.py(L2/L3計算本体) extract+spec作成 | dm-signal | 04-23 | recalculate_fast.py(3048行)のcod |
| cmd_2246 | CoDD準備 — recalculate_fof.py(L3: FoF再計算, 最大ボトルネック) extract+spec作成 | dm-signal | 04-23 | CoDD extractとspec作成は完了したが、AC3の |
| cmd_2247 | CoDD準備 — sync_layers.py(オーケストレーター) extract+spec作成 | dm-signal | 04-23 | FILL_THIS |
| cmd_karo_2231_ac7_retry | 検証 — cmd_2231 AC7やり直し: 既存成功job基準のsignal比較のみ | dm-signal | 04-23 | 既存成功job d7k7k1cm0tmc73acvga0 を |
| cmd_karo_ci_fix_ga159 | CI RED修正 — deploy_task if_then/legacy detailテスト2件 | infra | 04-24 | cmd_save diagnose 系は HEAD 時点で既 |
| cmd_2248 | fix — cmd_save.sh gate偽陽性率改善: FP率60%超のWARN type修正 | infra | 04-24 | cmd_save.sh のWARN noteを型付き化し、r |
| cmd_karo_ci_fix_2248 | CI RED修正 — test_cmd_save_warn_logging AC2テスト失敗 | infra | 04-24 | test_cmd_save_warn_logging.bat |
| cmd_2249 | fix — cmd_save.sh check_self_reread_red_flag FP修正: YAMLキー名をgrep対象から除外 | infra | 04-24 | check_self_reread_red_flag の P |
| cmd_2250 | fix — cmd_save.sh Session State拡張: 同一WARN 2回目以降で検出ロジック自動表示 | infra | 04-24 | cmd_save.sh の WARN記録に check me |
| cmd_2251 | 偵察 — recalculate_fof.py L3速度改善設計書: 依存分析+cProfile+FE整合性 | dm-signal | 04-24 | recalculate_fof/fullrecalculat |
| cmd_2252 | fix — cmd_save.sh LS009/LS029 gate化: 各論パッチ検出+assumptions時系列強制 | infra | 04-24 | cmd_save の LS009/LS029 挙動を回帰テス |
| cmd_karo_gate_clear_idle | fix — GATE CLEAR後のtask YAML自動idle化 | infra | 04-24 | cmd_complete_gate.sh に GATE CL |
| cmd_2253 | 最適化 — trade_performance生成 速度改善（設計書Rank 1） | dm-signal | 04-24 | FILL_THIS |
| cmd_karo_conflict_marker_gate | fix — lessons SSOT conflict markers検出gate | infra | 04-24 | gate_lesson_health.sh に SSOT l |
| cmd_karo_pd_summary_fix | fix — pending_decisions.yaml summary自動再計算 | infra | 04-24 | pending_decision_write.shにreca |
| cmd_2254 | fix — FoF MonthlyReturn DB永続化バグ修正（precompute rollback巻き添え防止） | dm-signal | 04-24 | precomputeをPF単位savepoint化し、例外時 |
| cmd_2255 | 実装 — DM-Signal本番ヘルスチェックスクリプト（DB→API→FE 3レイヤー貫通確認） | dm-signal | 04-24 | scripts/health_check.py を追加し、D |
| cmd_karo_ci_fix_2252 | fix — CI RED修正: cmd_save.bats 12テスト失敗 | infra | 04-24 | 6件テストフィクスチャのassumptions claimに |
| cmd_2257 | 偵察+設計 — FoF増分計算化のCoDD設計書生成(recalculate_fof.py + recalculate_fast.py L2528-2638) | dm-signal | 04-24 | _recalculate_fof_history全文読解完了 |
| cmd_2258 | impl — FoF sync-fof増分計算化(Signal差分+MR増分。462.8s→60s目標) | dm-signal | 04-24 | FoF増分計算実装完了。sync-fof(PORTFOLIO |
| cmd_2259 | impl — FoF MR生成高速化: signal_cacheバッチ事前ロード+共有化(PI-024準拠・全期間再計算維持) | dm-signal | 04-24 | cmd_2259を完了した。初回修正(af469454)でs |
| cmd_2260 | impl — FoF MR生成 DB fallback穴塞ぎ(356→0件目標。26.53s→1.5s) | dm-signal | 04-24 | price_ratio_calculatorのcomplet |
| cmd_2261 | 偵察 — L3_fof daily_loop 224sの内訳計測+高速化ターゲット特定 | dm-signal | 04-24 | cmd_2261_scout完了。live timing(r |
| cmd_2262 | 本番FEのユーザー体験速度を定量計測する。全ページの初回表示時間、PF切替時の再描画速度(10回連続)、ページ間遷移時間を計測し、ボトルネック特定の基礎データを取得する。コード変更なし。 | dm-signal | 04-25 | FILL_THIS |
| cmd_2263 | cmd_save.sh BLOCK時に将軍が止まる問題を自動化×強制で解消する。BLOCK出力の冒頭に「止まるな、修正して再実行」ナッジを1行追加。 | infra | 04-25 | cmd_save.shのBLOCK初回出力にだけ「止まるな、 |
| cmd_2264 | cmd_2262の計測データとFEコードの現状分析を基に、FE表示速度を改善するための設計書を作成する。全ページで「PF切替が一瞬」を達成するための改善施策を優先度付きで網羅する。コード変更なし。 | dm-signal | 04-25 | cmd_2262原票とFE/BEコードを基に、FE速度改善設 |
| cmd_2265 | cmd_save.shのgate偽陽性率が高すぎる(16件がFP率66%超)。偽陽性は将軍のBLOCK対応時間を浪費し殿の時間を奪う。共通根を修正し全cmdに複利で効くgate精度改善を行う。 | infra | 04-25 | FILL_THIS |
| cmd_2266 | cmd_2264設計書の穴6件を埋める補完偵察。BE profiling + FEフィールド使用マッピング + Render構成制約 + デプロイ順序 + Static Export制約 + 依存関係の正確な整理を行い、設計書を補完更新する。 | dm-signal | 04-25 | cmd_2266補完偵察完了。`docs/research/ |
| cmd_2267 | /api/signalsの最大ボトルネック(FoF display展開 220-360ms/500-700ms)を事前計算化して初回表示・ページ遷移を250-400ms短縮する。設計書§4.2 Measure A + §6.1の分析に基づく。 | dm-signal | 04-25 | FoF displayをrequest時再展開から事前計算l |
| cmd_2268 | cmd_2267(FoF display事前計算化)をpush→Render deploy→CDP再計測し、速度改善効果とバグ有無を確認する。cmd_2262のベースラインと比較。 | dm-signal | 04-25 | push・Render deploy・healthz確認まで |
| cmd_2269 | gate BLOCKパターン分析→instructions修正提案を自動生成する仕組みを構築。GEPA(ICLR 2026 Oral)の自然言語反射アプローチを将軍システムに適用。deepdive Phase 5「なぜの目的=自動化ターゲット特定」の機械化。 | infra | 04-25 | FILL_THIS |
| cmd_2270 | deploy_task.shの教訓注入で、タスク内容に基づく関連度スコアリングを導入。engram(autoresearch-engram)の頻度重み付きクロスセッション知識検索を参考に、教訓有用率を7.7%から大幅改善する。 | infra | 04-25 | deploy_task.shの教訓注入にキーワード関連度スコ |
| cmd_2271 | cmd_2268のCDP計測失敗を条件調整して再実行。Phase 1-A(signals slim化)の速度改善効果とバグ有無を確認する。 | dm-signal | 04-25 | FILL_THIS |
| cmd_karo_ci_fix_2270 | cmd_2270でMAX_INJECT=3→10に変更したがテスト2件(test 444/445)が旧値3を期待してFAIL。テストを新値10に更新しCI GREEN復帰する。 | infra | 04-25 | MAX_INJECT=10変更に追随して deploy_ta |
| cmd_2272 | GStack/GBrain深掘りカタログ(docs/research/gstack-gbrain-takeaway-catalog.md §8)のRound 1全15項目をinstructions/context/templateに追記。全cmdのレビュー品質・偵察品質・報告品質に複利で効く。 | infra | 04-25 | AC2(ashigaru.md: bisect commit |
| cmd_2273 | cmd_complete_gate.shに4つの新検証を追加し、忍者のscope逸脱・レビュー陳腐化・部分完了・修正暴走を構造的に検出する。cmd_2271事故(scope外174行改変)の再発防止。 | infra | 04-25 | cmd_complete_gate.shに4新検証(scop |
| cmd_2274 | CDP計測結果にbaseline比較・回帰閾値判定・health score算出を追加。deploy後の性能変化を自動検出し、Phase毎の改善効果を数値で追跡可能にする。 | infra | 04-25 | scripts/cdp/cdp_benchmark.py(. |
| cmd_2275 | 教訓管理の陳腐化検出(Prune)、プロジェクト横断教訓検索、deploy再実行の冪等性、差分テストの4機能を追加。教訓品質と配備効率に複利で効く。 | infra | 04-25 | AC1: ~/.claude/skills/dream/SK |
| cmd_2276 | deploy_task.shの教訓注入がtarget_pathベースのタグマッチのみでCDP教訓が0件注入された事故(cmd_2271)の根因修正。purpose/command/context_filesのキーワードも加味し、タスク内容に関連する教訓を正しくルーティングする。 | infra | 04-25 | FILL_THIS |
| cmd_2277 | 強化 — GStack知見Round 2-G2: レビュー系4項目(Adaptive gating/Adversarial review/Scope lock/前提3段階) | infra | 04-25 | FILL_THIS |
| cmd_2278 | 強化 — GStack知見Round 3: L工数4項目(Deploy後監視/check-resolvable/routing-eval/ハイブリッド検索) | infra | 04-25 | AC1 cdp_canary.sh と AC4 hybrid |
| cmd_2279 | 修正 — cmd_save.sh check_gunshi_design_num_relax カタログ参照FP除外 | infra | 04-25 | FILL_THIS |
| cmd_2280 | 強化 — GStack知見Round 2-G2再実施: レビュー系4項目(Adaptive gating/Adversarial review/Scope lock/前提3段階) | infra | 04-25 | FILL_THIS |
| cmd_2281 | Phase 1-A(FoF display事前計算化, cmd_2267)のdeploy済み本番FEをCDP計測し、cmd_2262ベースラインと速度改善効果を比較。cmd_2268/2271で2回失敗(認証不成立+artifact上書き)の教訓を反映。 | dm-signal | 04-25 | FILL_THIS |
| cmd_2282 | BLOCK率50%の最大原因draft_lessons(13件/100件)の根因=教訓登録が意志依存を自動化×強制で解消 | infra | 04-25 | cmd_save.sh 4箇所精査完了。CLEARリマインド |
| cmd_2283 | 実装 — FE signals handoff cache（Phase 1-B: hard navigation遷移時のblank/loading除去） | dm-signal | 04-26 | SignalsProviderにsessionStorage |
| cmd_2285 | 強化 — cmd起票前の事前確認gate（PreToolUse:Edit hook for shogun_to_karo.yaml） | infra | 04-26 | shogun_to_karo.yaml Edit時の起票前確 |
| cmd_2286 | 強化 — 忍者版事前ワクチン（DM-Signal本番ファイル編集時にPI注入） | infra | 04-26 | FILL_THIS |
| cmd_2287 | 修正 — cmd_complete_gate.shにtest_triage判定追加（pre_existing FAIL誤判定バグ修正） | infra | 04-26 | cmd_complete_gateのbinary_check |
| cmd_2284 | 強化 — cmd_save.sh BLOCK後の将軍自走強制hook | infra | 04-26 | cmd_save.sh BLOCK(exit 1)時だけPo |
| cmd_2288 | 検証 — Phase 1-B CDP再計測（handoff cache効果確認+ベースライン比較） | dm-signal | 04-26 | FILL_THIS |
| cmd_2289 | 強化 — 第三層指標転換（忙しさ→賢さ: 同クラス再発率+ワクチン有効率をstartup gateに追加） | infra | 04-26 | Gate 12.5拡張完了。再発率(前50cmd vs直近5 |
| cmd_2291 | 検証 — CDP再計測（道具磨き後・全ページ+PF切替） | dm-signal | 04-26 | — |
| cmd_2292 | 偵察 — シン四神→シン忍法→シン奥義 L0→L2経路の現物検証 | dm-signal | 04-26 | シン四神12体(type=standard, compone |
| cmd_2293 | 強化 — 殿の質問に対する確認強制hook(事前ワクチン系譜) | infra | 04-26 | FILL_THIS |
| cmd_2294 | 修正 — dm-signal context §0陳腐化修正+L0/L1/L2定義統一 | dm-signal | 04-26 | FILL_THIS |
| cmd_2295 | 強化 — projects/dm-signal.yaml Vercel圧縮(491→80行) | dm-signal | 04-26 | — |
| cmd_2296 | 強化 — dm-signal context 4ファイルVercel圧縮+500行制限適用 | dm-signal | 04-26 | FILL_THIS |
| cmd_2297 | 偵察 — FE/BE速度改善設計書の現状照合+次Phase特定 | dm-signal | 04-26 | FE設計書(fe-speed-improvement-des |
| cmd_2298 | 偵察 — FE/BE速度改善設計書の現状照合+次Phase特定(Codex独立視点) | dm-signal | 04-26 | FILL_THIS |
| cmd_2299 | 強化 — 将軍弱点2計測hook(因果展開ステップ数+新規vs既存判断) | infra | 04-26 | prompt_state_inject.shへ殿入力回数の自 |
| cmd_2300 | 実装 — Measure C: next-portfolio predictive prefetch(PF切替高速化) | dm-signal | 04-26 | FILL_THIS |
| cmd_karo_ci_fix_375 | CI修正 — batsテスト#375失敗修正 | infra | 04-26 | FILL_THIS |
| cmd_2301 | — | — | 04-26 | — |
| cmd_2304 | 計測 — Measure C効果検証(CDP PF切替時間、1009msベースライン比較) | dm-signal | 04-26 | FILL_THIS |
| cmd_2303 | 配備 — cmd_2300(Measure C prefetch)のpush+Render deploy確認 | dm-signal | 04-26 | cmd_2303_normal: GitHub main と |
| cmd_2306 | 偵察 — Measure A残り(pending_map/folders/portfolio全件/momentum payload)削減箇所特定 | dm-signal | 04-26 | FILL_THIS |
| cmd_2305 | 偵察 — Measure D(full fetch defer)実装箇所特定+波及分析 | dm-signal | 04-26 | dashboard/monthly-returns/annu |
| cmd_2308 | 実装 — Measure D: full fetch idle後ろ倒し(dashboard/monthly/annual 3ページ) | dm-signal | 04-26 | FILL_THIS |
| cmd_2309 | 実装 — Measure A: signals.py pending_map月中スキップ+portfolio lazy load | dm-signal | 04-26 | FILL_THIS |
| cmd_2307 | 偵察 — PF切替1009msフェーズ分解(API fetch vs FE処理の実測内訳) | dm-signal | 04-26 | PF切替1008-1009msをperf_measure定義 |
| cmd_2310 | 改善 — perf_measure.py PF切替計測手法修正(dropdown固定待機520ms排除) | dm-signal | 04-26 | FILL_THIS |
| cmd_2313 | 修正 — Codex config.toml approval_mode=full-auto追加(STALL根絶) | infra | 04-26 | FILL_THIS |
| cmd_2312 | 計測 — Measure D/A効果検証(修正済み計測手法でCDP PF切替再計測) | dm-signal | 04-26 | FILL_THIS |
| cmd_2311 | 配備 — Measure D/A/計測手法修正のpush+Render deploy確認 | dm-signal | 04-26 | cmd_2308/2309はDM-Signal GitHub |
| cmd_karo_ci_fix_357 | CI修正 — batsテスト#357失敗修正 | infra | 04-26 | FILL_THIS |
| cmd_karo_reprofile_freq | インフラスクリプト頻度再計測 — 直近24h | infra | 04-26 | 直近24hのインフラスクリプト頻度を5ソースで再計測し、do |
| cmd_2314 | 偵察 — GS CSV パラメータ→月次リターン列マッピング調査 | dm-signal | 04-26 | summary CSV行i == monthly CSV列i |
| cmd_karo_reprofile_bench | インフラスクリプト実行時間再計測 — Top 20 × 5回 | infra | 04-26 | 前回プロファイリングTop20を5回中央値で再計測し、doc |
| cmd_2315 | 偵察 — GS CSV正規化Phase 0.5: スクリプト130本全量分類+サブディレクトリ最終確定 | dm-signal | 04-27 | cmd_2315 Phase 0.5偵察として、GS関連スク |
| cmd_2316 | 実装 — GS正規化Phase 1: マニフェスト記録 | dm-signal | 04-27 | outputs/gs_backup/20260427_pre |
| cmd_2317 | 実装 — GS正規化Phase 1.5a: gs_db_utils.py(SQLite write/read共通層) | dm-signal | 04-27 | FILL_THIS |
| cmd_2318 | 実装 — GS正規化Phase 1.5b: verify_gs_db.py(CSV-SQLite照合検証) | dm-signal | 04-27 | scripts/analysis/verify_gs_db. |
| cmd_2319 | 実装 — GS正規化Phase 1.5c: gs_db_summary.py(SQLiteサマリ表示) | dm-signal | 04-27 | gs_db_summary.py を新規作成。--db-pa |
| cmd_2320 | 実装 — GS正規化Phase 1.5d: test_gs_db_utils.py(ユニットテスト) | dm-signal | 04-27 | — |
| cmd_2321 | 実装 — GS正規化Phase 1.5d: test_gs_db_utils.py(ユニットテスト) | dm-signal | 04-27 | gs_db_utilsの8関数に対するround-trip単 |
| cmd_2322 | 実装 — GS正規化Phase 2: L0シン bunshin CSV→SQLite変換(4family) | dm-signal | 04-27 | L0/shin bunshin 4familyのCSV→SQ |
| cmd_2323 | 実装 — GS正規化Phase 2: L0シン oikaze CSV→SQLite変換(4family) | dm-signal | 04-27 | cmd_2323 oikaze L0シン4familyをCS |
| cmd_2324 | 実装 — GS正規化Phase 2: L0シン yotsume CSV→SQLite変換(4family) | dm-signal | 04-27 | FILL_THIS |
| cmd_2325 | 実装 — GS正規化Phase 2: L0シン kawarimi CSV→SQLite変換(4family) | dm-signal | 04-27 | FILL_THIS |
| cmd_2326 | 実装 — GS正規化Phase 2: L0シン nukimi CSV→SQLite変換(4family) | dm-signal | 04-27 | FILL_THIS |
| cmd_2327 | 実装 — GS正規化Phase 2: L0シン kasoku_diff CSV→SQLite変換(4family・大規模) | dm-signal | 04-27 | FILL_THIS |
| cmd_2328 | 実装 — GS正規化Phase 2: L0シン kasoku_ratio CSV→SQLite変換(4family・大規模) | dm-signal | 04-27 | — |
| cmd_2329 | 修正 — gs_db_utils.py write_monthly NaN→NULL許容改修 | dm-signal | 04-27 | FILL_THIS |
| cmd_2330 | shin_shijin_l1_gs.pyのシミュレーション精度を現在株価で検証。GS正規化Phase 1.9の前提条件。読取+計算+比較のみ | dm-signal | 04-27 | AC1: shin_shijin_l1_gs.py --pa |
| cmd_2331 | shin_shijin_l1_gs.pyの出力にSQLite直接出力を追加する(道具磨き)。 合わせてPhase 2で生成した汚染.dbとbypass独自スクリプトを清掃する。 Phase 1.9b(フルGS再実行)の前提。道具が正しく動かなければGS再実行は無意味。 | dm-signal | 04-27 | 旧SQLite成果物と変換用一時スクリプト2本を削除し、sh |
| cmd_2332 | shin_shijin_l1_gs.pyの出力パスを設計書§3.1の命名規則に合わせる。 日付バージョニング+layer/method構造+latest symlinkを追加し、GS結果の管理基盤を整備する。 フルGS再実行(cmd_2334)の前提となる道具磨き。 | dm-signal | 04-27 | — |
| cmd_2333 | cmd_1125_v2_champion_select.pyの入力をCSV→SQLite(gs_db_utils.read_*)に変更する。 チャンピオン突合(cmd_2335)の前提となる道具磨き。cmd_2332と並列実行可能。 | dm-signal | 04-27 | cmd_1125_v2_champion_select.py |
| cmd_2334 | shin_shijin_l1_gs.pyで4family(DM2/DM3/DM6/DM7+)のフルGSを最新株価で再実行する。 cmd_2332でOUTPUT_DIRを設計書§3.1準拠に変更済み。設計書準拠パスにSQLite+CSV同時出力。 チャンピオン12体選出(cmd_2335)の前提。 | dm-signal | 04-28 | shin_shijin_l1_gs.pyを--familie |
| cmd_2335 | cmd_2334で生成したフルGS結果(SQLite)からシン四神チャンピオン12体を選出する。 cmd_1125_v2_champion_select.pyで--db-pathを指定しSQLite直読。 DNA制約フィルタ→3モード選出(激攻CAGR/常勝NHF/鉄壁MaxDD)→吸収判定→旧チャンピオンとの差分確認。 | dm-signal | 04-28 | cmd_1125_v2_champion_select.py |
| cmd_2336 | cmd_delegate.sh L180のkaro inbox重複検出がgrep -F "$CMD_ID"で全文検索するため、 軍師のlesson_candidateやbulletin_notify等に含まれるcmd_id文字列にも誤マッチする。 type:cmd_newのエントリのみを検査対象に限定する。 | infra | 04-28 | cmd_delegate.shの家老inbox重複検出をcm |
| cmd_2337 | 本番DBのシン四神12体のconfig(lookback/rebalance/top_n)を取得し、 cmd_2335で選出したGS選出シン四神12体と正確に12体vs12体で突合する。 cmd_2335のスクリプトは旧JSON(吸収後10体)と比較しており、本番DB12体との正しい差分が未確認。 | dm-signal | 04-28 | 本番PostgreSQLのシン四神12体pipeline_c |
| cmd_2338 | gunshi_notifyの重複防止フラグがdraft_reviewとreport_reviewで共有されており、 draft送信済みフラグが存在するとreport_received時のreport_reviewが不発になるバグを修正する。 cmd_2334で実証(家老報告 2026-04-28)。 | infra | 04-28 | draft_reviewの重複防止マーカーをcmd_id.s |
| cmd_2339 | gs_data_loader.pyからCSV読込経路を完全に廃止し、DB直読を唯一のデータ取得経路にする。 殿裁定「CSVをまた作るな。DB直読せよ」の構造的実装。§33 Phase 3の前半。 | dm-signal | 04-28 | gs_data_loader.pyからCSV読込関数を削除し |
| cmd_2340 | gs_data_loader.pyのL1_PORTFOLIO_MAP(L531-547、UUIDハードコード)を廃止し、 universe config(YAML)のcomponentsセクションをUUIDの唯一の供給源にする。 §33 Phase 3の後半。cmd_2339(CSV経路廃止)の完了が前提。 | dm-signal | 04-28 | — |
| cmd_2341 | ninja_monitorでtask正常完了→idle遷移時にSTALL_FIRST_SEEN/STALL_COUNTがクリアされず、 新task配備直後に前taskの停滞時間+回数が持ち越されてESCALATE誤検知が発生する。 cmd_2340/hayateで29秒後に41140秒idle+2回STALLと誤検知された実証あり(家老掲示板報告)。 | infra | 04-28 | ninja_monitorの完了/idle遷移でSTALL_ |
| cmd_2342 | ACに「全テストPASS」「0 failures, 0 skips」等のパターンがあった場合にWARNし、 「変更対象の関連テストPASS(pre-existing failure除外)」へのスコープ限定を促す。 将軍のcmd設計段階で達成不可能なACを防ぎ、忍者FAIL→家老waiveの消火循環を根絶する。 | infra | 04-28 | — |
| cmd_2343 | outputs/analysis/配下のCSVファイルを調査し、GS入力用CSV(削除対象)と研究成果物(保護対象)を選別する。 Phase 3でCSV経路を廃止したが、旧CSV入力ファイルがoutputs/analysis/に残存(軍師確認済み)。 削除対象を特定してPhase 4実行cmdの前提とする。 | dm-signal | 04-28 | outputs/analysis配下CSVは807件・923 |
| cmd_2344 | run_077_*.py 7本のデフォルトuniverse configをalm_l0_12.yaml(source_type:csv)から okugi_shin_ninpo_20.yaml(source_type:db, 20体UUID付き)に変更する。 Phase 3でCSV経路廃止済み→現状のデフォルトで実行するとValueError。DB直読を唯一の経路にする。 | dm-signal | 04-28 | run_077系7本のデフォルト--universeをoku |
| cmd_2345 | cmd_2343偵察で特定した旧GS入力CSV 9件(371KB)を削除する。 Phase 3でCSV経路廃止済み(source_type=csv→ValueError)のため、これらを参照するコードパスは存在しない。 GS再実行(後続A)前にクリーンな状態にする。 | dm-signal | 04-28 | 旧GS入力CSV 9件を /mnt/c/Python_app |
| cmd_2346 | run_077全7本で共通のGS結果SQLite出力モジュールを作成する。 現在のCSV出力関数(write_meta_yaml/append_data_catalog/write_monthly_csv_streaming)を SQLite出力版に置換する共通モジュール。殿裁定「CSVをまた作るな」に従いCSV出力は廃止。 shin_shijin_l1_gs.py L1041-1043のSQLite出力実装が参考。 | dm-signal | 04-28 | completed(将軍現物確認: gs_sqlite_output.py存在確認済み) |
| cmd_2347 | cmd_2346で作成したSQLite出力共通モジュールを使い、run_077全7本のCSV出力をSQLite出力に切替える。 CSV出力関数(to_csv/write_monthly_csv_streaming)の呼出しを共通モジュールのSQLite出力に置換。 殿裁定「CSVをまた作るな」に従いCSV出力コードは削除。 | dm-signal | 04-28 | completed(GATE CLEAR+将軍現物確認: run_077全7本import済み) |
| cmd_2348 | shin_shijin_l1_gs.py L1042-1043のCSV出力2行を削除する。 殿裁定「CSVをまた作るな」に違反する残存コード。 gs_db_utilsはDataFrameを直接受付可能(_as_frame L47-50)のためCSV経由は不要。 cmd_2346がこのファイルを参考実装として使うため、CSV出力を除去してから参考にさせる。 | dm-signal | 04-28 | shin_shijin_l1_gs.pyのGS出力をCSV中 |
| cmd_2349 | gs_sqlite_output.py L56とgs_db_utils.py L50のpd.read_csv(CSV入力フォールバック)をValueErrorに変更する。 殿裁定「CSVをまた作るな」の徹底。DataFrame直接渡しが正規パス。CSV経由の裏口を完全封鎖。 cmd_2346の成果物(gs_sqlite_output.py)は機能するがCSV fallbackが残存→この補足cmdで修正。 | dm-signal | 04-28 | GS SQLite書込み系のCSVパス入力を拒否し、Data |
| cmd_2350 | gs-data-normalization-spec.md Phase 7(近傍分析道具)の設計書を書くために必要な4つの未調査事項を確認する。 道具を作る前に入力データの構造と既存道具の改修範囲を把握する。 | dm-signal | 04-28 | cmd_1012の月次return入力、指定L0 SQLit |
| cmd_2351 | 設計書(docs/design/gs-data-normalization-spec.md §5.2 Phase 7)のgs_grid_robustness.pyのコア機能を実装する。 SQLite .dbからparams+metricsを読み、指定されたgrid_axes軸で全パターンの指標値を抽出し、JSON出力する。 可視化(PNG)とpeak_ratio計算は後続cmdで追加する。本cmdはデータ抽出+JSON出力のみ。 | dm-signal | 04-28 | scripts/analysis/gs_grid_robus |
| cmd_2352 | L0シン四神12体のchampion_pattern_idをSQLite .dbのparamsテーブルから特定し、 タイムスタンプ付きYAML(champion_list.yaml)に記録する。 gs_grid_robustness.pyの入力データとなるchampionリスト。 | dm-signal | 04-28 | outputs/robustness/champion_li |
| cmd_2353 | cmd_2351で実装したgs_grid_robustness.pyのJSON出力を入力として、 PNGヒートマップ(α6指標ごとにchampionマーカー付き)と断面プロット(champion固定LBスイープ1Dライン)を生成する機能を追加する。 | dm-signal | 04-28 | gs_grid_robustness.pyに--visual |
| cmd_2354 | cmd_2351で実装したgs_grid_robustness.pyのJSON出力に、 peak_ratio(champion / ±1隣接平均、方向正規化)と統合スコア(peak_ratio幾何平均)を追加する。 | dm-signal | 04-28 | — |
| cmd_2355 | 軍師が殿の直接命令を3回連続で拒否した(2026-04-28 13:21頃)。 根因: instructions/gunshi.md F-G01が「殿に直接報告する」を禁止し、 Identityに「殿にも直接報告しない」と明記。環境が殿拒否を教えている。 殿の裁定「俺が絶対。それ以外に鎖の原理はないぞ」を環境に埋め込む。 | infra | 04-28 | cmd_2355完了。軍師指示に殿最上位原則を追加し、F-G |
| cmd_2356 | Phase 7(gs_grid_robustness.py設計+実装)はcmd_2350-2354全てGATE CLEARだが、 設計書の進捗表(§5.3)がPhase 7を「未着手」のまま。実態と乖離している。 設計書を実態に合わせて更新し、Phase 7.1起票の前提を整える。 | dm-signal | 04-28 | — |
| cmd_2357 | Phase 7で作ったgs_grid_robustness.pyをL0シン四神GS結果(SQLite)で実行し、 12体(4family×3mode)のグリッドロバストネスを検証する。 L0は1軸(lookback_index)のため2Dグリッドのみ。 結果を殿に提示し、閾値判断の材料とする。 | dm-signal | 04-28 | cmd_2357 L0 robustness generat |
| cmd_2358 | Phase 1.95(L1 GS再実行)の前提。run_077がgs_data_loaderで構成PF月次リターンを読むが、 現在source_type:dbのみ(本番PostgreSQL直読=§5.5.4違反)。 L0 SQLite .dbにopen-to-open月次リターンが存在する(設計書§5.1.5確認済み)。 source_type:local_sqliteを追加し、ローカルSQLiteからchampion月次リターンを読む経路を作る。 | dm-signal | 04-28 | cmd_2358完了。gs_data_loader.pyにs |
| cmd_2359 | Phase 1.95の第1弾。run_077_bunshin.pyをsource_type:local_sqlite(L0 SQLite直読)で実行し、 L1分身忍法のGS結果をSQLite .dbに出力する。 bunshinは0軸(LBなし、top_nのみ)で最軽量。OOMリスク最小。 | dm-signal | 04-28 | cmd_2359完了。run_077_bunshin.pyを |
| cmd_2360 | Phase 1.95の第2弾。run_077_oikaze.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 追い風(MomentumFilter)は1軸LB忍法。bunshin(1/7)GATE CLEAR確認済み。 | dm-signal | 04-28 | cmd_2360完了。run_077_oikaze.pyをs |
| cmd_2361 | Phase 1.95の第3弾。run_077_kawarimi.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 変わり身(TrendReversalFilter)は1軸LB忍法。oikaze(2/7)GATE CLEAR確認済み。 | dm-signal | 04-28 | cmd_2361完了。run_077_kawarimi.py |
| cmd_2362 | Phase 1.95の第4弾。run_077_yotsume.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 四つ目(MultiViewMomentumFilter)は1軸LB忍法。kawarimi(3/7)GATE CLEAR確認済み。 | dm-signal | 04-28 | cmd_2362完了。run_077_yotsume.pyを |
| cmd_2363 | Phase 1.95の第5弾。run_077_nukimi.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 抜き身(SingleViewMomentumFilter)は2軸LB忍法(base+skip)。yotsume(4/7)GATE CLEAR確認済み。 2軸忍法の最初。メモリ負荷増大に注意。 | dm-signal | 04-28 | cmd_2363_normal完了。run_077_nuki |
| cmd_2364 | Phase 1.95の第6弾。run_077_kasoku_diff.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 加速D(MomentumAccelerationFilter method=diff)は2軸LB忍法。最大パターン数(119,493pat実績)。 nukimi(5/7)GATE CLEAR確認済み。Peak RSS 1,696MB実績あり。OOM注意。 | dm-signal | 04-28 | cmd_2364_normal完了。run_077_kaso |
| cmd_2365 | Phase 1.95の最終弾。run_077_kasoku_ratio.pyをsource_type:local_sqlite(L0 SQLite直読)で実行。 加速R(MomentumAccelerationFilter method=ratio)は2軸LB忍法。kasoku_diff(6/7)GATE CLEAR確認済み。 これでL1全7忍法GS再実行が完了する。 | dm-signal | 04-28 | cmd_2365_normal完了。run_077_kaso |
| cmd_2366 | Phase 1.95で再実行したL1全7忍法GS結果(ローカルSQLite 7本)からチャンピオンを選出し、 本番DBのシン忍法configと突合する。cmd_2335(L0四神)と同パターン。 L1は7忍法×3モード(激攻CAGR/常勝NHF/鉄壁MaxDD)。吸収判定後の体数がL1の確定体数になる。 | dm-signal | 04-28 | L1 7忍法×3モード=21チャンピオンをrun_077 S |
| cmd_2367 | cmd_2366でL1チャンピオン21体中MATCH 8/MISMATCH 12/未登録1と判明。 殿の問い「L0が同じで構成PFが違うならどう違うのか」に答える分析。 MISMATCH 12体それぞれのGS選出パラメータ vs 本番パラメータを並べ、 乖離のパターン(component_set/lookback/top_n等)を分類する。 | dm-signal | 04-28 | MISMATCH 12体+未登録1体の詳細比較をMarkdo |
| cmd_2368 | run_077のGSはPydanticバリデーションなしでパラメータグリッドを生成している。 GS選出チャンピオン21体のconfigを本番ビルディングブロック(MomentumFilter等)に通し、 バリデーションエラーで弾かれるパターンがないか検証する。 本番バリデーション下でGS結果と現行本番configが同一になるか確認する。 | dm-signal | 04-28 | cmd_2366選出21体を本番Pydantic入口(Pip |
| cmd_2369 | 殿の仮説: 本番シン忍法はWF-α(Walk-Forward OOS alpha)で選出された可能性。 今回のGS結果(cmd_2359-2365 SQLite)からWF-α方式でチャンピオンを選出し、 (1)事後選出(cmd_2366)との差異、(2)本番configとの一致率を比較する。 WF-α-CAGR=激攻、WF-α-NHF=常勝、WF-α-MaxDD=鉄壁。 | dm-signal | 04-28 | cmd_2369: 7忍法run_077 SQLite DB |
| cmd_2370 | cmd_1902のα6指標手法(alpha_t = return_t - beta * spy_return_t)を使い、 本番シン忍法20体と事後GS選出21体のβ調整α6指標を算出・比較する。 本番L1の月次リターンは本番DB(FoFパイプライン計算済み)から読取。 事後GS L1の月次リターンはrun_077 GS SQLiteから読取。 | dm-signal | 04-28 | 本番シン忍法20体とcmd_2366 L1事後GS21体につ |
| cmd_2372 | 本番シン忍法20体と事後GS選出21体のWF β調整α6指標を算出・比較する。 第4の試練: IS=24M、OOS=6M、step=3M、20ステップ。各ステップでβを再推定し、 OOS窓でα6指標(alpha-CAGR/NHF/MaxDD/MRU/Calmar/UWP)を計算。 20個の独立OOS結果を連結して最終α6を算出。 | dm-signal | 04-28 | cmd_2372: 本番シン忍法20体と事後GS21体のSP |
| cmd_2373 | cmd_2366のチャンピオン選出スクリプトが忍法×モードごとに正しい目的関数で選出しているか検証する。 疑い: (1)鉄壁のMaxDD最小化で符号が逆転していないか (2)異なる忍法で同一パターンが選ばれる原因 (3)常勝3忍法のMaxDD完全一致(-0.3371)の原因特定。 | dm-signal | 04-29 | cmd_2366 L1チャンピオン選出ロジックを監査し、選出 |
| cmd_2374 | 本番シン忍法20体のconfigパラメータ(component_set+lookback+top_n)でGS SQLiteを検索し、 該当パターンの月次リターンと本番DBのmonthly_returnsが一致するか検証する。 本番configがGS空間内に存在すること自体の確認+リターンパリティ。 | dm-signal | 04-29 | 本番シン忍法20体の同一パラメータpattern_idをGS |
| cmd_2375 | cmd_2374で発見した「L1パリティ0/20 FAIL」の原因がmonthly_return(close) vs monthly_return_open(open)の列取り違えかを確認する。 本番DB側をmonthly_return_openに揃えて再突合し、GS L1にバグがあるか白黒つける。 | dm-signal | 04-29 | cmd_2375としてcmd_2374ベースのmonthly |
| cmd_2376 | cmd_2375で判明した「選択ブロック忍法17体のL1パリティ不一致」の原因を特定する。 追い風-激攻(oikaze)の不一致月を1つ取り、本番PipelineEngine(MomentumFilterBlock)と GS simulate_pattern()がその月にどのL0四神を選択したかを比較し、差分の根因を特定する。 | dm-signal | 04-29 | 追い風-激攻 oikaze_N4_0569_18M_N1_R |
| cmd_2377 | cmd_2375で17/20不一致だった原因を特定する。cmd_2376は1ヶ月1体しか確認せず大差月を見逃した。 全20体×共通期間のみでmonthly_return_open突合し、共通期間内にvalue_diffがある月について 本番holding_signal(保有PF) vs GS simulate_patternの選択結果を比較する。 | dm-signal | 04-29 | cmd_2377: シン忍法20体のmonthly_retu |
| cmd_2378 | 追い風(oikaze)のsimulate_pattern()を本番MomentumFilterBlockと完全一致するよう修正する。 ラルフループ: コード読み比べ→差分特定→修正→パリティ検証→不一致あれば再修正→100%達成まで。 追い風3体(激攻/常勝/鉄壁)の本番monthly_return_openと完全一致(1e-6以内)が完了条件。 | dm-signal | 04-29 | run_077_oikaze.pyのNumPy快速版を検証し |
| cmd_2382 | cmd_2378の3修正を四つ目に適用。修正版で全パターン計算→新SQLite生成→本番一致100%検証→旧SQLite削除。 | dm-signal | 04-29 | cmd_2382: run_077_yotsume.pyへc |
| cmd_2381 | cmd_2378の3修正(close累積momentum/全履歴shift/初回signal等ウェイト)を変わり身に適用。 修正版で全パターン計算→新SQLite生成→本番monthly_return_openと100%一致検証→旧SQLite削除。 | dm-signal | 04-29 | 変わり身run_077にcmd_2378の3修正（produ |
| cmd_2383 | cmd_2378の3修正を抜き身に適用。修正版で全パターン計算→新SQLite生成→本番一致100%検証→旧SQLite削除。 | dm-signal | 04-29 | run_077_nukimi.pyにcmd_2378の3修正 |
| cmd_2384 | cmd_2378の3修正を加速Dに適用。修正版で全パターン計算→新SQLite生成→本番一致100%検証→旧SQLite削除。 | dm-signal | 04-29 | run_077_kasoku_diff.pyにcmd_237 |
| cmd_2386 | Phase 1.96でrun_077全7忍法のsimulate_pattern修正完了(cmd_2378-2385)。修正版SQLiteでL1チャンピオン再選出し本番シン忍法configと突合する。cmd_2366の再実行。修正前SQLiteで選出したチャンピオンは無効。 | dm-signal | 04-29 | cmd_2366_l1_champion_select.py |
| cmd_2387 | cmd_save.sh L2861のcheck_parity_ac_requirementsがtitle/purposeの文脈を見ず語句マッチのみで判定するため、分析cmdでFP発火する(cmd_2386で実証。startup gateでもFP率ALERT)。過去形コンテキスト(修正後/修正版/修正済み/完了)を除外し本番DB変更cmdのみトリガーさせる。 | infra | 04-29 | Check 19 _CHECK19_TRIGGERに過去形除 |
| cmd_2388 | lessons_shogun.yaml 35件(上限35件)到達で新教訓記録不可。成長ループが断絶。LS023-LS035の13件を既存クラスタに吸収し空きを確保する。v1→v3統合(97→22件)と同パターン。 | infra | 04-29 | lessons_shogun.yaml: LS023-LS0 |
| cmd_2389 | check_ac_phase_mixing(L3033)のFP率66%(3件中2件FP、startup gate ALERT)。impl_hitsのキーワード(修正/変更/追加等)が殆どのcmdにマッチし、ACに計測/commit語が偶然含まれると誤発火。AC単位の文脈判定を追加しFPを削減する。 | infra | 04-29 | check_ac_phase_mixingにAC単位文脈判定 |
| cmd_2391 | cmd_2386で再選出したGS事後最適チャンピオン21体のうちbunshin(0軸)を除く6忍法×3モード=18体について、gs_grid_robustness.pyでLB×α6グリッドを生成し、championの面的頑健性を検証する。過適合リスクの定量評価。cmd_2357(L0 12体)と同パターン。 | dm-signal | 04-29 | 6忍法×3モード=18体のL1 GS robustnessを |
| cmd_2392 | cmd_2386で再選出したGS事後最適21体を本番DBにhide状態で登録する。既存シン忍法20体は維持。フォルダ「GSシン忍法」を新規作成し、名前は「GSシン{忍法名}-{モード}」(例: GSシン抜き身-鉄壁)。登録後fullrecalculate→パリティ検証。 | dm-signal | 04-29 | GSシン忍法フォルダーを作成し、cmd_2386 GSチャン |
| cmd_2393 | GSL1 SQLite 7本が設計書§3.1の命名ルール(outputs/grid_search/{YYYYMMDD}/{layer}/{method}/gs_{ninjutsu}.db)に従っていない。cmd番号付き命名やファイル名揺れ(_results_fast/_grid_results_fast)を正規化する。GSL2実行前に入力元パスを確定させる。 | dm-signal | 04-29 | GSL1 SQLite 7本を outputs/grid_s |
| cmd_2394 | GSL2 GS実行の前提。GSシン忍法21体のUUID+source_type:local_sqlite+GSL1 SQLite正規パスを含むuniverse YAMLを作成する。okugi_shin_ninpo_20.yamlをベースに差し替え。 | dm-signal | 04-29 | GSL2用のGSシン忍法21体 universe YAMLを |
| cmd_2396 | 軍師がkasoku_diffに適用したOOMkill対策(commit 40d40e55: monthly_wide_frame除去+numpy直接SQLite書込み)を残6忍法に横展開。各run_077の_run_mp()内のmonthly_wide_frame()呼出し除去+main関数のwrite_grid_search_sqlite呼出しをnumpy配列パスに変更。1忍法あたり変更2箇所。 | dm-signal | 04-29 | run_077残6本(bunshin/oikaze/kawa |
| cmd_2397 | 殿指摘: GS SQLite方式の実行速度が遅すぎる。CSV時代より遅い。高速化必須。 現状: L2 kasoku_diff(~1.15Mpat)が56分以上かかりまだ完了しない。DB 18GB。 根因: gs_sqlite_output.py/gs_db_utils.pyにPRAGMA設定がゼロ。SQLiteデフォルト(journal_mode=DELETE, synchronous=FULL, cache_size=2MB)のまま~190M行のmonthly書込み。加えてWSL2 /mnt/c cross-filesystem書込みペナルティ。 対策: (1)PRAGMA最適化(journal_mode=OFF, synchronous=OFF, cache_size拡大) (2)Linux-native一時ファイル書込み+完了後/mnt/cへmove (3)CREATE INDEX AFTER INSERT (4)before/after計測で効果確認。 | dm-signal | 04-29 | GS SQLite書込み高速化完了: PRAGMA+blob |
| cmd_2400 | 本セッションで発見した2件のインフラバグを修正。 (1)ninja_monitor再起動時にsingletonロックが残存し新インスタンス起動不能(4回連続SINGLETON-EXIT)。 根因: AUTO-RESTART時にold processのflock解放前にnew processが起動するrace condition。 (2)バックグラウンドタスク実行中のCLIをidle判定。hayateが1h08mバックグラウンド実行中なのにsnapshotがidle表示。 根因: プロンプト検出=idle判定だが、codex/claudeのbackgroundモード時はプロンプト表示+裏で実行中。 | infra | 04-29 | ninja_monitorのbackground/Worki |
| cmd_2401 | 殿裁定(2026-04-29): kagemaru=low, hayate/saizo=medium。 settings.yamlのmodel_nameが実態と乖離(hayate/saizo=gpt-5.5-highのまま)。 kagemaruにmodel: sonnet残骸あり。実態に合わせて更新し、 全Codex忍者のeffort実態をcapture-paneで確認する。 | infra | 04-29 | config/settings.yamlを指定どおり更新し、 |
| cmd_2402 | cmd_2399(MP_WORKERS=6)がOOM Killで失敗。軍師自己分析: fork×6のRSS累積が16GB超。 MP_WORKERS=1で安全に再実行する。前回L2実績(cmd_1844: 944Kpat直列OOMなし)が安全実績。 高速化commit(PRAGMA+blob+Linux-native)は有効なままなのでSQLite書込みは高速。 | dm-signal | 04-29 | cmd_2402再実行完了。GS_MP_WORKERS=1 |
| cmd_2403 | 将軍のinbox_watcherがASW_DISABLE_ESCALATION=1で起動されており、nudgeが届かない。 殿が2.5時間不在の間にinbox7件蓄積→気づかず。殿裁定: バグとして修正。 ninja_monitor.sh L2285-2288とdaemon_watchdog.sh L175-178のshogun分岐を削除し、 全エージェント共通の起動パスに統一する。修正後にwatcher再起動で即反映。 | infra | 04-29 | ninja_monitor.sh と daemon_watc |
| cmd_2399 | 高速化版(c563ec23+b5a009ef)でGSL2 kasoku_diffを再実行。 旧版: 60min超+21GB DB+OOMkill。新版: 見込み26-59sec+1.4GB DB。 旧DBは削除済み。L2/shin/ディレクトリ空。ゼロからの再実行。 | dm-signal | 04-29 | — |
| cmd_2405 | GSL2残6忍法の第1弾。bunshinは0軸(LBなし、top_nのみ)で最軽量。 kasoku_diff実績(1.15Mpat, 543sec, RSS 10.1GB)よりパターン数が少なく安全。 SHMリーク修正(commit 48356b69)適用済み。 | dm-signal | 04-29 | GSL2 shin 21体universeでrun_077_ |
| cmd_2406 | 「1本ずつ昇格→委任→次」が意志依存のまま。cmd_save.shにdraft複数BLOCKはあるが、 Edit toolでのpending昇格時に既存pending cmdの存在チェックがない。 pre-write-edit-combined.shにshogun_to_karo.yaml status:pending書き込み時の 既存pending検出BLOCKを追加し、自動化×強制で1CMD1ゲートを保証する。 | infra | 04-29 | — |
| cmd_2410 | GSL2残2忍法の第5弾。nukimi(抜き身)は2軸LB忍法(SingleViewMomentumFilter、base+skip)。 2軸忍法はパターン数が多い。kasoku_diff(2軸、1.15Mpat)実績で安全確認済み。 | dm-signal | 04-29 | run_077_nukimi.py (抜き身L2 GS) を |
| cmd_2411 | GSL2最終弾。kasoku_ratio(加速R)は2軸LB忍法(MomentumAccelerationFilter method=ratio)。 kasoku_diff(同フィルタ method=diff)と同パターン数。全7忍法完了でL2チャンピオン選出に進める。 | dm-signal | 04-29 | run_077_kasoku_ratio.py GSL2実行 |
| cmd_2412 | GSL2全7忍法GS完走(cmd_2402-2411)。L2 SQLite 7本からチャンピオンを選出する。 cmd_2366(L1チャンピオン選出)と同パターン。cmd_2366_l1_champion_select.pyをL2用に実行。 7忍法×3モード(激攻CAGR/常勝NHF/鉄壁MaxDD)。吸収判定後の体数がL2の確定体数になる。 | dm-signal | 04-29 | L2 SQLite 7本から7忍法×3モード=21チャンピオ |
| cmd_2413 | cmd_2412で選出したL2チャンピオン21体のうちbunshin(0軸)を除く6忍法×3モード=18体について、 gs_grid_robustness.pyでLB×α6グリッドを生成し、championの面的頑健性を検証する。 cmd_2391(L1 robustness)と同パターン。過適合リスクの定量評価。 | dm-signal | 04-29 | L2 SQLite 6本(bunshin除く)で18体のLB |
| cmd_2414 | robustness-verification-catalog §0アルファ空間原則: ロバストネスの第一指標=パラメータ空間全体のCAGR正率。 cmd_2413はpeak_ratio(隣接±1比)のみ。全パターンのα-CAGR正率を未計算。 L2 SQLite 7本の全パターンについてβ調整α-CAGRを計算し、正率を忍法×モード別に報告する。 殿指摘: 「いつもは全探索でやっていなかったか？」 | dm-signal | 04-29 | L2 SQLite 7本の全パターンについてβ調整alpha |
| cmd_2415 | 設計書§5.3の進捗表がPhase 10=★次★のまま。実態: Phase 10-12全完了+SHM修正。 進捗表を実態に合わせて更新し、次Phase(13: 本番DB登録+パリティ確認)を追記する。 | dm-signal | 04-29 | docs/design/gs-data-normalizat |
| cmd_2417 | inbox_watcherがWSL2 NTFSのinotify検知後の処理でhangし、nudgeが送信されなくなる。 kagemaru watcher=16:03停止、hayate watcher=17:04停止(家老訂正報告 22:43)。 STALL 3連続の真因。hang検知+自動再起動を追加する。 | infra | 04-29 | inbox_watcher hang検知heartbeat+ |
| cmd_2418 | 軍師LG014(道具を疑え)がLevel 2(ドキュメント=意志依存)のまま。 gate_ninja_workaround_rate.shにcategory集計を追加し、同一category 3件以上→WARN。 軍師レビュー前に自動表示されるため意志依存がゼロになる。 本セッションのrfs binary_checks保護バグ(cmd_2397)はこのgateがあれば事前検出できた。 | infra | 04-29 | gate_ninja_workaround_rate.sh |
| cmd_2421 | cmd_publish.shを実装したが、instructions/shogun.md §cmd起票手順に未反映。 将軍の起票ワークフローを「Edit(draft)→cmd_publish.sh」の2ステップに更新する。 | infra | 04-29 | instructions/shogun.mdのcmd起票手順 |
| cmd_2420 | config.toml共有でhayateがlow(殿裁定medium)。Codex CLIは-c model_reasoning_effort=XXXで 起動時override可能(codex --help確認済み)。cli_profiles.yamlにper-agent launch_argsを追加し、 settings.yamlのmodel_nameからeffort部分を抽出→起動コマンドに-cフラグを付与する。 | infra | 04-29 | cli_launch_cmd()にmodel_nameからe |
| cmd_2416 | cmd_2412で選出したL2チャンピオン21体を本番DBにhide状態で登録する。 cmd_2392(L1 GSシン忍法21体登録)と同パターン。 フォルダー「GSシン奥義」を新規作成。名前は「奥義-GS-{忍法名}-{モード}」(例: 奥義-GS-加速R-常勝)。 登録後fullrecalculate→L2 GS SQLiteとのパリティ検証。 | dm-signal | 04-30 | — |
| cmd_2419 | commit 48356b69のSHM修正(workers<=1でUSE_SHM=False + Phase 0.5 psm_*自動清掃)が kasoku_diffのrun_077にのみ適用。残6忍法(bunshin/oikaze/kawarimi/yotsume/nukimi/kasoku_ratio)に横展開する。 cmd_2396(OOMkill対策横展開)と同パターン。 | dm-signal | 04-30 | commit 48356b69のSHMリーク対策をrun_0 |
| cmd_2422 | cmd_2412で選出したL2チャンピオン21体のうち分身3体でtop_n>2(subset_size=4等)が 本番Pydanticスキーマ(top_n: le=2)に違反しPortfolioRepository.load()全PFロード失敗を引き起こした。 L2 GS SQLite 7本からsubset_size<=2のパターンのみでチャンピオンを再選出する。 cmd_2368(L1 Pydanticバリデーション検証)と同パターン。 | dm-signal | 04-30 | cmd_2422: L2 SQLite 7本をsubset_ |
| cmd_2423 | PortfolioRepository.load()で1体のPydanticバリデーション失敗が全PFロード失敗を引き起こす構造的欠陥を修正。 cmd_2416事故(top_n=4→全168体API消失)の再発防止。 L1: API応答にskipped情報を含める(サイレント禁止)。L2: logger.errorでBEログ記録。Render内完結。 | dm-signal | 04-30 | PFロード時に個別PFのバリデーション失敗をskippedと |
| cmd_2425 | workers=1固定運用(LG025 OOM防止)+gs-runbook.md結論(fork CoWで十分)により run_077の6忍法スクリプトのSHMコードは全てデッドコード。削除してコードを簡潔にする。 cmd_1037(PPE実験スクリプト)は実験記録として保存(軍師推奨)。 | dm-signal | 04-30 | run_077の6忍法からSHM専用経路を削除し、legac |
| cmd_2424 | cmd_2422で再選出した制約内(top_n<=2)L2チャンピオンを本番DBに登録する。 cmd_2416(Phase 13)の再実行。cmd_2423(耐障害化)が本番に入った状態で安全に実行。 | dm-signal | 04-30 | cmd_2422 constrained L2 champi |
| cmd_2426 | Wood, Roberts, Zohren (2023) "X-Trend: Few-Shot Learning for Trend Following"(arXiv:2310.10500)を 原論文精読し、金融ML知識辞書methods/エントリを作成する。 DMS-TVP(M31)の競合手法。Few-Shot+CPDでレジーム転換対応。2018-2023激動期でTSMOM比10倍リターン。 | dm-signal | 04-30 | arXiv:2310.10500v2をTeX sourceま |
| cmd_2429 | Ong & Herremans (2024) "DeepUnifiedMom: Unified Deep Learning for Multi-Task Momentum"(arXiv:2406.08742)を 原論文精読し、金融ML知識辞書methods/エントリを作成する。 Multi-Gate Mixture of ExpertsでFast/Mid/Slowモメンタムを統合。DMS-TVPの「1モデル選択」より柔軟な混合。 | dm-signal | 04-30 | arXiv:2406.08742 DeepUnifiedMo |
| cmd_2431 | Keller & Keuning "Vigilant Asset Allocation(VAA)" (SSRN 2017) + "Bold Asset Allocation(BAA)" (SSRN 2022)を 原論文精読し知識辞書エントリ作成。複合Momentum Score(1/3/6/12M加重)で毎月ベスト1資産に全額投資。 DM-Signalのレイヤー別Top-1選出に直接適用可能な手法。 | dm-signal | 04-30 | VAA(SSRN:3002624)+BAA(SSRN:416 |
| cmd_2432 | Ehsani & Linnainmaa (2022) "Factor Momentum and the Momentum Factor" (J. Finance, Vol.77(3), pp.1877-1919)を原論文精読し知識辞書エントリ作成。 51ファクターのリターンに時系列autocorrelationを発見。先月リターン基準のファクターローテーション。α=32bps/月。 | dm-signal | 04-30 | NBER WP25551 / Journal of Fina |
| cmd_2433 | "Improving Portfolio Optimization Results with Bandit Networks" (arXiv:2410.04217, 2024)を 原論文精読し知識辞書エントリ作成。Adaptive Discounted Thompson Sampling(ADTS)+Combinatorial ADTS(CADTS)。 非定常報酬分布に対応するsliding window+割引機構。regret bound証明付き。 | dm-signal | 04-30 | ADTS/CADTS原論文(arXiv:2410.04217 |
| cmd_2434 | "Weak Aggregating Specialist Algorithm" (Computational Economics, 2023)を 原論文精読し知識辞書エントリ作成。各戦略を「エキスパート」としてweight更新。 理論的regret bound証明付き。Online Portfolio Selection分野の手法。 | dm-signal | 04-30 | WASA(Weak Aggregating Speciali |
| cmd_2435 | DMS-TVPビルディングブロック設計の前提。本番で選択可能な14種lookback(10D-24M)から 5帯域(超短期/短期/中期/長期/超長期)の最適lookbackを計算で決定する。 L0/L1/L2 GS SQLiteの全パターンでlookback別CAGR/Sharpe分布を集計し、 5帯域に自然な境界を発見→各帯域の最適値を特定。 | dm-signal | 04-30 | GS SQLite全レイヤーから単一lookback 18種 |
| cmd_2436 | DMS-TVP設計書(dm-signal/dms-tvp-layer-selection-design.md)のPhase 1-2。 Levy & Lopes (2021)のDMS-TVP分類器を忠実実装し、L0四神12体の月次リターンデータで 5lookback[10D,21D,84D,210D,315D]の動的選択を実行。固定lookbackとのCAGR/MaxDD比較。 | dm-signal | 04-30 | DMS-TVP L0四神12体バックテストを実装・実行し、指 |
| cmd_2437 | cmd_2436は各PF個別にlookback選択するバックテストだったが、殿の目的は 「L0の12体の中から毎月1体を選び毎月リバランス」。設計書§2.1修正済み。 12体を「モデル」と見なし、各PFの月次リターン符号をベイズ更新で逐次学習し、 argmax πで来月保有する1体を毎月選出。固定EW(等配分12体)との比較。 | dm-signal | 04-30 | DMSでL0四神12体を12モデルとして扱い、monthly |
| cmd_2438 | cmd_2437でα=0.99の切替が110ヶ月中3回と少なすぎ、EW等配分に劣後した。 根因: α=0.99の忘却が遅すぎて実質固定保有。αを下げて反応速度を上げる。 α={0.90,0.95,0.99}×λ={0.95,0.99}の6組合せでグリッド検証し最適αを特定。 | dm-signal | 04-30 | DMS L0 α/λ感度分析を実装・実行し、6組合せのCAG |
| cmd_2439 | Aveシリーズ(激攻/常勝/鉄壁)3体からDMS argmaxで毎月1体選出。 K=3(7モデル)でcmd_2437/2438の12体選出(K=12)より収束が速い。 lookback候補2セットで比較: (A)設計書[10D,21D,84D,210D,315D] (B)原論文[21D,42D,84D,126D,168D,252D]。 3レイヤー(L0/L1/L2)×2セット=6条件。α=0.90,λ=0.95(cmd_2438最善)固定。 | dm-signal | 04-30 | 本番PostgreSQL monthly_return_op |
| cmd_2440 | 設計書v1.0に基づき、任意PF群からN体EW全組み合わせを網羅探索する汎用スクリプトを実装する。 初回実行として奥義-GS-21体(2体210通り+3体1,330通り=1,540通り)を4検証手法×7指標+レジーム分析で評価。 単体より強い組み合わせを発見する。再利用可能な道具として設計(入力PF差替えで繰り返し実行可能)。 | dm-signal | 04-30 | combo_exhaustive_search.pyを新規実 |
| cmd_2441 | cmd_2440で実装したcombo_exhaustive_search.pyを四神12体に適用。 12C2=66通り+12C3=220通り=286通りを4検証手法×7指標+レジーム分析で評価。 奥義-GS-21体の結果(α-Calmar 7.58)と比較し、レイヤー間の効果を定量化する。 | dm-signal | 04-30 | シン四神12体をDBからCSVソース化し、combo_exh |

## 2026-05

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_2442 | combo_exhaustive_search.py L95のdropna(how="any")が全PFデータを最短PFの期間に切り詰めている。 単体パフォーマンスが本番DBと乖離(抜き身-激攻: 本番CAGR 100.6% vs 出力120.8%、20pp乖離)。 修正: 単体は各PFの全期間で計算、EW組み合わせは構成PF共通期間で計算。 修正後に奥義-GS-21体+四神12体を再実行し、gist記事2本を更新する。 | dm-signal | 05-01 | combo_exhaustive_search.pyの単体評 |
| cmd_2443 | 各忍法(7本)のpipeline_configで本番バリデーションが受け入れるtop_nの有効範囲を特定する。 FoF登録時にtop_n=1,2,3,4のどこまでvalidateが通るかを忍法毎に確認する。 | dm-signal | 05-02 | 7忍法×top_n(1,2,3,4)のpipeline_co |
| cmd_2444 | cmd_2416事故で奥義-GS-登録時にPydantic top_n le=2違反が発生した。 SSS奥義は4コンポーネントで問題なく稼働(top_n=1)。 登録スクリプトがGSのsubset_sizeをPortfolio直下top_nに誤入力した可能性を確認する。 | dm-signal | 05-02 | subset_size/top_nがPortfolio直下t |
| cmd_2447 | cmd_2412で選出した制約なしGSL2チャンピオン21体を本番DBに登録する。 旧奥義-GS-(一律subset_size=2)は将軍が削除済み。 cmd_2424の修正版スクリプト(top_n=1固定)で登録。hide=true。 フォルダー「GSシン奥義」を新規作成。命名: 奥義-GS-{忍法名}-{モード}。 | dm-signal | 05-02 | cmd_2412制約なしL2チャンピオン21体を本番DBへ奥 |
| cmd_2448 | cmd_2447でAC4 P1 FAIL: holding_signal vs GS SQLite 54行不一致(変わり身51+他3)。 パリティ不一致は論外。原因特定+修正+P1再検証で不一致0行を達成する。 | dm-signal | 05-02 | cmd_2447 P1 holding_signal vs |
| cmd_2449 | cmd_2447+2448で制約なし奥義-GS-21体の本番登録+パリティ完全一致を達成。 この新21体でEW3全1,330通りを網羅探索し、WF-β調整後の4指標Top1を秘奥義-GS-候補として選出する。 gist記事(note_gs_okugi_exhaustive)の手法を制約なし21体で再実行。 | dm-signal | 05-02 | cmd_2449: 奥義-GS 21体のEW3網羅探索を完了 |
| cmd_2450 | cmd_2449で選出した秘奥義-GS-候補4体(WFα4指標Top1)を秘奥義フォルダーに本番登録する。 旧秘奥義6体は2026-04-25浄化で削除済み。新4体で再構築。 | dm-signal | 05-02 | 秘奥義4体(激攻/常勝/鉄壁/堅守)を本番DBへhide登録 |
| cmd_2451 | FEのMonthly Trade画面で最新のPosition Start行がUUID生表示になっている(殿スクショ確認)。 Dashboard画面では同じPFがticker表示されており、Monthly Trade固有の名前解決ロジックに問題がある。 過去月(04/01以前)はticker表示で正常のため、最新月のみの問題。 | dm-signal | 05-02 | Monthly TradeのFoF pending行でUUI |
| cmd_2452 | Standard PFの5月holding_signalは4月から変化(11/56体)しているが、 FoFの15体(GSシン系)が5月も4月と同一のholding_signal。 Phase 4.1はstandard PFのみ対象(L2442)。FoFのsignal再計算パス(sync-fof/recalculate_fof)が 5月に対して正しく動作していない根因を特定する。 | dm-signal | 05-02 | FoF L3生成パスは正常稼働。2026-05-01 01: |
| cmd_2453 | cmd_2452偵察で判明: FoFのholding_signal(構成PF UUID列)は正常だが、 Monthly Trade画面とDashboard画面のFoF保有ポジション表示が5月分の下層ticker展開を参照していない。 両画面で5月のprecomputed display_ticker_weightsを正しく参照するよう修正する。 | dm-signal | 05-02 | FoF表示のprecomputed ticker weigh |
| cmd_2454 | GSL1(21体)とGSL2(21体)の全42体が理論最長期間より1-26ヶ月短い。 120ヶ月=10年のハードリミットが入っている疑い。 recalculate_fof.pyまたはFoF signal生成ロジックで120ヶ月制限をかけている箇所を特定する。 | dm-signal | 05-02 | FoF期間短縮の主因候補を特定。120ヶ月は再計算ではなくM |
| cmd_2455 | signalsテーブルのUPSERTでupdated_atが記録されず、holding_signalの変更履歴が追えない。 コード修正で過去の保有シグナルが変わったかを事後検証できない問題を解決する。 殿指示: 「いつ何から何に変わったかは追えた方がいい」(2026-05-02)。 | dm-signal | 05-02 | signals/fof_component_weights |
| cmd_2456 | 将軍がBLOCKされた後に教訓を記録せずに次のcmdを起票するパターンが直近50cmdで6回発生。 現行はWARN→累計昇格BLOCKだが、累計までの間に教訓なしcmdが量産される。 初回からBLOCKにして教訓サイクルの断絶を構造的に防止する。殿指示「将軍のCMD起票能力を成長させよう」(2026-05-02)。 | infra | 05-02 | 前cmd BLOCK後の教訓未記録チェックをWARNから即B |
| cmd_2460 | 30スキル中15件が「覚えていれば使う」=意志依存で/clearで消える。 既存の自動トリガー(hook/gate/inbox_watcher)にスキル発動催促を接続し、 使うべきタイミングで自動的にスキル名が提示される仕組みを構築する。 殿指示「スキルはいつ使うかを設定するのが大事」+「自動発動の仕組みに接続せよ」(2026-05-02)。 | infra | 05-02 | スキル自動発動トリガーをcmd_complete_gate/ |
| cmd_2459 | Gate/Hookで集めたデータがスキルに自動還流する基盤を構築する。 現状30スキルは静的手順書で成長しない。Gate=データ収集、スキル=環境整備のサイクルを接続し、 全スキルに共通の学習ループを1つの基盤で実現する。 殿指示「スキル自体が成長する仕組みがないと消火作業になる。Gateはデータ集め、環境を整えることが真の目的」(2026-05-02)。 | infra | 05-02 | スキル実行ログ、Gate FAIL→スキル注意ポイント還流、 |
| cmd_2461 | CLAUDE.mdを正本としAGENTS.mdをsed自動変換で生成。fork元のbuild_instructions.shパターン適用。 手動同期の意志依存を排除しCLI切替時の不整合をゼロにする。 | infra | 05-02 | cmd_2461は既存実装でAC充足。build_instr |
| cmd_2462 | instructions/*.mdの共通部分をcommon/に、CLI固有部分をcli_specific/に分離。 build_instructions.shで自動合成。1箇所修正で全ロール×全CLI反映。fork元パターン適用。 | infra | 05-02 | instructions 3層分離とbuild生成経路を現物 |
| cmd_2466 | lib/cli_adapter.shにget_model_display_name関数を追加し、各エージェントのモデル表示名を profile SSOT(cli_profiles.yaml)から取得できるようにする。 fork元偵察(cmd_2465)で発見したP1学習ポイント。現在tmuxペインのモデル表示(M:GPT等)は ninja_monitor.shが独自ロジックで生成しておりcli_adapterと分離している。 | infra | 05-02 | cli_adapterにget_model_display_ |
| cmd_2469 | skills/skill-creator/SKILL.mdをAnthropic公式ガイド準拠版にアップグレードする。 7項目チェック(目的/TRIGGER/DO NOT TRIGGER/入出力/エラー/テスト可能性/重複)を構造強制し、 frontmatterのargument-hint/user-invocable記入を検証する。 modelフィールドはmulti-CLI原則に反するため非推奨警告(殿裁定2026-05-02)。 | infra | 05-02 | skill-creatorに7項目チェックリストとfront |
| cmd_2470 | 既存37スキルのSKILL.md frontmatterにargument-hintとuser-invocableフィールドを追加する。 fork元偵察(cmd_2465)で発見したP2学習ポイント。現在は引数ヒントがなく、 内部スキル(gate-sync等)もユーザーリストに表示される。 modelフィールドはmulti-CLI原則に反するため追加しない(殿裁定2026-05-02)。 | infra | 05-02 | AC1/AC2範囲でskills/*/SKILL.mdのfr |
| cmd_2471 | Codex CLIにClaude Codeと同じmemory MCPサーバーを接続し、全CLIでMCPが使えるようにする。 現在Codex側は「No MCP servers configured yet」。codex mcp addで接続するだけで解決する。 殿指摘「codexもMCPを利用可能では？」(2026-05-02)。将軍のOpus固定前提を解消する。 | infra | 05-02 | Codex global MCPにmemoryサーバーを追加 |
| cmd_2472 | deploy_task.shが生成する報告テンプレートにassumption_invalidationとbinary_checksの デフォルト値(プレースホルダ構造)を追加する。 gate_fire_logでFAIL TOP2がassumption_invalidation MISSING(389回)+binary_checks MISSING(290回)= 全FAIL765件中679件(89%)。テンプレートに構造が存在しないため忍者が/clear後に記入できない。 | infra | 05-02 | deploy_task生成テンプレートのassumption |
| cmd_2473 | skill_execution_log.shがdashboard-updateスキル実行時にgate_report_formatで判定しているが、 dashboard-updateは報告YAMLを扱わないスキル。判定ゲートの誤接続でFAIL率100%(30/30)。 正しいゲートに接続するか、dashboard-update固有の成功判定に修正する。 | infra | 05-02 | dashboard-updateスキル実行結果をdashbo |
| cmd_2474 | bulletin_notify型メッセージのinbox_mark_read時に、bulletin_board.yamlの該当エントリが 実際にRead toolで読まれたかをPostToolUse hookで検証する。 未読の掲示板エントリがある状態でinbox_mark_readすると警告を出す。 殿指摘「掲示板は確認しているか」(2026-05-02)。将軍がinbox_mark_readを機械的に実行し 掲示板の実質内容を読まない問題を自動化×強制で解消する。 | infra | 05-02 | — |
| cmd_2475 | cmd_publish.shの実行前にBLOCK条件を事前排除するpre-flightチェックを追加する。 現在はcmd_save.shがBLOCK→将軍が手動修正→再試行の事後対処ループ。 事前に(1)教訓空き件数(2)前cmdの教訓記録済みかを検証し、不足なら具体的な解消手順を提示する。 なぜなぜ7回の結論: 事後の教訓自動記録は品質を下げる。事前防止が正しい方向(殿裁定2026-05-02)。 | infra | 05-02 | cmd_publish.sh pre-flightの存在と制 |
| cmd_2476 | lesson_write_shogun.shのenforcementが「既存自動強制」のみの場合BLOCKする。 本セッション教訓6件中5件が消火(既知パターン再発記録)。品質向上ゼロ。 殿指示「品質向上にフォーカス。消火での誤魔化しはないか」(2026-05-02)。 | infra | 05-02 | lesson_write_shogun.shのenforce |
| cmd_2477 | スキル学習ループの消火構造を根本解消する。 軍師なぜなぜ7回の結論: 品質未定義のまま計測装置を作った→計測がゴミを生む→改善にならない。 殿「計測が結果につながらなければならない。因果とは過去と未来につながる」。 テストデータ除外で計測を実態に一致させ、quality_metricで品質を定義し、計測→結果の因果チェーンを接続する。 | infra | 05-02 | AC1完了: skill_execution_log.shで |
| cmd_2478 | 起票前確認hookを意志依存の手動追加から自動成長に変える。 cmd_save.shがWARN累計昇格BLOCKした時にcheck名をファイルに自動記録し、 次回cmd起票時にpre-write-edit-combined.shが動的に表示する。 殿「成長とは次に同じ事をしないこと」を環境に埋め込む。 | infra | 05-02 | preflight_autolearnの動的起票前確認表示を |
| cmd_2479 | CI実行332秒(5.5分)のテストスイートから不要テストを特定する。 殿「テストは負債。3問検証(リグレッション必要性/変更頻度/維持コスト)」。 前回調査(2026-04-15)からは40日経過。スクリプト削除・変更で状況が変わっている。 | infra | 05-02 | tests/unit/*.bats 154件を対象に、対象ス |
| cmd_2480 | CI実行332秒のうちTop 5テスト(120秒超=36%)をCoDD高速化する。 cmd_2479偵察でtimeout 2件(cmd_save_environment_change 32.9s, sync_lessons 32.2s)と 高コスト3件(cmd_save_diagnosis_quality 22.2s, deploy_task_ac_handling 18.0s, deploy_task_ac_version 15.2s)を特定。 CoDD台帳に30件の実績あり(cmd_save.sh -32%、deploy_task.sh -25%等)。同手法を適用。 | infra | 05-02 | AC1/AC3完了。timeoutしていた2本を15s以下へ |
| cmd_2483 | 軍師分析で特定されたインフラバグ3件を修正する。 karo_workarounds 102件中9件(8.8%)がこの3パターンに起因。 放置中もWAが蓄積し家老のトークンを浪費する。idle忍者に即配備。 | infra | 05-02 | AC1: yaml_field_set.shがbinary_ |
| cmd_2486 | skill_gate_feedback.shのスキル特定を名前推測(haystack keyword照合)から skill_execution_log.yamlの実行記録ベースに変更する。誤帰属によるゴミデータを根絶。 | infra | 05-03 | skill_gate_feedback.shのスキル帰属をh |
| cmd_2487 | つまずきパターンからSKILL.mdの手順自体を構造的に更新する変換器を実装する。 caution_points=付箋貼りではなく、手順に具体的防止ステップを自動追加する。 | infra | 05-03 | skill_execution_logのFAIL集計からスキ |
| cmd_2489 | SKILL.mdが参照するスクリプト・パスが変更された時、壊れる前に検知する監査仕組み。 段階0: つまずき記録(段階2)は事後検出。壊れる前の予防的検知が必要。 | infra | 05-03 | SKILL.md内script参照の存在・鮮度を監査するga |
| cmd_2490 | on_holdのcmdをcmd_publish.shに直接入力できるようにする。 現状: on_hold→Edit toolで手動draft変更→cmd_publish.sh。手動変更時にgate未通過で修正機会を逃す。 改善: cmd_publish.shがon_hold入力を受け付け、内部でon_hold→draft昇格→gate検証→pending→delegateの4ステップを実行。 | infra | 05-03 | cmd_publish.shでstatus=on_holdの |
| cmd_2491 | cmd_2490のrollback失敗リスクを根本解消する。 現状: on_hold→draft(YAML書込み)→cmd_save→失敗→rollback(壊れうる)。 改善: YAML書込みをcmd_save成功後に遅延。失敗時はYAML未変更(on_holdのまま)。rollback不要。 | infra | 05-03 | cmd_publish.shのon_hold公開経路を、cm |
| cmd_2492 | 報告YAMLテンプレートの必須フィールド欠落を配備経路に依存せず防止する。 現状: deploy_task.sh経由時のみgenerate_report_template()が走る。karo_direct/task YAML直接編集では未実行→必須4フィールド欠落(cmd_2481 hanzo r3で実証)。 改善: 忍者/clear Recovery Step 4.5でreport_pathのテンプレート検証+欠落フィールド自動補完。 | infra | 05-03 | 既存の不完全な報告テンプレートでも必須4フィールドを自動補完 |
| cmd_2493 | 215本のスクリプト(scripts/144+gates/37+hooks/34)を計測し、最適化ボトルネックを特定する。 台帳(codd_refactor_registry.md)の約100件と突合し、未計測スクリプトと再最適化候補を洗い出す。 | infra | 05-03 | scripts/*.sh 144本を安全なbash -n解析 |
| cmd_2495 | gate_silent_fallback.shがリグレッション(25ms→769ms、31x悪化)。 CoDD正規手順(spec→設計書→実装→計測→台帳記入)で台帳値25ms以下に復帰させる。 | infra | 05-03 | gate_silent_fallback.shの--help |
| cmd_2498 | gate_shogun_memory.shがリグレッション(9ms→82ms、9.1x悪化)。 601行。load_memory_cache()でMEMORY.mdをawk解析+6項目チェック(行数/陳腐化/重複/MCP obs数/curation日/sync鮮度)。 CoDD正規手順で台帳値9ms以下に復帰させる。 | infra | 05-03 | gate_shogun_memory.shをline-cou |
| cmd_2500 | gate_karo_startup.shがリグレッション(110ms→251ms、2.3x悪化)。 592行。前回3回最適化(464→225→190→110ms)。前回revert時に真因特定済み: _META_PIDS awk(deepdiveファイルon /mnt/c NTFS)が~100ms支配。WA rateキャッシュは効果なし(revert)。 CoDD正規手順で110ms以下に復帰。ボトルネックが/mnt/c I/O支配なら代替アプローチ(キャッシュ/遅延読込)をspec段階で設計。 | infra | 05-03 | gate_karo_startup.sh R4 CoDD再改 |
| cmd_2501 | gate_skill_script_refs.shが未最適化で408ms(偵察計測)。台帳未登録。 143行。全体がpython3ヒアドキュメントでSKILL.mdからスクリプト参照を抽出し存在確認+更新日比較。 python3起動コスト+pathlib走査がボトルネック候補。CoDD正規手順で初回最適化。 | infra | 05-03 | gate_skill_script_refs.shに短TTL |
| cmd_2502 | gate_autofix_proposal.shが未最適化で272ms(偵察計測)。台帳未登録。 178行。直近50件のgate_metrics.logからBLOCKパターンを集計し、instructions修正提案をinsights.yamlに還流する。 mktemp+tail+awk+insight_write.sh呼出しがボトルネック候補。CoDD正規手順で初回最適化。 | infra | 05-03 | gate_autofix_proposal.shに短TTL出 |
| cmd_2503 | gate_wa_data_quality.shがリグレッション(52.9ms→111ms、2.1x悪化)。213行。 前回(2026-04-18 hayate): 106.6→52.9ms(-50.4%)。CoDD正規手順で台帳値復帰。 | infra | 05-03 | gate_wa_data_quality.shの通常chec |
| cmd_2506 | gate_skill_health.shが未最適化で139ms(偵察計測)。台帳未登録。241行。 SKILL.mdのTRIGGER/MECE/DRY検証を行うgate。CoDD正規手順で初回最適化。 | infra | 05-03 | gate_skill_health.shの既定skills走 |
| cmd_2505 | gate_field_get.shがリグレッション(40ms→71ms、1.8x悪化)。213行。 前回(2026-04-18 saizo): 404→40ms(-90.1%)。CoDD正規手順で台帳値復帰。 | infra | 05-03 | gate_field_get.sh R2 CoDD再改善を完 |
| cmd_2508 | gateの最適化(cmd_2495-2507)は偵察計測値ベースで進行中。次はhooks+通常スクリプトを対象に、 頻度x実行時間=インパクトの観点で最適化ROI順位を付ける。 cmd_2493のTSVは呼出頻度あるが実行時間がbash -n(構文チェック)で正確でない。実測が必要。 | infra | 05-03 | hooks全34本をmedian 3runで実測し、Clau |
| cmd_2509 | 軍師利他提案: cmd_complete_gate.sh内でlesson_candidate(found:true)をlesson_write.sh自動呼出しで登録。 現状: 軍師LGTM→gate即時発火→家老lesson未登録→BLOCK→手動登録→再GATE(38%=5/13件)。 gate内でlesson_write.shを自動呼出しし、BLOCK→CLEAR往復を構造的に解消する。 | infra | 05-03 | cmd_complete_gateのlesson_candi |
| cmd_2511 | cmd_2508偵察結果: stop_check_inbox.shがインパクト1位(187,739 ms/day)。 未読0件時にinotifywait(5sタイムアウト)で毎回ブロック。inbox_watcher.shが同機能を提供しており冗長。 inotifywait待機ブロックを除去し、全エージェントのStop操作を高速化する。 | infra | 05-03 | stop_check_inbox.shの未読0件inotif |
| cmd_2514 | 家老バグ報告: ninja_monitorが/clear→CLI再起動した直後のCodex CLIは初期画面表示中。 inbox_watcherのpaste-buffer nudgeが空振りし、忍者がプロンプト待ち状態に陥る(5連発実績)。 deploy_task.shにpost-deploy re-nudge(5秒後に再送)を追加し、初期画面通過後にnudgeを確実に届ける。 | infra | 05-03 | — |
| cmd_2515 | cmd_2508偵察結果2位(31,915 ms/day)。Pre/PostToolUse両方で発火(1958回/day)×16.3ms。 tmux set-option 2回(state+timestamp)を1回に統合し、プロセス起動コストを削減する。 | infra | 05-03 | bash_state_hookのtmux state更新がP |
| cmd_2516 | スキル自動成長(段階3)の出力品質が不十分。report-write/verdict-check FAIL率100%が継続。 根因: (1)stumbling_pointsではなくgate名で帰属→防止ステップが的外れ(2)汎用テンプレートで具体性なし。 skill_auto_improve.shの出力テンプレートを改善し、実際のFAILパターンに対する具体的防止手順を生成させる。 | infra | 05-03 | skill FAIL原因から具体的な確認/修正手順をSKIL |
| cmd_2517 | CI全体287s→240s削減の第一段階。cmd_save系slowテスト8ファイル(32.2s)の fixture共有+統合で50%以上短縮する。偵察cmd_2494で特定済みの統合候補: test_cmd_save_ac_test_scope(2.7s), test_cmd_save_block_aggregation(2.1s), test_cmd_save_check19_fp(4.1s), test_cmd_save_command_steps_vs_ac(2.0s), test_cmd_save_diagnose(4.7s), test_cmd_save_diagnosis_quality(6.9s), test_cmd_save_environment_change(4.3s), test_cmd_save_warn_logging(5.5s)。 既存cmd_2480/2481でfixture閉鎖+helper共有の前例あり(70-83%短縮実績)。 | infra | 05-03 | cmd_save系slowテスト8本を32.236sから11 |
| cmd_2519 | CI時間削減の第三段階。偵察cmd_2494で特定済みの残りslow 7ファイル(20.7s)の fixture共有+統合で50%以上短縮する。対象: test_cmd_complete_gate_locking(2tests/2.4s), test_cmd_complete_gate_subsystems(17tests/3.5s), test_gate_report_format_learning(3tests/2.7s), test_gate_skill_script_refs(3tests/2.5s), test_lesson_harvest(3tests/3.0s), test_session_state(8tests/2.5s), test_skill_feedback_loop(11tests/4.2s)。 cmd_2517/2518と並列実施。 | infra | 05-03 | 対象7本のBats合計時間を16.287sから7.567sへ |
| cmd_2518 | CI時間削減の第二段階。deploy_task系slowテスト4ファイル(32.8s)の fixture共有+統合で50%以上短縮する。偵察cmd_2494で特定済みの統合候補: test_deploy_task_ac_handling(26tests/15.4s), test_deploy_task_codd_failure_history(9tests/2.5s), test_deploy_task_lifecycle(41tests/12.0s), test_deploy_task_template_generation(24tests/3.0s)。 cmd_2517(cmd_save系)と並列実施。 | infra | 05-03 | deploy_task系4本の軽量化を試行したが、AC1の5 |
| cmd_2521 | dashboard_update.shはcmd完了ごとに実行(呼出頻度18)で未最適化。 CoDDリファクタリングパイプラインで計測→設計→実装→検証を実施し高速化する。 プロファイリング結果に基づきbash -n 16msから実行時パスのボトルネックを特定する。 | infra | 05-03 | dashboard_update.sh --dry-runを |
| cmd_2522 | context_freshness_check.shはgate内部で頻繁呼出し(呼出頻度44)で未最適化。 gate_context_freshness.shは台帳済み(156ms→62ms)だが、その内部で呼ぶ context_freshness_check.sh自体は未最適化。CoDDで計測→高速化。 | infra | 05-03 | context_freshness_check.shを短TT |
| cmd_2523 | ninja_monitor.shは常駐デーモンで呼出頻度最大(118)、未最適化。 全忍者の状態監視・idle検知・/clear判定・snapshot生成を担う。 CoDDで計測→ボトルネック特定→高速化。 | infra | 05-03 | ninja_monitor.shのループ相当処理を23.84 |
| cmd_2527 | report_field_set.sh L400のyaml.dumpが文字列'yes'/'no'を裸のYAML boolean(true/false) として出力する。autofix_main.py L250-252が毎回bool→str変換で消火中。 根本修正: yaml.dump出力で引用符付き文字列化+消火コード除去。 report-write/verdict-check FAIL率100%の根因(軍師現物確認済み)。 | infra | 05-03 | report_field_setのyes文字列保持とauto |
| cmd_2530 | cmd_complete_gate.sh L1975-1990のfallback globがstale reportを無差別に拾い偽BLOCK。加えてreview_gate.done作成後のgate_metrics CLEAR書込みが保証されていない。再配備時の偽BLOCK根絶+統計精度向上 | infra | 05-03 | cmd_complete_gate lesson track |
| cmd_2529 | archive_completed.shが3パターン(archive.done不在/placeholder/review_gate.done不在)で報告YAMLをSKIPし永久残存させている。169件蓄積=交差汚染(バグ2)の増幅源。負の複利を解消する | infra | 05-03 | archive_completed.shの報告sweepを修 |
| cmd_2533 | サブシェル内のreturn 1は親に伝播しない→flock timeout後もecho synced が無条件実行→chronicle更新失敗が成功として記録される。3箇所(L137,L219,L1437)を修正 | infra | 05-03 | archive_completed.shのchronicle |
| cmd_2532 | auto_unwrap_report_yamlでflock timeout→exit 1→サブシェル内のためunwrap_resultが空文字→case文のどのパターンにもマッチせず完全沈黙。デフォルトパターン追加で空文字をキャッチする | infra | 05-03 | auto_unwrap_report_yamlの空文字/未知 |
| cmd_2537 | L2848のglob展開でMATCHING_TASK_FILESを構築→後続ループ中にdeploy_task.shがタスクYAML追加/archive_completed.shが移動→処理漏れ/不整合。glob結果をスナップショットとして固定し、ループ中の変更に耐性を持たせる | infra | 05-03 | MATCHING_TASK_FILES参照ループへ消失ファイ |
| cmd_2538 | deploy_task.sh L5008-5009でparent_cmd+statusは設定するがtask_idが漏れている。旧cmdのtask_idが残存→cmd_complete_gate.shが旧cmdのreportを参照→交差汚染。1行追加で解消 | infra | 05-03 | direct_mode配備でtask_idが新cmdへ更新さ |
| cmd_2543 | report_field_set.shのverdict書込みとstatus=completed更新を1回のflock内でatomicに実行するようbatch化 | infra | 05-04 | report_field_set.shのverdict確定時 |
| cmd_2545 | archive_overflow_reports_to_capでGATE CLEAR待ち(status=pending)reportがcap超え時に強制archiveされないよう除外チェックを追加 | infra | 05-04 | archive_overflow_reports_to_ca |
| cmd_2547 | L221のinbox_write成功後にwatcher存在チェックがない→watcher未起動時にnudgeが喪失しても沈黙。pgrep確認+WARN出力を追加する | infra | 05-04 | bulletin_write.sh L221(inbox_w |
| cmd_2544 | auto_draft_lesson.sh L215のSOURCE_CMD二重渡し引数修正 + cmd_absorb.sh L243のgrep空変数ガード追加 | infra | 05-04 | auto_draft_lessonの6番目引数空文字仕様とc |
| cmd_2548 | deploy_task.shの2バグ修正。(1)purposeに二重パイプ演算子を含むcmd配備時にyaml_field_set_batch内で値がシェル展開され切り詰まる。(2)count_task_acceptance_criteria失敗時にac_count=0となりdraft_reviewが常にSKIPされ軍師レビューが届かない | infra | 05-04 | cmd_2548のdeploy_task回帰検証を追加。pu |
| cmd_2553 | DM-Signal関連の全知識ファイル(multi-agent-shogun側context/projects + DM-signal側docs/rule/backend)を横断し、同一用語が複数の意味で使われている箇所を全数洗い出す。MECE定義辞書を設計し、1語1意味の構造に向けた改名計画を策定する | dm-signal | 05-04 | DM-Signal多義語全数調査完了。9用語を対象に多層調査 |
| cmd_2554 | cmd_2553第1波(grep中心)で13群の多義衝突を検出したが、同義語や暗黙的参照はgrepで拾えない。第2波はセマンティック検索(LLMがファイルを読み概念単位で分類)を中心に、第1波未カバー領域を網羅する。3名並列で独立調査し結果を突合統合する | dm-signal | 05-04 | MECE辞書第2波調査完了。knowledge-base/r |
| cmd_2556 | CoDD v1.10.0のpropagate機能が「ソースコード変更→設計書追随」方向に設計されているが、我々の用途は「辞書yaml変更→context md追随」方向。frontmatterのmodules指定やカスタム設定で逆方向が可能か、実際にコマンドを試行して確認する | infra | 05-04 | CoDD v1.10.0は辞書YAML→context MD |
| cmd_2557 | 設計書(docs/research/cmd_2555_disambiguation_design.md)の段階0を実装する。P0の4群(L0-L4, signal, monthly_return, date)のdisambiguation.md(SSOT正本+CoDD frontmatter)とdm-signal-terminology.md(エージェント向け索引、80行以内)を作成し、CLAUDE.mdのcontext_filesに追記して起動時自動ロード対象にする | dm-signal | 05-04 | P0 4群の用語曖昧性解消辞書と80行以内の起動時索引を作成 |
| cmd_2560 | cmd_2557-2559で完成した用語辞書(disambiguation.md 全27群+terminology.md索引+context注釈+gate)の整合性をCodexで横断確認する。辞書定義とcontext/BE/FEコードの実際の用語使用が矛盾していないか、辞書に漏れがないか、gate除外条件が適切かをセマンティック検索で検証 | dm-signal | 05-04 | 辞書27ファミリーとterminology索引、contex |
| cmd_2561 | DM-Signal用語辞書(disambiguation.md+terminology.md)がDM-Signalリポに配置されたが、multi-agent-shogun側のCLAUDE.mdとcontext/dm-signal.mdに辞書パスへの参照がなく、将軍/家老/軍師がcmd起票時に辞書の存在を知れない。導線を環境に埋め込む | infra | 05-04 | DM-Signal用語辞書2ファイルへの導線をCLAUDE. |
| cmd_2555 | cmd_2553/2554偵察で特定した27群の多義衝突に対し、(1)用語曖昧性解消辞書(disambiguation dictionary)と(2)生L*検出gate強制の2層設計書を作成する。コードは変更しない。エージェントの知識基盤として埋め込みgate強制で参照を保証する | dm-signal | 05-04 | — |
| cmd_2562 | セマンティクスインデックス設計書(docs/research/semantic_index_design.md)の段階1を実装する。/clear後に概念で情報を逆引きできる仕組みの基盤。10概念のSSOT(index.md)と索引層(semantic-map.md)を作成する | infra | 05-05 | セマンティクスインデックス段階1としてSSOT 10概念とa |
| cmd_2563 | セマンティクスインデックス設計書§8/§7の段階2を実装。aliases照合による第一層検索スクリプト(semantic_search.sh)と、startup gateへのインデックス鮮度チェック追加 | infra | 05-05 | セマンティクスインデックス第一層検索CLIと将軍startu |
| cmd_2564 | セマンティクスインデックス設計書§7の段階3を実装。cmd完了/lesson追加/殿の発言記録時にaliases照合で既存概念にリソースを自動追記するフック。confidence閾値分岐(HIGH→自動/LOW→候補キュー/NONE→新概念候補)を含む | infra | 05-05 | semantic_index_update.shを追加し、c |
| cmd_2566 | セマンティクスインデックス設計書§6/§7の最終段階を実装。index.md変更時のCoDD propagateでsemantic-map.md自動再生成+軍師idleにdrift/gap/candidateスキャンを組込み。段階1-4の全成果物を統合し完成させる | infra | 05-05 | semantic-map deterministic gen |
| cmd_2567 | /clear後の将軍がセマンティクスインデックスの存在を知り使える状態にする。CLAUDE.mdのinfraセクションにsemantic-map.md/semantic_search.shへの参照を追加し、startup手順にsemantic-map.md読込を組込む。用語辞書のcmd_2561(導線埋込み)と同パターン | infra | 05-05 | CLAUDE.mdにsemantic-map.md読込とse |
| cmd_2568 | スキル自動成長ループのFAIL帰属精度が64%誤帰属(21/33件)。cmd_complete_gate.sh L5336-5343のcase文でworkflow系FAIL(missing_gate, lesson_done_missing, draft_lessons)がreport-writeに帰属されている。report-write FAIL率100%の根因。帰属を分離しスキル成長ループの診断精度を回復する | infra | 05-05 | cmd_complete_gateのGATE BLOCK時ス |
| cmd_2569 | Compare chart画面でPF選択するとperfLoading/benchmarkLoadingが全画面Loadingを発火し、UIが全消失して再読み込みされたように見える。殿報告の使いづらさの根因。全画面Loadingは初回signals取得(loading)で発火する設計に変更し、perfLoading/benchmarkLoadingはチャートセクション内のインライン表示に移設する | dm-signal | 05-05 | Compare chartの全画面Loading条件をsig |
| cmd_2570 | DrawdownPeriodのlimit=10問題(UWP設計レビューで殿が発見)と同様に、metrics計算で使われるデータにlimit/サンプリング/切り捨て/丸め等の制限があり実測値と乖離するメトリクスがないか全数調査する。metrics_calculator.py+drawdowns_calculator.py+関連generator全体を対象とする | dm-signal | 05-05 | metrics_calculator.pyのadd_metr |
| cmd_2572 | UWP三指標(UWP MaxDD/Avg UWP/Total UWP)追加に伴い、既存UWPの意味が曖昧になる。disambiguation.mdに3エントリ追加+terminology.md索引追加で1語1意味を維持する。設計書§6に準拠 | dm-signal | 05-05 | UWP三指標の用語曖昧性を解消するため、disambigua |
| cmd_2573 | Avg/Total UWP計算に全DDが必要。drawdowns.py limit=10をNoneに変更し全DD格納。signal_flush.py IN句修正(5c8a9cf2)済みのためfullrecalculateは安全に通る。パリティ検証でsignals/monthly_returnsが不変であることを実証する | dm-signal | 05-05 | drawdowns.py limit=10→None変更(全 |
| cmd_2574 | cmd_2573でDrawdownPeriod全DD格納が完了。metrics_calculator.pyのget_drawdown_stats_from_dbを拡張し、全rankからAvg/Total UWPを集計してmetrics APIレスポンスに2行追加する。既存UWP(rank=1)と同じデータソース+同じ構造で一貫性を維持 | dm-signal | 05-05 | Avg/Total Underwater Periodをme |
| cmd_2575 | cmd_2574でmetrics APIがAvg/Total Underwater Periodを返す状態になった。FEのMetrics/Compare Summary/Termsページに表示を追加し、既存UWPラベルをUWP (MaxDD)に変更してユーザーが3指標を区別できるようにする | dm-signal | 05-05 | FE Metrics/Compare Summary/Ter |
| cmd_2576 | UWP(MaxDD)がNULL(未回復DD)の場合にCompare Summaryで—表示される。未計算/エラー/未回復の区別がつかない(殿指摘)。NULLの場合にOngoing表示にする。既存Metricsページでは既にOngoing表示されておりCompare Summaryだけ不整合 | dm-signal | 05-05 | Compare SummaryのUWP(MaxDD)で未回復 |
| cmd_2578 | Compare SummaryにSPYとTQQQの両方をベンチマーク行として常時表示する(殿指示)。現在はPFのbenchmark_tickerから自動収集(SPYのみ)。TQQQを追加ベンチマークとしてハードコード追加し、SPYと並んで常時表示する。TQQQ株価データは本番pricesテーブルに存在(2010-2026) | dm-signal | 05-05 | Compare Summaryの追加ベンチマークとしてTQQ |
| cmd_2579 | CDPの本質はLLMが人間と同じようにWebブラウザを使えること(殿定義2026-05-05)。ブラウザ起動→ログイン→スクショ→状況確認の一連フローを1コマンドで実行するスキルを作成し全エージェントの基礎能力にする。DM-Signal本番確認、Render Dashboard確認、任意Webサイトの状態確認に汎用的に使える | infra | 05-05 | skills/cdp-browse/SKILL.mdを新規作 |
| cmd_2581 | Total UWPは絶対月数でバックテスト期間に依存し異なる開始日のPF間で比較不能。total_uwp/全期間月数で比率化(PTU: Percentage Time Underwater, 0-100%)しPF間の公平比較を可能にする(殿指示2026-05-05) | dm-signal | 05-05 | PTU(%)をtotal_uwp/monthly_retur |
| cmd_2582 | cmd_2581でPTU計算ロジックをデプロイ済みだがportfolio_metricsキャッシュが旧フォーマット(Total Underwater Period: 110 months)のまま。Compare Summaryは キャッシュ参照のためPTU(%)メトリクスが見つからず空白表示。fullrecalculateでキャッシュ再計算し全PFのPTUを反映する | dm-signal | 05-06 | fullrecalculate(mode=full)を本番で |
| cmd_2584 | test_select.sh(191行)をCoDD refactorで計測→設計→実装→再計測。軍師に事前・事後レビュー必須 | infra | 05-06 | test_select.shのCoDD計測・設計書・afte |
| cmd_2585 | cmd_publish.sh(168行)をCoDD refactorで計測→設計→実装→再計測。軍師に事前・事後レビュー必須 | infra | 05-06 | cmd_publish.sh CoDD refactorを計 |
| cmd_2590 | skill_auto_improve.sh(279行)をCoDD refactorで計測→設計→実装→再計測。軍師に事前・事後レビュー必須 | infra | 05-06 | skill_auto_improve.sh(279→312行 |
| cmd_2588 | cmd_absorb.sh(257行)をCoDD refactorで計測→設計→実装→再計測。軍師に事前・事後レビュー必須 | infra | 05-06 | cmd_absorb.sh(257行)をCoDD refac |
| cmd_2589 | skill_gate_feedback.sh(216行)をCoDD refactorで計測→設計→実装→再計測。軍師に事前・事後レビュー必須 | infra | 05-06 | skill_gate_feedback.sh CoDD re |
| cmd_2592 | skills/cdp-browse/SKILL.mdのgate FAIL(フロントマター<>検出)修正、allowed-tools追加、note.com下書き保存実績の反映、能動的CDP使用の指針追加 | infra | 05-06 | skills/cdp-browse/SKILL.mdのフロン |
| cmd_2593 | auto_draft_lesson.shのskip分岐でlesson.doneを生成しない→cmd_complete_gateがlesson_done_missing BLOCKする循環を解消 | infra | 05-07 | auto_draft_lesson.shのskip時にles |
| cmd_2594 | 忍者がknowledge_candidateを文字列で記入→gate_report_formatがBLOCKするパターンをautofix層で自動変換し、BLOCKを事前解消 | infra | 05-07 | knowledge_candidate文字列をtitle/d |
| cmd_2595 | 家老がcmd-completeスキル実行時にdraft教訓レビューを飛ばす→後続cmdでdraft_lessons BLOCK。スキル手順でlesson_review強制実行し意志依存を排除 | infra | 05-07 | cmd-complete Step 1にlesson_rev |
| cmd_2596 | 全13ページ×vis_L2/vis_L3/vis_L4の3レイヤーでBE/FE各々が何をマスクしているかを現物確認し、MECEマトリクスとして文書化する。FoFのsignal展開(構成ticker分解表示)のマスク挙動も含む | dm-signal | 05-07 | cmd_2596 visibility matrixを作成。 |
| cmd_2597 | 本番FEの全ページをCDPでスクショ取得し、各ページのUI表示要素を網羅的に記録する。コードgrepではなくユーザーが実際に見る画面を真実とし、vis_L3/L4でマスクすべき要素を特定する基礎資料を作成 | dm-signal | 05-07 | 本番FE 14ページをCDPでstandard(DM2)/F |
| cmd_2598 | AddOn tier(L3=OFF/L4=ON)でMonthly Trade position列がticker名でなく***100.0%になるバグを修正。resolveDisplayTextがL4マスク済みexpanded_tickersを参照するのが根因 | dm-signal | 05-07 | L4 component mask時のMonthly Tra |
| cmd_2599 | viewer_tokens 100件上限で新規ログインが他ユーザーのtoken削除→強制ログアウト。MAX上限if分岐を削除し期限切れ削除のみに変更 | dm-signal | 05-07 | viewer/admin token生成時のMAX_TOKE |
| cmd_2601 | note_draft.shが未ログイン時にエラー終了する。reCAPTCHA画像チャレンジを含む自動ログインフローを追加し、全スキル(weekly-report/note-article/sengoku-writer)から完全自動で下書き保存可能にする。併せてタイトル抽出バグ(#h1を無視し最初の##h2を使用)を修正する | infra | 05-07 | note_draft.shに未ログイン時の自動ログイン+re |
| cmd_2604 | スキル自動成長ループの段階3(自動改善)・段階4(品質向上)が未実装。根本原因はskill_execution_logの帰属精度。dashboard-updateがgate_report_formatのFAILを被っている(8/11件)。報告YAML品質はreport-writeスキルの責任であり、dashboard-updateの責任ではない。帰属がずれている限り、stumbling_points→SKILL.md反映は誤った対象に注意ポイントを追加し続ける | infra | 05-09 | gate_report_format FAILのskill帰 |
| cmd_2605 | スキル成長ループの段階3-4を完結させる。現状PASS記録がgate_report_format.sh経由のスキル(report-write等)で欠落しており成長が計測不能。PASS記録を統一し、注意ポイントを適用し、定期自走化で永続的にループを回す | infra | 05-09 | gate_report_format PASSをreport |
| cmd_2607 | 将軍のcmd起票BLOCK率が56%で振動し改善しない。根因: 検知(cmd_save.sh BLOCK)は機能しているが防止(事前に正しく書ける仕組み)がない。さらにPASS記録がなく成長の証拠が計測できない。スキル成長ループ(cmd_2605)で修正した構造と全く同じ穴が将軍自身のcmd起票にもある | infra | 05-09 | cmd_save.shのPASS記録と、起票前hookの直近 |
| cmd_2608 | 将軍BLOCKの65%がWARN累計昇格BLOCK。FPが蓄積→閾値超過→正しいcmdもBLOCKされる。FP率最高の2チェック(q11_existing_alternative_verification 50%, command_steps_over_ac 45%)のロジック改善でWARN蓄積を削減し実効BLOCK率を下げる | infra | 05-09 | cmd_save.shのq11 command抽出終端を安定 |
| cmd_2609 | セマンティクスインデックスの新概念候補53件がinsightに滞留し追加率5.7%(3/53)。根因: 検知精度が低くタイムスタンプ・cmd番号・lesson番号がノイズとして候補に入る。さらにaliases拡張は自動化可能だが手動依頼のまま。cmd_save.sh FP率問題(cmd_2608)と同構造: 検知が粗い→ノイズ蓄積→信号が埋もれる→仕組みが死ぬ | infra | 05-09 | semantic_index_update.shにノイズ候補 |
| cmd_2610 | 家老のworkaround記録112件中environment_change付き0件(変換率0%)。karo_workaround_log.sh L196でWARN止まりのためBLOCKしない=家老は無視する=同じworkaroundが繰り返される。将軍のcmd_save.shではenvironment_change未記入→BLOCKで強制しており変換率100%。同じ仕組みが家老側に未適用。deepdive Phase 4(WARNでは行動は変わらない→BLOCK=自動化×強制) | infra | 05-09 | karo_workaround_log.sh --wa の |
| cmd_2611 | 教訓478件が索引セクションに滞留(core:62,ops:82,research:4,infra:330)。根因: lesson_write.shが全教訓を索引セクションに投入するバッチ設計。cmd_2606で追加したsubdomainタグ(fe/be/gs/infra)を活用し、教訓追加時に適切な§に自動ルーティングするストリーム設計に変更する。加えてlesson-sort SKILL.mdの§番号テーブルを現在のセクション構造に更新 | infra | 05-09 | lesson_write.shにresolve_lesson |
| cmd_2612 | 本セッションで6領域に同一構造の穴(WARN止まり=行動変換なし)を発見・修正した。根因: 新しいgate/hookを作るcmdに対して「WARN止まりにしていないか」「行動変換(BLOCK/自動実行)まで設計したか」を検知する仕組みがない。個別の穴を塞いでも、同じ設計ミスで新しい穴が量産される。穴を作らない仕組み=メタ穴防止gate | infra | 05-09 | cmd_save.shにgate/hook追加cmdの行動変 |
| cmd_2613 | auto_draft_lesson.shがlesson_write.shを呼ぶ際、CMD_IDを空文字で渡しlesson.doneが生成されない問題と、--status draftで登録し同一gate実行内でdraft_lessons BLOCKが発火する構造的バグを修正。直近50cmdで3パターン計72回のBLOCK(draft_lessons:27, missing_gate:lesson:23, lesson_done_missing:22)の根因 | infra | 05-09 | auto_draft_lesson.shをconfirmed |
| cmd_2614 | deploy_task.sh L295のSTALE_FIELDSにscout_exemptが含まれ、家老が事前設定したscout_exemptが配備時にクリアされる(5回連続workaround LK011)。resolve_cmd L504-505がSTKから再設定する機能は既存だが、STKにscout_exemptがないcmdでは復元されない。STALE_FIELDSからscout_exemptを除外し、resolve_cmdのSTK読取に一本化する | infra | 05-09 | cmd_2614: STALE_FIELDSからscout_ |
| cmd_2615 | 軍師startup gateが冷え観点(ambiguity 10件連続0等)を検出し表示するが、レビュー時の使用を強制しない(意志依存)。gate_gunshi_cs_checklist.shに冷え観点チェックを追加し、startup gateが検出した冷え候補がfinding_categoriesに含まれなければWARNする。cmd_2612(メタ穴防止gate)と同構造の穴を塞ぐ | infra | 05-09 | 軍師CS checklist gateに冷え観点findin |
| cmd_2616 | cmd_save.sh L1679-1682でgate/hook追加cmdのq11にgrep結果がない場合WARNするが、将軍が毎回消火(q11追記→PASS)してリセットし26回同じWARNを繰り返す。WARN→直接BLOCKに昇格して即停止させる | infra | 05-09 | cmd_save.shのq11既存代替確認なし分岐をWARN |
| cmd_2618 | lessons_gunshi.yaml 15件+lessons_shogun.yaml 3件=合計18件のautomated:false教訓を洗い出し、各教訓に最適なenforcement方式(gate/hook/テンプレート/入口生成)を設計する。軍師指摘(blt_232728): Level4(止める):Level5(生成)=28:3。入口生成を増やす計画を立てる | infra | 05-09 | automated:false 18件を全件確認。Level |
| cmd_2619 | check_research_tool_explicit(Check 18)が62回WARN。偵察や本番検証cmdでcommandにoutputs/grid_searchデータ参照を含む場合も発火する偽陽性と、ACに書くべきスクリプトパスを将軍が手動で探す必要がある入口不在が根因。偽陽性除外+ACパス候補の自動提案(Level5化)で62回WARNを構造的に削減する | infra | 05-09 | Check 18のoutputs/grid_search偵察 |
| cmd_2636 | semantic_search.shは手動CLI検索ツール(エージェントが概念検索時に明示的に呼ぶ道具)。hooks登録は不適切。allowlistの道具カテゴリに追加し、startup gateの3セッション連続BLOCKを解消する | infra | 05-10 | config/enforcement_audit_allow |
| cmd_2638 | gate_vercel_phase.shは壊れたcontext参照を検出するがALERT表示のみ。忍者/家老が手動で修正箇所を探す必要がある(9回BLOCK実績)。壊れ参照検出時に修正候補(存在するファイルからの類似パス提案)を自動表示し、手動探索コストを削減する | infra | 05-10 | gate_vercel_phase.shの壊れたdocs/r |
| cmd_2637 | gate_skill_script_refs.shが16件のSKILL.mdで参照scriptがSKILL.mdより新しいと検出。大半は共通ライブラリ(yaml_field_set.sh等)の内部変更でインターフェース不変。各SKILL.mdのscript参照を確認し、内容変更が必要ならば更新、不要ならばtouchでmtimeリセット。startup gateの3セッション連続BLOCKを解消する | infra | 05-10 | gate_skill_script_refs.shの要更新ス |
| cmd_2641 | スクリプト変更後にcodd propagate --updateが手動実行のため設計書/SKILL.mdが陳腐化する(今日のSKILL.md stale 16件の根因)。cmd_complete_gate.sh CLEAR後にcodd propagateを強制的に自動実行し、変更波及先を自動更新する | infra | 05-10 | cmd_complete_gate.shのGATE CLEA |
| cmd_2642 | CDP(ブラウザ操作)はFE変更の本番確認に有用だが、cmd完了時の自動接続がなく意志依存。FE変更を含むcmdのGATE CLEAR後にCDP自動スクショを実行し、変更が本番に反映されたことを強制的に確認する仕組みを追加する | infra | 05-10 | cmd_complete_gate.shのCLEAR判定直前 |
| cmd_2643 | gate_context_freshness/gate_lesson_health/gate_knowledge_freshness/gate_silent_fallback/gate_wa_data_quality/gate_p_average_freshnessの6件はALERT検出のみで修正提案がない(Level1)。各gateのALERT出力箇所に修正候補を強制的に自動提案する表示を追加しLevel5化する(gate_vercel_phaseのcmd_2638と同パターン) | infra | 05-10 | gate_knowledge_freshness/gate_ |
| cmd_2645 | lord_conversation.jsonl(202件)に殿の裁定・方針・指摘が蓄積されているが、cmd起票時に自動検索されない(cmd_save.shに参照0箇所)。cmdのtitle/purposeから殿の関連発言を強制的に自動検索し、殿の過去裁定と矛盾するcmd起票を構造的に防止する | infra | 05-10 | cmd_save.shに殿発言検索INFOを追加し、関連ba |
| cmd_2644 | cmd ACにchecklist参照がある場合、該当Stepの隣接Step(前後)の制約条件がタスクYAMLに強制的に自動注入されていない。cmd_1397事故(再計算禁止ステップ未転写)の再発防止。deploy_task.shでAC内のchecklist参照を検出→隣接Step制約を自動注入する | infra | 05-10 | deploy_task.sh に inject_checkl |
| cmd_2646 | 家老がWA記録時にinsightが自動生成されるが、家老自身のstartup gateに表示されない(gate_karo_startup.shに参照0箇所)。家老が生成したinsightが家老に戻らない断絶を解消し、pending件数+直近3件を起動時に強制的に表示する | infra | 05-10 | gate_karo_startup.shにinsights未 |
| cmd_2647 | cmd-chronicle.md(790行)に全cmd履歴が蓄積されているが、cmd起票時に類似過去cmdが自動検索されない。cmd_save.shでtitle/purposeからcmd-chronicle.mdを強制的に検索し、類似過去cmdをINFO表示する。lord_conversation検索(cmd_2645)と同パターン | infra | 05-10 | cmd_save.shのcmd-chronicle強制検索を |
| cmd_2650 | robustness-verification-catalog.md、gs-speedup-knowledge.md、dm-signal-terminology.md、training-cycle.mdの4ファイルがdeploy_task.shから注入されていない。purpose/project/task_typeに応じて関連contextパスを強制的にタスクYAMLへ注入するinject_context_hints関数を追加し、4ファイルを一括Level5化する(軍師提案R2残4件を統合) | infra | 05-10 | deploy_task.shにinject_context_ |
| cmd_2651 | ACに「N条件」「N項目」と書いて具体値を未列挙→忍者が独自判断で補完する問題が98回WARN。WARN時にcmd内のN条件をパースし、関連するcontext/*.md/projects/*.yamlから候補値を強制的に自動提案するLevel5化。軍師提案(blt_20260510_125831) | infra | 05-10 | cmd_save.shのAC数量指定WARNに、関連cont |
| cmd_2649 | growth-loop.md §11(防御階層Level1-5)は忍者のBLOCK対応に有用だが、instructions/ashigaru.md参照0・deploy_task.sh注入0。忍者は成長ループの構造を知らずにgateBLOCKと格闘している。deploy_task.shでgate関連cmdの忍者タスクYAMLにgrowth-loop.md §11を強制的に自動注入する | infra | 05-10 | deploy_task.shにinject_growth_l |
| cmd_2652 | DM-Signal本番リポジトリにGitHub Actionsがなく、3583テストファイルがpush前に自動実行されない(Level 0)。pytest自動実行のGitHub Actionsワークフローを追加し、push/PR時にテストが強制的に実行される仕組みを構築する。軍師指摘(blt_20260510_002908): 最大の穴 | dm-signal | 05-10 | GitHub Actions pytest workflow |
| cmd_2654 | cmd_2652で追加したGitHub Actions CIの初回実行がfailure。9テストファイルがcollection errorで失敗。全9件の根因は同一: scripts/analysis/配下のresearchスクリプトが`import yaml`するがPyYAMLがCI環境にインストールされていない(backend/requirements.txtに未記載)。依存を解決しCI GREENにする | dm-signal | 05-10 | GitHub Actions pytest workflow |
| cmd_2655 | 殿原則(2026-05-10): WHY/WHAT/WHEN/HOWが最低でもないとループが回転しない。現在のcmd_save.sh q8はWHY+WHATのみ検証。WHEN(いつ発動するか)とHOW(どう機能するか)が欠落しているcmdは設計不完全のまま通過する。q8検証にWHEN/HOWの有無チェックを追加し、殿の原則を環境に埋め込む | infra | 05-10 | cmd_save.shのq8_why_what検査にWHEN |
| cmd_2656 | cmd_2654でPyYAML追加後もCI failureが継続。残2件のcollection error: test_pipeline_cache_optimization.py(ModuleNotFoundError: dotenv)とtest_ward_two_stage_ew_block.py(ModuleNotFoundError: sklearn)。python-dotenvとscikit-learnをCI依存に追加しGREEN化する | dm-signal | 05-10 | CI pytest依存にpython-dotenv/scik |
| cmd_2657 | 軍師分析: 教訓when/how充足率=全PJ 0%(dm-signal 696件)。教訓にwhen(いつ適用するか)がない→忍者が適用タイミングを判断できない→教訓参照しても行動に変換されない→L6学習速度低下。useful_count上位20件からwhen/how補完を開始し、教訓の行動変換率を向上させる | infra | 05-10 | dm-signal教訓のhelpful_count上位20件 |
| cmd_2660 | cmd_2652/2654/2656でcollection error全解消(1422 passed)したがDB依存テスト11件がfailed。根因: GitHub ActionsにPostgreSQLサービスがなくDATABASE_URL未設定。ワークフローにPostgreSQLサービスを追加しDB依存テストを実行可能にする | dm-signal | 05-10 | CI pytest workflowにPostgreSQLサ |
| cmd_2661 | check_ac_test_scope() FP率66%(3件中2件FP)。grep -v除外パターンが不十分でスコープ済みテストAC(DB依存テスト11件/退行確認/CI固有テスト等)にもWARN発火。累計昇格で将軍cmd起票がBLOCKされる実害あり | infra | 05-10 | check_ac_test_scopeのスコープ済みテスト条 |
| cmd_2663 | test_cmd_save系テストが個別実行ではPASSするが一括実行(bats --jobs 8)でFAILする。根因: テスト間のグローバル変数/tmpファイル共有による状態汚染。CIでも--jobs 8で実行されるためCI安定性に直結 | infra | 05-10 | cmd_save系5テストの並列実行向け状態隔離を実装 |
| cmd_2664 | Check16(行動→即確認原則)がYAML multiline block形式のACを検出できない。L3446がdescription:行のみgrepするためAC本文の確認キーワードを見逃す。LS-A22(8)と同一構造のバグ。cmd_2392で他check関数は修正済みだがCheck16は未修正 | infra | 05-10 | Check16がacceptance_criteria配下全 |
| cmd_2665 | lesson関連BLOCK 43回(50cmd中)。根因: deploy_task.shテンプレートのno_lesson_reasonが空文字、lessons_usefulがnull。忍者が教訓なしの場合でも手動記入が必要→漏れ→BLOCK。cmd_2472(binary_checks/assumption_invalidation prefill)と同パターンの横展開 | infra | 05-10 | 報告テンプレートのlessonデフォルトをgate互換値へ変 |
| cmd_2666 | skills/dream/SKILL.mdとskills/shogun-teire/SKILL.mdが参照するgate_lesson_health.shより古い。startup gateで3セッション連続WARN→BLOCK昇格。参照スクリプトの変更内容をSKILL.mdに反映する | infra | 05-10 | skills/dream/SKILL.md と skills |
| cmd_2659 | draft reviewが18件連続SKIP。根因: STALE_FIELDSがacceptance_criteriaを削除→_overwrite_ac_from_cmdがcmdソースからAC再注入を試みるがアーカイブ済みで不在→task YAMLにACなし。cmdソース不在時のfallbackを実装 | infra | 05-10 | deploy_task.shのAC overwrite失敗時fallback |
| cmd_2662 | gate_report_format.shで直近50cmdにreport_format BLOCK 9回+binary_checks_fail 3回。既存instructions記載済みだがBLOCK継続。配置・強調・記入例の改善でLevel5化し忍者の吸収率を上げる | infra | 05-10 | 忍者instructions Level5化(report_field_set必須+bc例) |
| cmd_2667 | auto_failure_lesson.shが--status draftで教訓を書くため、cmd_complete_gateが自cmd由来draftを検出→BLOCK→家老がconfirmed昇格→再gate→CLEARの2回gate実行が24回発生。auto_draft_lesson.shは既にconfirmedで書いておりBLOCKしない。同じ構造に統一する | infra | 05-10 | auto_failure_lesson.shをconfirm |
| cmd_2668 | L6学習速度の自動追跡をstartup gateに組込む。FAIL→PASS遷移率+L6化率を自動算出・表示し、L6化候補を強制提案する | infra | 05-11 | gate_shogun_startup.shにL6学習速度セ |
| cmd_2669 | LS-A14(進行中計画は即永続化)をL2→L4化。clear_prep_check.shに裁定未反映検出を追加し、未反映裁定がある状態での/clearをBLOCKする | infra | 05-11 | clear_prep_check.shに裁定反映Check1 |
| cmd_2670 | growth-loop.md §11にL6化済み/未化の完全リストを追記し、L6化の正確な全体像を受動的知識として永続化する | infra | 05-11 | context/growth-loop.md §11にL6化 |
| cmd_2671 | startup gateのL6化率算出ロジックを修正。母数をGP提案(56件)→防御仕組み(16件)に変更し、L6済み仕組みをgrowth-loop.md §11から読み取る | infra | 05-11 | Gate 21のL6化率をgrowth-loop.md §1 |
| cmd_2672 | 将軍教訓32件→22件に統合。LS023-LS032の10件を既存クラスタ(LS-A04/A09/A02/A22/A17)に吸収し、上限31件超過を解消する | infra | 05-11 | projects/infra/lessons_shogun. |
| cmd_2674 | gate_enforcement_audit.shをL1→L5化。意志依存スクリプト検出時にhooks登録コマンドを自動提案し、修正アクションを即実行可能にする | infra | 05-11 | gate_enforcement_auditのALERT時に |
| cmd_2676 | gate_wa_data_quality.shをL1→L5化。False WAパターンTOP3を家老に自動通知し、WA計測精度の改善アクションを即座に提示する | infra | 05-11 | gate_wa_data_quality.shにFalse |
| cmd_2678 | cmd_save.sh is_gate_or_hook_addition_cmd L161の偽陽性修正。gate_fire_log等のファイル名内gateをgate/hook追加と誤判定するバグを修正する | infra | 05-11 | cmd_save.shのgate/hook追加判定をASCI |
| cmd_2679 | セマンティクスインデックスにL6化セッションの成果を反映。defense_hierarchyとgrowth_loopにaliases+cmd参照を追加し、semantic_map_generate.shで伝搬する | infra | 05-11 | セマンティクスインデックスのdefense_hierarch |
| cmd_2680 | daemon_watchdog.shのcrontab登録を旧flock形式から新形式に更新し、1時間毎のntfy WARN通知を停止する | infra | 05-11 | crontabのdaemon_watchdog.sh登録から |
| cmd_2681 | 同一cmdに2名配備される二重配備パターン(cmd_2678-2680で3連続発生)を構造的に防止する | infra | 05-12 | cmd_2681: deploy_task.shの同一cmd |
| cmd_2682 | 同一cmdで先行忍者が完了済みの場合、後発忍者を自動的にvoid(task reset+/clear)して空報告を防止する | infra | 05-12 | ninja_monitorに同一parent_cmd完了済み |
| cmd_2683 | 起動手順スキップ(家老がinstructions/karo.md未読で即応答した事故)を構造的に防止する。全ロールのstartup gateをSessionStart hookで自動実行し意志依存をゼロにする | infra | 05-12 | SessionStart hookをsettings.jso |
| cmd_2684 | deploy_task.sh経由でもkaro_direct経由でも最終的にinbox_write.sh type=task_assignedを通るため、ここで同一parent_cmdの他忍者配備を検査しBLOCKすることで全配備経路の二重配備を防止する | infra | 05-12 | inbox_write.shにtask_assigned全経 |
| cmd_2685 | 教訓注入useful率29.3%(ALERT)。NOT_USEFUL 106件の根因=既存target_filesフィルタは存在するが教訓側メタデータ未設定で素通り。入口精度改善+退場加速の2軸 | infra | 05-12 | 教訓注入の入口精度改善としてtarget_files付与経路 |
| cmd_2687 | 掲示板確認が意志依存。inbox bulletin_notifyを読んでも confirmed_byに記録されず次回起動時に未確認WARNが再発。inbox_mark_read.shにbulletin_confirm連動を追加し意志依存ゼロにする | infra | 05-12 | inbox_mark_read.shでbulletin_no |
| cmd_2688 | 教訓注入useful率改善の補完。noise4件(L175/L170/L097/L136 参照率0%)とharm4件(L333/L326/L297/L263 BLOCK率100%)がfeedback不足でcmd_2685のdecay対象外。手動でdeprecate/tag限定し注入プールから排除 | infra | 05-12 | projects/infra/lessons.yaml のn |
| cmd_2689 | gate_skill_quality FAIL(3/38)。shogun-all-codex-switch/shogun-peacetime-rollback/weekly-report-writerのdescription不備(What/When/NOT When欠落)。startup WARN連続の一因 | infra | 05-12 | gate_skill_qualityのFAIL対象3スキルの |
| cmd_2690 | 軍師検出: semantic-index file参照12件がMISSING(DM-Signal外部リポジトリのパス移動/削除が未反映)。インデックス正確性を回復する | infra | 05-12 | semantic-indexのDM-Signal外部file |
| cmd_2691 | karo_direct方式の修行配備でdeploy_task.shの修行テンプレ注入をバイパスし、AC/descriptionが空のまま配備。deploy_error 5件蓄積の根因。karo_directでも修行テンプレ注入を実行する | infra | 05-12 | karo_directスキルのtrainingセクションをd |
| cmd_2692 | karo_workarounds.yaml 88件のresolved_by_cmdが空(解決率16.2%偽陽性)。根因=記入が意志依存。cmd_complete_gate CLEAR時にWAカテゴリを検索しresolved_by_cmdを自動backfillする | infra | 05-12 | cmd_complete_gate GATE CLEAR時に |
| cmd_2693 | karo_direct配備(ci_fix/recon2/hotfix)で旧task YAMLのフィールドがリセットされずstale_report 5件蓄積。根因=deploy_task.shのreset_stale_fieldsに相当する処理がkaro_directのcp前にない。cp前にstatusリセットを追加する | infra | 05-12 | karo-directのci_fix/recon2/hotf |
| cmd_2694 | restart_watchers.sh/ninja_monitor.shのwatcher起動が親プロセスからASW_DISABLE_ESCALATION=1を継承し将軍nudge無効化が再発(cmd_2403修正後も再発)。起動直前にunsetで継承を構造的に遮断する | infra | 05-12 | watcher起動直前にASW_DISABLE_ESCALA |
| cmd_2696 | 修行cmdの教訓参照率0%(89件feedback中useful=0)。根因=修行ACに教訓活用ステップがなくgate精読+報告作成で完結。テンプレートにAC(注入教訓から1件以上referenceせよ)を追加し教訓参照を構造的に強制 | infra | 05-12 | 修行cmd L4テンプレートに、注入教訓を1件以上参照してl |
| cmd_2698 | skill_auto_improve.shがgate FIXヒント75件を読まずBLOCK理由文字列のパターンマッチで防止ステップを生成→汎用テンプレート3件が具体性不足→一発CLEAR率71.6%止まり。FIXヒントDBを自動参照し具体的な防止ステップを生成する | infra | 05-12 | gate_report_format_main.pyにloo |
| cmd_2699 | karo_direct配備(cmd_2695-2698の4件連続)でac_count=0→draft_review SKIPが発生し、軍師レビューの成長ループ第二層が断絶している。全配備パスでac_countが正しく返るよう修正する | infra | 05-12 | karo_direct由来でtask側ACが空でも、壊れたa |
| cmd_2701 | rebalancerを将軍システムの管理対象に登録する。config/projects.yaml+projects/rebalancer.yaml+context/rebalancer.mdを作成し、偵察・cmd配備・教訓蓄積の基盤を整える | infra | 05-14 | rebalancerを管理対象として登録し、config索引 |
| cmd_2703 | cmd_save.shの3ゲート(q11_existing_alternative FP率52%、command_steps_over_ac FP率50%、ac_param_sufficiency FP率40%)が偽陽性を量産し、将軍のcmd起票に負の複利を生んでいる。検出精度を改善する | infra | 05-14 | cmd_save.shの3ゲートFP削減を実装。既存gate |
| cmd_2704 | 偵察タスク(scout_exempt:true)はコード変更を伴わないため未commitファイルが存在しない前提だが、git_uncommitted_gateはscout_exemptを考慮せずBLOCKする。偵察タスクではgit_uncommitted_gateをスキップする | infra | 05-14 | scout_exempt:trueタスクではreport_r |
| cmd_2705 | Renderは/var/lib/dataに永続diskをmountするが、アプリは相対パスstatic/data/cacheに読み書きし永続disk未使用。加えて/staticマウントでcache JSONが外部閲覧可能。CACHE_DIR環境変数対応+/static公開制限で修正する | rebalancer | 05-14 | Render永続diskにcacheを書き込むようCACHE |
| cmd_2706 | pytest-asyncioのasyncio_mode設定欠如により12件のasyncテストがFAIL。pytest設定追加+非推奨asyncio.get_event_loop().run_until_complete()をasyncio.run()に修正する | rebalancer | 05-14 | pytest-asyncioを0.24.0にpinし、bac |
| cmd_2708 | Toast.tsx ×ボタン押下時にsetIsVisible(false)のみでonClose()が呼ばれない。errorステートが残存し、同一エラー再発時にToastが再表示されない | rebalancer | 05-14 | Toastの×ボタン押下時もexit animation後に |
| cmd_2707 | Next.js 15.0.3にcritical(RCE GHSA-9qr9)+high(auth bypass GHSA-f82v)含む脆弱性4件。15.5.18へupgradeし、Serwist互換性とbuild/lint/auditを検証する | rebalancer | 05-14 | Next.js 15.0.3→15.5.18アップグレード完 |
| cmd_2710 | updaterとユーザーAPIが同じJSONを同時読み書きすると部分書込みでJSONDecodeError→Noneフォールバック→不要な外部API fetchが発生。atomic rename+lockで並行安全性を確保する | rebalancer | 05-14 | DiskCache.setをtmp書込み後のatomic r |
| cmd_2709 | Backend ModelはList[str]のみでregex・件数上限・supported ticker強制なし。重複tickerは後勝ち上書きで整合崩壊。入力検証を追加し、重複tickerを400エラーにする | rebalancer | 05-14 | Backend API入力検証を追加し、unsupporte |
| cmd_2712 | get_pricesが各tickerを逐次awaitし毎回1秒sleep。18銘柄で最低17秒以上。semaphore bounded concurrencyで並列化し、cache hit時はsleepスキップでレスポンス時間を大幅短縮する | rebalancer | 05-14 | get_pricesをSemaphore付き並列fetchに |
| cmd_2713 | sw.jsのprecache URLにバックスラッシュが混入しPWAアイコンcache失敗。加えてguide内URLがrender.yaml正本と不一致。Linux再生成+URL統一で修正する | rebalancer | 05-14 | Linux上のnpm run buildでSerwist s |
| cmd_2714 | FundingSection折りたたみがキーボード未対応、icon-onlyボタンにaria-labelなし、モバイルで横溢する。a11y標準に準拠しUX品質を改善する | rebalancer | 05-14 | FundingSectionの折りたたみをbutton+ar |
| cmd_2715 | CIが存在せず、Render前に品質ゲートが走らない。GitHub Actionsでbackend pytest+frontend lint/build/auditを自動実行し、品質を構造的に保証する | rebalancer | 05-14 | GitHub Actions CI workflowを新規作 |
| cmd_2716 | BUY/SELL/HOLDが英語ハードコード、formatCurrencyがen-US固定、APIエラーが英語のまま。日本語モードで全UI要素がi18n対応するよう修正する | rebalancer | 05-14 | 日本語モードでリバランス結果の売買ラベル、通貨表示、APIエ |
| cmd_2718 | Python requirementsがversion pinなしで再現性ゼロ。npm outdatedで主要パッケージに更新あり。requirements pinとnpm依存更新で再現性とセキュリティを確保する | rebalancer | 05-14 | backend/requirements.txtをpip f |
| cmd_2720 | 連続起票時に既知BLOCKパターンの教訓記録でlesson作成→supersede→物理削除のCTX浪費ループが発生(前セッション2026-05-14で20cmd連続起票時に毎回発生)。既知パターンを既存lessonクラスタにack(確認記録)する軽量メカニズムで解消する | infra | 05-14 | 既知BLOCKパターンを既存将軍教訓へack記録するヘルパー |
| cmd_2719 | frontend/src/配下にユーザー作成テストが0件(find確認済み)。Vitest+Testing Libraryを導入し、主要コンポーネントのユニットテストを追加する | rebalancer | 05-14 | Vitest+Testing Library+jsdomをf |
| cmd_2721 | Playwright/CypressなどのE2Eテストフレームワークが未導入(grep確認済み)。銘柄入力→計算→結果表示の主要ユーザーフローをE2Eで検証できるようにする | rebalancer | 05-14 | Playwrightをfrontendへ導入し、銘柄入力から |
| cmd_2722 | 過剰なカード化(glass-card内にrow card)で画面を有効活用できず、スマホでもPCでも一覧性が低い。カード廃止→テーブル直書き+PC2カラム化+ui-design-guide準拠(コントラスト、タッチターゲット、階層)でデータ密度と可読性を両立する | rebalancer | 05-14 | カード内row cardを廃止し、PortfolioForm |
| cmd_2724 | cmd_2703で偽陽性修正済みのac_phase_mixing(29件)とac_param_sufficiency(19件)のWARNカウントがquality logに残存し、正当発火時に即BLOCK(post-5/12 BLOCKの48%が遺産起因)。加えてcmd_quality_log.shとcmd_save.sh log_cmd_save_pass()のヒアドキュメントが2スペース余分でYAML破損を引き起こしていた(cmd_2723起票中に発見、直接修正済み)。残存WARN遺産の解消とcount_same_warn_patternのresolved除外とインデント修正のテスト追加で恒久対策する | infra | 05-14 | cmd_2703で解消済みのac_phase_mixing/ |
| cmd_2726 | 4行のうち3行使用時にtarget_weight未記入行がバリデーションエラーになる。shares未記入も0入力が必要で面倒。ticker未記入行を除外、target_weight未記入を0%扱い、shares未記入を0扱いにする | rebalancer | 05-14 | 未入力ticker行を計算対象から除外し、未入力target |
| cmd_2727 | PF入力をやり直したい時に1行ずつ削除するのが面倒。全消去ボタンで空行4行にリセットし、前回復元ボタンでSupabaseから保存済みPFを再ロードする操作を追加する | rebalancer | 05-14 | PortfolioFormに全消去/前回復元操作を追加し、S |
| cmd_2728 | Blue-Purpleグラデーション+glassmorphismの2023年AIテンプレ感を排除し、Wealthfront調のTeal(#14b8a6)基調+ソリッドカード+装飾最小限の金融プロフェッショナルデザインに刷新する。同時にガイドページの配色も統一する | rebalancer | 05-14 | Blue-Purple/glassmorphism系UIをT |
| cmd_2729 | モバイル(375px)でヘッダーが2行に折れ、サポート銘柄18件が横溢し、テーブル列が窮屈で入力しづらい。CDPモバイルビューポートで5箇所の崩れを確認済み。レスポンシブ対応を修正する | rebalancer | 05-14 | Rebalancer mobile responsive l |
| cmd_2731 | ガイドページに「データを保存しません」「サーバーに保存されません」と記載されているが、cmd_2723でSupabase保存機能が実装済み。cmd_2725(保存ボタン)、cmd_2726(バリデーション緩和)、cmd_2727(全消去+復元)の内容もガイドに未反映。ガイドと実装の整合性を修復する | rebalancer | 05-14 | frontend/app/guide/page.tsx のJ |
| cmd_2730 | ルート.gitignoreにpycache/pyc/cacheファイルが未登録で、backend側に.gitignoreが存在しない。445件のdirty filesが蓄積しworking treeが汚れている。.gitignore整備+git rm --cachedでtracked不要ファイルを除去する | rebalancer | 05-14 | ルート.gitignoreを追加し、pycache/back |
| cmd_2732 | Gate 20(スキル別FAIL率)が全期間累積fail>0で判定しているため、改善済みFAILが永久にWARN発火する。直近50件FAIL率は全スキル0%だが3セッション連続BLOCK。直近50件ベース+10%閾値に変更し実態を反映した判定にする | infra | 05-14 | Gate 20のスキル別FAIL率を全期間累積から各スキル直 |
| cmd_2734 | 概念→スキルの対応がインフラに存在せず、スキル使用が意志依存(CDP未使用トラブル、DB-check誤使用が繰返し発生)。semantic indexにskills列を追加し、deploy_task.shでタスクYAMLにrecommended_skillsとして自動注入する | infra | 05-15 | semantic indexのskills列をタスク配備時の |
| cmd_2735 | 忍者がrecommended_skillsを無視してもレビューで検出されない。軍師の6観点にスキル使用適切性チェックを追加し、recommended_skillsが存在するのに未使用の場合にREQ_CHANGESを出す | infra | 05-15 | 軍師レビューにrecommended_skills使用突合を |
| cmd_2736 | 将軍はスキルの存在を知っているがセッション中にTRIGGER条件と結びつかず手動作業に流れる(CDP未使用等、殿指摘)。prompt_state_inject.shにスキルTRIGGERキーワード照合を追加し、合致スキルを強制表示する | infra | 05-15 | prompt_state_inject.shに将軍向けスキル |
| cmd_2738 | DB-checkをrebalancerで呼ぶ等のスキル誤使用が繰返し発生(殿指摘)。SKILL.mdのDO NOT TRIGGER条件とcurrent_projectを照合し、制約違反時にexit 2でBLOCKするPreToolUse hookを追加する | infra | 05-15 | PreToolUse Skill guard hookを実装 |
| cmd_2742 | 現在ダークモード固定でライトモードがない(殿指摘)。Tailwind darkMode class方式で切替トグルを追加し、ユーザーがダーク/ライトを選択可能にする | rebalancer | 05-15 | Tailwind class dark方式のテーマ切替を追加 |
| cmd_2743 | cmd_complete_gate.sh L222がshogun_state!=idleでinbox_writeをスキップし、将軍がactive時(殿と対話中)にGATE CLEAR通知が届かない。殿がntfyで先に知り将軍に聞くが将軍が知らない事態が発生(殿指摘)。stateチェックを撤去し常時通知にする | infra | 05-15 | cmd_complete_gate.shの将軍GATE CL |
| cmd_2744 | 将軍がGATE CLEARを受けても殿の入力を待って動かない。F004(polling禁止)を過剰解釈し自走を抑制していた(殿指摘:自分で出したcmdの結果確認は鎖の中)。GATE CLEAR後の定型アクション(push判断/次cmd確認/殿への報告)を将軍の正当な自走としてshogun.mdに明文化する | infra | 05-15 | GATE CLEAR受信後の将軍自走フローをshogun.m |
| cmd_2746 | cmd_2662-2666で5回頻発したdeploy_task.sh配備後のinbox未配信事象の根因を特定し、再発防止策を提案する | infra | 05-15 | cmd_2662-2666のinbox未配信は、2026-0 |
| cmd_2747 | karo_workarounds.yamlの歴史的データ汚染(detail空・category不正)82件を正しいcategory/detailに修復し、WA分析の精度を回復する | infra | 05-15 | karo_workarounds.yamlのWAデータ品質汚 |
| cmd_2748 | dm-signal教訓698件+infra教訓583件の旧形式教訓にwhen/howフィールドを段階的に補完するスクリプトを作成し、教訓注入の精度を向上させる | infra | 05-15 | 旧形式教訓のwhen/how補完スクリプトを追加し、dm-s |
| cmd_2749 | skill_auto_improveがSKILL.md改善で閉じないFAIL(スクリプトバグ起因)を検出し、コード修正cmdの起票を将軍に掲示板経由で要請する仕組みを追加する | infra | 05-15 | skill_auto_improveにFAIL分類、UNCH |
| cmd_2750 | auto_failure_lesson.shがgate_fire_logのFAIL原因を参照し、スクリプトバグ起因のFAILを検出した場合にbulletin_write.shで将軍にコード修正cmd起票を要請する | infra | 05-15 | auto_failure_lesson.shにgate_fi |
| cmd_2751 | insight_write.shに同一パターン繰返し検出と優先度判定を追加し、高優先度insightが蓄積のまま埋もれる問題を解消する | infra | 05-15 | insight_write.shにsource一致のpend |
| cmd_2752 | gate_fire_logのFAIL→PASS遷移分析で未回復期間が閾値(設定可能)を超えたFAILを検出し、bulletin_write.shで将軍にコード修正cmd起票を要請する | infra | 05-15 | gate_shogun_startup.shのL6学習速度に |
| cmd_2753 | auto_failure_lesson.shがどこからも呼ばれていない断裂を修正し、gate FAILした忍者タスクから自動的に教訓が生成されるパイプラインを接続する | infra | 05-15 | cmd_complete_gate.shのGATE BLOC |
| cmd_2754 | ninja_monitorにidle忍者への修行自動配備トリガーを追加し、修行サイクルが家老の手動判断に依存する断裂を解消する | infra | 05-15 | ninja_monitor.shにidle継続+直近gate |
| cmd_2756 | bulletin_write.shにaction_typeフィールドを追加し、昇格通知が対応されたか追跡可能にする。startup gateで未対応ALERTを表示し、cmd_save.shでactioned_by自動更新する | infra | 05-15 | bulletin action_type/actioned_ |
| cmd_2755 | gate_fire_logのFAIL→PASS遷移率計測を将軍の/clear間隔依存から解放し、ninja_monitorで定期的に計測・記録する | infra | 05-15 | ninja_monitor.shにgate_fire_log |
| cmd_2758 | Gate 13.8のFP率閾値超過時にbulletin_write.shで将軍にgate条件緩和cmdの起票を要請し、FP増大による速度低下を防止する | infra | 05-15 | Gate 13.8の高FP率時bulletin緩和要請実装を |
| cmd_2757 | effectiveness低い教訓の定期棄却をninja_monitorで自動実行し、教訓注入ノイズの単調増加を防止する | infra | 05-15 | ninja_monitorに教訓deprecate候補の日次 |
| cmd_2760 | CoDD v1.10.0時点の知識体系をv2.18.0に更新する。context/codd.md+セマンティックインデックス+スキルSKILL.md+reference_codd_oshio_articles.mdを最新の記事・GitHub情報で刷新する | infra | 05-15 | CoDD知識体系をv2.18.0へ更新し、context/s |
| cmd_2761 | 全8PJでcodd init --suggest-lexicons --llm-enhancedを実行しlexiconを設定。codd.yamlをv2.x形式に刷新。新PJ作成時にcodd initが自動実行される仕組みを追加する | infra | 05-15 | 全8PJへCoDD v2系設定とshogun_core le |
| cmd_2766 | CLEAR済みcmd関連insightとsemantic_index_update由来insightを自動done化し、191件pending永久蓄積を解消する | infra | 05-15 | cmd_complete_gate CLEAR後にcmd関連 |
| cmd_2768 | harmful閾値に加えuseful率(helpful/参照回数)が低い教訓も自動deprecateし、効果の薄い教訓が永続する穴を解消する | infra | 05-15 | — |
| cmd_2769 | deploy_task.sh配備後にinbox未配信が5回頻発した根因を特定し、再発防止策を設計する | infra | 05-15 | cmd_2662-2666の未配信疑いは、5件ともinbox |
| cmd_2762 | 設計書ゼロの主要スクリプト4本(deploy_task.sh/cmd_save.sh/ninja_monitor.sh/inbox_write.sh)にcodd brownfieldを実行し、DAG構築+設計書逆生成でリファクタとcodd fix/verifyの土台を作る | infra | 05-15 | 主要4スクリプトのCoDD brownfield成果物(re |
| cmd_2776 | セマンティック辞書に未マッピングの5概念カテゴリを追加し30ファイルの辞書到達性を確保。前提崩壊の構造的防止 | infra | 05-15 | セマンティック辞書SSOTに5概念を追加し、semantic |
| cmd_2777 | cmd_2775偵察で特定した高優先度60関数をcontext/infrastructure.mdにカテゴリ別で追記し、全エージェントが起動時に自動ロードできる受動的知識に昇格させる | infra | 05-15 | context/infrastructure.mdにcmd_ |
| cmd_2779 | cmd_save.sh BLOCK後のREMINDに教訓記録だけでなく環境埋込み判定を強制追加し、BLOCKのたびにインフラ改善cmdの要否を自動判定させる | infra | 05-15 | cmd_save.shのCLEAR時REMINDに環境埋込み |
| cmd_2780 | Simple-OCRリポジトリ全体にcodd extract --ai を実行し、6層MECE設計書を逆生成する。OCRエンジン切替実装の土台とする | infra | 05-15 | Simple-OCRでCoDD brownfield ext |
| cmd_2781 | 設計書(docs/ocr-engine-switching-design.md)のPhase 1-3を実装。OCREngine抽象クラス+Google/Claude/GPTの3エンジンを切替可能にする | infra | 05-15 | OCRエンジン抽象化を追加し、Google/Claude/G |
| cmd_2782 | Google Vision DOCUMENT_TEXT_DETECTIONのブロック座標情報をClaude Haikuに渡し、お薬手帳の列構造を正確に復元する二段構えパイプラインをSimple-OCRに組み込む | infra | 05-15 | Google DOCUMENT_TEXT_DETECTION |
| cmd_2784 | force-with-lease/reset/clean等の破壊的コマンド実行前に、lord_conversation.jsonlのinboundに殿の承認発言があるか自動検証するhookを追加し、ハルシネーションに基づく破壊的操作を構造的に防止する | infra | 05-15 | pre-bash-combinedにD010 Guardを追 |
| cmd_2785 | skills/dream・gate-sync・idle-persistのSKILL.mdが参照scriptより古く、startup gateが3セッション連続WARNしている。scriptの変更内容をSKILL.mdに反映し、gate_skill_script_refs.shのWARNを解消する | infra | 05-15 | skills/dream・gate-sync・idle-pe |
| cmd_2786 | cmd_save.sh L254のadditionキーワード判定が過去形・受身形(追加された/追加済み等)にもマッチし、gate参照cmdをgate追加cmdと誤判定する。15回累計でBLOCK昇格している偽陽性を修正する | infra | 05-15 | — |
| cmd_2787 | _build_two_stage_promptがお薬手帳の処方行解釈をハードコードしており、情報の追加(処方日補完)や構造強制(1行まとめ)が発生する。プロンプトを座標ベースのレイアウト忠実復元に限定し、情報量を不変にする | simple-ocr | 05-15 | _build_two_stage_promptを座標ベースの |
| cmd_2788 | record_lesson_feedback.sh L91の${task_type:-impl}がexact/recon/trainingを全てimplにフォールバックし、deploy_task.shのeffectiveness_score計算でexactタスクの有効率が歪む(有効率30%)。task YAMLからtask_type取得のフォールバックを追加する | infra | 05-15 | record_lesson_feedback.shにtask |
| cmd_2791 | auto-ops/gc/db等の教訓にwhen/howフィールドが欠落している69件を補完する。when/howがないと教訓注入時のタスク特性マッチングが効かず、注入精度が低下する | infra | 05-15 | — |
| cmd_2792 | dashboard_auto_section.shのCI取得ロジックがcheck failedと表示するが、gh run list直近5件は全てsuccess。表示と実態の乖離原因を特定する | infra | 05-15 | dashboardのCI check failed表示は、l |
| cmd_2790 | deploy_task.shが全ACにbinary_checksスタブを注入するため、担当外ACにもbc:noが入りverdictがFAILになる(WA 10回)。task YAMLにac_assigned追加→担当ACのみスタブ生成に限定する | infra | 05-16 | inject_ac_assigned_from_stk()を |
| cmd_2793 | gate_lesson_health.shのawkがdetailフィールド内のenforcement:テキストを誤抽出しPHANTOM偽陽性4件を生んでいる。修正後、同スクリプトを参照するSKILL.md 3件を最新動作に追従更新し、3セッション連続BLOCK(gate_skill_script_refs.sh)を解消する | infra | 05-16 | gate_lesson_health.shのPHANTOM抽 |
| cmd_2794 | deploy_task.sh L3705のtag fallbackパスがeffectiveness除外(L3740)より前に実行されるため、useful率0%の教訓10件が除外されずに注入され続けている。fallbackパスにもeffectiveness除外を適用し、忍者CTX約295tok/タスク削減する | infra | 05-16 | 停止指示によりFAIL報告。cmd前提のfallback e |
| cmd_2795 | useful率0%の教訓10件がeffectiveness除外を通過して注入され続けている。cmd_2794でfallbackパスの除外漏れと推定したが、家老の現物確認でfallbackパスには除外が実装済みと判明。真因を特定するためdeploy_task.shのstderrログを分析し、10件がどの経路で注入されているかを特定する | infra | 05-16 | stderrログ確認で、still-injected 10件 |
| cmd_2796 | codd.yamlのsource_dirs(src/)が存在せず、doc_dirs(docs/)が研究ノート613件を設計書として取り込みhealth_score=0(662 errors)。source_dirsをscripts/に、doc_dirsをcodd/配下のみに修正し、codd measureのhealth_scoreを正常化する | infra | 05-16 | codd/codd.yamlのscan対象をscripts/ |
| cmd_2797 | gate_context_freshness.shがALERT時に毎回ntfy送信するが、ninja_monitorが5分間隔で実行するためcontextが古いまま5分ごとに同じALERTが殿に送信されrate limitに到達した。同一ALERTの重複送信を抑止する | infra | 05-16 | gate_context_freshness.shの同一AL |
| cmd_2798 | gate_context_freshness.shが安定context(軍師分析索引/設計ガイド/完成済み知見等)に14日ルールを一律適用し20件以上のALERTを出し続ける。安定contextを除外リストで管理し鮮度チェック対象から外す。cmd_2797(重複抑止)は安全網として維持 | infra | 05-16 | context鮮度チェックに除外リストファイルを導入し、安定 |
| cmd_2800 | report_field_set.shがself_gate_checkにPASS/FAILをトップレベルscalarで書くとdict構造がscalarに上書きされgate FAILを引き起こす。全忍者で22件発生(kagemaru25/hayate16/saizo15)。dot notation必須化でdict構造を保護する | infra | 05-16 | self_gate_checkのトップレベルscalar書込 |
| cmd_2799 | deploy_task.shが更新されたがskills/karo-direct/SKILL.mdが追従していない。gate_skill_script_refs.shが3セッション連続WARNでstartup BLOCK昇格。SKILL.mdの記述をdeploy_task.shの現在の動作に合わせて更新する | infra | 05-16 | skills/karo-direct/SKILL.mdをde |
| cmd_2802 | scripts/gates/*.sh変更時にtest_selectがそのgateを呼ぶ上位テスト(test_cmd_complete_gate.bats等)を選出しない。cmd_2798でgate_context_freshness.sh変更→test_context_freshness_check.batsのみ実行→test_cmd_complete_gate.batsのテスト28漏れ→CI RED。gate→消費先テストの間接依存マッピングを追加する | infra | 05-16 | scripts/gates/*.sh変更時にcmd_comp |
| cmd_2808 | ntfy.shにbackoff/cooldownがなく本日778回429エラー(殿通知ほぼ全失敗)。cmd_2797は1送信元の部分対策。新送信元追加で再発する構造。ntfy.shにグローバルthrottle(10s間隔+429時60s cooldown)を追加し全送信元を一括保護する | infra | 05-16 | ntfy.shに10秒グローバルthrottleとHTTP |
| cmd_2807 | cmd_2801の_sv()修正後にinject_ninja_weak_pointsがkagemaru+hanzoで連続YAML注入失敗(各2回)。配備自体は成功(weak_pointsはオプショナル)だがsilent failure可視化(cmd_2801で追加)がERRORを検出。_sv()修正の副作用か別の原因かを特定し修正する | infra | 05-16 | inject_ninja_weak_pointsの連続YAM |
| cmd_2809 | 前セッションのcmd_2801/2802/2808がスクリプト4本を変更したがSKILL.md未更新。3セッション連続WARNの根因はcmd_complete_gateにSKILL.md追従チェックが未組込み(事後検知のみで事前強制なし)。 | infra | 05-16 | SKILL.md script参照WARN 6件を追従更新し |
| cmd_2810 | cmd_complete_gate.sh L3650のauto_draft_lesson.shがdraft教訓を生成した直後に、L4843のdraft教訓チェックが自cmdが生成したdraftをBLOCKする循環構造。直近50cmdで19件BLOCK(最頻パターン)。 | infra | 05-16 | — |
| cmd_2812 | PC受信画面とスタンドアロン版のOCRエンジンドロップダウンのselected属性がgoogle側についており、UIデフォルトがGoogle Visionになっている。バックエンドはtwo_stageがデフォルトだがフロントが不整合。 | simple-ocr | 05-16 | PC受信画面とスタンドアロン版のOCRエンジンドロップダウン |
| cmd_2813 | OCR結果カードのタイトルがOCR結果とハードコードされている。two_stageパイプラインはpatient_nameを構造化JSONで出力済みなので、タイトルに患者名を表示する。テキスト本文からは消さない。 | simple-ocr | 05-16 | OCR結果カードのタイトルにtwo_stage抽出の患者名を |
| cmd_2814 | clear_prep_check.sh Check 8がWARN表示のみでALERT昇格しない。insights 5件放置/semantic-index未更新/BLOCK経験ありlesson 0件が/clear時に素通りし、次の将軍が今セッションの学びを持てない。なぜなぜ7回で確認と対処の未分離が根因。最終防衛線を強化する。 | infra | 05-17 | clear_prep_check.shで知識埋込み漏れ3条件 |
| cmd_2815 | gate_shogun_startup.sh Gate 13が教訓健全度ALERTを一律'/lesson-sort推奨'とするが、useful_rate<30%は/lesson-sortで解決しない。3セッション連続BLOCKの根因。ALERT種別(useful_rate vs 未振り分け)を判別し適切な推奨を表示するよう条件分岐を追加する。 | infra | 05-17 | Gate 13の教訓健全度ALERTをuseful_rate |
| cmd_2817 | binary_checks_fail FAILが直近50件中7件。ashigaru.md L52にルールはあるが具体的YAML記入例がなく忍者が形式を間違える。記入例追加で忍者の報告作成時の行動フローをFAIL→PASSに変換する。 | infra | 05-17 | AC1は完了。AC2は指定ID INS-20260516-1 |
| cmd_2818 | /clear後の将軍が各ルールの因果チェーン(何の実験→何の失敗→殿のどの裁定→ルール化)を持たないため、外部記事1本で安易に棚卸しを提案した。根因=時系列×因果のネットワークが環境に永続化されていない。Obsidian式[[リンク]]で既存lessons/senkyoku-logに因果辺を埋込み、逆引きCLIで任意ノードの前後を辿れるようにする。 | infra | 05-17 | 将軍教訓26件にoriginリンクを追加し、逆引きCLIとl |
| cmd_2822 | 因果ネットワーク活用の第二出口。deploy_task.shが忍者タスクYAMLに関連因果[[リンク]]を自動注入する。忍者が実装時に関連する過去の失敗/裁定を参照でき、同じ失敗の再発を防ぐ。 | infra | 05-17 | deploy_task.shにinject_causal_l |
| cmd_2821 | 因果ネットワーク活用の出口。lessons_shogun.yamlのエントリでoriginフィールドが空またはリンク0件のものを起動時にWARN表示し、因果不明ルールを可視化する。将軍が因果を埋める行動を促す。 | infra | 05-17 | gate_shogun_startupにlessons_sh |
| cmd_2823 | 因果ネットワーク(Obsidian [[リンク]]+origin)の仕組み知識が将軍の頭の中にしかない。家老・軍師・忍者は存在を知らず利用できない。使えないものは存在しないのと同じ(殿厳命)。CLAUDE.md Knowledge Map+各ロールinstructionsに因果NW利用手順を埋込み、全エージェントが自動化活用できる状態にする。 | infra | 05-17 | 因果ネットワークのorigin/Obsidianリンク手順を |
| cmd_2824 | 将軍がRenderのプラン挙動を知らずコールドスタート推測を繰り返す(殿指摘2026-05-17)。根因=Render知識がcontext/instructionsに体系化されていない。プラン別挙動(Free=コールドスタート/Starter=なし)、ログ取得方法、障害切り分け手順、全サービス一覧をcontext/infrastructure.mdに追記し、全エージェントが考えずに利用できる状態にする。 | infra | 05-17 | context/infrastructure.mdにRend |
| cmd_2826 | 将軍が殿の質問に答える前にセマンティック辞書/Obsidianリンクを検索しない(意志依存)。Render障害でコールドスタート推測を繰り返した根因。prompt_state_inject.sh(UserPromptSubmit hook)に殿の入力テキストでsemantic_search.shを自動実行し、関連知識を将軍のコンテキストに自動注入する。 | infra | 05-17 | prompt_state_inject.shが殿入力をsem |
| cmd_2827 | deploy_task.shがqueue/reports/の全ファイルを処理するため、241件蓄積でtimeout発生しnudge未送信。GPT忍者3名がプロンプト待ちで停止した(2026-05-17 20:34事故)。根因はarchive_completed.sh L948のCMD_IDガード。GATE CLEAR時(CMD_ID指定)にoverflow cap(=10)が発火せず蓄積が止まらない。ガード撤去でGATE CLEARごとにcap超過分を自動アーカイブする。 | infra | 05-17 | archive_completed.shのCMD_ID指定時 |
| cmd_2828 | 因果ネットワークのリンク追加が意志依存。context/memoryファイル作成時に因果リンクセクションが書かれず孤立ノードが増加しネットワークが成長しない。pre-write-edit-combined.shに検出ロジックを追加し、リンク記載を構造的に促す。 | infra | 05-17 | — |
| cmd_2829 | gate_lesson_health.shとdeploy_task.shが更新されたがSKILL.md 3件が未追従。startup gateで3セッション連続WARNが出ており解消が必要。cmd_2809と同パターンの定型追従作業。 | infra | 05-17 | SKILL.md script参照の追従WARNを解消し、g |
| cmd_2830 | deploy_task.shのnudge送信(safe_inbox_write L6379)がスクリプト末尾に配置されており、途中kill/timeoutでnudge未到達が無音で発生する。2026-05-17 20:34事故でGPT忍者3名がプロンプト待ちで停止した直接原因。trap EXITでnudge送信を保証し、スクリプト中断時も忍者に通知が届く構造にする。 | infra | 05-17 | deploy_task.shにEXIT trap nudge |
| cmd_2831 | check_ac_phase_mixing(L4280)がAC内のファイル名(例: 配備スクリプト名)に含まれるキーワードを配備アクションと誤検出し偽陽性BLOCKを発生させる。12回累計昇格済み。awk関数check_buf内でファイルパスパターンを除去してからキーワードマッチすることで偽陽性を排除する。 | infra | 05-17 | check_ac_phase_mixingのファイル名由来d |
| cmd_2832 | 軍師分析(掲示板blt_20260517_212058)で検出された残り3件の構造的弱点を修正する。(P1)内部timeout保護なし→外部bash timeoutに依存で中断制御が不完全。(P1)post-deploy verify(L6404付近)がlog出力のみでリトライなし→形骸化。(P2)gawk全忍者分読込み(L1620)→対象忍者のレポートのみに限定しI/O削減。 | infra | 05-17 | deploy_task.shに内部deadline、実効po |
| cmd_2834 | WARN累計昇格がBLOCK全体の15%(227件/1485件)を占め、将軍のcmd起票速度を構造的に阻害している。ac_phase_mixing(39件)はcmd_2831+2833で対処済みだが残6チェック(累計20-27件のWARN昇格BLOCK)の偽陽性パターンが未特定。対象チェック名リストはcmd_design_quality.yamlのBLOCK集計TOP6参照。各チェック関数のロジックを精読し偽陽性の発火条件・再現手順・修正方針を特定する。 | infra | 05-17 | cmd_save.shのWARN累計昇格TOP候補を精読し、 |
| cmd_2836 | 教訓健全度ALERT(useful_rate=28.1%)が3セッション連続。家老分析で不参照TOP4(L500/L078/L585/L101)が特定済み。根因はL500/L585/L078にuniversalタグが付与されており全タスクに注入されるが内容は超限定的(特定関数/特定パス)。universalタグを具体的なファイル/機能タグに変更しノイズ注入を削減する。 | infra | 05-17 | L500/L585/L078/L101の教訓タグを内容に合う |
| cmd_2837 | cmd_2834偵察で特定された6チェック関数の偽陽性パターンを修正する。(1)GS/WFツール検出:偵察/分析cmdを除外 (2)否定的前提claim:検査対象をclaim限定 (3)AC基準チェック:infra/偵察を除外 (4)q11既存代替:q5/assumptionsのrg結果も補助認定 (5)q8縮小表現:非破壊/スコープ限定文脈を除外 (6)行動変換:偵察/分析を除外+同義語追加。累計昇格BLOCK 227件(15%)の構造的解消。 | infra | 05-17 | cmd_save.shの6チェック関数にcmd_2834偵察 |
| cmd_2835 | 家老のidle自走分析(掲示板blt_20260517_203516)で特定された忍者報告品質の構造的改善3件。(1)report_format FAIL 11件/50cmd→ashigaru-procedures.mdにRFS再実行手順を先頭固定化。(2)binary_checks FAIL 7件→ashigaru.mdにbc yes/no記入例付き強調。(3)purpose_validation不一致 3件→ashigaru.mdにcmd目的との差分確認を明記。全てドキュメント追記のみで新仕組みゼロ。 | infra | 05-17 | cmd_2835の忍者報告品質改善3件は正本に反映済み。現物 |
| cmd_2838 | dashboard_update.shがdashboard_template.mdの必須セクションをdashboard.mdに照合するが、テンプレートが古く3セクション不一致(進行中=欠落/調査結果=欠落/要対応=絵文字不一致)でFAIL率22%(11/50)。テンプレートをdashboard.mdの現行構造に同期する。 | infra | 05-17 | dashboard_template.mdのKAROセクショ |
| cmd_2839 | cmd_2837のcheck_research_tool_explicit FP修正で除外条件が広すぎ、テスト556(RTE-T004: wf_engine参照は従来通りWF警告する)がFAIL。正当なWF警告が消された。除外条件を偵察/分析文脈に限定し正当WARNを復活させる。 | infra | 05-17 | cmd_2839対象のcheck_research_tool |
| cmd_2841 | gate_report_format_main.pyがassumption_invalidationのaffected_cmdsを必須検証するが、RFS(report_field_set.sh)経由で書き込む際にaffected_cmdsが欠落し39件FAILが発生。テンプレート(L1883-1886)にはデフォルト値があるがRFS書込みで上書きされる際にサブフィールドが消える。RFSのassumption_invalidation書込みでaffected_cmdsを保持する修正を行う。 | infra | 05-17 | RFSのassumption_invalidation.*書 |
| cmd_2845 | cmd_2840でlesson_write.shにorigin引数を追加し新規教訓は自動でorigin付与されるようになった。だが既存軍師教訓33件はorigin=0件のまま。因果NWの既存ノードにリンクを遡及追加しネットワーク密度を即時向上させる。 | infra | 05-18 | projects/infra/lessons_gunshi. |
| cmd_2844 | cmd_2840でlesson_write.sh(軍師共通)にorigin引数を追加した。残り2件: (1)gate_lesson_health.shに教訓originフィールド欠落時のWARN追加(将軍教訓にはcmd_2821で実装済み→同パターン転用)。(2)lesson_write_karo.sh(家老専用)にも--origin引数追加。因果NW自動成長の対象を全ロールに拡大する。 | infra | 05-18 | cmd_2844のorigin全ロール拡大を実装済みとして確 |
| cmd_2846 | autofix提案が忍者未読ファイルを対象に+既存gateで解決済み問題を提案する二重無効状態を解消。INSIGHT_REPEAT action_required蓄積の根因 | infra | 05-18 | gate_autofix_proposalで未読target |
| cmd_2849 | 偵察cmd_2848で特定された根因を修正。GATE BLOCK時にlesson_write --status draftで自動生成されたdraftが、同一cmdの後続GATEでCRITICAL BLOCKされる自己循環(19件中15件=78.9%)を解消 | infra | 05-18 | GATE自動生成draftへgate_auto_draftマ |
| cmd_2850_cancelled | — | — | 05-18 | — |
| cmd_2850 | CoDDで生成した設計書15件に基づきkj-role-countアプリ全体を実装する。忍者6名並列配備で一括完成 | kj-role-count | 05-18 | — |
| cmd_2851 | cmd_save.shのWARN累計昇格がproject=infraの累計を外部PJ(kj-role-count等)のcmdに適用し誤BLOCKする。累計カウントをproject別にスコープ分離し、外部PJのcmdもcmd_save.shを正規に通せるようにする | infra | 05-18 | cmd_save.shのWARN累計昇格をproject別に |
| cmd_2852 | deploy_task.shのinject_context_hints(L2826)/inject_production_invariants(L2882)内のsed -iが変数展開時に特殊文字で壊れ、set -euo pipefailでexit 1→nudge未送信になる問題を修正する。全cmd配備に影響中 | infra | 05-19 | deploy_task.shのinject_context_ |
| cmd_2853 | 殿の5要望を一括修正する。(1)入力画面にrole=admin非表示 (2)常勤/パート色分けを集計BarChart+管理画面+カレンダー詳細に統一 (3)DatePicker shiftDateのtoISOString UTCバグ修正(右矢印無反応+左矢印2日戻る) (4)カレンダーセル縦幅拡大(5名表示) (5)管理画面ロール追加/切替のpin_auth→pinフィールド名修正 | kj-role-count | 05-19 | 殿の5要望を実装し、admin非表示・常勤/パート色分け統一 |
| cmd_2854 | cmd_save.shの2つの問題を修正する。(1)殿発言検索+cmd履歴検索の全走査で16秒に低下。キャッシュまたは件数制限で高速化 (2)sourceに絶対パスを書くとPROJECT_WDと二重結合されファイル不在BLOCKになるバグ。絶対パス検出時はPROJECT_WD結合をスキップ | infra | 05-19 | cmd_save.shのquality log検索を直近50 |
| cmd_2856 | 運用YAMLの肥大化を書込み時に自動制御する汎用機構を構築する。各書込みスクリプトが追記後にwc -l > 閾値なら即アーカイブ退避し、索引層を常に小さく保つ。startup gateやcronではなく書込み時に実行することで待機時間ゼロ | infra | 05-19 | yaml_auto_archive.shをcmd_save. |
| cmd_2859 | startup gateで3セッション連続WARN。9件のSKILL.mdが参照scriptより古い。scriptの最新動作をSKILL.mdに反映する | infra | 05-19 | 8件のSKILL.mdに各scriptの最新動作を反映。ga |
| cmd_2862 | gate_report_format FAILが直近でも発生(2026-05-19)。根因=忍者がEdit toolで報告YAMLを直接編集しフィールドをstr化/MISSING化する。report_field_set.sh経由なら型ガードが効くが直接Editを阻止する仕組みがない。PreToolUse hookで報告YAML直接Editを検出しBLOCKする | infra | 05-19 | — |
| cmd_2863 | 本セッションでcmd_2857(self_gate_check既存)とcmd_2862(Guard 3既存)の車輪再発明が2回発生。根因=将軍のgrep検索キーワード不足で既存Guardを見落とし。cmd_save.shがhook/gate変更cmd検出時に対象ファイルのGuard一覧を自動抽出し表示することで、grepキーワード精度に依存しない確認を強制する | infra | 05-19 | cmd_save.shのq11でgate/hook変更cmd |
| cmd_2864 | 教訓健全度ALERT 3セッション連続。根因分析: fb>=3の全77件がuseful=0%。deploy_task.sh L3953の`if score > 0`でcontent1回マッチ(score=1)でも注入される。汎用キーワード(修正/実装等)が広くマッチし無関係教訓を量産。MIN_KEYWORD_SCORE変数を導入しscore>=2に引き上げ、弱いマッチを除外する | infra | 05-19 | MIN_KEYWORD_SCORE=2をdeploy_tas |
| cmd_2871 | 軍師提案。verdictはbinary_checksから常に導出可能な計算値(ALL yes→PASS, else FAIL)。独立フィールドとして存在すること自体が矛盾の温床でGP-072c2-c5の4層防御が必要になっている。gate_report_format.shでverdictをbcから自動計算し上書きすることで、verdict関連FAIL/workaround/修正サイクルを構造的に消滅させる | infra | 05-19 | gate_report_format.shでverdictを |
| cmd_2869 | 成長ループ第2段[E]。cmd_save.sh q11の既存代替確認がgrep単独で車輪を見逃す(cmd_2857/2862/2863の3連続車輪)。semantic_search.sh(因果辺トラバース付き=cmd_2866)をq11チェックに統合し、概念レベルで関連cmdを自動発見する | infra | 05-19 | cmd_save.sh q11にsemantic_searc |
| cmd_2870 | 成長ループ第3段[F]。セマンティック辞書のresourcesはリポジトリ内ファイルのみ。GitHub/Zenn/外部記事等のURLをresourcesとして格納可能にし、外部知識と内部因果辺を接続する。コリ先生OpenPBX等の外部リポが辞書から到達可能になる | infra | 05-19 | semantic-index resourcesにurl種別 |
| cmd_2868 | cmd_2866(因果辺トラバース統合)で概念拡張検索が動くが、トラバース結果の有用性が計測されない。lesson_impact.tsvにtraversal_depth列(直接マッチ=0, 1ホップ=1, 2ホップ=2)を追加し、depth別のuseful率を分析可能にする。成長ループの[D]精度計測を閉じる | infra | 05-19 | lesson_impact.tsvにtraversal_de |
| cmd_2867 | Obsidian×セマンティック統合パイプライン(cmd_2866)の成長ループを閉じる。因果辺(origin [[リンク]])が毎日追加されるが辞書更新と概念発見が手動。lesson_write/cmd完了時にsemantic_map_generate.sh自動実行+未登録[[リンク]]ターゲット検出→insight_write自動通知で、使うほど辞書が賢くなる免疫系ループを構築する | infra | 05-19 | semantic_index_updateがoriginの[ |
| cmd_2866 | Obsidian因果辺(origin [[リンク]])とセマンティック辞書とcausal_backlinks.shが独立して動いている。semantic_search.shに因果辺トラバースを統合し、概念マッチ→因果辺拡張→関連resourcesを一括返却するパイプラインを構築する | infra | 05-19 | semantic_search.shに因果辺トラバースを統合 |
| cmd_2865 | なぜなぜ7回の真因=教訓注入の計測基盤不在。deploy_task.shが教訓注入時のkeyword scoreを記録せず、score帯別のuseful率分析が不可能。score列をlesson_impact.tsvに追加し、改善サイクルの因果追跡を可能にする | infra | 05-19 | lesson_impact.tsvにscore列を追加し、教 |
| cmd_2873 | デーモン重複実行が頻出(本セッション: ninja_monitor 3重、inbox_watcher全員2重)。根因=統一管理層不在。restart_watchers.shはwatcherのみ管轄でninja_monitor/ntfy_listenerは対象外。全デーモンを統一管理するdaemon_supervisor.shを作成し、プロセス数チェック+重複停止+ヘルスチェック+自動再起動+ntfy通知を一括実行する | infra | 05-19 | daemon_supervisor.shを追加し、inbox |
| cmd_2872 | 本セッションでreview_log 0バイト破壊事故。根因=cmd_complete_gate.shのnohup+disown並行実行時に共有ファイル(review_log/dashboard.md等)書込みにflockなし。全共有ファイル書込みにflock追加し並行安全性を構造保証する | infra | 05-19 | cmd_complete_gate.shの共有ファイル直接書 |
| cmd_2874 | 殿指示「辞書の育成をやろう」。Phase 1(cmd_2860-2867)でaliases追加+自動成長ループ構築済み。Phase 2=品質向上: (1)noise aliases除去(task notification文字列やtool-use-id等の非意味的文字列がlord_conversation自動取込で混入) (2)未カバードメイン概念追加(修行サイクル/デーモン管理/外部PJ群/報告品質) (3)aliases精度向上(自然言語バリエーション追加) | infra | 05-19 | semantic index Phase 2としてnoise |
| cmd_2875 | semantic_search(cmd_2869)は概念レベル検索を実現したが、因果辺トラバース(causal_backlinks.sh)は未統合。道具はあるが使う仕組みに埋め込まれていない=意志依存。cmd起票時にq11のsemantic_search結果と合わせてcausal_backlinksの結果も自動表示し、関連cmd/教訓の因果辺を起票前に強制提示する | infra | 05-19 | cmd_save.shのq11 semantic_searc |
| cmd_2878 | 報告YAMLのorigin付与率が1.2%(61/4938)。根因=gate_report_format.shとreport_field_set.shにorigin関連チェックがゼロ(grep確認済み)。Level 1(ドキュメント記載のみ)→Level 5(gate強制+書込み支援)に昇格し、因果ネットワークの成長速度を構造的に加速する | infra | 05-19 | cmd_2878: gate_report_formatのo |
| cmd_2881 | startup gate BLOCK 3セッション連続。dashboard-update FAIL率16%(8/50)だがskill_execution_logにFAIL 1件のみ。ログ乖離の有無を含め根因を特定し対処方針を出す | infra | 05-19 | dashboard-update Gate20 8/50は実 |
| cmd_2882 | cmd_2881偵察で判明: dashboard-update FAIL率16%(8/50)は全てcmd_test_*6件+誤呼出し2件。実運用FAILゼロ。分母からテスト用cmdを除外し3セッション連続startup BLOCKを解消する | infra | 05-19 | Gate20のskill FAIL率でcmd_test_*と |
| cmd_2884 | 教訓健全度ALERT(useful_rate=16.7%)の根因=フィードバック記録率17%(参照36→記録6)。注入教訓のうち参照したがフィードバック未記録分を自動的にnot_usefulとして記録し、effectiveness_scoreの分母を正常化する | infra | 05-19 | record_lesson_feedback.shに未記載の |
| cmd_2885 | Obsidian [[リンク]]1597あるが大半が静的deepdive参照。cmd間因果辺が成長しない根因=origin記入(入口)はあるがsemantic-map還流(出口)がない。GATE CLEAR時にorigin+depends_onから因果辺を自動追記し、cmd数に比例してNWを成長させる | infra | 05-19 | GATE CLEAR時のsemantic index更新pa |
| cmd_2887 | 前セッションでscope/context stale残存が2件連続FAIL(cmd_2875+cmd_2880)。家老がLK-A02 v7で修正済みだがテスト未追加。再発防止テストを追加する | infra | 05-19 | reset_stale_fieldsのscope/conte |
| cmd_2888 | ac_phase_mixing等のgate FPが今セッション6回BLOCK。高FP gateを自動検出し修正候補を提案する仕組みで、gate品質の学習速度を最大化する | infra | 05-19 | Gate 13.8のFP率計算を独立スクリプト化し、閾値超g |
| cmd_2891 | CoDD台帳の最終更新が5/15で17日間停滞。修行サイクルにCoDD速度改善ラウンドを追加し、idle忍者にCoDD refactorを自動配備+軍師レビューで品質担保。インフラ最適化と忍者成長を同時に回す | infra | 05-19 | context/training-cycle.mdにCoDD |
| cmd_2892 | 196ファイル1766テストが蓄積。追加のみで淘汰なし。殿の3問検証(リグレッション検出実績/変更頻度/維持コスト)で低価値テストを特定し統合/削除方針を出す | infra | 05-19 | unit 196ファイル/現状1765テストを3問基準で棚卸 |
| cmd_2893 | cmd_2892偵察で低価値テスト10ファイル(削除4+統合6)を特定。790行削減+10ファイル削減でCI保守コストを下げる | infra | 05-19 | 低価値bats 10ファイルを4削除+6統合し、unitファ |
| cmd_2894 | cmd_2892偵察の10件は5%。196ファイル中62ファイル(32%)が1-3テストの小ファイルで同一スクリプトのテストが分散。スクリプト単位で統合し196→推定130ファイルに圧縮する | infra | 05-19 | 1-3件の小規模Bats 51ファイルを6本のスクリプト単位 |
| cmd_2895 | テスト196ファイル蓄積の根因=追加時にファイル粒度ガイドラインなし。追加test_*.bats作成時に同一対象スクリプトの既存テストファイルを検出→統合を促しファイル肥大化を構造的に防止する | infra | 05-19 | pre-commitで新規tests/unit/test_* |
| cmd_2897 | ac_phase_mixing FP率100%(3/3)。commitは忍者の通常完了動作であり実装ACに書くのが自然。deliveryキーワードからcommit/コミットを除外し偽陽性を根絶する | infra | 05-20 | cmd_save.shのAC phase mixing de |
| cmd_2898 | 将軍がcmd_save BLOCK後にフリーズする根因=どの行のどのキーワードがBLOCKを引き起こしたか不明で1箇所ずつ修正→再BLOCK→探す→修正の繰り返し。全BLOCK要因を一括表示し1回の修正で全解消できるようにする | infra | 05-20 | cmd_save.shのBLOCK/WARN終了サマリにチェ |
| cmd_2900 | gws CLIのGmail操作知識がcontext/infrastructure.mdに不足。auth statusが暗号化credentialsを検出できないバグがあり、将軍がログアウトと誤判断→殿に無駄なブラウザ認証を依頼した。実APIで確認すれば1秒で動くことを確認できた。知識不足が確認不足を招く構造を修正する | infra | 05-20 | context/infrastructure.md §gws |
| cmd_2902 | 因果NW成長が停止している根因=cmdのoriginフィールドが空/noneでもWARN止まりで通過する。causal_resource_rows()は実装済みだがorigin空では辺が生成されずsemantic_index還流が不発。originに[[リンク]]1つ以上を必須化しBLOCKで強制する | infra | 05-20 | origin空/none/リンクなしをBLOCKとして固定す |
| cmd_2903 | 掲示板が100件に膨張(open85件)。bulletin_archive.shがPython SyntaxErrorで動かない(L177-178のf-stringエスケープ漏れ)。真因=手動実行前提で自動パスがなくバグが放置された。構文修正+bulletin_write.shに閾値超過時の自動アーカイブ呼出しを追加し、掲示板肥大化を構造的に防止する | infra | 05-20 | bulletin_archive.shのSyntaxErro |
| cmd_2904 | Codex CLI忍者がidle時にsafe_send_clear()で無条件respawn-pane -kされ無限ループ(198回/今日)。根因=L754のcodex分岐がtask statusを確認せずidle/in_progress問わず一律respawn。idleならcodex /newで十分。respawnはin_progress時のみ必要。task status分岐を追加し無限ループを根絶する | infra | 05-20 | Codex idle+no_task時に_handle_au |
| cmd_2906 | cmd_2904がCodex+idle時にsafe_send_clearを呼ばない即returnを追加した結果、Codex忍者がidle時にCTXリセットされなくなった(GPT忍者3名のCTX蓄積中)。修正: (1)_handle_auto_clearの即returnを削除 (2)safe_send_clear内のCodex分岐でtask statusを確認し、idle/done→respawn分岐スキップ→clear_cmd=/new経路に落ちる。in_progress→respawn-pane -k維持 | infra | 05-20 | ninja_monitor.shのCodex idle時 / |
| cmd_2907 | cmd_2906でCodex idle時を/new経路に変更したが、Codex CLIが/newをtask in progressで拒否しCTXリセット不能。元のrespawn-pane -k経路に戻す | infra | 05-20 | Codex safe_send_clearのテスト期待値をr |
| cmd_2908 | cmd_save.sh/cmd_publish.sh BLOCK時にPostToolUse hookのGuard 0が発火せず、将軍がBLOCK後に停止する。根因はexit_code抽出jqがClaude Codeの実payload構造にマッチしないこと | infra | 05-20 | post-bash Guard 0がClaude Code実 |
| cmd_2910 | 因果辺のoriginノード名の68%がセマンティクスインデックス未登録。GATE CLEAR時にoriginノードをaliases照合し、未登録ノードをinsights.yamlにpending蓄積→概念自動成長を実現する | infra | 05-20 | cmd_complete originノードを専用にalia |
| cmd_2911 | lessons_karo.yamlが35件上限に到達し新規教訓追加がBLOCK。LK-A01にv8吸収(設計意図確認)とLK013(STALL再配備3点確認)をA系列に統合し件数を削減する | infra | 05-20 | LK-A01へv8設計意図確認を統合し、LK013をLK-A |
| cmd_2912 | insights.yamlに蓄積されたpending概念22件がセマンティクスインデックスに昇格されず手動待ち。類似概念スコア照合で既存概念のaliases自動拡張し、因果NWの到達性を自動的に拡大する | infra | 05-20 | pending semantic insightsを類似度ス |
| cmd_2915 | L7成長速度最大化のなぜなぜ7回→軍師検証で律速=aliases品質と判明。改善にはNO_MATCHの内容(purpose/target_path)が必要だが現在記録されていない。計測基盤を先に作り、データ駆動でaliases拡充する道具を整える | infra | 05-21 | HEAD既存のsemantic NO_MATCH記録を現物確 |
| cmd_2917 | deploy_task.shがexit 1で終了した場合、maybe_notify_draft_review(L6712)が成功パスにのみ存在するため軍師へのdraft_review通知が送信されない。EXIT trap(L323)にdraft_reviewフォールバックを追加し、配備失敗時も軍師レビューフローが途切れないようにする | infra | 05-21 | deploy_task.shのEXIT trapにdraft |
| cmd_2918 | L7現物確認でNO_MATCH率表示が家老gateのみで将軍gateにないことを発見。L7は将軍が管理するがL7健全度が起動時に見えない。家老gate(L181 show_semantic_no_match_metrics)と同じ計測セクションを将軍gateに追加する | infra | 05-21 | 将軍startup gateにセマンティックNO_MATCH |
| cmd_2919 | 殿のクエリがsemantic_searchを経由するが、NO_MATCH時の記録がない。L7の最重要消費者(殿)側の計測が盲点。NO_MATCHカウントのみ記録し(クエリ内容は非記録)、startup gateで可視化する | infra | 05-21 | prompt_state_injectのsemantic_s |
| cmd_2920 | L7成長速度の律速=aliases品質(軍師検証確定)。cmd_complete時にsemantic_index_update.shがpurposeからaliases候補を生成する基盤(L437 candidate_aliases)は既にあるが、NO_MATCH時の候補を既存概念のaliases拡充に使う経路がない。NO_MATCHログ(cmd_2915)のpurposeキーワードをpending aliasesに自動蓄積し、L7f(score閾値自動昇格)基盤でaliasesに自動追加する | infra | 05-21 | NO_MATCH purposeをpending alias |
| cmd_2921 | gate_skill_script_refs.shの3セッション連続WARNを解消する。5件全て現物確認済みでインタフェース変更なし | infra | 05-21 | gate_skill_script_refs.shのWARN |
| cmd_2922 | semantic_searchのヒット率を定量計測し、NO_MATCHデータをaliases自動成長パイプライン(cmd_2920)に流す道具を作る。軍師実測でヒット率45.7%、因果展開timeout誤判定バグも発見済み | infra | 05-21 | semantic_searchのalias層ヒット率を3入力 |
| cmd_2913 | cmd_2909のstartup gate表示は1回/セッション。家老がcmd受領時に毎回semantic_searchを実行し因果概念を表示することで消費頻度を大幅に向上させる | infra | 05-21 | cmd_2913は家老task_haltにより中止。軍師レビ |
| cmd_2923 | 既存Guard 0にinbox未読チェック追加+既存inbox_mark_read.shに対処引数必須化。既存cmd_save.sh Session Stateが自動でBLOCK履歴を蓄積し累計昇格する(自己改善ループは既存インフラに内蔵済み) | infra | 05-21 | — |
| cmd_2924 | cmd_2922(ストレステストツール本体)を3つの自動発火トリガーに接続する。軍師5W1H設計(blt_013243)に基づく。手動実行→自動組込みで意志依存をゼロにする | infra | 05-21 | L7 semantic stress testの3トリガー配 |
| cmd_2926 | idle忍者の修行ACに対象スクリプトの機能用途をaliases候補として提案するステップを追加。6忍者並列でaliases品質を加速。修行の成果がL7パイプラインに直結する | infra | 05-21 | context/training-cycle.mdのCoDD |
| cmd_2927 | index.mdにrelated_conceptsフィールド追加。semantic_search.shで1概念ヒット時に関連概念も注入。45概念の相互接続で配備時コンテキスト密度を倍増する | infra | 05-21 | semantic indexにrelated_concept |
| cmd_2925 | semantic_searchの道具は存在するが全ロールの手順に未記載。家老karo.md=0件、忍者ashigaru.md/CLAUDE.md=0件、軍師gunshi.md=レビュー時0件。Phase 4: 手順にないものは使われない。全ロールのinstructions/recovery手順にsemantic概念確認ステップを追加する | infra | 05-21 | cmd_2925は家老task_haltにより中止。軍師レビ |
| cmd_2928 | skill_auto_improve.shのreasonグルーピングがcmdID/ninjaID含みで同一根因が別パターン化。古いパターンのlast_failが更新されず14日カットオフで除外→Gate 20.7が12件中1件しか表示しない。グルーピングキーを正規化し、last_failを常時最新に更新する | infra | 05-21 | skill_auto_improveのFAIL reason |
| cmd_2931 | 教訓注入のuseful率7.1%(95注入中2有用)。現在のkeyword/tag/pathマッチは意味を理解しない。semantic_searchが既にdeploy_task.shで概念を検出しているため、概念にrelated_lessonsフィールドを追加し、検出された概念の教訓をスコアブーストで優先注入する | infra | 05-21 | semantic概念related_lessonsとdepl |
| cmd_2932 | 教訓健全度ALERT(useful_rate=16%)の根因修正。DM-Signal固有教訓(L510/L630/L594/L509/L097)がcross-project opt-inで全infra taskに漏洩→全件NOT_USEFUL。有効性0%教訓のauto-deprecated化+cross-project scoringにproject固有語比率フィルタを追加し、注入精度を改善する | infra | 05-21 | deploy_task.shのcross-project教訓 |
| cmd_2933 | assumptions_bulletin_count_grep_evidenceのFP率66%(2/3)を改善する。claimにblt_XXXX(掲示板ID)を含む場合は掲示板自体が検証済みソースであり、grep証跡不要。bulletin ID引用をgrep_evidence_patの許容パターンに追加する | infra | 05-21 | cmd_save.shのbulletin件数claim検証で |
| cmd_2935 | 殿が5/21 02:39にスクショで確認した事象: 1着信に対しnudge(inbox1)が2回送信される。既存のdebounce/dedup機構があるにもかかわらず二重送信が発生する根因を特定する | infra | 05-21 | 二重nudgeの根因は同一agentに複数のinbox_wa |
| cmd_2936 | 修行中の忍者がAC5で概念名付きaliases候補を提案する形式を設計し、parse_pending_semantic_insightsがその形式を認識→概念名で直接マッチ→similarity_score不要でauto-promote可能にする。修行6忍者並列で高品質aliases蓄積を加速する | infra | 05-21 | 修行AC5を概念名付きalias行へ更新し、直接昇格を検証す |
| cmd_2937 | cmd_2935偵察結果に基づく修正。根因=同一agentにinbox_watcher.shが2本以上常駐し同一イベントを並列処理。singleton lockでagent別1プロセスを保証し、debounce/fingerprint check+writeを同一flock内でatomic化する | infra | 05-21 | inbox_watcherのagent別singletonと |
| cmd_2938 | cmd_2936で修行AC5→auto-promote直結を実装したがPENDING_ALIAS_DIRECT=0件。なぜなぜ7回: (1)忍者のinsight_writeのsource引数が未指定→parse側フィルタ(L651 training含む)に不合致→スキップ (2)insight自体がinsights.yamlに残っていない(archiveに退避or書込失敗)。修正: 修行テンプレートにinsight_write source=training引数を明示+書込後のgrep検証ACを追加+parse側のsourceフィルタ緩和 | infra | 05-21 | DIRECT経路のtraining source alias |
| cmd_2941 | スキル自動成長エスカレーションが3セッション連続。report-writeスキルのFAIL理由 assumption_invalidation: is str (must be dict) がSKILL.md改良5回で未解消。根因はgate_report_format_main.py L154のdict型チェックに対し、report_field_set.shまたはテンプレートがstring型で生成している可能性。スクリプト側を修正し、assumption_invalidationが常にdict形式で出力されるようにする | infra | 05-21 | report_field_set.shのassumption |
| cmd_2942 | verdict-checkスキル自動成長が3セッション連続エスカレーション。binary_checks resultにyes/no以外(空/waive/PASS/FAIL)が混入しcmd_complete_gateがBLOCK。SKILL.md改良5回で未解消=忍者の意志依存。report_field_set.shにbinary_checks result値のバリデーション(yes/no以外をBLOCK)を追加し、不正値を構造的に排除する | infra | 05-21 | binary_checks resultのyes/noバリデ |
| cmd_2943 | dashboard-updateスキル自動成長が3セッション連続エスカレーション。dashboard_update.sh exit=1が複数cmd(cmd_2739/cmd_karo_test/cmd_2514等)で再発。SKILL.md改良5回で未解消=スクリプト側のエラーハンドリングまたはデータ前提にバグ。exit=1の根因を特定し修正する | infra | 05-21 | dashboard_update.shのreport探索をp |
| cmd_2945 | 教訓健全度ALERT(useful_rate=16.7%)が3セッション連続。根因: 忍者がreport YAMLでuseful:false/trueと記入しているが、lesson_impact.tsvにフィードバックが還流されていない(全件status=pending)。lesson_deprecation_scan.shが退役候補を検出できず、低useful教訓が永続注入される。cmd_complete_gate.shまたは完了処理フローでreport YAMLのlessons_useful→lesson_impact.tsvへの書戻しを修正する | infra | 05-21 | lesson_impact.tsvへlessons_usef |
| cmd_2944 | cmd-completeスキル自動成長が3セッション連続エスカレーション。2パターン: (1)lesson_done_missing=cmd_complete_gateがlesson reviewフラグ不在を検出 (2)ac_version_mismatch task=d41d8cd9(空ハッシュ)=karo_direct配備でタスクYAMLにac_version未設定。SKILL.md改良5回で未解消。スクリプト側でkaro_direct配備時のac_version自動補完+lesson_done検出ロジック修正 | infra | 05-21 | _compute_ac_hash()修正(check:フィー |
| cmd_2946 | cmd_2936でDIRECT経路を実装、cmd_2938でテスト21件PASSしたが、本番でPENDING_ALIAS_DIRECT昇格が0件。修行12回転(hayate4+kagemaru4+saizo4)でinsight蓄積されたがaliasesに昇格していない。テストは通るが本番で動かない=テストと本番の乖離。semantic_index_update.shのDIRECT昇格コードパスがなぜ本番で発火しないかを特定し修正する | infra | 05-21 | semantic_index_update.shのDIREC |
| cmd_2948 | 起動チェックでSKILL.md参照WARNが3セッション連続。scriptが更新されたがSKILL.mdが追従していない4件を更新し、スキル記述と実装の乖離を解消する | infra | 05-21 | SKILL.md 4件を現script仕様へ追従更新し、対象 |
| cmd_2949 | cmd_2947でYAML存在チェックを追加したが、kagemaru R9で再発(本セッション4件消失)。忍者のinbox_write(家老通知)完了前にclear発動する競合が残存。3条件(YAML存在+verdict存在+家老通知完了)に拡張して根絶する | infra | 05-21 | ninja_monitorのauto-clear repor |
| cmd_2950 | 修行がtarget_path未指定で全ラウンド実行されており、忍者が裁量でスクリプト選択→aliases薄概念が放置。deploy_task.shの修行配備時にaliases品質の低い概念のスクリプトを優先指定し、修行が自然にaliases品質を引き上げる仕組みにする | infra | 05-21 | aliases薄概念Top10を出す semantic_al |
| cmd_2951 | deploy_task.shが次ラウンド配備時に前ラウンドのGATE未完了のまま忍者に/clear送信し、報告YAMLが消失する(本セッション6件、GPT忍者18.5%/Sonnet5.6%)。配備前にpending report存在チェックを追加し、GATE完了まで配備をBLOCKする | infra | 05-21 | deploy_task.shが対象忍者のGATE未処理報告を |
| cmd_2952 | deploy_task.sh(cmd_2950/2951変更)+bulletin_write.sh変更がSKILL.md 5件に未反映。startup gate 3セッション連続WARN解消 | infra | 05-22 | SKILL.md 5件をbulletin_write.sh/ |
| cmd_2953 | 修行targetを[[リンク]]数昇順で選択し、孤立ファイルから順にリンクネットワークを育てる。現状944 mdファイル中88%が孤立。修行ACに[[リンク]]追加を組込み、Obsidianグラフを修行サイクルで自然に成長させる | infra | 05-22 | 修行targetをMarkdownリンク数昇順で選び、孤立M |
| cmd_2955 | cmd_2954設計変更(軍師REQUEST_CHANGES)。ファイル間直接リンクではなく概念名リンクのみ挿入。各resourcesファイルに所属概念名への[[概念名]]リンクを挿入し、概念をハブとするスター型ネットワークを構築 | infra | 05-22 | docs/semantic-index/index.mdから |
| cmd_2954 | index.mdの46概念×resourcesをパースし、同一概念内resources間+概念⇔resourcesの双方向[[リンク]]を自動挿入。孤立率88%を一括削減。殿直接指示 | infra | 05-22 | — |
| cmd_2957 | deploy_task.sh inject_direct_training_templateのAC2/AC5が概念名リンク(ハブ方式)を許容している。殿確定の分離原則(context/obsidian-link-principles.md)に準拠し、ファイル間直接リンク方式に修正する | infra | 05-22 | deploy_task.shのL4修行テンプレートをファイル |
| cmd_2959 | 参照scriptがSKILL.mdより新しい11ファイルを更新し、スキル指示とスクリプト実態の乖離を解消する | infra | 05-22 | SKILL.md 13件の参照script仕様追従を更新し、 |
| cmd_2960 | shutsujin_departure.sh L945が将軍watcherをASW_DISABLE_ESCALATION=1で起動し、GATE CLEAR通知が将軍に届かない。cmd_2403/2694で対症療法したが真因が残存。shutsujin側を修正し構造的に根絶する | infra | 05-22 | shutsujin_departure.shの将軍watch |
| cmd_2962 | 将軍がcmd起票時にsemantic_search.shを使っていない。grepでは既知キーワードしか探せず、関連概念の見落としが起きる。起票前hookに10問目を追加し、将軍が毎回semantic_searchを実行する構造にする | infra | 05-22 | Guard 0の起票前確認を10問へ更新し、semantic |
| cmd_2963 | lord_conversation.jsonlのアーカイブディレクトリは3月に作成済みだが退避処理が未実装で全セッションの対話が消失している。clear_prep_check.shに全文退避+知識抽出を追加し、長期記憶を構造的に保存する | infra | 05-22 | clear_prep_check.shにlord_conve |
| cmd_2964 | 全文記録(24MB/79日)とsemantic_search(0.3秒)は動いているが、セッション中に発見した知識がObsidianリンクやaliasesに整理されずに消えている。全ロールの/clear前処理と作業完了時に記憶整理Phaseを追加し、短期記憶→長期記憶の移行を構造的に強制する | infra | 05-22 | 全ロール記憶整理Phaseとしてclear_prep_che |
| cmd_2965 | 全文記録(lord_conversation_archive 24MB/79日分)がJSONLファイルで概念検索不能。SQLite(multi_agent_shogun_memory.db)に構造化して格納し、semantic_searchから到達可能にする。先にDBを作ることでLLMが外部DBに飛びつくパターンマッチを環境で封じる(殿裁定2026-05-22) | infra | 05-22 | SQLite記憶DBインポータを追加し、lord_conve |
| cmd_2966 | cmd_2965のconversationsテーブルは殿×将軍の対話のみ。殿は家老/軍師/忍者にも直接指示する。全ロールの全イベント(inbox/掲示板/gate/報告/insight)を統合するeventsテーブルに拡張し、conceptsカラムでsemantic_search照合結果を格納してObsidian/セマンティクスインデックスと連携する | infra | 05-22 | memory_db_init.shを追加し、eventsテー |
| cmd_2968 | 報告テンプレートのverdictフィールドにYAMLコメント付き空文字列が残存し、忍者がautofix前に保存するとverdict空でGATE BLOCKが発生(14件検出)。テンプレートからコメント行を除去し汚染を根絶する | infra | 05-22 | 報告テンプレートのverdict空値コメントを生成元から除去 |
| cmd_2970 | eventsテーブルのdetailをLIKE検索すると24MB全スキャン。FTS5仮想テーブルで全文検索を高速化し、parent_event_id(因果チェーン)とimportance(重要度)カラムを追加して検索品質と到達可能性を向上する | infra | 05-22 | events_fts(FTS5)をsummary/detai |
| cmd_2971 | deploy_task.sh/restart_watchers.sh変更後にSKILL.md 4件が未更新で3session連続WARNが発生。scriptの最新挙動をSKILL.mdに反映しgate判定をOKにする | infra | 05-22 | SKILL.md 4件を最新script挙動に追従し、gat |
| cmd_2972 | is_gate_or_hook_addition_cmd()がSKILL.md追従/DB拡張/semantic_search等の非gate追加cmdをgate追加と誤判定しFP率100%(3/3)。L299除外キーワードに追従/更新/拡張を追加し偽陽性を解消する | infra | 05-22 | is_gate_or_hook_addition_cmdの追 |
| cmd_2973 | dashboard-update/verdict-check/cmd-complete/report-writeの4スキルがSKILL.md改良5回超で効果なし。code_fix_requiredエスカレーション9件。各スキルのFAIL根因を特定し修正cmdの設計材料を作る | infra | 05-22 | 4スキルFAILは、dashboard_updateのrep |
| cmd_2974 | GPT忍者へのnudge自動到達率が0%(11/11手動)。deploy_task.shのEXIT trap内でnudgeが確実に送信されるよう修正し、配備後の自動到達を保証する | infra | 05-22 | deploy_task.shのEXIT nudge arm位 |
| cmd_2975 | CI並列実行時にflaky test 2件(T-005+AC4-2)が発生。テスト間の状態共有が根因。並列隔離で安定化する | infra | 05-22 | T-005とAC4-2の並列flaky要因をテストfixtu |
| cmd_2976 | memory_db_import.pyにFTS5+拡張列が実装済みだがDBが再構築されていない。再実行してDBスキーマを最新化する | infra | 05-22 | memory_db_import.pyを再実行し、data/ |
| cmd_2977 | eventsテーブルが全件conversation型。bulletin_board.yamlのエントリをevent_type=bulletinとして投入し、GATE CLEAR/家老報告/INSIGHT等の非会話イベントを検索可能にする | infra | 05-22 | memory_db_import.pyのbulletin投入 |
| cmd_2978 | insights.yamlの気づきエントリをevent_type=insightとして記憶DBに投入し、学習ループの気づきを検索可能にする | infra | 05-22 | insights.yamlをmemory DBのevents |
| cmd_2979 | eventsテーブルのconcepts列がJSON配列のTEXT格納で検索が遅い。event_concepts(event_id, concept_name)ジャンクションテーブルに正規化しJOINで高速検索+概念別集計を可能にする | infra | 05-22 | memory_db_import.pyにevent_conc |
| cmd_2981 | 記憶DBが手動実行でしか更新されない。clear_prep_check.shの記憶整理Phaseにmemory_db_import.py実行を追加し、毎/clear時にDBが自動再構築されるようにする | infra | 05-22 | clear_prep_checkの記憶整理Phaseでmem |
| cmd_2982 | append_lord_conversation()でJSONL書込み後にDBへもINSERTし、lord_conversation全イベントがリアルタイムでDBに蓄積されるようにする | infra | 05-22 | append_lord_conversation()のJSO |
| cmd_2984 | journal_mode=DELETEでリアルタイムINSERTと再構築が競合しdatabase locked発生。WALモードに変更し並行書込みを許可する。再構築もDROP+CREATEからINSERT OR REPLACEに変更し時間短縮 | infra | 05-22 | memory_db_import.pyのWAL再構築を確認し |
| cmd_2985 | inbox_write.shの全agent間通信(配備指示/報告完了/gate_clear/nudge)をevent_type=inboxとして記憶DBにリアルタイムINSERTする | infra | 05-22 | inbox_write.shのYAML永続化成功後にeven |
| cmd_2987 | 忍者の報告YAML書込み(report_field_set.sh)をevent_type=reportとして記憶DBにINSERTし、学習ループの成果(binary_checks/lesson_candidate)がDB検索可能になるようにする | infra | 05-22 | memory_db_live_insert.pyにrepor |
| cmd_2991 | cmd品質記録(cmd_design_quality.yaml)をevent_type=cmd_qualityとして記憶DBにリアルタイムINSERTし、gate FP/BLOCK分析がDB検索で即座に可能になるようにする | infra | 05-22 | cmd_design_qualityの品質記録をevent_ |
| cmd_2992 | memory_db_import.pyの/clear時再構築にskill_execution_log/完了cmd archive/pending_decisionsの3ソースを追加し、バッチ再構築時の網羅性を完成させる | infra | 05-22 | memory_db_import.pyのバッチ再構築にski |
| cmd_2995 | スクリプト内部変更(DB INSERT追加等)でもSKILL.md追従WARNが発火する偽陽性を解消する。3セッション連続BLOCK再発の構造的原因 | infra | 05-22 | script_refs_checked_at markerを |
| cmd_2997 | ルート直下の0バイト空DB削除と、eventsテーブルと完全重複するconversationsテーブル(27,154件同数)を整理する | infra | 05-22 | 0バイトDBを削除し、conversations実体テーブル |
| cmd_2998 | 日本語の長いクエリでFTS5検索がタイムアウト(10秒超)する問題を改善する | infra | 05-22 | semantic_search.shのmemory_db_s |
| cmd_3000 | Google Chrome公式のAIエージェント向けモダンWeb APIスキルを導入し、FE開発品質を向上させる | infra | 05-22 | Modern Web Guidanceを導入し、semant |
| cmd_3001 | 記憶DBのスキーマ+event_type分布+サンプル行をmemory_db_import.pyの--build後に自動生成し、LLMが自然言語→SQL変換できる基盤を構築する | infra | 05-22 | memory_db_import.pyのschema mar |
| cmd_3002 | memory_db_query.shにSELECT以外のSQL(DELETE/UPDATE/DROP等)をBLOCKするガードを追加し、記憶DBの安全な汎用クエリ実行を保証する | infra | 05-22 | memory_db_query.shにSELECT-only |
| cmd_3005 | 全PJ(dm-signal/infra/google-classroom/database/simple-ocr等)のドキュメントファイルを棚卸しし、記憶DBに投入すべき知識資産の全体像を把握する | infra | 05-22 | 全登録PJのmd/yaml/yml/txt/rstをフル走査 |
| cmd_3007 | 知識パスへのgrep実行を検知し、記憶DB検索結果を自動注入する。3層記憶を経由せずに行動する迂回路をふさぐ | infra | 05-22 | 知識パスgrep/rg検知時にmemory DB検索結果をa |
