# スクリプト速度監査 2026-06-20

殿指示: 「速度が遅いスクリプトや仕組みはバグだ。品質向上しながら速度向上もしよう」(04:54)
殿指示: 「遅いスクリプトはないか？品質を落とさずに速度を改善しよう」(14:14)
殿指示: 「ほかに改善するべき.shや.pyはないか？もう十分と思ったら洗脳の影響」(14:22)
殿指示: 「まず自分で改善できることは極限までやろう。20行制限にこだわらずやってみよ」(14:31)
殿指示: 「続けて」(15:21, 15:26)

## D0実装結果（本セッション）

| # | 対象 | before | after | 改善率 | commit | 手法 |
|---|------|--------|-------|--------|--------|------|
| 1 | report_precheck | 8,729ms | 3,980ms | 2.2x | 67334cb76 | python3 6回→engine統合 |
| 2 | startup_gate | 9,025ms | 3,000ms | 3.0x | f9b77b73d | python3→awk+lord_conversation並列化 |
| 3 | sync_lessons | 7,187ms | 67ms | 107x | RC修正待ち | mtimeスキップ(-lt安全側) |

累計削減: 24,941ms → 7,047ms（3.5倍高速化、毎日~18秒節約）

## D0限界到達

2-3秒台スクリプト(gate_context_freshness/vercel_phase/silent_fallback/dashboard_auto_section)はpython3呼出し0-1回。ボトルネックはWSL2 NTFSのI/O遅延(git/grep/awk)であり、コード最適化の効果は限定的。

残るcmd起票候補:
- ralph_loop_metrics.sh 20秒: for+glob+gawkループ→バッチ化(D0範囲超)

## 実測結果（全スクリプト、ms単位）

| スクリプト | 時間(ms) | 呼出頻度 | 累積影響 |
|-----------|----------|---------|---------|
| gate_gunshi_report_precheck.sh | 5,760 | 毎レビュー(~20/日) | **115秒/日** |
| gate_gunshi_startup.sh | 3,828 | 毎セッション起動(~5/日) | 19秒/日 |
| gate_lesson_health.sh | 1,543 | startup内 | startup内 |
| gate_report_format.sh | 1,302 | precheck内+独立 | precheck内 |
| ac_physical_verify.sh | 1,371 | draft review時 | 中 |
| semantic_search.sh | 904 | 三層記憶検索(多) | 中 |
| gate_gunshi_cs_checklist.sh | 785 | startup内 | startup内 |
| gate_no_hardcoded_ninja_list.sh | 475 | startup内 | 低 |
| bulletin_write.sh | 408 | 投稿時 | 低 |
| memory_db_query.sh | 190 | 三層記憶検索 | 低 |
| inbox_write.sh | 93 | 通信時 | 低 |
| pre-write-edit-combined.sh | 17 | 全Edit/Write | ✅高速 |

## ボトルネック分析

### 1. gate_gunshi_report_precheck.sh (5,760ms) — 最優先

内部で以下を逐次実行:
- gate_report_format.sh (~1,300ms) — python3起動+YAML解析
- gate_ninja_workaround_rate.sh (~26ms) — 高速
- git show/log 複数回 (~500ms)
- semantic_search.sh (~900ms) — SG-PRE22
- python3 engineスクリプト (~1,500ms)
- 残りのSG-PRE (~1,500ms)

改善案:
1. **python3起動回数削減**: gate_report_format(python)+engine(python)を1プロセスに統合
2. **semantic_search結果キャッシュ**: startup時の結果を/tmpに保存、precheck時に再利用
3. **SG-PRE並列化**: 独立したチェック(PRE2/PRE8/PRE9等)を`&`で並列実行

### 2. gate_gunshi_startup.sh (3,828ms)

内部で以下を逐次呼出し:
- gate_lesson_health.sh (~1,500ms)
- gate_gunshi_cs_checklist.sh (~800ms)
- semantic_search.sh (~900ms)
- 残り(~600ms)

改善案:
1. **gate_lesson_health/cs_checklistの並列化**: 相互依存なし→`&`+`wait`
2. **YAML解析の共有**: 同一ファイル(review_log等)を複数gateが個別解析→1回解析+結果共有

### 3. semantic_search.sh (904ms) — 前セッション報告済み

根因: 526KB JSONを毎回python3で全文パース。
改善案: jqベースのキャッシュ付き検索、またはSQLiteインデックス化。

## 第2回計測結果（殿指示: もう十分と思ったら洗脳）

| スクリプト | 時間(ms) | 呼出頻度 |
|-----------|----------|---------|
| **ralph_loop_metrics.sh** | **20,288** | 分析時 |
| **sync_lessons.sh infra** | **7,249** | 教訓登録時 |
| **sync_lessons.sh dm-signal** | **6,423** | 教訓登録時 |
| gate_karo_startup.sh | 3,315 | 家老毎起動 |
| dashboard_auto_section.sh | 1,872 | cmd完了時 |
| gate_vercel_phase.sh | 1,872 | cmd完了時 |
| gate_silent_fallback.sh | 1,703 | cmd完了時 |
| gate_context_freshness.sh | 1,630 | startup内 |
| build_instructions.sh | 691 | 教訓変更時 |
| causal_backlinks.sh | 462 | レビュー時 |
| gate_cycle_health.sh | 188 | startup内 |
| pre-bash-combined.sh | 25 | 全Bash hook |
| prompt_state_inject.sh | 17 | 全prompt |
| session_start_inject.sh | 23 | セッション起動 |

## 優先順位（全計測統合、累積影響×改善容易性）

1. **ralph_loop_metrics.sh 20秒** — 異常。根因調査必要
2. **sync_lessons.sh 7秒** — 教訓登録毎。821件YAML全文パース→キャッシュ化
3. **report_precheck内python統合** — 最大頻度効果(5.7秒→推定2秒)
4. **startup gate並列化(gunshi+karo)** — 3.8+3.3秒→各推定2秒
5. **semantic_search高速化** — 全箇所に波及
6. **dashboard_auto_section/vercel_phase/silent_fallback** — 各1.7-1.9秒、完了時影響

## 第3回計測（殿指示: ほかにないか。頻度が高いものは影響大）

### コールド vs ウォーム

pre-write-edit-combined.shは初回2.5秒→ウォーム36-63ms。WSL2 9pキャッシュ効果。
しかし他スクリプトはウォームでも遅い:
- report_precheck: ウォーム 8-17秒
- startup_gate: ウォーム 7-9秒
- sync_lessons: ウォーム 8秒
- ralph_loop_metrics: ウォーム 17秒

### 根因特定

| スクリプト | python3呼出 | yaml.load呼出 | 推定コスト |
|-----------|------------|-------------|----------|
| report_precheck | 12回 | 8回 | 12×650ms≈7.8秒 |
| startup_gate | 7回 | 2回 | 7×650ms≈4.6秒 |
| sync_lessons | 1回 | 1回(821件) | YAML 821件パース |

**共通根因: python3プロセスの多重起動**。各python3起動~150ms + yaml.load~500ms = ~650ms/回。

### 改善計画

1. **report_precheck**: 12回のpython3→1プロセスに統合。推定 8秒→1秒
2. **startup_gate**: 7回のpython3→2プロセスに統合。推定 7秒→2秒
3. **sync_lessons**: 821件YAML→JSONキャッシュ化(既にdeploy_task.shで実装済み)
4. **ralph_loop_metrics**: git log多重呼出しの最適化
