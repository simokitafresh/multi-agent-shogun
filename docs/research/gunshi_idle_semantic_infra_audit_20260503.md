# セマンティック・インフラ監査 — 全バグ統合レポート

- 調査者: 軍師 (gunshi)
- 日付: 2026-05-03
- 手法: 4並列エージェントによるセマンティック探索(silent failure / state transition / race condition / implicit assumption)
- 殿指示: 「grepでは見逃すセマンティック検索」

## 要約

grep不可能なバグ**23件**検出(重複排除後)。urgentクラス5件。

## Tier 1: urgent (再発性+影響大)

### U1. archive_completed.sh — gate_metrics.logローテーション後のfallback崩壊
- **現象**: gate_metrics.logがローテーション(MAX_LINES=1000)→古いcmdのCLEAR記録が消失→fallback判定(L1103)失敗→report永久SKIP
- **根因**: L1103は現行gate_metrics.logのみ参照。archive/gate_metrics_*.logを見ない
- **影響**: バグ1(161件stale report)の根因の一つ。時間経過で悪化する負の複利
- **修正案**: fallback検索をarchive/gate_metrics_*.logにも拡張。またはarchive.done不在+一定日数経過→強制archive
- **行番号**: archive_completed.sh:1101-1106, rotate_gate_metrics.sh:46-51

### U2. archive_completed.sh — review_gate.done placeholder上書き漏れ (54件)
- **現象**: deploy_task.shが配備時にreview_gate.doneを`source: deploy_preflight`で仮作成。karo_direct配備やCI修正cmdで本物に上書きされない
- **根因**: placeholder→本物への上書きがGATEフロー内(cmd_complete_gate.sh)でのみ実行。GATE未通過cmdはplaceholder永久残存
- **影響**: archive_completed.sh L1112-1115でSKIP→report永久残存(54件)
- **修正案**: GATE CLEAR時にplaceholder上書きを保証。またはplaceholderを一定日数後に有効扱い
- **行番号**: archive_completed.sh:1112-1115, deploy_task.sh(review_gate.done仮作成箇所)

### U3. cmd_complete_gate.sh:81-142 — flock timeout時のunwrap_result空文字沈黙
- **現象**: auto_unwrap_report_yamlでflock timeout→exit 1→unwrap_resultが空→case文の全パターン不一致→**完全沈黙**
- **根因**: case文に空文字列(`""`)のハンドリングなし
- **影響**: レポートYAML破損が検出されず後段のgate検査が不正結果を返す
- **修正案**: case文にデフォルト(`*`)パターンを追加し、空文字列=flock_timeout扱い
- **行番号**: cmd_complete_gate.sh:81-142

### U4. report status: pending永久残存 → archive不能
- **現象**: report_field_set.shがstatus:pendingを自動注入(L3316)。忍者がverdict書込み時にstatusを更新しない→status:pendingのまま→archive_completed.sh L1124でsweep対象外
- **根因**: verdict→status遷移ロジックが不在。verdictとstatusが独立フィールド
- **影響**: 237件stale reportの一因。pending報告は永久にarchiveされない
- **修正案**: verdict書込み時(report_field_set.sh)にstatus自動更新(PASS/FAIL→completed)
- **行番号**: report_field_set.sh:3316-3322, archive_completed.sh:1120-1129

### U5. archive_completed.sh:137 — サブシェルreturn偽装成功
- **現象**: chronicle sync内のflock timeout→`return 1`→**サブシェル内のreturnは親に伝播しない**→後続の`echo "synced"`が無条件実行
- **根因**: bashのサブシェル内return=サブシェル終了のみ。親シェルの実行フローに影響しない
- **影響**: chronicle更新失敗が「成功」として記録される
- **修正案**: サブシェルの戻り値を`$?`で捕捉、またはflock外で結果変数チェック
- **行番号**: archive_completed.sh:137,209,219

## Tier 2: high (潜在的+特定条件で発生)

### H1. deploy_task.sh:688,983 — mktemp未検証
- mktemp失敗(ディスクフル/NTFS遅延)→py_output空→Python出力消滅→エラー検出不可
- L983はさらに`|| true`でPython失敗も握りつぶし→AC検証が沈黙スキップ
- **行番号**: deploy_task.sh:688, 983-984

### H2. karo_direct配備時のtask_id/parent_cmd/report_filename未更新
- deploy_task.sh `--direct`フラグ(L156)→reset_stale_fields(L272-368)未呼出→古いcmdのフィールド残存
- kotaro stale事故(2026-05-03)と同構造。全karo_direct配備で潜在発生
- **行番号**: deploy_task.sh:143-156, 272-368

### H3. cmd_complete_gate.sh:2817 — glob展開後のファイル増減レース
- MATCHING_TASK_FILESをglob(L2817)→ループ中にdeploy_task.shが新タスク追加/archive_completed.shが移動→処理漏れ/不整合
- **行番号**: cmd_complete_gate.sh:2817-2823

### H4. inbox_write.sh:255 — mv失敗時のメッセージ消失
- tmp_file書込み成功→mv失敗(inbox_fileがflock長時間保持)→tmp_fileは残存、inbox_fileは未更新
- **行番号**: inbox_write.sh:255-265

### H5. ninja_monitor.sh:2263 — inbox_watcher kill→ゾンビ残存
- 古いinbox_watcher.shにkill送信(SIGTERM)→ハング状態で終了せずゾンビ化→新旧watcher共存→メッセージインターセプト
- **行番号**: ninja_monitor.sh:2263-2337, 2311-2320

## Tier 3: medium (稀な発生条件/影響限定)

### M1. archive_completed.sh:397 — 二重flock timeout時のpending_decisions無視
### M2. ninja_monitor.sh:173 — inbox_write.sh戻り値無視(バックグラウンド実行)
### M3. report_field_set.sh — 複数フィールド更新の非atomic性
### M4. archive_completed.sh:1169 — archive.doneチェックのTOCTOU
### M5. bulletin_write.sh→inbox_watcher.sh — watcher未起動時の通知喪失
### M6. task in_progress→idle自動遷移なし — 次タスク配備BLOCK
### M7. cmd delegated→done遷移の非決定性 — completed_ids 2源不完全
### M8. cmd_complete_gate.sh:1977 — symlink+原本の重複カウント

## 因果鎖(全体)

```
配備経路分岐(deploy_task.sh vs karo_direct)
  → フィールド未更新(H2) + placeholder残存(U2)
  → archive条件不成立(U1+U4) + gate_metrics消失(U1)
  → stale report 237件蓄積(バグ1)
  → cmd_complete_gate.sh glob交差汚染(バグ2)
  → 偽BLOCK + manual_override(家老の時間消費)
  → 負の複利(時間経過で蓄積)
```

## 修正優先度マトリクス

| ID | 修正規模 | 影響範囲 | 頻度 | ROI |
|----|---------|---------|------|-----|
| U4 | 小(1行追加) | 237件解消 | 毎cmd | ★★★★★ |
| U3 | 小(1行追加) | gate信頼性 | 稀だが致命的 | ★★★★ |
| U5 | 小(変数捕捉) | chronicle正確性 | WSL2 flock時 | ★★★★ |
| U1 | 中(archive検索拡張) | stale解消 | ローテ後 | ★★★★ |
| U2 | 中(上書きロジック) | 54件解消 | karo_direct時 | ★★★ |
| H2 | 中(reset_stale統合) | karo_direct全件 | 配備時 | ★★★ |

## grepでは見つからなかった理由

| バグ | なぜgrepで見つからないか |
|------|------------------------|
| U1 | 「gate_metrics.logを参照」は正常。**ローテーション後に参照範囲が縮小する**という意味的推論が必要 |
| U3 | case文の各パターンは正常。**空文字列がどのパターンにもマッチしない**という網羅性分析が必要 |
| U4 | status:pendingの設定もarchiveのcase文も各々正常。**両者の間に遷移ロジックが不在**という不在の検出が必要 |
| U5 | `return 1`は正しいbash構文。**サブシェル内returnが親に伝播しない**というbashセマンティクスの理解が必要 |
| H2 | `--direct`フラグの処理は正常。**呼ばれない関数(reset_stale_fields)の効果**という制御フロー分析が必要 |

generated: 2026-05-03T22:50:00+09:00
