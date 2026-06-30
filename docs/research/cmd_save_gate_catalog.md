# cmd_save.sh Gate設計思想カタログ

> cmd_3608 Phase 1 / recon1_front_half_29_functions  
> 作成者: hanzo / 作成日: 2026-06-30  
> 対象: `scripts/cmd_save.sh` check/gate系定義順の前半29件

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
| 3 | `check_gate_script_execution_evidence` | cmd_3360 | grepだけでgate/script未実行判断する事故 | L4 | preflight | BLOCK | `record_block_reason`, stderr/stdout | q5に実行コマンド・exit code・出力要点あり | q5がgrep/コード断片のみ | `tests/unit/test_cmd_save_q5.bats` | `scripts/cmd_skeleton.sh:110` | O(text grep) | 個別FP率未記録 | LS063/LS-A22 | 2026-06-26 | なし | `[[cmd_3360]] -> [[実行せず起票]] -> [[q5実行証拠BLOCK]]` |
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
| 18 | `check_cmd_text_pipe_danger` | D008 pipe-to-shell防御 | `curl|bash`等の危険操作 | L4 | save | BLOCK/WARN | block/warn | 危険パターンなし | pipe-to-shell記載 | `tests/unit/test_cmd_save.bats` | indirect | O(text grep) | 個別FP率未記録 | Destructive D008 | 2026-06-26 | なし | `[[remote code execution]] -> [[pipe_to_shell]] -> [[D008防御]]` |
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
