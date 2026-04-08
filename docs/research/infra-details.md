# インフラ詳細リファレンス
<!-- source: context/infrastructure.md から移動 -->
<!-- last_updated: 2026-02-23 -->

> context/infrastructure.md の索引から参照される詳細情報。

## 目次

- [§1 コンテキスト管理 詳細](#1-コンテキスト管理-詳細)
- [§2 直近改善 cmd_181〜cmd_255](#2-直近改善)
- [§3 ninja_monitor.sh 詳細](#3-ninja_monitorsh-詳細)
- [§4 inbox_watcher.sh 詳細](#4-inbox_watchersh-詳細)
- [§5 ntfy.sh 詳細](#5-ntfysh-詳細)
- [§6 tmux設定 詳細](#6-tmux設定-詳細)
- [§7 編成 詳細](#7-編成-詳細)
- [§8 WSL2固有 詳細](#8-wsl2固有-詳細)

---

## §1 コンテキスト管理 詳細

| エージェント | 外部トリガー | 方法 |
|-------------|-------------|------|
| 忍者 | ninja_monitor.sh | idle+タスクなし → /clear送信（CTX>0%時） |
| 家老 | ninja_monitor.sh | idle+CTX>50% → /clear送信（陣形図付き） |
| 将軍 | 殿の手動操作 | CTX>50%でntfyアラート → 殿が判断 |

| 項目 | 値 |
|------|-----|
| ソフト閾値 | 50%（外部トリガー発動条件） |
| ハード閾値 | 90%（CLAUDE_AUTOCOMPACT_PCT_OVERRIDE） |
| 忍者方式 | /clear（CTX汚染防止。hayate v1→v4事件が教訓） |
| 家老方式 | /clear（陣形図snapshotで状態保全。/compactの5-8分停止を解消） |
| CLI差異 | /compact挙動はCLI種別で異なる。`config/settings.yaml`参照 |
| 設定経路 | settings.json → env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE → 全エージェント自動適用 |
| statusline | イベント駆動。JSON入力にcontext_window.used_percentage含む |

## §2 直近改善

| cmd | 改善 | 問題 | 解決 |
|-----|------|------|------|
| cmd_181 | acknowledged status追加 | assigned状態でCLI停止との区別不能→ゴースト配備誤判定 | assigned→acknowledged→in_progress遷移を明文化 |
| cmd_183 | ペイン消失検知+remain-on-exit | ペイン落ちで配備状態消失→監視不能 | remain-on-exit=on + ninja_monitor.shに自動回復処理 |
| cmd_188 | inbox re-nudge | 初回ナッジ見落とし→未読残存→タスク未着手 | @inbox_unread表示 + ninja_monitor.shから自動再ナッジ |
| cmd_189 | inbox_mark_read.sh | Edit toolはflock非対応→inbox直接編集でLost Update | flock+atomic writeの専用スクリプトで既読化経路統一 |
| cmd_191 | idle家老auto-nudge | pending cmd残存+家老idle→コマンド取りこぼし | ninja_monitor.shがpending cmd検知時に家老へ自動ナッジ |
| cmd_192 | grep -c改行バグ修正 | `grep -c \|\| echo 0`で0件時に`0\n0`化→件数判定崩壊 | awk代替で単一数値返却に統一 |
| PD-016/cmd_239 | 穴3:裁定伝播遅延→検出+警告 | 殿裁定がcontext未反映のまま放置 | resolve時にcontext_synced:false自動付与→gate WARNING（非ブロッキング） |
| PD-017/cmd_239 | 穴2:知識鮮度→deploy時警告 | context/*.mdが古くても検知されない | deploy_task.shがlast_updated検査→14日超WARNING（非ブロッキング） |

## §3 ninja_monitor.sh 詳細

| 機能 | 詳細 |
|------|------|
| idle検知 | CTX>50%で忍者に/clear、家老に/clear自動送信 |
| is_task_deployed() | YAML status + capture-pane + @current_task空チェックの二重チェック（cmd_049修正） |
| STALE-TASK検出 | YAML上作業中だがペインidle → ログ出力して対処 |
| CLEAR_DEBOUNCE | 300秒（5分）でループ防止 |
| get_context_pct() | capture-pane出力から「CTX:XX%」を直接パース（tmux変数は不安定） |
| write_karo_snapshot() | 毎サイクルqueue/karo_snapshot.txt自動生成（家老/clear復帰用圧縮陣形図） |
| KARO_CLEAR_DEBOUNCE | 120秒（2分）— /clear復帰~30秒のため大幅短縮 |
| 状態遷移検知 | cmd_255, commit 11c71d2。同一状態の繰り返し通知排除→状態遷移時のみ通知。nudge嵐解決策の一翼 |

## §4 inbox_watcher.sh 詳細

| 機能 | 詳細 |
|------|------|
| 検知方式 | inotifywaitでqueue/inbox/{agent}.yaml変更検知→send-keysで短ナッジ |
| ナッジ形式 | `inboxN`（例: inbox3=未読3件）。内容は送らない |
| symlink注意 | エージェントリネーム後はsymlink必要（旧名→新名） |
| 手動起動 | `nohup bash inbox_watcher.sh {agent} {pane} claude` |
| fingerprint dedup | cmd_255, commit 4eda239。未読ID集合のsort後hash→同一未読セットへの重複nudge排除 |

## §5 ntfy.sh 詳細

| 項目 | 内容 |
|------|------|
| Usage | `bash scripts/ntfy.sh "メッセージ"` **のみ。引数追加厳禁** |
| トピック | shogun-simokitafresh |
| 既知事故 | インターフェース変更で全通知が無言で壊れた（--sendフラグガード事件） |
| スモークテスト | shutsujin_departure.shに組込み済み |

## §6 tmux設定 詳細

| 項目 | 値 |
|------|-----|
| prefix | Ctrl+A（.tmux.conf設定済み。デフォルトCtrl+Bではない） |
| レイアウト文字列 | `1a7c,167x49,0,0{...}`（shutsujin_departure.shで適用） |
| セッション | shogun / Window 1: main（将軍） / Window 2: agents（8ペイン: 家老+軍師+忍者6） |
| 形式 | shogun:2.{pane_index} |

| pane | 名前 | pane | 名前 | pane | 名前 |
|------|------|------|------|------|------|
| 1 | karo | 4 | hayate | 7 | saizo |
| 2 | sasuke | 5 | kagemaru | 8 | kotaro |
| 3 | kirimaru | 6 | hanzo | 9 | tobisaru |

karo.mdのpanes設定はshogun:2.{N}に修正済み(cmd_206)。`tmux list-panes -t shogun:2`で確認可能。

## §7 編成 詳細

| 階級 | 名前 |
|------|------|
| 上忍(jonin) | 半蔵(hanzo) 才蔵(saizo) 小太郎(kotaro) 飛猿(tobisaru) 疾風(hayate) 影丸(kagemaru) |
| 下忍(genin) | 佐助(sasuke) 霧丸(kirimaru) |

- CLI種別・モデル・effort → `config/settings.yaml`のcli.agentsがSSOT
- 個別CLI設定は`config/settings.yaml`に従う（手元設定値を前提にしない）

## §8 WSL2固有 詳細

| 項目 | 内容 |
|------|------|
| inotifywait | /mnt/c/上では不可。statポーリング(15-30秒)を標準パターンとして使え |
| .wslconfig | ネットワーク設定ミスで全エージェント凍死の事例あり |
