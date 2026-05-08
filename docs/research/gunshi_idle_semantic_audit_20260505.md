# セマンティック監査結果 2026-05-05

## 概要

直近変更スクリプト17本に対して3カテゴリ(silent_failure/state_transition/implicit_assumption)の並列セマンティック監査を実施。

## 対象スクリプト

cmd_2542以降に変更: archive_completed.sh, auto_draft_lesson.sh, bulletin_write.sh, cmd_absorb.sh, cmd_complete_gate.sh, cmd_save.sh, deploy_task.sh, gate_loop_health.sh, gate_shogun_startup.sh, gunshi_next_action.sh, lesson_write.sh, yaml_field_set.sh, log_terminal_input.sh, report_field_set.sh, semantic_index_update.sh, semantic_map_generate.sh, semantic_search.sh

## 検出→検証後の実問題(P2)

### 1. cmd_complete_gate.sh L5177 — 非同期status更新競合(P2)
- `(yaml_field_set ... status completed ... || true) &` でstatus:completedを非同期書込み
- 後続のarchive_completed.shがstatus:completedを前提とするが、waitなし
- 実害: flock使用のため数ms完了。実害報告ゼロ。理論的競合のみ
- 対策不要: WSL2 NTFSのflock遅延対策として意図的非同期(LG016参照)

### 2. deploy_task.sh L5126-5130 — rollback時の部分クリア(P2)
- 重複配備BLOCK時のrollback: 5つのyaml_field_setが`|| true`で連鎖
- flock timeout発生時に中間のフィールドだけクリアされる可能性
- 実害: flock timeout自体が極めて稀(WSL2 NTFS特有。通常数ms)
- 対策不要: 実害報告ゼロ

## 偽陽性(検証で除外)

1. **report_field_set.sh L1121 recursion**: スキャナーは無限再帰を指摘したが、verdictをFAILに設定後は再帰条件(INCONSISTENT)を満たさない。最大1回で停止
2. **semantic_index_update.sh L52 flock subshell**: exit 1はsubshell内で正常動作。親スクリプトはsubshell外で実行されない
3. **awk field order**: yaml_field_set.sh経由でYAML構造が保証されており、直接awkパースのfield order問題は該当しない

## D0修正(同日実施)

- **index.md**: 重複3概念削除+discussion汚染2件サニタイズ(commit 03245e5c)
- **semantic_index_update.sh**: summary 120文字制限+XMLタグ除去+重複IDスキップ(commit 513fc3c7)
- **insights**: semantic_index関連14件resolve、重複通知6件resolve(38→18件)

## スキャナー偽陽性判別3基準（次回セマンティック監査用）

スキャン結果を鵜呑みにするな。以下3基準で現物検証してから報告:

1. **`|| true`が意図的か**: オプショナル機能(semantic_index_update, log_terminal_input等)の`|| true`はcmd本流に影響しない設計上の意図的パターン。P1→P3格下げ
2. **再帰の出口条件**: `bash "$0" ... verdict FAIL` → verdictをFAILに設定した後は再帰条件(INCONSISTENT)が消える → 最大1回で停止。**再帰先で状態が変わるかを現物で確認**
3. **async `&`のflock保護**: yaml_field_set.shはflock使用で数ms完了。async書込みの後続読取りとの競合は理論的のみ(実害報告ゼロでP2)

## insights batch処理4パターン（次回棚卸し用）

1. **蓄積通知**(stale_report N件蓄積): 最新のみ保持。旧はduplicate resolve
2. **高頻度FAIL**: gate_fire_logでFAIL直後にPASSがあるか確認 → 全件リトライPASS = 免疫正常 = 追加gate不要
3. **semantic_index LOW一致**: index.mdに手動追記して解消 → batch resolve
4. **DREAM計測**: 現物計測(grep/wc)で効果実証 → resolve

## 因果鎖

auto-update hook(semantic_index_update.sh)→未サニタイズ入力+重複チェックなし→index.md汚染+重複(負の複利)→サニタイズ+重複ガード実装→データ品質回復+再発防止(正の複利)。修正は全P2以下でcmd起票不要。
