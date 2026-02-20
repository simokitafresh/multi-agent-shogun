# インフラコンテキスト

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

最終更新: 2026-02-21

## コンテキスト管理

コンテキスト管理は**全て外部インフラが自動処理する。エージェントは何もするな。**

| エージェント | 外部トリガー | 方法 |
|-------------|-------------|------|
| 忍者 | ninja_monitor.sh | idle+タスクなし → /clear送信（CTX>0%時） |
| 家老 | ninja_monitor.sh | idle+CTX>50% → /clear送信（陣形図付き） |
| 将軍 | 殿の手動操作 | CTX>50%でntfyアラート → 殿が判断 |

- ソフト閾値: 50%（外部トリガー発動条件）
- ハード閾値: 90%（CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90、最後の安全弁）
- 忍者=/clear（コンテキスト汚染防止。hayate v1→v4事件が教訓）
- 家老=/clear（陣形図snapshotで状態保全。/compactの5-8分停止を解消）
- CLI種別により/compact挙動が異なるため、実際の動作は`config/settings.yaml`を参照
- 設定: settings.json → env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE。全エージェントに自動適用
- statusline.sh: イベント駆動。JSON入力にcontext_window.used_percentage含む

## 直近10日間の改善（2026-02-21追記）

1. acknowledged status追加（cmd_181）
   - 問題: 忍者が受領済みでもtask YAMLが`assigned`のまま残り、CLI停止との区別がつかずゴースト配備判定が増えた。
   - 解決: タスク状態に`acknowledged`を追加し、受領直後に`assigned → acknowledged`へ遷移する運用に変更。
   - 参照cmd: `cmd_181`

2. ペイン消失検知 + remain-on-exit（cmd_183）
   - 問題: tmuxペインが落ちると配備状態が消え、監視側が実態を追跡できなくなった。
   - 解決: tmux `remain-on-exit=on`でペイン消失を防止し、`ninja_monitor.sh`にペイン消失検知と自動回復処理を追加。
   - 参照cmd: `cmd_183`

3. inbox re-nudge導入（cmd_188）
   - 問題: 初回ナッジを見落とすと未読が残り続け、忍者がタスク配備に気づけないケースがあった。
   - 解決: `@inbox_unread`で未読件数をtmux枠に表示し、未読ありの忍者へ`ninja_monitor.sh`が再ナッジを自動送信。
   - 参照cmd: `cmd_188`

4. inbox_mark_read.sh追加（cmd_189）
   - 問題: Edit toolは`flock`非対応のため、inbox YAMLを直接編集すると`inbox_write.sh`と競合してLost Updateが発生した。
   - 解決: `flock + atomic write`で既読化する`inbox_mark_read.sh`を導入し、inbox既読化の唯一経路に統一。
   - 参照cmd: `cmd_189`

5. idle家老へのauto-nudge（cmd_191）
   - 問題: pending cmdが残っていても、家老がidle状態だと復帰後にコマンドを取りこぼすことがあった。
   - 解決: pending cmd検知時に`ninja_monitor.sh`が家老へ自動ナッジを送る機構を追加。
   - 参照cmd: `cmd_191`

6. grep -c改行バグ修正（cmd_192）
   - 問題: `grep -c pattern || echo 0`で0件時に`0`が二重出力され、変数が`0\n0`化して件数判定が壊れた。
   - 解決: 件数集計を`awk`代替へ切り替え、0件時でも単一の数値のみ返る実装に修正。
   - 参照cmd: `cmd_192`

## ninja_monitor.sh

- idle検知+CTX>50%で忍者に/clear、家老に/clearを自動送信
- is_task_deployed(): YAML status + capture-pane + @current_task空チェックの二重チェック（cmd_049で修正）
- STALE-TASK検出: YAML上作業中だがペインidle → ログ出力して対処
- CLEAR_DEBOUNCE=300（5分）でループ防止
- get_context_pct(): capture-pane出力から「CTX:XX%」を直接パース（tmux変数は不安定）
- write_karo_snapshot(): 毎サイクルqueue/karo_snapshot.txtを自動生成（家老/clear復帰用の圧縮陣形図）
- KARO_CLEAR_DEBOUNCE=120（2分）— /clear復帰~30秒のため大幅短縮

## inbox_watcher.sh

- inotifywaitでqueue/inbox/{agent}.yaml変更検知 → send-keysで短いナッジ送信
- ナッジ形式: `inboxN`（例: inbox3=未読3件）。内容は送らない
- エージェントリネーム後はsymlink必要（旧名→新名、Pythonのopen()がsymlinkを辿る）
- watcher欠落時の手動起動: `nohup bash inbox_watcher.sh {agent} {pane} claude`

## ntfy.sh

- Usage: `bash scripts/ntfy.sh "メッセージ"` **のみ。引数追加厳禁。**
- トピック: shogun-simokitafresh
- インターフェース変更で全通知が無言で壊れた事故あり（--sendフラグガード事件）
- shutsujin_departure.shにスモークテスト組み込み済み

## tmux設定

- prefix: Ctrl+A（.tmux.conf設定済み。デフォルトのCtrl+Bではない）
- レイアウト文字列: `1a7c,167x49,0,0{...}`（shutsujin_departure.shで適用）
- セッション: shogun | Window 1: main（将軍） | Window 2: agents（家老+忍者9ペイン）
- 形式: shogun:2.{pane_index}

| pane | 名前 | pane | 名前 | pane | 名前 |
|------|------|------|------|------|------|
| 1 | karo | 4 | hayate | 7 | saizo |
| 2 | sasuke | 5 | kagemaru | 8 | kotaro |
| 3 | kirimaru | 6 | hanzo | 9 | tobisaru |

- karo.mdのpanes設定はshogun:2.{N}に修正済み(cmd_206)。`tmux list-panes -t shogun:2`で確認可能

## 編成

| 階級 | CLI | 名前 |
|------|-----|------|
| 上忍(jonin) — CLI設定はsettings.yaml参照 | settings.yaml参照 | 半蔵(hanzo) 才蔵(saizo) 小太郎(kotaro) 飛猿(tobisaru) 疾風(hayate) 影丸(kagemaru) |
| 下忍(genin) — CLI設定はsettings.yaml参照 | settings.yaml参照 | 佐助(sasuke) 霧丸(kirimaru) |

- `config/settings.yaml`の`cli.agents`をSSOTとして参照
- 個別CLI設定（種別・モデル・effort）は`config/settings.yaml`を参照
- 利用クライアント種別は`config/settings.yaml`に従う（手元設定値を前提にしない）

## WSL2固有

- /mnt/c/上ではinotifywait不可。statポーリング(15-30秒)を標準パターンとして使え
- .wslconfigのネットワーク設定ミスで全エージェント凍死の事例あり
