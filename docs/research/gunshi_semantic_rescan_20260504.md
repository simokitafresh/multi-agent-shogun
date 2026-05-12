# セマンティック再スキャン結果 — 修正後(12件CLEAR)のコードベース

- 調査者: 軍師 (gunshi)
- 日付: 2026-05-04
- 手法: 5並列エージェント(silent failure全224本/副作用/state transition/implicit assumption/race condition)

## 要約

| カテゴリ | 検出数 | 前回比 |
|---------|--------|--------|
| silent failure (全224本) | 42件 | 前回7件(5本限定)→6倍。範囲拡大効果 |
| 修正副作用 | 5件 | **新規カテゴリ。2件P0** |
| state transition | 1件 | 新規 |
| implicit assumption | 8件 | 前回4件→支援スクリプト拡大 |
| race condition | 4件 | 新規(修正起因含む) |
| **合計(重複排除後)** | **~55件** | |

## P0: 即時修正必要 (2件)

### P0-1. cmd_2533副作用: trim_cmd_chronicle flock失敗→archive_completed.sh全体exit
- **原因**: cmd_2533でchronicle flock failureをreturn 1で伝播するよう修正→しかしtrim_cmd_chronicle(L1618)の呼出しに`|| true`がない→set -euo pipefailでarchive_completed.sh全体がexit 1
- **影響**: chronicle flock timeout→以降のレポート/STK/dashboardアーカイブが全スキップ
- **修正**: L1618に`|| true`追加。chronicle失敗はWARN only で処理続行

### P0-2. cmd_2539副作用: set +e/set -eの危険な範囲
- **原因**: archived_count取得でset +eを使用→その間の全エラーが無視される
- **影響**: set +e区間でpending_decisions破損が見逃される
- **修正**: set +e/set -eの範囲を最小化。captured_rc=$?の直後にset -e復帰

## P1: 高優先度 (6件)

### P1-1. detect_task_type _exact/_normal未認識 (state transition)
- cmd_complete_gate.sh L1966-1976のdetect_task_typeが`_exact/_normal`を"unknown"と判定
- deploy_task.sh L5017で設定→cmd_complete_gate.shで未認識→type別処理が欠落

### P1-2. cmd_2530副作用: fallback_report_allowed厳格すぎ
- マルチワーカー配備時、current_assigneesに含まれない忍者のlessonが記録されない
- parent_cmdチェックをprimaryにし、assigneeはsecondaryに

### P1-3. cmd_2529副作用: overflow cap=10がgate CLEAR待ち報告も対象
- 並行完了時に15+報告→cap超え分が古い順に強制archive→gate待ち報告が誤archive
- gate CLEAR待ち(status=pending)を明示的に除外

### P1-4. verdict→status非atomic (race condition, 修正副作用)
- report_field_set.shでverdict書込み→flock解放→status書込みの間に中間状態が見える
- yaml_field_set 2回→batch化で1回に

### P1-5. auto_draft_lesson.sh引数不一致 (implicit assumption)
- lesson_write.shの6番目引数にSOURCE_CMDを渡している(auto_failure_lesson.shは空文字)
- 修正: L212を`"" --status draft`に統一

### P1-6. cmd_absorb.sh:243 grep失敗→空変数 (silent failure)
- grep失敗時matches=''→stale lessons警告スキップ→吸収済みcmdの孤立教訓が未検出

## P2: 中優先度 (8件)

- archive_completed.sh write_archive_done_from_metrics flock未保護 (race)
- ninja_monitor.sh フォアグラウンドinbox_writeのメインループブロック (race)
- cmd_quality_log.sh:130 verdict_line空文字化 (silent failure)
- gate_gunshi_report_precheck.sh:190 CMD_SPEC空文字化 (silent failure)
- inbox_write.sh:1028/1051 find+sort|head空文字化 (silent failure)
- pre-karo-edit-guard.sh:90 cmd_id空→編集制御迂回 (silent failure)
- deploy_task.sh:258 awk失敗→親cmd参照喪失 (silent failure)
- bulletin_write.sh BULLETIN_NOTIFY通知テスト不足 (implicit assumption)

## P3: 低優先度 (20+件)

cmd_complete_gate.sh内の14件(model label/timestamp/CI status等)、
gunshi_next_action.sh 4件、cdp_measure.sh 1件、ci_status_check.sh 2件、
bulletin_write.sh 2件、その他支援スクリプト。
いずれもgrep結果が空→デフォルト値使用で動作は継続するが、精度が低下する。

## 前回→今回の比較

| 指標 | 前回(初回) | 今回(再スキャン) |
|------|----------|----------------|
| スキャン範囲 | 主要5本 | 全224本 |
| 検出数 | 23件 | ~55件 |
| 修正件数 | 12件CLEAR | - |
| 残存urgent | 5件→0件 | P0: 2件(修正副作用) |
| 新規カテゴリ | - | 修正副作用(5件) |

## 修正副作用の教訓

12件の修正のうち5件(42%)に副作用が発生。根因パターン:
1. **return 1伝播の波及範囲未確認**: set -euo pipefail環境でreturn 1が想定外の箇所に波及(P0-1)
2. **set +e/set -eの広すぎるスコープ**: エラー無視区間が意図より広い(P0-2)
3. **フィルタ条件の厳格化による偽陰性**: マルチワーカーケースの考慮漏れ(P1-2)
4. **上限値の固定**: 進行中状態の除外漏れ(P1-3)
5. **非atomic 2ステップ更新**: 中間状態の可視化(P1-4)

generated: 2026-05-04T00:55:00+09:00
