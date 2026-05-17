# セマンティック監査: 因果NW導入後スクリプト変更 (9ファイル)
<!-- generated: 2026-05-17T20:40:00+09:00 by gunshi idle analysis -->

## 対象

直近20コミットで変更されたスクリプト9本:
- scripts/causal_backlinks.sh (新規)
- scripts/cmd_save.sh
- scripts/deploy_task.sh
- scripts/gates/gate_lesson_health.sh
- scripts/gates/gate_shogun_startup.sh
- scripts/inbox_watcher.sh
- scripts/lesson_write_shogun.sh
- scripts/ninja_monitor.sh
- scripts/pending_decision_write.sh

## 検出結果

| ファイル | カテゴリ | 問題 | 優先度 | 対処 |
|---------|---------|------|--------|------|
| cmd_save.sh L806 | side_effect | check_origin_field regexが`[[ルール/殿裁定]]`のみ許容。`[[cmd_XXXX]]` `[[LGXXX]]`にマッチせず偽陽性WARN量産 + ERE `[^\]]+`が「not-backslash」解釈 | P0 | **D0修正済み**(commit 948057bb) |
| causal_backlinks.sh L30-36 | silent_failure | rg 0件ヒット時exit 1(set -euo pipefail)。将来デーモンから呼ばれた場合にクラッシュ源 | P3 | 現時点安全(スタンドアロンCLI) |
| gate_shogun_startup.sh L1056 | silent_failure | python3エラー完全吸収(`2>/dev/null \|\| true`)。YAML不正時に空結果→WARNで検知されるがエラー詳細は消失 | P2 | WARNで部分検知あり |

## 問題なし確認済みファイル

| ファイル | 変更内容 | 評価 |
|---------|---------|------|
| inbox_watcher.sh | MTIME_POLL fallback追加(WSL2 inotifywait 3hハング対策) | clean。set+eスコープ適切。zombie risk P3のみ |
| deploy_task.sh | inject_causal_links()追加。`\|\| true`で呼出し(Level5 optional) | clean。tmpfile cleanup適切 |
| lesson_write_shogun.sh | origin引数追加。手動f.write使用(yaml.dump禁止遵守) | clean |
| pending_decision_write.sh | origin引数追加。_atomic_write_text使用 | clean |
| ninja_monitor.sh | snapshot乖離補正(idle+CTX>0%→capture-pane検証) | clean |
| gate_lesson_health.sh | is_set_value()から「未設定」チェック削除 | clean |

## セマンティクスインデックス確認

- drift: なし(因果リンク関連概念は`codd_methodology`に登録済み)
- gap: `causal_backlinks.sh`が`codd_methodology`概念のresourcesに未登録 → insight INS-20260517-203820164-47f9に記録済み

## ERE `[^\]]+` バグの一般教訓

POSIX ERE(grep -E)のブラケット式では`\`はエスケープ文字ではなくリテラル。
- `[^\]]` = 「backslashでもなく」then リテラル`]` (意図と異なる)
- `[^]]` = 「`]`以外」(`]`を`^`直後に置く) (正しい)
- awkでは`[^\\]]`が「backslash以外」として正しく動く（異なる仕様）

他スクリプトに同パターンなし(grep確認済み)。

## 5カテゴリ並列エージェント監査結果 (統合)

3カテゴリ(silent_failure/side_effect/race_condition)を並列エージェントで実行。
直接分析(implicit_assumption/state_transition)と統合した結果:

### P0 (即時修正) — 1件
| # | ファイル | 問題 | 対処 |
|---|---------|------|------|
| 1 | cmd_save.sh L806 | origin regex ERE解釈バグ+パターン狭 | **D0修正済み** commit 948057bb |

### P2 (中) — 4件 (実運用影響は限定的)
| # | ファイル | カテゴリ | 問題 | 評価 |
|---|---------|---------|------|------|
| 2 | gate_shogun_startup.sh L1056 | silent_failure | python3エラー吸収(2>/dev/null\|\|true) | 空結果→WARN検知あり。エラー詳細は消失 |
| 3 | ninja_monitor.sh L3094 | side_effect | check_agent_busy rc=2(UNKNOWN)をbusy扱い→偽陽性in_progress | 偽idle(見逃し)より安全。意図的なfail-safe |
| 4 | pending_decision_write.sh L166-200 | race_condition | dashboard.md RMWがflock対象外 | 実運用で並行PD作成は稀。低発火リスク |
| 5 | deploy_task.sh L2591-2623 | race_condition | inject_causal_links非atomic(tmp→cp) | `\|\| true`呼出し+配備直列実行で緩和 |

### P3 (低) — 3件
| # | ファイル | カテゴリ | 問題 |
|---|---------|---------|------|
| 6 | causal_backlinks.sh L30-36 | silent_failure | rg 0件→exit 1。呼出元なし(スタンドアロン) |
| 7 | inbox_watcher.sh L821-843 | race_condition | MTIME_POLL TOCTOU。最悪10s遅延、次ポールで捕捉 |
| 8 | lesson_write_shogun.sh L91-97 | side_effect | origin="未指定"がgate検査で再WARN(重複通知) |

### エージェント検出→偽陽性/過大評価フィルタ
| エージェント判定 | 実際 | 理由 |
|----------------|------|------|
| deploy_task.sh mktemp P0 | P3 | set -euo pipefailで関数abort→\|\| trueでcatch。task_file無影響 |
| deploy_task.sh TOCTOU P0 | P2 | 配備は直列実行(1忍者ずつ)。並行アクセスは発生しない |
| cmd_save.sh read-race P0 | P3 | WARNのみ。race発生してもstale値でWARNが出る/出ないだけ |
| inbox_watcher.sh set+e P1 | P3 | set+e内は全て\|\| true。process_unread前にset -e復帰 |

### 因果チェーン (全体)
```
因果NW導入(cmd_2819-2823)
  → 5スクリプトにorigin関連変更
  → cmd_save.sh regex不備(ERE知識不足×初期パターン狭) → D0修正
  → 他4スクリプトはclean(flock/atomic/optional guard適切)
  → エージェント過大評価パターン: 「\|\| true」を見てsilent failureと判定するが
    実際にはLevel5 optional(失敗しても機能に影響なし)の設計意図
```
