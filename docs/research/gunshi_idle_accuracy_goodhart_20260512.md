# Accuracy Goodhart Effect — gate_result不在による精度膨張の発見と根因修正
<!-- generated: 2026-05-12T00:12:00+09:00 by gunshi idle analysis -->

## 要約

gunshi_gate_sync.shが`gate_result: null`のみ検索し、フィールド不在エントリを検出しなかった。
結果、accuracy計算の分母からフィールド不在エントリが除外され、99.6%→97.1%の精度膨張が発生。
Phase 2追加で271件backfill、BLOCK 60件（従来3件）が可視化された。

## なぜなぜ7回

| 回 | 問い | 答え |
|----|------|------|
| 1 | なぜgate_result空文字が20件溜まっていた？ | gate_resultの記入がレビュー時に行われず、後からsyncで埋める構造 |
| 2 | なぜレビュー時にgate_resultを記入しないか？ | レビュー時点ではGATE結果未出。時系列: レビュー→GATE→結果通知→記入 |
| 3 | なぜGATE結果通知がreview_logに反映されないか？ | /gate-syncスキルがあるが手動実行が必要。/clear前にsync未完了 |
| 4 | なぜ/clear前にgate_syncが完了しないか？ | inbox処理(mark_read)とreview_log更新(gate_sync)が別プロセス |
| 5 | なぜinbox受信時にreview_logが自動更新されないか？ | inbox_watcher→nudge→手動/gate-syncの流れ。自動化されていない |
| 6 | なぜ自動化されていないか？ | /gate-syncスキルは作ったがinbox処理フローに統合していない。意志依存 |
| 7 | なぜ意志依存のままか？ | スキル作成で満足。Phase 6「1サイクル目で完璧と思った」と同構造 |

**根因**: gunshi_gate_sync.shのPhase 1がnull検索のみでフィールド不在を検出しない構造バグ。

## 修正内容

gunshi_gate_sync.sh update_log()にPhase 2追加:
- Phase 1(既存): `gate_result: null` → 置換
- Phase 2(新規): gate_resultフィールド不在のdraft/reportエントリ → review_type行直後に挿入

追加修正: Phase 1のgrep結果なし時のpipefail対策(`|| true`)

## 定量結果

| 指標 | 修正前 | 修正後 |
|------|--------|--------|
| gate_result null | 10件 | 0件 |
| gate_resultフィールド不在 | 261件 | 0件 |
| 全体accuracy | 99.6% (678/681) | 97.1% (1984/2044) |
| BLOCK総数 | 3件(visible) | 60件(true) |
| APPROVE/LGTM→BLOCK | 3件 | 48件 |

## BLOCK原因分類(48件APPROVE/LGTM→BLOCK)

| 原因 | 件数 | 軍師レビュー範囲 |
|------|------|-----------------|
| draft_lessons(教訓未登録) | ~20件 | 範囲外(家老プロセス) |
| report_format | ~10件 | precheck範囲 |
| missing_gate(report_merge) | ~5件 | 範囲外(gate固有) |
| ac_version_mismatch | ~5件 | precheck範囲 |
| empty_lessons_useful | ~5件 | precheck範囲(LG006) |
| その他 | ~3件 | 要個別分析 |

大部分(draft_lessons)は軍師レビューの盲点ではなく家老プロセスの問題。
report_format/ac_version系はprecheck(SG-PRE)で捕捉すべき項目。

## BLOCK原因全体像(gate_metrics.log 314件)

| 原因 | 件数 | 軍師範囲 | 備考 |
|------|------|---------|------|
| draft_lessons | 154 | 範囲外 | 家老の教訓登録プロセス |
| missing_gate | 47 | 範囲外 | gate設計(report_merge等) |
| report_format | 42 | precheck | 5月35件中kagemaruの空報告が大半 |
| empty_lessons_useful | 22 | precheck | SG-PRE9対応済み |
| lesson_done_missing | 20 | 範囲外 | hayate11/kagemaru4/saizo3/hanzo2 |
| binary_checks_fail | 14 | レビュー | hayate10/kagemaru2/saizo2 |
| ac_version_mismatch | 5 | precheck | SG-PRE対応済み |
| lesson_candidate_missing | 4 | precheck | SG-PRE対応済み |
| その他 | 6 | 混合 | purpose_validation等 |

月別推移(precheck対象): 4月=12件 → 5月=57件(急増)。
5月急増の主因=kagemaru空報告(二重配備構造問題)+hanzoフィールド欠落。

## 教訓

- **Goodhart効果の実例**: 計測対象(gate_result判明分)を最適化→計測対象外(フィールド不在)が見えなくなる
- **syncスクリプトの検出範囲**: null検索だけでなくフィールド不在も検出すべき
- **消火vs根因修正**: 手動でデータを埋める(消火)→syncの検出漏れを修正(根因)→自動backfillで永続解消
