# セマンティック監査 — cmd_2681-2684変更5スクリプト
<!-- generated: 2026-05-12T12:05:00+09:00 by gunshi idle analysis -->

## 対象

cmd_2681-2684(二重配備3層防御) + cmd_karo_ci_fix_e2e_parallel で変更された5スクリプト:
1. scripts/ac_physical_verify.sh
2. scripts/deploy_task.sh
3. scripts/hooks/session_start_inject.sh
4. scripts/inbox_write.sh
5. scripts/ninja_monitor.sh

## 監査方法

5カテゴリ並列エージェント起動 → P0検出 → 現物検証(偽陽性除外)

## P0検出結果(4件→2件真の問題)

| P0 | ファイル | カテゴリ | 判定 | 影響度 |
|----|---------|---------|------|--------|
| P0-1 | deploy_task.sh | state_transition | **真の問題** | 低～中 |
| P0-2 | inbox_write.sh | state_transition | 偽陽性 | N/A |
| P0-3 | ninja_monitor.sh | state_transition | 偽陽性 | N/A |
| P0-4 | ninja_monitor.sh | race_condition | **真の問題(低リスク)** | 低 |

### P0-1: deploy_task.sh yaml_field_set 5回非atomic

**現象**: deploy_task_has_completed_peer_report判定後、yaml_field_set 5回(status→idle, parent_cmd→"", _ac_task_id→"", report_path→"", report_filename→"")がflock外で逐次実行。中間状態(status=idleだがparent_cmd非空)が観察可能。

**根因**: yaml_field_setは各呼出しで独立flock。5回の間に他プロセス(ninja_monitor等)がYAML読み取り可能。

**影響**: 低～中。発生確率=低(BLOCK条件がレア)。実害=論理矛盾状態の一時的観察。WA=0継続なので実際の障害発生なし。

**対策候補**: yaml_field_set_batch(同一lockで一括処理)への統合。またはflock包含。

### P0-4: ninja_monitor.sh find→flock間TOCTOU

**現象**: find_completed_parent_cmd_report_for_other_ninja(flock外)の結果を、auto_void_if_parent_cmd_completed(flock内)で使用。find実行～flock取得間にarchive_completed.shがreportを移動する可能性。

**安全網**: (1)auto_void内で再チェック(still_completed_report)実施 (2)archive時にsymlink作成 (3)reportが消失した場合exit 1で安全停止

**影響**: 低。symlink失敗時のみ発火。直近WA=0で実害確認なし。

**対策候補**: find()とauto_void開始を同一flock(ARCHIVE_LOCK)でカバー。

## P0偽陽性2件の除外理由

- **P0-2(inbox_write exit 1)**: サブシェル内exit 1は設計意図通り。callerがstatus=$?で捕捉し、persistence確認で安全判定。
- **P0-3(ninja_monitor orphan化)**: flock内再チェック+exit 1安全弁が実装済み。report消失時は処理中止。

## P1以下サマリ(12件)

| カテゴリ | 件数 | 主な内容 |
|---------|------|---------|
| silent_failure | 5件 | 2>/dev/null による parse error隠蔽、flock失敗無視 |
| state_transition | 2件 | budget truncation、ロック取得失敗後の状態未定義 |
| side_effect | 3件 | 新規ロジック追加による出力変化、context消費増加 |
| implicit_assumption | 2件 | パスハードコード、環境変数依存 |

## 結論

直近変更(二重配備3層防御)の品質は安定。真のP0は2件あるが低リスク(WA=0継続が裏付け)。P0-1(yaml_field_set非atomic)はbatch化で根本対処可能だが、発火確率を考えると優先度は中程度。監視継続。
