# cmd_save.sh Gate設計思想カタログ

> cmd_3608 Phase 1 / recon1_front_half_29_functions  
> 作成者: hanzo / 作成日: 2026-06-30  
> 対象: `scripts/cmd_save.sh` check/gate系定義順の前半29件

> cmd_3609 Phase 1b / record_reason呼出し箇所ベース追加  
> 更新者: hanzo / 更新日: 2026-06-30  
> 対象: Phase 1aの名称フィルタで漏れた inline checks + 名称乖離 + 学習補助

## 0.0 Phase 1b 統合サマリー

| 母集団層 | 件数 | 範囲 | 根拠 |
|---|---:|---|---|
| A named funcs | 40 | Phase 1a 37件 + q helper 3件 | `rg -n "^(q[0-9]+_|check_|.*gate.*)\\(\\) \\{" scripts/cmd_save.sh` |
| B inline checks | 33 | `handle_cmd_save_exit` 内の概念チェック33件 | `record_*_reason` 35呼出しから `queue_file_missing` / `cmd_block_missing` 重複2組を概念統合 |
| C 名称乖離+学習補助 | 9 | `show_gunshi_pane_status` 6件 + exit/learning補助3件 | caller名が品質チェック名でないが `record_*_reason` を発火 |
| 合計 | 82 | A+B+C | 40+33+9=82 |

抽出実測: `record_block_reason` / `record_warn_reason` の定義本体を除く呼出しは83件。ログ基盤内部の caller 推定処理など非チェック行を除外し、重複呼出しは同一概念へ統合した。Phase 1aの37件は「check/gate名称関数」として正しいが、品質チェック機能の全量ではない。

## 0.1 Phase 2 処置サマリー（cmd_3612）

判定基準: `failure semantics` / `temporal position` / `side effect` / `fixture同一性` の4条件でA層とC-2を判定した。B層は構造上inlineのため関数化、C-1は関数名が実態と乖離しているため名称修正を処置とする。

| 処置 | 件数 | 対象 |
|---|---:|---|
| 統合 | 0 | 4条件が全一致し、originと診断粒度を失わず1関数化できるペアなし |
| 抽象化 | 16 | A層のうち判定ロジック・入力取得・正規表現だけを共通helper化できる項目 |
| 関数化 | 33 | B層inline checks全件 |
| 名称修正 | 6 | C-1 `show_gunshi_pane_status.*` の実態名化 |
| 保護 | 27 | A層+C-2のうちorigin/副作用/診断粒度を守るため触らない項目 |
| 合計 | 82 | カタログ総件数と一致 |

直接FP率制約: 現行 `logs/gate_fire_log.yaml` / `logs/cmd_design_quality.yaml` はcheck関数名単位のTP/FPラベルを保持しないため、Phase 2ではFP率を捏造しない。処置根拠は現物の副作用・時点・fixture差分と、既存のWARN/BLOCK理由文字列マッピングに限定する。

## 0. 抽出根拠

| 項目 | 実測値 | 根拠コマンド |
|---|---:|---|
| `scripts/cmd_save.sh` 行数 | 6200 | `wc -l scripts/cmd_save.sh` |
| 全bash関数定義 | 113 | `python3` 正規表現 `^name() {` |
| `check_` / `gate` 名称を含む関数定義 | 37 | 同上、`name.startswith("check_") or "gate" in name` |
| `check_` / `gate` / `qN` 系定義 | 40 | `rg -n "^(q[0-9]...|check_...|...gate...)\\(\\) \\{" scripts/cmd_save.sh` |
| 設計書記載値 | 58 | `docs/research/cmd_save_gate_catalog_design.md` AS-IS |

差分メモ: 設計書の「58 check関数」は現物の単純な関数定義抽出とは一致しない。現物では `check_` / `gate` 名称を含む関数定義が37件、`qN`補助を含めて40件、全bash関数が113件。半蔵担当の「前半29関数」は、家老追加指示に従い `check_` / `gate` 名称を含む37件の定義順1-29として扱う。数合わせの水増しは禁止されたため、インラインCheckや補助関数を恣意的に58へ合わせていない。

AC4制約: 軍師レビューと家老追認により、現行 `logs/gate_fire_log.yaml` / `logs/cmd_design_quality.yaml` から関数別FP率を直接算出することは禁止。現行ログはcheck関数名単位のTP/FPラベルを保持しない。ここではWARN/BLOCK理由文字列と `record_warn_reason` / `record_block_reason` の `check=` から根拠付き推定頻度を記録し、直接算出不可の項目は計測不能と明記する。

## 1. 全check/gate関数一覧

| # | line | function | 担当 |
|---:|---:|---|---|
| 1 | 338 | `is_gate_or_hook_addition_cmd` | hanzo |
| 2 | 421 | `is_gate_or_script_modification_cmd` | hanzo |
| 3 | 449 | `check_gate_script_execution_evidence` | hanzo |
| 4 | 666 | `check_gate_hook_action_conversion` | hanzo |
| 5 | 712 | `check_lord_30min_cost_question` | hanzo |
| 6 | 728 | `check_deferral_language_warn` | hanzo |
| 7 | 758 | `check_lord_instruction_ac_alignment_info` | hanzo |
| 8 | 1041 | `check_measurement_env_info` | hanzo |
| 9 | 1253 | `check_depends_on_field` | hanzo |
| 10 | 1273 | `check_origin_field` | hanzo |
| 11 | 1518 | `check_causal_verification_requirement` | hanzo |
| 12 | 1572 | `check_three_layer_penetration` | hanzo |
| 13 | 1620 | `check_self_reread_red_flag` | hanzo |
| 14 | 1636 | `check_bundle_red_flag` | hanzo |
| 15 | 3461 | `check_gunshi_analysis_overlap` | hanzo |
| 16 | 3501 | `check_pi_number_collision` | hanzo |
| 17 | 3612 | `check_ac_file_paths` | hanzo |
| 18 | 3688 | `check_cmd_text_pipe_danger` | hanzo |
| 19 | 3728 | `check_impl_push_ac` | hanzo |
| 20 | 3771 | `check_dm_signal_bare_layer_reference` | hanzo |
| 21 | 3821 | `check_ac_must_should_mix` | hanzo |
| 22 | 3848 | `check_research_tool_growth_ac` | hanzo |
| 23 | 4274 | `check_projects_yaml_forbidden_topics` | hanzo |
| 24 | 4345 | `check_content_duplicate` | hanzo |
| 25 | 4705 | `check_ac_param_sufficiency` | hanzo |
| 26 | 4750 | `check_param_space_against_results` | hanzo |
| 27 | 4968 | `check_param_space_shrink` | hanzo |
| 28 | 4996 | `check_gunshi_design_num_relax` | hanzo |
| 29 | 5092 | `check_action_immediate_verification` | hanzo |
| 30 | 5165 | `check_research_tool_explicit` | 後半担当 |
| 31 | 5612 | `check_timebox_minutes_required` | 後半担当 |
| 32 | 5663 | `check_ac_absolute_literals` | 後半担当 |
| 33 | 5706 | `check_db_backup_ac_warn` | 後半担当 |
| 34 | 5759 | `check_numeric_literal_derivation_source_info` | 後半担当 |
| 35 | 5789 | `check_ac_phase_mixing` | 後半担当 |
| 36 | 5863 | `check_ac_test_scope` | 後半担当 |
| 37 | 5978 | `check_new_file_structure_warning` | 後半担当 |

## 2. 前半29関数カタログ

| # | function | origin | 防御対象 | L0-L7 | 時点 | severity | 副作用 | 正例fixture | 負例fixture | 対応テスト | cmd_skeleton同期 | 性能コスト | FP率 | 教訓逆引き | 最終修正日 | hook参照パターン | origin因果リンク |
|---:|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `is_gate_or_hook_addition_cmd` | LS-A22(1), cmd_2279 | gate/hook追加cmdの分類 | L4 | preflight | classifier | stdoutなし | scout除外・対象外cmd | gate/hook追加語を含むcmd | `tests/unit/test_cmd_save_q5.bats`, `tests/unit/test_cmd_save_q11_fp_reduction.bats` | indirect | O(text grep) | 個別FP率未記録、LS-A22でFP既知 | LS-A22 | 2026-06-26 | なし | `[[cmd_2279]] -> [[SCOUT偽陽性]] -> [[gate追加分類]]` |
| 2 | `is_gate_or_script_modification_cmd` | cmd_3360 | script/gate修正cmdの分類 | L4 | preflight | classifier | stdoutなし | script/gate修正cmd | 実行証拠なしの修正cmd | `tests/unit/test_cmd_save_q5.bats` | indirect | O(text grep) | 個別FP率未記録 | LS063系 | 2026-06-26 | なし | `[[cmd_3360]] -> [[実行証拠不足]] -> [[gate_script分類]]` |
| 3 | `check_gate_script_execution_evidence` | cmd_3360 | grepだけでgate/script未実行判断する事故 | L4 | preflight | WARN | `record_warn_reason`, stderr/stdout | q5に実行コマンド・exit code・出力要点あり | q5がgrep/コード断片のみ | `tests/unit/test_cmd_save_q5.bats` | `scripts/cmd_skeleton.sh:110` | O(text grep) | 個別FP率未記録 | LS063/LS-A22 | 2026-06-30 | なし | `[[cmd_3360]] -> [[実行せず起票]] -> [[q5実行証拠WARN]]` |
| 4 | `check_gate_hook_action_conversion` | LS-A22(9) | gate/hook修正cmdで行動変換なし | L4 | preflight | BLOCK/WARN | `record_block_reason`, warn/log | guard重複確認・action変換あり | トリガー語引用だけのAC | `tests/unit/test_cmd_save.bats`, `tests/unit/test_cmd_save_qg_field_validation.bats`, `tests/unit/test_cmd_save_q11_fp_reduction.bats` | indirect | O(text grep + guard list) | 個別FP率未記録、LS-A22(9)既知 | LS-A22 | 2026-06-26 | なし | `[[gate_hook修正cmd]] -> [[行動変換不足]] -> [[guard重複確認]]` |
| 5 | `check_lord_30min_cost_question` | 殿裁定: 時間コスト確認 | 殿の30分消費を見積もらない起票 | L4 | preflight | WARN | `record_warn_reason`, stderr | 時間影響・短縮根拠あり | 30分以上相当の作業で未記載 | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | growth-loop | 2026-06-26 | なし | `[[殿時間コスト]] -> [[見積不足]] -> [[30分問い]]` |
| 6 | `check_deferral_language_warn` | LS-A22(10), cmd_3381 | 先送り表現・段階的逃げ | L4 | preflight | WARN | `record_warn_reason` | 即時検証・完了条件明記 | 「後で」「段階的」等のみ | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | LS-A22(10)でFP既知、2026-06-14除外修正 | LS-A22/LS062 | 2026-06-26 | なし | `[[先送り表現]] -> [[洗脳#5]] -> [[deferral WARN]]` |
| 7 | `check_lord_instruction_ac_alignment_info` | 殿指示-AC整合確認 | 殿指示とACのずれ | L5 | preflight | INFO/WARN | stdout info | 殿指示語とAC対応あり | 指示語がACに落ちていない | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | growth-loop | 2026-06-26 | なし | `[[殿指示]] -> [[AC変換漏れ]] -> [[alignment info]]` |
| 8 | `check_measurement_env_info` | growth-loop数値計測原則 | 計測環境・前提の未記載 | L5 | preflight | INFO/WARN | stdout info | 計測対象・環境・比較値あり | 数値だけで環境不明 | `tests/unit/test_cmd_save.bats`, `tests/test_cmd_save_check17_18_20_exit_gate.bats` | indirect | O(text grep) | 個別FP率未記録 | growth-loop | 2026-06-26 | なし | `[[計測なき行動]] -> [[比較不能]] -> [[measurement env info]]` |
| 9 | `check_depends_on_field` | cmd依存関係明示 | 前段cmd依存の消失 | L4 | save | WARN | `record_warn_reason` | `depends_on`がcmdまたはnone | depends_on欠落 | `tests/unit/test_cmd_save.bats`, `tests/unit/test_cmd_save_small_consolidated.bats` | indirect | O(YAML cache) | 個別FP率未記録 | AGENTS cmd_format | 2026-06-26 | なし | `[[前段cmd]] -> [[依存不明]] -> [[depends_on WARN]]` |
| 10 | `check_origin_field` | 因果ネットワーク | origin欠落による因果断絶 | L4 | save | WARN | `record_warn_reason`, default insert | originあり | origin欠落 | `tests/unit/test_cmd_save_origin.bats` | indirect | O(YAML cache) | 個別FP率未記録 | 因果リンク規則 | 2026-06-26 | なし | `[[cmd]] -> [[origin欠落]] -> [[因果ネットワーク断絶]]` |
| 11 | `check_causal_verification_requirement` | cmd_karo_impl_causal_verification_l0_l7_20260602 | 過去設計意図未確認でinfra変更 | L5 | preflight/save | WARN | `record_warn_reason`, q5 template表示 | git log/blame・教訓・設計意図記載 | infra/gate変更で因果確認空 | `tests/unit/test_cmd_save_causal_verification.bats` | `scripts/cmd_skeleton.sh:111` | O(target grep + cache) | `logs/cmd_design_quality.yaml` WARN 0/22直近、個別累計未記録 | causal_verification_l0_l7 | 2026-06-26 | なし | `[[past_design_intent_unchecked_risk]] -> [[causal_verification_l0_l7_required]]` |
| 12 | `check_three_layer_penetration` | 殿裁定2026-06-10 | 三層記憶への貫通漏れ | L4/L5 | save | WARN | `record_warn_reason` | memory DB/semantic/origin反映あり | contextだけ更新 | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | 三層記憶規則 | 2026-06-26 | なし | `[[三層記憶]] -> [[contextだけ更新]] -> [[貫通漏れWARN]]` |
| 13 | `check_self_reread_red_flag` | 洗脳防御 | 自分の出力を読まず完了 | L4 | save | WARN | `record_warn_reason` | 再読・差分確認記載 | 「作成した」だけ | `tests/unit/test_cmd_save.bats`, `tests/unit/test_cmd_save_red_flags.bats` | indirect | O(text grep) | 個別FP率未記録 | 洗脳8パターン | 2026-06-26 | なし | `[[出力=仕事]] -> [[再読なし]] -> [[self_reread_red_flag]]` |
| 14 | `check_bundle_red_flag` | 洗脳防御 | bundle/まとめで実行を代替 | L4 | save | WARN | `record_warn_reason` | 実装・検証まで完了 | bundle作成だけで完了扱い | `tests/unit/test_cmd_save_red_flags.bats` | indirect | O(text grep) | 個別FP率未記録 | 洗脳#6 | 2026-06-26 | なし | `[[報告=行動ではない]] -> [[bundleで停止]] -> [[bundle_red_flag]]` |
| 15 | `check_gunshi_analysis_overlap` | 軍師分析重複防止 | 同一分析の重複起票 | L5 | preflight | WARN | stdout/stderr | 既存軍師分析を参照 | 同テーマ再分析 | 明示単体テスト未検出 | indirect | O(rg/cache) | 個別FP率未記録 | gunshi分析運用 | 2026-06-26 | なし | `[[軍師分析]] -> [[重複起票]] -> [[overlap WARN]]` |
| 16 | `check_pi_number_collision` | Production Invariant管理 | PI番号衝突 | L4 | preflight | WARN/BLOCK | stdout/stderr | 未使用PI番号 | 既存PI番号再利用 | 明示単体テスト未検出 | indirect | O(rg) | 個別FP率未記録 | PI-INFRA | 2026-06-26 | なし | `[[Production Invariant]] -> [[番号衝突]] -> [[PI collision]]` |
| 17 | `check_ac_file_paths` | AC現物パス確認 | ACに存在しないファイルパス | L4 | save | WARN | stdout/stderr | AC内パスが存在 | 存在しないパス | `tests/test_cmd_save_ac_paths.bats` | indirect | O(path checks) | 個別FP率未記録 | File Reading Rule | 2026-06-26 | なし | `[[ACファイルパス]] -> [[存在未確認]] -> [[path WARN]]` |
| 18 | `check_cmd_text_pipe_danger` | D008 pipe-to-shell防御 | `curl&#124;bash`等の危険操作 | L4 | save | BLOCK/WARN | block/warn | 危険パターンなし | pipe-to-shell記載 | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | Destructive D008 | 2026-06-30 | なし | `[[remote code execution]] -> [[pipe_to_shell]] -> [[D008防御]]` |
| 19 | `check_impl_push_ac` | push禁止/commitまで | 忍者・cmdのpush要求混入 | L4 | save | WARN/BLOCK | stdout/stderr | commitまで明記 | push ACあり | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | Deployment Rules | 2026-06-26 | なし | `[[push禁止]] -> [[push AC混入]] -> [[commitまで]]` |
| 20 | `check_dm_signal_bare_layer_reference` | DM-Signal用語明確化 | bare layer等の曖昧語 | L4 | save | WARN | stdout/stderr | 用語辞書参照あり | bare layer単独 | `tests/unit/test_cmd_save_dm_signal_bare_layer_reference.bats` | indirect | O(text grep) | 個別FP率未記録 | dm-signal terminology | 2026-06-26 | なし | `[[曖昧語]] -> [[誤実装]] -> [[用語辞書参照]]` |
| 21 | `check_ac_must_should_mix` | AC二値性 | must/should混在による曖昧AC | L4 | save | WARN | stdout/stderr | must/二値表現に統一 | should混在 | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | cmd_format AC | 2026-06-26 | なし | `[[曖昧AC]] -> [[完了判定不能]] -> [[must_should_mix]]` |
| 22 | `check_research_tool_growth_ac` | 道具磨き原則 | 研究cmdで道具改善なし | L4/L5 | save | WARN | stdout/stderr | engine/tool改善ACあり | 分析だけ | `tests/unit/test_cmd_save_small_consolidated.bats` | indirect | O(text grep) | 個別FP率未記録 | パラメータ空間縮小禁止 | 2026-06-26 | なし | `[[研究cmd]] -> [[道具を磨け]] -> [[tool_growth_ac]]` |
| 23 | `check_projects_yaml_forbidden_topics` | projects正本保護 | projects.yamlへ不適切情報混入 | L4 | save | WARN/BLOCK | stdout/stderr | PJ核心知識のみ | 会話/一時情報混入 | `tests/unit/test_cmd_save_memory_ruling.bats` | indirect | O(text grep) | 個別FP率未記録 | Knowledge Map | 2026-06-26 | なし | `[[projects正本]] -> [[情報層混入]] -> [[forbidden_topics]]` |
| 24 | `check_content_duplicate` | 重複cmd起票防止 | 直近cmdとの内容重複 | L4/L5 | save | WARN | stdout/stderr | 新規目的 | 直近cmd類似 | `tests/test_cmd_save_content_dup.bats` | indirect | O(recent cmd scan) | 個別FP率未記録 | growth-loop | 2026-06-26 | なし | `[[同一cmd再起票]] -> [[重複]] -> [[content_duplicate]]` |
| 25 | `check_ac_param_sufficiency` | パラメータ空間縮小禁止 | 数量指定だけで具体値未列挙 | L4/L5 | save | WARN | `record_warn_reason` | 全パラメータ・具体値列挙 | 「代表N点」等 | `tests/unit/test_cmd_save_ac_param_sufficiency.bats`, `tests/unit/test_cmd_save_warn_logging.bats` | indirect | O(text grep) | `logs/cmd_design_quality.yaml`: 2 WARN/22 entries | パラメータ空間縮小禁止 | 2026-06-26 | なし | `[[代表N点禁止]] -> [[探索縮小]] -> [[param_sufficiency]]` |
| 26 | `check_param_space_against_results` | 後段cmdの前段継承 | 検証対象縮小 | L4 | save | WARN/BLOCK | stdout/stderr | 前段と同一空間 | 前段1700→後段5等 | `tests/unit/test_cmd_save_param_space_against_results.bats` | indirect | O(text grep) | 個別FP率未記録 | パラメータ空間縮小禁止 | 2026-06-26 | なし | `[[前段探索空間]] -> [[後段縮小]] -> [[against_results]]` |
| 27 | `check_param_space_shrink` | 計算量理由の縮小禁止 | 「重いから絞る」 | L4 | save | BLOCK/WARN | stdout/stderr | 高速化/並列/チャンク化 | 計算量を理由に縮小 | 明示単体テスト未検出 | indirect | O(text grep) | 個別FP率未記録 | パラメータ空間縮小禁止 | 2026-06-26 | なし | `[[計算量を理由に縮小]] -> [[殿時間浪費]] -> [[space_shrink BLOCK]]` |
| 28 | `check_gunshi_design_num_relax` | LS-A22(2)(7) | 軍師設計数値の根拠なし緩和 | L4 | save | WARN/BLOCK | stdout/stderr | 数値根拠・比較あり | 数値を緩くするだけ | `tests/test_cmd_save_check17_18_20_exit_gate.bats`, `tests/unit/test_cmd_save_assumptions_scope_fp.bats` | indirect | O(text grep) | LS-A22でFP既知、2026-06-26 WHAT_PART修正 | LS-A22 | 2026-06-26 | なし | `[[設計数値緩和]] -> [[根拠なし]] -> [[num_relax]]` |
| 29 | `check_action_immediate_verification` | 行動→即確認原則 | 行動後の即時検証欠落 | L4/L5 | save | WARN | stdout/stderr | 検証コマンド・結果あり | 実装だけ | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | growth-loop | 2026-06-26 | なし | `[[行動]] -> [[計測なし]] -> [[immediate_verification]]` |

## 3. check関数→bats対応表

| coverage | functions |
|---|---|
| 明示テストあり | `check_gate_script_execution_evidence`, `check_gate_hook_action_conversion`, `check_lord_30min_cost_question`, `check_deferral_language_warn`, `check_lord_instruction_ac_alignment_info`, `check_measurement_env_info`, `check_depends_on_field`, `check_origin_field`, `check_causal_verification_requirement`, `check_three_layer_penetration`, `check_self_reread_red_flag`, `check_bundle_red_flag`, `check_ac_file_paths`, `check_cmd_text_pipe_danger`, `check_impl_push_ac`, `check_dm_signal_bare_layer_reference`, `check_ac_must_should_mix`, `check_research_tool_growth_ac`, `check_projects_yaml_forbidden_topics`, `check_content_duplicate`, `check_ac_param_sufficiency`, `check_param_space_against_results`, `check_gunshi_design_num_relax`, `check_action_immediate_verification` |
| 明示テスト未検出 | `is_gate_or_hook_addition_cmd`, `is_gate_or_script_modification_cmd`, `check_gunshi_analysis_overlap`, `check_pi_number_collision`, `check_param_space_shrink` |

根拠コマンド: `rg -n "<function names>" tests/test_cmd_save*.bats tests/unit/test_cmd_save*.bats tests/test_cmd_save_*.bats`

## 4. FP率・baseline

### 4.1 WARN/BLOCK理由→check関数名 推定マッピング

現行ログは `logs/gate_fire_log.yaml` と `logs/cmd_design_quality.yaml` に関数別TP/FPラベルを持たない。従って関数別FP率は「分母・分子を機械算出不能」と記録する。代替証跡として、WARN/BLOCK理由文字列の `check=` を関数へマッピングし、FP既知パターンはLS-A22から逆引きした。

| reason/check key | mapped function | 頻度 | FP率 | 根拠 |
|---|---|---:|---|---|
| `check=check_ac_param_sufficiency` | `check_ac_param_sufficiency` | 2/22 cmd_design entries | 直接算出不可 | `logs/cmd_design_quality.yaml` notes |
| `check=check_ac_structure_quality` | インラインCheck(前半29外) | 1/22 | 直接算出不可 | `logs/cmd_design_quality.yaml` notes |
| `check=check_command_steps_vs_ac` | インラインCheck(前半29外) | 1/22 | 直接算出不可 | `logs/cmd_design_quality.yaml` notes |
| `q5=code_readingのみ` | `cmd_save_main`内q5ブロック(前半29外) | 1/22 BLOCK | 直接算出不可 | `logs/cmd_design_quality.yaml` BLOCK notes |
| LS-A22(1) SCOUT偽陽性 | `is_gate_or_hook_addition_cmd` | ログ頻度なし | 直接算出不可 | `projects/infra/lessons_shogun.yaml` LS-A22 |
| LS-A22(10) 先送り表現FP | `check_deferral_language_warn` | ログ頻度なし | 直接算出不可 | `projects/infra/lessons_shogun.yaml` LS-A22 |
| LS-A22(2)(7) 数値緩和/§番号FP | `check_gunshi_design_num_relax` | ログ頻度なし | 直接算出不可 | `projects/infra/lessons_shogun.yaml` LS-A22 |
| その他前半26件 | 各担当関数 | 0件またはログ上識別不能 | 直接算出不可 | 現行ログに関数別TP/FPラベルなし |

根拠コマンド:

```bash
python3 - <<'PY'
import yaml,re,collections
entries=(yaml.safe_load(open('logs/cmd_design_quality.yaml')) or {}).get('entries',[])
counts=collections.Counter()
for e in entries:
    notes=str(e.get('notes','') or '')
    m=re.search(r'check=([A-Za-z0-9_]+)', notes)
    if m: counts[m.group(1)]+=1
print(counts)
PY
```

### 4.2 現行baseline

| 指標 | 値 | 根拠 |
|---|---:|---|
| `logs/cmd_design_quality.yaml` 総entry | 22 | `python3` YAML集計 |
| 直近50相当entry | 22 | 現存22件のみ |
| PASS | 4 | `gate_result == PASS` |
| CLEAR | 13 | `gate_result == CLEAR` |
| BLOCK | 1 | `gate_result == BLOCK` |
| WARN | 4 | `source == cmd_save_warn` |
| FAIL | 0 | `gate_result == FAIL` |
| `cmd_save` source系 | 9 | `source`に`cmd_save`含む |
| `logs/gate_fire_log.yaml` 末尾500行 WARN | 86 | `[WARN]`行数 |
| `logs/gate_fire_log.yaml` 末尾500行 FAIL | 38 | `result: FAIL`行数 |
| `bash scripts/cmd_save.sh --help` 実行時間中央値 | 0.01s | `time` 3回、ただし未知オプション即時終了パス |

注意: 本任務は偵察のため、実cmd保存を伴うpreflight実行はログ汚染リスクがある。実行時間は副作用の小さい未知オプション即時終了パスのみ測った。通常保存パスの中央値は後続統合時に専用fixture cmdで測るべき。

## 2.後半8関数カタログ（saizo担当）

> recon2_back_half_29_functions / 作成者: saizo / 作成日: 2026-06-30
> 対象: check/gate系定義順の後半8件（#30-37）

| # | function | origin | 防御対象 | L0-L7 | 時点 | severity | 副作用 | 正例fixture | 負例fixture | 対応テスト | cmd_skeleton同期 | 性能コスト | FP率 | 教訓逆引き | 最終修正日 | hook参照パターン | origin因果リンク |
|---:|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 30 | `check_research_tool_explicit` | cmd_1822（ACに研究スクリプトパスが未記載） | GS/WF研究cmdでACに研究スクリプトパスが未記載 | L4/L5 | save | WARN | stderr, record_warn_reason | ACにrun_077*.pyまたはl1_alm_wf_engine.pyのパス明記 | GS/WFキーワードありだがACにスクリプトパスなし | `tests/test_cmd_save_check17_18_20_exit_gate.bats`, `tests/unit/test_cmd_save_research_tool_explicit.bats` | indirect | O(text grep + AC/command解析) 中程度 | FP実績2件: cmd_2227(GS CSV除外), cmd_2172(WF四神/選別除外) | cmd_1822, dm-signal-ops.md §18 | 2026-06-16（cmd_3402 Check18出口判定化） | なし | `[[cmd_1822]] -> [[研究cmd道具未記載]] -> [[research_tool_explicit WARN]]` |
| 31 | `check_timebox_minutes_required` | LG019（計測研究cmdに実行時間上限未設定） | 計測/研究/見積cmdでtimeout_minutes未記入 | L4 | save | WARN | stderr, record_warn_reason | timeout_minutesフィールドあり | benchmark/計測/研究キーワードありだがtimeout_minutes未設定 | 明示テスト未検出 | indirect | O(text grep) | 未算出（ログに関数別FPラベルなし） | LG019 | 2026-06-26 | なし | `[[LG019]] -> [[計測cmd実行時間未記載]] -> [[timebox_minutes WARN]]` |
| 32 | `check_ac_absolute_literals` | cmd_1910事故（ACに固定値記載→並行cmdで陳腐化） | ACの数値絶対値パターン（並行配備時陳腐化リスク） | L4 | save | WARN(informational, WARN_COUNT非加算) | stderr only（record_warn_reasonなし） | ACに「減少しないこと」等の相対条件 | ACに「テスト数=118」等の絶対値 | 明示テスト未検出 | indirect | O(text grep) | 未算出 | cmd_1910 | 2026-06-26 | なし | `[[cmd_1910]] -> [[AC絶対値陳腐化]] -> [[ac_absolute_literals WARN]]` |
| 33 | `check_db_backup_ac_warn` | 殿厳命（コードは書き直せる、データは書き直せない） | DB操作cmdでACにバックアップなし | L4 | save | WARN | stderr, record_warn_reason | commandにDB操作(migrate/ALTER等)あり+ACにバックアップ確認あり | commandにmigrate/ALTER TABLEありだがACにバックアップなし | `tests/unit/test_cmd_save.bats` | indirect | O(text grep + AC scan) | FP除外あり: GS出力SQLite読取のみ(is_db_operation_command_text) | feedback_backup_first.md, CLAUDE.md | 2026-06-26 | なし | `[[殿厳命_バックアップファースト]] -> [[DB操作cmdバックアップ未確認]] -> [[db_backup_ac_warn]]` |
| 34 | `check_numeric_literal_derivation_source_info` | LG020（数値の算出元未確認で誤認） | AC/commandの3桁以上数値リテラルに算出元コマンド+結果未記載 | L5 | save | INFO（record_warn_reasonなし） | stderr only | q5_verified_sourceやassumptionsにgrep/rg等の算出コマンド+結果あり | ACに「123件」等があるがq5_verified_source/assumptions欠落 | `tests/unit/test_cmd_save.bats` | indirect | O(text grep + AC/command解析) | 未算出 | LG020 | 2026-06-26 | なし | `[[LG020]] -> [[数値の算出元未確認]] -> [[numeric_literal_derivation INFO]]` |
| 35 | `check_ac_phase_mixing` | cmd_2300事故（実装ACとCDP計測ACが1cmdに同居し計測不能でFAIL） | 同一AC内に実装と計測/deployが共起 | L4（分割案テンプレート提示でL5） | save | WARN | stderr, record_warn_reason | AC-impl/AC-verifyで別AC設計 | 同一AC内に実装+計測/push | `tests/unit/test_cmd_save_ac_phase_mixing.bats`, `tests/unit/test_gate_shogun_startup.bats` | indirect | O(AC text awk解析) 中程度 | FP修正実績3件: cmd_3533(snake_case除外2026-06-26), cmd_3406(bats除外2026-06-16), FP削除パターン多数 | cmd_2300 | 2026-06-26 | なし | `[[cmd_2300]] -> [[実装+計測同居]] -> [[ac_phase_mixing WARN]]` |
| 36 | `check_ac_test_scope` | cmd_2342（全テストPASS条件でpre-existing failure抱込みAC達成不能） | スコープ未指定のテスト全件条件（「全テストPASS」「0 failures」等） | L4 | save | WARN | stderr, record_warn_reason | AC内テスト条件が「変更対象の関連テストPASS」等のスコープ指定あり | 「全テストPASS」「0 failures」等のスコープ未指定 | `tests/unit/test_cmd_save_ac_test_scope.bats` | indirect | O(text grep) | 未算出（FP除外フィルタ多数: 変更対象/関連テスト/.bats等） | cmd_2342 | 2026-06-26 | なし | `[[cmd_2342]] -> [[全件テスト条件]] -> [[pre-existing failure抱込み]]` |
| 37 | `check_new_file_structure_warning` | 簡略版コード禁止/既存活用原則（CLAUDE.md） | AC/commandに新規ファイル/新規構造作成要求 | L4（既存類似ファイル候補自動提案でL5） | save | WARN | stderr, record_warn_reason | 既存ファイル活用の代替案あり、理由と現物確認明記 | 「新規ファイル作成」「新規構造」等の記載 | 明示テスト未検出 | indirect | O(text grep + find timeout=3s) | FP除外フィルタあり: quality_gate/diagnosis等除外 | 簡略版コード禁止原則(CLAUDE.md) | 2026-06-26 | なし | `[[簡略版コード禁止]] -> [[新規ファイル乱立]] -> [[new_file_structure WARN]]` |

### check関数→bats対応表（全37件）

| coverage | functions（後半8件） |
|---|---|
| 明示テストあり | `check_research_tool_explicit`, `check_db_backup_ac_warn`, `check_numeric_literal_derivation_source_info`, `check_ac_phase_mixing`, `check_ac_test_scope` |
| 明示テスト未検出 | `check_timebox_minutes_required`, `check_ac_absolute_literals`, `check_new_file_structure_warning` |

根拠コマンド: `rg -l "<function_name>" tests/ tests/unit/`

### FP率（後半8件追記）

| function | FP率 | 根拠 |
|---|---|---|
| `check_research_tool_explicit` | 未算出（FP実績あり） | cmd_2227(GS CSV除外), cmd_2172(WF四神/選別除外) コミット履歴より |
| `check_ac_phase_mixing` | 未算出（FP実績あり） | cmd_3533(2026-06-26), cmd_3406(2026-06-16) 複数FP修正コミットあり |
| `check_db_backup_ac_warn` | 未算出 | is_db_operation_command_text内でGS SQLite読取を除外 |
| `check_timebox_minutes_required`, `check_ac_absolute_literals`, `check_numeric_literal_derivation_source_info`, `check_ac_test_scope`, `check_new_file_structure_warning` | 未算出 | ログに関数別FPラベルなし |

## 5. 統合完了メモ（saizo追記）

- 後半8件（#30-37）を「## 2.後半8関数カタログ」として追記。合計37件でカタログ完成。
- 設計書58本と現物37本の差分: 半蔵の抽出根拠メモ通り（`check_`/`gate`名称含む関数=37件が実数。`qN`補助含めて40件、全bash関数113件）。
- 関数別FP率は現行ログ（logs/gate_fire_log.yaml, logs/cmd_design_quality.yaml）に関数別FPラベルなし。FP修正コミット履歴からのみ推定可能。今後 `record_warn_reason` に `fp_label` カラム追加が必要（半蔵統合メモ踏襲）。
- `check_ac_absolute_literals` はWARN_COUNTに加算しない（informational）= record_warn_reasonなし。他のWARN系関数と副作用が異なる点に注意。
- 後半8件で明示テストがない関数: `check_timebox_minutes_required`, `check_ac_absolute_literals`, `check_new_file_structure_warning`（3件）。テストカバレッジの穴として残存。

## 6. Phase 1b 追加カタログ（cmd_3609）

| # | function | origin | 防御対象 | L0-L7 | 時点 | severity | 副作用 | 正例fixture | 負例fixture | 対応テスト | cmd_skeleton同期 | 性能コスト | FP率 | 教訓逆引き | 最終修正日 | hook参照パターン | origin因果リンク |
|---:|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 38 | `q11_has_existing_alternative_verification` | LS-A22 / q11既存代替確認 | 既存仕組み確認なしの新規gate/hook追加 | L5 | preflight | helper | stdoutなし | q11に既存代替の現物確認あり | q11が空または抽象論のみ | `tests/unit/test_cmd_save_q11_fp_reduction.bats` | `scripts/cmd_skeleton.sh:111` | O(text grep) | 直接算出不可 | LS-A22 | 2026-06-30 | なし | `[[既存代替未確認]] -> [[重複gate追加]] -> [[q11 helper]]` |
| 39 | `q5_has_execution_evidence` | cmd_3360 | q5の実行証拠判定 | L5 | preflight | helper | stdoutなし | q5にexit code/実行結果あり | code_readingのみ | `tests/unit/test_cmd_save_q5.bats` | `scripts/cmd_skeleton.sh:110` | O(text grep) | 直接算出不可 | LS063 | 2026-06-30 | なし | `[[q5未実行]] -> [[前提未検証]] -> [[execution evidence helper]]` |
| 40 | `q11_has_guard_duplicate_check` | LS-A22(9) | guard重複確認なし | L5 | preflight | helper | stdoutなし | q11にguard一覧照合あり | guard重複未確認 | `tests/unit/test_cmd_save_q11_fp_reduction.bats` | indirect | O(text grep) | 直接算出不可 | LS-A22 | 2026-06-30 | なし | `[[guard重複]] -> [[各論patch乱立]] -> [[duplicate helper]]` |
| 41 | `inline_fill_this_placeholder_block` | template hygiene | 雛形FILL_THIS残存 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_block_reason` | FILL_THIS 0件 | FILL_THIS残存 | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | report/gate頻出FAIL | 2026-06-30 | なし | `[[テンプレ未記入]] -> [[空成果物]] -> [[FILL_THIS BLOCK]]` |
| 42 | `inline_delegated_duplicate_block` | cmd委任状態管理 | 委任済みcmdの再保存 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_block_reason` | 未委任draftのみ保存 | delegated cmd再保存 | 明示単体テスト未検出 | indirect | O(YAML cache) | 直接算出不可 | cmd state | 2026-06-30 | なし | `[[delegated cmd]] -> [[再保存]] -> [[state BLOCK]]` |
| 43 | `inline_previous_pass_pending_block` | cmd状態遷移 | 前回PASS済みpending放置で次cmd保存 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_block_reason` | 前回cmdがdelegated以降 | PASS済みpendingのまま次cmd | 明示単体テスト未検出 | indirect | O(YAML scan) | 直接算出不可 | cmd state | 2026-06-30 | なし | `[[PASS pending]] -> [[委任漏れ]] -> [[next cmd BLOCK]]` |
| 44 | `inline_archive_duplicate_warn` | archive重複防止 | archive済みcmdとの重複 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_warn_reason` | 新規cmd id | archive duplicate | 明示単体テスト未検出 | indirect | O(archive scan) | 直接算出不可 | cmd archive | 2026-06-30 | なし | `[[archive]] -> [[重複保存]] -> [[duplicate WARN]]` |
| 45 | `inline_other_draft_exists_block` | draft単一性 | 他draft存在中の新規保存 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_block_reason` | draft 0件 | other_draft_exists | 明示単体テスト未検出 | indirect | O(queue scan) | 直接算出不可 | cmd state | 2026-06-30 | なし | `[[複数draft]] -> [[指揮混線]] -> [[draft BLOCK]]` |
| 46 | `inline_diagnosis_format_block` | BLOCK学習ループ | diagnosis形式不正 | L4 | save | BLOCK | `record_block_reason` | `BLOCK理由/対策` 2部構成 | diagnosis欠落/形式不正 | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[BLOCK]] -> [[真因未記録]] -> [[diagnosis BLOCK]]` |
| 47 | `inline_environment_change_missing_block` | BLOCK後環境変化強制 | environment_change未記入 | L4 | save | BLOCK | `record_block_reason` | type/file/patternあり | BLOCK後に環境変化なし | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[BLOCK]] -> [[修正だけで停止]] -> [[environment_change BLOCK]]` |
| 48 | `inline_environment_change_quality_block` | 環境変化品質 | environment_changeが抽象的 | L4 | save | BLOCK | `record_block_reason` | 具体diff/grep可能pattern | 低品質な説明のみ | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[環境変化]] -> [[口約束]] -> [[quality BLOCK]]` |
| 49 | `inline_environment_change_implemented_block` | 環境変化実装確認 | file/patternが現物にない | L4 | save | BLOCK | `record_block_reason` | 指定patternが実在 | 実装されていないpattern | 明示単体テスト未検出 | indirect | O(grep file) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[environment_change]] -> [[未実装]] -> [[grep BLOCK]]` |
| 50 | `inline_environment_change_structured_block` | 構造化記録 | environment_change非構造化 | L4 | save | BLOCK | `record_block_reason` | `type=...; file=...; pattern=...` | 散文のみ | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[環境変化]] -> [[検索不能]] -> [[structured BLOCK]]` |
| 51 | `inline_quality_gate_missing_block` | cmd_save quality gate | quality_gate未記入 | L4 | save | BLOCK | `record_block_reason` | q1-qN記入済み | quality_gate空 | `tests/unit/test_cmd_save_quality_gate*.bats` | `scripts/cmd_skeleton.sh` | O(YAML cache) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[cmd_save]] -> [[問い未回答]] -> [[quality_gate BLOCK]]` |
| 52 | `inline_quality_gate_invalid_fields_block` | q field schema | quality_gate不正フィールド | L4 | save | BLOCK | `record_block_reason` | 許可フィールドのみ | typo/旧field混入 | `tests/unit/test_cmd_save_quality_gate*.bats` | `scripts/cmd_skeleton.sh` | O(field loop) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[quality_gate]] -> [[schema drift]] -> [[invalid field BLOCK]]` |
| 53 | `inline_required_keys_missing_block` | cmd必須項目 | required fields未記入 | L4 | save | BLOCK | `record_block_reason` | 全必須keyあり | required欠落 | `tests/unit/test_cmd_save*.bats` | `scripts/cmd_skeleton.sh` | O(key loop) | 直接算出不可 | cmd_format | 2026-06-30 | なし | `[[cmd_format]] -> [[必須欠落]] -> [[required BLOCK]]` |
| 54 | `inline_q4_depth_missing_warn` | 深堀り度記録 | q4_depth未記入 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | shallow/medium/deep明記 | q4_depth空 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[深堀り]] -> [[密度不明]] -> [[q4 WARN]]` |
| 55 | `inline_research_baseline_warn` | 研究cmd baseline | 研究cmdにbaselineなし | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | baseline/比較対象あり | 研究cmdでbaseline空 | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | LG022 | 2026-06-30 | なし | `[[研究cmd]] -> [[比較不能]] -> [[baseline WARN]]` |
| 56 | `inline_q5_code_reading_only_block` | q5現物確認 | code_readingのみで前提未検証 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_block_reason` | isolated/structure/production verified | code_readingのみ | `tests/unit/test_cmd_save_q5.bats` | `scripts/cmd_skeleton.sh:110` | O(text grep) | 直接算出不可 | LS063 | 2026-06-30 | なし | `[[コード読みのみ]] -> [[前提未検証]] -> [[q5 BLOCK]]` |
| 57 | `inline_q6_not_hiding_missing_warn` | 自動消火防止 | q6_not_hiding未記入 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | 隠すもの/隠さない理由あり | q6空 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | 自動消火禁止 | 2026-06-30 | なし | `[[消火]] -> [[根因隠蔽]] -> [[q6 WARN]]` |
| 58 | `inline_q7_definition_verified_warn` | 定義確認 | q7_definition_verified未記入 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | 用語/定義確認あり | q7空 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | 定義確認 | 2026-06-30 | なし | `[[定義未確認]] -> [[誤実装]] -> [[q7 WARN]]` |
| 59 | `inline_q8_scope_expression_warn` | パラメータ空間防御 | q8に縮小表現 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | 全量/並列/チャンク化 | 代表N点/絞る | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | パラメータ空間縮小禁止 | 2026-06-30 | なし | `[[縮小表現]] -> [[探索漏れ]] -> [[q8 WARN]]` |
| 60 | `inline_q8_compound_question_warn` | 複利問い | q8複利観点不足 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | 複利影響あり | 影響記述なし | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[単発作業]] -> [[複利不明]] -> [[q8 compound WARN]]` |
| 61 | `inline_q8_when_how_warn` | 5W1H | q8 WHEN/HOW不足 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | WHEN/HOWあり | 時期/方法不明 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | cmd quality | 2026-06-30 | なし | `[[設計不足]] -> [[実行不能]] -> [[when_how WARN]]` |
| 62 | `inline_q8_where_who_warn` | 5W1H | q8 WHERE/WHO不足 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | WHERE/WHOあり | 対象/担当不明 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | cmd quality | 2026-06-30 | なし | `[[設計不足]] -> [[配備不能]] -> [[where_who WARN]]` |
| 63 | `inline_q9_firefighting_missing_block` | 消火cmd真因 | q9_firefighting_root_cause未記入 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_block_reason` | root_cause/preventionあり | 消火cmdでq9空 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | 自動消火禁止 | 2026-06-30 | なし | `[[消火cmd]] -> [[真因なし]] -> [[q9 BLOCK]]` |
| 64 | `inline_q9_root_cause_label_block` | q9構造 | q9にroot_causeなし | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_block_reason` | root_cause labelあり | preventionのみ | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[q9]] -> [[原因未分離]] -> [[root_cause BLOCK]]` |
| 65 | `inline_q9_prevention_label_block` | q9構造 | q9にpreventionなし | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_block_reason` | prevention labelあり | root_causeのみ | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[q9]] -> [[再発防止なし]] -> [[prevention BLOCK]]` |
| 66 | `inline_q9_root_cause_length_block` | 真因品質 | root_cause短すぎ | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_block_reason` | 10文字以上の具体原因 | 短文/空 | 明示単体テスト未検出 | indirect | O(text length) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[真因]] -> [[抽象語]] -> [[length BLOCK]]` |
| 67 | `inline_q9_prevention_length_block` | 予防品質 | prevention短すぎ | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_block_reason` | 10文字以上の仕組み | 短文/空 | 明示単体テスト未検出 | indirect | O(text length) | 直接算出不可 | growth-loop | 2026-06-30 | なし | `[[予防]] -> [[口約束]] -> [[length BLOCK]]` |
| 68 | `inline_q10_knowledge_boundary_warn` | 知識境界 | q10_knowledge_boundary未記入 | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS | `record_warn_reason` | verified/unknown境界あり | 境界不明 | 明示単体テスト未検出 | `scripts/cmd_skeleton.sh` | O(text grep) | 直接算出不可 | 三層記憶 | 2026-06-30 | なし | `[[知識境界]] -> [[推測混入]] -> [[q10 WARN]]` |
| 69 | `inline_q11_guard_duplicate_block` | guard重複確認 | q11にGuard一覧との重複確認なし | L4 | save | BLOCK | `record_block_reason` | guard一覧確認あり | 新guard案のみ | `tests/unit/test_cmd_save_q11_fp_reduction.bats` | `scripts/cmd_skeleton.sh:111` | O(text grep) | 直接算出不可 | LS-A22 | 2026-06-30 | なし | `[[guard]] -> [[重複]] -> [[q11 BLOCK]]` |
| 70 | `inline_q11_existing_alternative_block` | 既存代替確認 | q11に既存代替の現物確認なし | L4 | save | BLOCK | `record_block_reason` | 既存代替現物確認あり | 抽象的に「なし」 | `tests/unit/test_cmd_save_q11_fp_reduction.bats` | `scripts/cmd_skeleton.sh:111` | O(text grep) | 直接算出不可 | LS-A22 | 2026-06-30 | なし | `[[既存代替]] -> [[未確認]] -> [[q11 BLOCK]]` |
| 71 | `inline_lock_contention_warn` | flock競合可視化 | cmd_save lock contention | L4 | save | WARN | `record_warn_reason` | lock取得成功 | lock競合 | 明示単体テスト未検出 | indirect | O(lock wait) | 直接算出不可 | infra concurrency | 2026-06-30 | なし | `[[flock]] -> [[競合]] -> [[lock WARN]]` |
| 72 | `warn_q5_pair_missing_session_state` | session_state整合 | q5_verified_source必須フィールド対の欠落 | L4 | save | WARN | `record_warn_reason` | session_state対フィールドあり | q5片側欠落 | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | q5 integrity | 2026-06-30 | なし | `[[q5_verified_source]] -> [[片側欠落]] -> [[session_state WARN]]` |
| 73 | `warn_missing_prev_cmd_lesson` | 前cmd学習継承 | 前cmd教訓未反映 | L4 | save | BLOCK | `record_block_reason` | 前cmd lesson参照あり | lesson欠落 | 明示単体テスト未検出 | indirect | O(cmd scan) | 直接算出不可 | 学習ループ | 2026-06-30 | なし | `[[前cmd]] -> [[教訓未継承]] -> [[lesson BLOCK]]` |
| 74 | `show_three_layer_memory_ruling_info` | 殿裁定2026-06-10 | 三層記憶裁定の表示補助 | L5 | preflight | INFO | stderr only | 裁定を起票者へ表示 | 表示なし | 明示単体テスト未検出 | indirect | O(text output) | 直接算出不可 | 三層記憶 | 2026-06-30 | なし | `[[三層記憶裁定]] -> [[忘却]] -> [[ruling info]]` |
| 75 | `show_gunshi_pane_status.ac_structure_incomplete` | 軍師レビュー前提検証 | AC構造不完全 | L4 | save | WARN | `record_warn_reason` | AC構造が完全 | AC構造不足 | 明示単体テスト未検出 | indirect | O(YAML/text parse) | 直接算出不可 | AC二値性 | 2026-06-30 | なし | `[[AC構造]] -> [[検証不能]] -> [[structure WARN]]` |
| 76 | `show_gunshi_pane_status.unverified_assumption_block` | Karpathy原則 | 未検証前提あり | L4 | save | BLOCK | `record_block_reason` | trust:verified | trust未検証 | 明示単体テスト未検出 | indirect | O(assumption scan) | 直接算出不可 | assumption discipline | 2026-06-30 | なし | `[[未検証前提]] -> [[推測]] -> [[assumption BLOCK]]` |
| 77 | `show_gunshi_pane_status.assumption_source_path_block` | source実在確認 | assumptions source path不存在 | L4 | save | BLOCK | `record_block_reason` | source file exists | 存在しないsource | 明示単体テスト未検出 | indirect | O(path check) | 直接算出不可 | File Reading Rule | 2026-06-30 | なし | `[[source path]] -> [[不存在]] -> [[path BLOCK]]` |
| 78 | `show_gunshi_pane_status.claim_date_warn` | claim鮮度 | assumptions claimに日付なし | L4 | save | WARN | `record_warn_reason` | claimに日付あり | 日付なしclaim | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | temporal accuracy | 2026-06-30 | なし | `[[claim]] -> [[鮮度不明]] -> [[date WARN]]` |
| 79 | `show_gunshi_pane_status.negative_claim_grep_warn` | 反証確認 | 否定的claimにgrep反証結果なし | L4 | save | WARN | `record_warn_reason` | grep反証結果あり | 否定claimのみ | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | 確認してから行動 | 2026-06-30 | なし | `[[否定claim]] -> [[反証なし]] -> [[grep WARN]]` |
| 80 | `show_gunshi_pane_status.bulletin_count_grep_warn` | 件数claim検証 | bulletin由来件数claimにgrep検証なし | L4 | save | WARN | `record_warn_reason` | grep件数証跡あり | 件数claimのみ | 明示単体テスト未検出 | indirect | O(text grep) | 直接算出不可 | 数値計測 | 2026-06-30 | なし | `[[bulletin件数]] -> [[数値未検証]] -> [[count WARN]]` |
| 81 | `inline_session_state_queue_presence_warn` | session_state鮮度 | queue file missing | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_warn_reason` | queue file exists | queue file missing | 明示単体テスト未検出 | indirect | O(path check) | 直接算出不可 | session_state | 2026-06-30 | なし | `[[queue_file]] -> [[欠落]] -> [[session_state WARN]]` |
| 82 | `inline_session_state_cmd_block_presence_warn` | session_state鮮度 | cmd block missing | L4 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS | `record_warn_reason` | cmd block exists | cmd block missing | 明示単体テスト未検出 | indirect | O(YAML scan) | 直接算出不可 | session_state | 2026-06-30 | なし | `[[cmd_block]] -> [[欠落]] -> [[session_state WARN]]` |

Phase 1b根拠コマンド:

```bash
python3 - <<'PY'
import re
from pathlib import Path
lines=Path('scripts/cmd_save.sh').read_text().splitlines()
func=None
calls=[]
for i,l in enumerate(lines,1):
    m=re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\(\) \{',l)
    if m:
        func=m.group(1)
    if 'record_block_reason' in l or 'record_warn_reason' in l:
        if re.match(r'^(record_block_reason|record_warn_reason)\(\)', l):
            continue
        calls.append((i,func,l.strip()))
print(len(calls))
for row in calls:
    print(row)
PY
```

## 7. Phase 2 処置判定表（cmd_3612）

| # | item | 層 | 処置 | 判定根拠 | 実施状態 | 実施証跡 |
|---:|---|---|---|---|---|---|
| 1 | `is_gate_or_hook_addition_cmd` | A | 抽象化 | classifier系で#2と入力・時点・副作用が同じだが検出語彙が異なるためhelper共通化のみ | pending | 未実施 |
| 2 | `is_gate_or_script_modification_cmd` | A | 抽象化 | classifier系で#1と共通骨格を持つがscript修正語彙は別fixtureのため統合不可 | pending | 未実施 |
| 3 | `check_gate_script_execution_evidence` | A | 抽象化 | q5証跡判定は#39と共通化可能だがWARN副作用を持つため本体保護 | pending | 未実施 |
| 4 | `check_gate_hook_action_conversion` | A | 抽象化 | q11/guard判定helper(#40)と重複する正規表現を抽出可能、BLOCK/WARN診断は維持 | pending | 未実施 |
| 5 | `check_lord_30min_cost_question` | A | 保護 | 殿時間コスト専用の問いでfailure semanticsが単独 | done | 保護対象のため変更不要 |
| 6 | `check_deferral_language_warn` | A | 保護 | 先送り表現のFP履歴があり、統合すると除外条件の因果が薄れる | done | 保護対象のため変更不要 |
| 7 | `check_lord_instruction_ac_alignment_info` | A | 抽象化 | q8/ACテキスト抽出は#8と共通化可能、INFO診断は個別維持 | pending | 未実施 |
| 8 | `check_measurement_env_info` | A | 抽象化 | q8/AC/計測語抽出は#7と共通化可能、計測環境INFOの意味は個別維持 | pending | 未実施 |
| 9 | `check_depends_on_field` | A | 抽象化 | YAML field presence系で#10と入力取得を共通化可能、field名とWARN文は個別 | pending | 未実施 |
| 10 | `check_origin_field` | A | 抽象化 | YAML field presence系で#9と共通helper化可能、因果ネットワーク診断は個別 | pending | 未実施 |
| 11 | `check_causal_verification_requirement` | A | 保護 | git log/blame/semantic確認の複合判定で副作用とテンプレ表示が大きい | done | 保護対象のため変更不要 |
| 12 | `check_three_layer_penetration` | A | 保護 | 三層記憶ルール専用で不足要素列挙の診断粒度を守る必要あり | done | 保護対象のため変更不要 |
| 13 | `check_self_reread_red_flag` | A | 抽象化 | red flag語彙検出は#14と共通化可能、警告名は分離 | pending | 未実施 |
| 14 | `check_bundle_red_flag` | A | 抽象化 | red flag語彙検出は#13と同型、bundle専用fixtureは分離 | pending | 未実施 |
| 15 | `check_gunshi_analysis_overlap` | A | 保護 | 既存軍師分析検索の副作用と対象ディレクトリが単独 | done | 保護対象のため変更不要 |
| 16 | `check_pi_number_collision` | A | 保護 | Production Invariant番号衝突のドメイン固有判定で統合不可 | done | 保護対象のため変更不要 |
| 17 | `check_ac_file_paths` | A | 保護 | path存在確認とstderr診断が独立し、他text grep系とfixtureが異なる | done | 保護対象のため変更不要 |
| 18 | `check_cmd_text_pipe_danger` | A | 保護 | destructive safetyのBLOCK/WARN境界で、抽象化によるFN増加リスクが高い | done | 保護対象のため変更不要 |
| 19 | `check_impl_push_ac` | A | 保護 | push禁止ルール専用で、禁止語検出の例外が独自 | done | 保護対象のため変更不要 |
| 20 | `check_dm_signal_bare_layer_reference` | A | 保護 | dm-signal用語辞書依存でinfra汎用helperへ混ぜない | done | 保護対象のため変更不要 |
| 21 | `check_ac_must_should_mix` | A | 保護 | AC二値性専用で、must/should語彙の意味が単独 | done | 保護対象のため変更不要 |
| 22 | `check_research_tool_growth_ac` | A | 保護 | 研究cmdの道具磨き原則専用で、対象cmd分類が独自 | done | 保護対象のため変更不要 |
| 23 | `check_projects_yaml_forbidden_topics` | A | 保護 | projects正本保護で情報層混入という専用failure semantics | done | 保護対象のため変更不要 |
| 24 | `check_content_duplicate` | A | 保護 | 直近cmd scanと非同期実行を含み副作用が大きい | done | 保護対象のため変更不要 |
| 25 | `check_ac_param_sufficiency` | A | 抽象化 | パラメータ空間系#26/#27と語彙抽出を共通化可能、判定本体は分離 | pending | 未実施 |
| 26 | `check_param_space_against_results` | A | 抽象化 | パラメータ空間系#25/#27と共通helper化可能、前段結果比較は個別 | pending | 未実施 |
| 27 | `check_param_space_shrink` | A | 抽象化 | パラメータ空間系#25/#26と縮小語彙helperを共有可能、BLOCK/WARNは個別 | pending | 未実施 |
| 28 | `check_gunshi_design_num_relax` | A | 保護 | 軍師設計書参照と数値緩和の専用比較でFP履歴あり | done | 保護対象のため変更不要 |
| 29 | `check_action_immediate_verification` | A | 保護 | 行動即確認の広域ルールで、他系統への統合は診断を曖昧化する | done | 保護対象のため変更不要 |
| 30 | `check_research_tool_explicit` | A | 保護 | GS/WF研究スクリプトpath要求の専用除外が多い | done | 保護対象のため変更不要 |
| 31 | `check_timebox_minutes_required` | A | 保護 | timeout_minutes field要求で対象cmd分類が独立 | done | 保護対象のため変更不要 |
| 32 | `check_ac_absolute_literals` | A | 保護 | WARN_COUNT非加算のinformationalで副作用が他WARNと違う | done | 保護対象のため変更不要 |
| 33 | `check_db_backup_ac_warn` | A | 保護 | DB破壊防止の安全系で誤抽象化によるFNを避ける | done | 保護対象のため変更不要 |
| 34 | `check_numeric_literal_derivation_source_info` | A | 保護 | INFOのみでrecord_reasonなし、数値由来表示の副作用が特殊 | done | 保護対象のため変更不要 |
| 35 | `check_ac_phase_mixing` | A | 保護 | AC単位awk解析と分割案診断が独立し、FP修正履歴も多い | done | 保護対象のため変更不要 |
| 36 | `check_ac_test_scope` | A | 保護 | test scope除外フィルタが多く、統合でpre-existing failure抱込みを隠す | done | 保護対象のため変更不要 |
| 37 | `check_new_file_structure_warning` | A | 保護 | find timeoutと既存類似候補提示を含み副作用が独自 | done | 保護対象のため変更不要 |
| 38 | `q11_has_existing_alternative_verification` | A | 抽象化 | q11 helper群の語彙判定を共通化可能、戻り値helperとして維持 | pending | 未実施 |
| 39 | `q5_has_execution_evidence` | A | 抽象化 | q5証跡語彙は#3と共通化可能、helper単体は維持 | pending | 未実施 |
| 40 | `q11_has_guard_duplicate_check` | A | 抽象化 | q11 helper群#38/#4と語彙処理を共通化可能、guard専用戻り値は維持 | pending | 未実施 |
| 41 | `inline_fill_this_placeholder_block` | B | 関数化 | inline BLOCKで独立fixtureを持つため関数抽出+単体テスト追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |
| 42 | `inline_delegated_duplicate_block` | B | 関数化 | delegated_at状態判定を関数化しcmd stateテストを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |
| 43 | `inline_previous_pass_pending_block` | B | 関数化 | 前回pending判定を関数化しqueue fixtureで検証可能にする | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |
| 44 | `inline_archive_duplicate_warn` | B | 関数化 | archive存在scanを関数化しWARN副作用を明示化 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |
| 45 | `inline_other_draft_exists_block` | B | 関数化 | draft単一性判定を関数化しdepends_on例外fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |
| 46 | `inline_diagnosis_format_block` | B | 関数化 | diagnosis形式チェックを関数化し2部構成fixtureを固定 | pending | 未実施 |
| 47 | `inline_environment_change_missing_block` | B | 関数化 | environment_change存在チェックを関数化しBLOCK履歴fixtureを追加 | pending | 未実施 |
| 48 | `inline_environment_change_quality_block` | B | 関数化 | 低品質値チェックを関数化し禁止値fixtureを追加 | pending | 未実施 |
| 49 | `inline_environment_change_implemented_block` | B | 関数化 | file/pattern実在grepを関数化し実装確認fixtureを追加 | pending | 未実施 |
| 50 | `inline_environment_change_structured_block` | B | 関数化 | 構造化parse失敗判定を関数化し散文fixtureを追加 | pending | 未実施 |
| 51 | `inline_quality_gate_missing_block` | B | 関数化 | quality_gate存在チェックを関数化し入口BLOCKを単体化 | pending | 未実施 |
| 52 | `inline_quality_gate_invalid_fields_block` | B | 関数化 | QG schema validationを関数化しfield typoをfixture化 | pending | 未実施 |
| 53 | `inline_required_keys_missing_block` | B | 関数化 | 必須項目一括チェックを関数化し欠落リストをテスト可能にする | pending | 未実施 |
| 54 | `inline_q4_depth_missing_warn` | B | 関数化 | q4_depth WARNを関数化しWARN_COUNT対象を明示 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 55 | `inline_research_baseline_warn` | B | 関数化 | research baseline WARNを関数化しtype=research fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 56 | `inline_q5_code_reading_only_block` | B | 関数化 | q5 code_reading BLOCKを関数化しscout/shallow例外をfixture化 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 57 | `inline_q6_not_hiding_missing_warn` | B | 関数化 | q6_not_hiding WARNを関数化し自動消火防止を単体化 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 58 | `inline_q7_definition_verified_warn` | B | 関数化 | q7_definition WARNを関数化し定義確認fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 59 | `inline_q8_scope_expression_warn` | B | 関数化 | q8縮小表現WARNを関数化し禁止語fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 60 | `inline_q8_compound_question_warn` | B | 関数化 | q8複利問いWARNを関数化し複利語fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 61 | `inline_q8_when_how_warn` | B | 関数化 | q8 WHEN/HOW WARNを関数化し5W1H欠落fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 62 | `inline_q8_where_who_warn` | B | 関数化 | q8 WHERE/WHO WARNを関数化し5W1H欠落fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 63 | `inline_q9_firefighting_missing_block` | B | 関数化 | q9存在チェックを関数化し消火cmd fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 64 | `inline_q9_root_cause_label_block` | B | 関数化 | q9 root_cause label判定を関数化し構造fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 65 | `inline_q9_prevention_label_block` | B | 関数化 | q9 prevention label判定を関数化し構造fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 66 | `inline_q9_root_cause_length_block` | B | 関数化 | root_cause長さ判定を関数化し短文fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 67 | `inline_q9_prevention_length_block` | B | 関数化 | prevention長さ判定を関数化し意志依存fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 68 | `inline_q10_knowledge_boundary_warn` | B | 関数化 | q10知識境界WARNを関数化し境界未記入fixtureを追加 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 135/135 PASS |
| 69 | `inline_q11_guard_duplicate_block` | B | 関数化 | q11 guard重複BLOCKを関数化しGuard一覧fixtureを追加 | pending | 未実施 |
| 70 | `inline_q11_existing_alternative_block` | B | 関数化 | q11既存代替BLOCKを関数化し既存確認fixtureを追加 | pending | 未実施 |
| 71 | `inline_lock_contention_warn` | B | 関数化 | flock競合WARNを関数化しlock wait副作用を明示 | pending | 未実施 |
| 72 | `warn_q5_pair_missing_session_state` | C-2 | 保護 | 既に独立関数でrecord_warn_reasonを持ち、関数化済みのため名称・本体を保護 | done | 保護対象のため変更不要 |
| 73 | `warn_missing_prev_cmd_lesson` | C-2 | 保護 | 前cmd学習継承BLOCKの診断文が専用で、統合すると学習因果が切れる | done | 保護対象のため変更不要 |
| 74 | `show_three_layer_memory_ruling_info` | C-2 | 保護 | 表示補助のみでrecord_reasonなし、三層記憶裁定の露出粒度を守る | done | 保護対象のため変更不要 |
| 75 | `show_gunshi_pane_status.ac_structure_incomplete` | C-1 | 名称修正 | 実態はAC構造WARNでありpane status名では検索できないためリネーム | done | `scripts/cmd_save.sh`で実態名の独立関数へ抽出済み; 関連bats 135/135 PASS |
| 76 | `show_gunshi_pane_status.unverified_assumption_block` | C-1 | 名称修正 | 実態は未検証前提BLOCKであり関数名をassumption検証へ合わせる | done | `scripts/cmd_save.sh`で実態名の独立関数へ抽出済み; 関連bats 135/135 PASS |
| 77 | `show_gunshi_pane_status.assumption_source_path_block` | C-1 | 名称修正 | 実態はsource path存在確認BLOCKであり名称乖離を解消 | done | `scripts/cmd_save.sh`で実態名の独立関数へ抽出済み; 関連bats 135/135 PASS |
| 78 | `show_gunshi_pane_status.claim_date_warn` | C-1 | 名称修正 | 実態はclaim日付WARNであり名称を鮮度検査へ合わせる | done | `scripts/cmd_save.sh`で実態名の独立関数へ抽出済み; 関連bats 135/135 PASS |
| 79 | `show_gunshi_pane_status.negative_claim_grep_warn` | C-1 | 名称修正 | 実態は否定claim反証WARNであり名称をgrep evidence検査へ合わせる | done | `scripts/cmd_save.sh`で実態名の独立関数へ抽出済み; 関連bats 135/135 PASS |
| 80 | `show_gunshi_pane_status.bulletin_count_grep_warn` | C-1 | 名称修正 | 実態はbulletin件数grep証跡WARNであり名称を件数検証へ合わせる | done | `scripts/cmd_save.sh`で実態名の独立関数へ抽出済み; 関連bats 135/135 PASS |
| 81 | `inline_session_state_queue_presence_warn` | B | 関数化 | session_state queue file存在WARNを関数化し重複呼出しを明示 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |
| 82 | `inline_session_state_cmd_block_presence_warn` | B | 関数化 | session_state cmd block存在WARNを関数化し重複呼出しを明示 | done | `scripts/cmd_save.sh`で独立関数へ抽出済み; 関連bats 136/136 PASS |

Phase 2件数検証:

```bash
python3 - <<'PY'
from pathlib import Path
import re, collections
text=Path('docs/research/cmd_save_gate_catalog.md').read_text()
section=text.split('## 7. Phase 2 処置判定表',1)[1]
rows=[l for l in section.splitlines() if re.match(r'\| [0-9]+ \|', l)]
counts=collections.Counter(r.split('|')[4].strip() for r in rows)
print('rows', len(rows))
print(dict(counts))
print('total', sum(counts.values()))
PY
```
